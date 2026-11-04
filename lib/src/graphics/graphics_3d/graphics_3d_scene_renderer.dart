import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show compute, debugPrint, visibleForTesting;
import 'package:flutter/painting.dart';
import 'package:just_dart/just_dart.dart' show Aabb3, JustMatrix4, Matrix4;
import 'package:just_graphics_engine/assets.dart';
import 'package:just_graphics_engine/gpu.dart';
import 'package:just_graphics_engine/renderer.dart';

import '../../ecs/ecs.dart';
import '../../interfaces/frame_view.dart';
import '../../rendering/rendering.dart';
import 'animation_3d_system.dart';
import 'model_components.dart';
import 'lighting/environment_component.dart';
import 'lighting/light_3d_component.dart';
import 'graphics_3d_models.dart';
import 'graphics_3d_shapes.dart';
import 'materials/material_3d_library.dart';
import 'materials/material_overrides_3d_component.dart';
import 'render_providers.dart';
import 'shapes/primitive_3d_component.dart';

/// What an editor shows in its views of the scene beyond what the game
/// draws: what it hides, the selection's outline, a view mode and a slice.
/// Set by the editor (`Graphics3DSceneRenderer.aids`), never by a game, and
/// left out of the [plainViews] — the game's own camera seen in the editor.
final class SceneEditorAids {
  /// Whether `entity` is drawn; null draws everything. Hidden and isolated
  /// things answer false.
  bool Function(Entity entity)? drawFilter;

  /// What is outlined: the selection.
  Iterable<Entity> Function()? highlighted;

  /// The outline's colour (straight RGBA).
  (double, double, double, double) highlightColor = (1.0, 0.62, 0.15, 1.0);

  /// Lit, unlit or wireframe.
  RenderViewMode viewMode = RenderViewMode.lit;

  /// A slice: nothing higher than this (engine Y, so 3 m up is -3) is
  /// drawn. Null for none.
  double? sliceY;

  /// Views drawn exactly as the game draws them, aids or not.
  final Set<FrameView> plainViews = Set.identity();

  /// Views not drawn at all: the game's own while the editor draws its
  /// viewport split into panes of its own.
  final Set<FrameView> skippedViews = Set.identity();
}

/// Draws a world's 3-D components (Model, the shapes, Light, Environment)
/// from the engine's camera — the [SceneRenderer] a `Graphics3D` adds.
///
/// Each frame it brings its [scene] up to date with the world: the model
/// and shape instances are looked over only when the world's structure
/// changes or a model finishes loading — what still stands is kept, only
/// what is new is made — and otherwise just follow their entities'
/// transforms — a shape whose sizes or look changed takes another mesh or
/// material from [shapes]. It does so once a frame however many views it
/// draws (an editor's panes), when [frame] says which frame is drawn.
/// It then renders into a texture at the viewport's size in physical pixels
/// times [renderScale] and draws that texture over the viewport.
///
/// Between fixed updates an entity is drawn the frame's interpolation of the
/// way from its previous pose to its pose, when whatever moves it captured
/// that previous pose in the last update ([TransformComponent.captureCount]:
/// physics bodies and characters). Anything else is drawn where it is: a
/// transform only gameplay writes has a previous pose that may be stale.
///
/// Without a GPU ([unsupportedReason] set) it still keeps the models'
/// bounds up to date, and draws a short note instead of the image.
///
/// What it draws from stays loaded — models, material files, maps — until
/// [releaseUnused] lets go of what the world no longer draws (after a level
/// changes, say).
final class Graphics3DSceneRenderer extends SceneRenderer {
  /// Draws the world [world] gives with [renderer], models from [models].
  Graphics3DSceneRenderer({
    required this.world,
    required this.renderer,
    required this.models,
    this.unsupportedReason,
    this.frame,
  }) {
    models.listeners.add(_onModelLoaded);
  }

  /// The world drawn, asked for each frame: an engine's
  /// (`() => engine.world`).
  final World Function() world;

  /// What draws it.
  final Renderer3D renderer;

  /// Where models come from.
  final Graphics3DModels models;

  /// Why there is no GPU to draw with, or null when there is one.
  final String? unsupportedReason;

  /// The frame being drawn, asked for each view: an engine's
  /// (`() => engine.rendering.drawingFrame`). Views drawn in one frame — an
  /// editor's panes, its preview of the game's camera — share one look at
  /// the world (models posed, shapes, providers, lights and environment
  /// followed); only what differs per view (the editor's aids, the camera)
  /// is done for each. Null, or a null answer (a view drawn outside the
  /// engine's frame), looks the world over again for every view.
  final int? Function()? frame;

  /// The scene as last extracted from the world.
  final RenderScene scene = RenderScene();

  /// What an editor adds to its views; null in a game.
  SceneEditorAids? aids;

  // Whether the aids apply to the view being drawn.
  bool _aided = false;

  /// What kits draw (terrain, scatter, tiles): the world's context's
  /// [RenderProviders].
  RenderProviders get providers => world().context.renderProviders;

  late final RenderProviderContext _providerContext = RenderProviderContext(
    uploader: renderer.uploader,
    models: models,
    shapes: shapes,
  );

  /// The shapes' meshes and materials.
  late final Graphics3DShapes shapes = Graphics3DShapes(
    renderer.uploader,
    models.read,
    inUse: _shapesInUse,
    library: materials,
  );

  /// The material files shapes and models are drawn with
  /// ([Primitive3DComponent.material], [ModelComponent.materials]).
  late final Material3DLibrary materials = Material3DLibrary(
    renderer.uploader,
    models.read,
  );

  /// The meshes and materials the shapes are drawn with now.
  Iterable<Object> _shapesInUse() sync* {
    for (final proxy in _shapeProxies) {
      final instance = proxy.instance;
      if (instance == null) continue;
      yield instance.primitive;
      yield instance.material;
    }
  }

  /// Fraction of the physical resolution rendered (0.25..1 makes sense;
  /// above 1 supersamples).
  double renderScale = 1.0;

  /// Lowers the resolution while frames run slow (off by default).
  final DynamicResolution dynamicResolution = DynamicResolution();

  final Stopwatch _clock = Stopwatch();
  FrameView? _timed;

  /// Physical pixels per viewport pixel; null reads the screen's.
  double? pixelRatio;

  /// Drawn at all.
  bool visible = true;

  /// Renders on a device with no GPU too (tests of the CPU side).
  @visibleForTesting
  bool renderWithoutGpu = false;

  /// Completes when the GPU has finished the last frame.
  Future<bool>? lastFrame;

  @override
  int get order => -100;

  @override
  bool get enabled => visible;

  // A surface per view it draws: the game's, and any other drawn in the
  // same frame (an editor's small view through the game camera) — frames
  // of one surface would overwrite each other's images. Each with the
  // render it last drew in.
  final Map<FrameView, _Surface> _surfaces = Map.identity();
  int _renders = 0;

  /// Renders a view's surface is kept for after its last: one that stops
  /// drawing (an editor's split panes put away) lets go of its textures.
  static const int keepSurfaceRenders = 600;

  GpuSurface _surfaceFor(FrameView view) {
    final now = ++_renders;
    if (now % 60 == 0) {
      _surfaces.removeWhere((_, s) => now - s.drawn > keepSurfaceRenders);
    }
    final known = _surfaces[view];
    if (known != null) return (known..drawn = now).surface;
    // The game's view, an editor's (as many as it splits into) and its
    // preview of the game's camera: past eight, the one drawn longest ago
    // goes.
    if (_surfaces.length >= 8) {
      final oldest = _surfaces.entries
          .reduce((a, b) => a.value.drawn <= b.value.drawn ? a : b)
          .key;
      _surfaces.remove(oldest);
    }
    final surface = renderer.device.createSurface(1, 1);
    _surfaces[view] = _Surface(surface, now);
    return surface;
  }

  /// How many views' surfaces are kept, for tests.
  @visibleForTesting
  int get debugSurfaces => _surfaces.length;

  final RenderView _view = RenderView();
  final Matrix4 _scratch = Matrix4.identity();
  final Matrix4 _root = Matrix4.identity();
  double _alpha = 1;
  final List<_Proxy> _proxies = [];
  final List<_ShapeProxy> _shapeProxies = [];
  int _shapeRevision = -1;
  final List<_ProviderProxy> _providerProxies = [];
  int _providerVersion = -1;
  final List<PunctualLight> _lightPool = [];
  // Each light's colour made linear, worked out again only when it changes.
  final List<_LinearColor> _lightColors = [];
  final _LinearColor _sunColor = _LinearColor();
  World? _world;
  // The frame the world was last looked over in (see [frame]).
  int? _lookedFrame;
  // What the editor's aids hid for the last view, shown again for the next.
  final List<MeshInstance> _hiddenInstances = [];
  final List<InstanceBatch> _hiddenBatches = [];
  int _structureVersion = -1;
  int _seenUpdates = -1;
  bool _dirty = true;
  Object? _failure;
  TextPainter? _note;
  String? _noteText;

  bool get _gpu => unsupportedReason == null && _failure == null;

  void _onModelLoaded(String path) => _dirty = true;

  /// Stops listening to [models] and lets go of its views' surfaces; call
  /// once it is no longer drawn.
  void dispose() {
    _disposed = true;
    models.listeners.remove(_onModelLoaded);
    _surfaces.clear();
    _note?.dispose();
    _note = null;
    _noteText = null;
  }

  @override
  void render(Canvas canvas, FrameView view) {
    final size = view.viewportSize;
    if (size.isEmpty) return;
    if (aids?.skippedViews.contains(view) ?? false) return;
    if (!_gpu && !renderWithoutGpu) {
      // Nothing to draw with: only the models' bounds are kept up to date.
      _refresh(world());
      _drawNote(canvas, size, _failure?.toString() ?? unsupportedReason!);
      return;
    }
    update(view);
    final surface = _surfaceFor(view);
    try {
      final done = renderer.render(scene, _view, surface);
      lastFrame = done;
      unawaited(done.then((_) {}, onError: _fail));
    } on Object catch (error) {
      _fail(error);
      return;
    } finally {
      // The renderer is shared (a model's thumbnail, say): an editor's view
      // settings stay with its views.
      renderer
        ..viewMode = RenderViewMode.lit
        ..clipPlane = null;
    }
    final image = surface.image;
    if (image == null) return;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.low,
    );
    image.dispose();
  }

  void _fail(Object error) {
    if (_failure != null) return;
    _failure = error;
    debugPrint('just_game_engine: 3D rendering stopped: $error');
  }

  /// Looks the world over again when what it draws may have changed: its
  /// structure, a provider, a model loaded or a model's path.
  void _refresh(World world) {
    if (!identical(world, _world) ||
        _queriesVersion(world) != _structureVersion ||
        // Registering a provider changes what is drawn, no entity changed.
        providers.version != _providerVersion ||
        _dirty ||
        _pathsChanged()) {
      _rebuild(world);
    }
  }

  /// Brings [scene] and the render view up to date with the world and
  /// [view]. [render] calls it; tests may call it alone.
  void update(FrameView view) {
    final world = this.world();
    _showHidden();
    final alpha = view.interpolation.clamp(0.0, 1.0);
    final frame = this.frame?.call();
    // Once a frame: a second view of the same frame, between the same two
    // steps, sees the world as the first did.
    if (frame == null ||
        frame != _lookedFrame ||
        alpha != _alpha ||
        !identical(world, _world)) {
      _lookedFrame = frame;
      _alpha = alpha;
      _refresh(world);
      _checkCaptures(world);
      _follow();
      _followShapes();
      _followProviders();
      _extractLights(world);
      _extractEnvironment(world);
    }
    final aids = this.aids;
    _aided = aids != null && !aids.plainViews.contains(view);
    _applyAids();

    final ratio =
        pixelRatio ??
        ui.PlatformDispatcher.instance.implicitView?.devicePixelRatio ??
        1.0;
    // Timed by the first view drawn (the game's): a second view drawn in
    // the same frame would halve the time seen between frames.
    if (identical(_timed ??= view, view)) {
      if (_clock.isRunning) {
        dynamicResolution.frame(_clock.elapsedMicroseconds / 1e6);
      }
      _clock
        ..reset()
        ..start();
    }
    final scale = ratio * renderScale * dynamicResolution.scale;
    _view
      ..width = math.max(
        1,
        math.min(8192, (view.viewportSize.width * scale).round()),
      )
      ..height = math.max(
        1,
        math.min(8192, (view.viewportSize.height * scale).round()),
      );
    _view.view.setFrom(view.view);
    _view.projection.setFrom(view.projection);
    _view.cameraPosition.setFrom(view.cameraPosition);
  }

  /// The largest version of the queries [_rebuild] reads, the providers'
  /// among them, and of the providers themselves.
  int _queriesVersion(World world) {
    var version = math.max(
      world.queryVersion(const [TransformComponent, ModelComponent]),
      world.queryVersion(const [TransformComponent, Primitive3DComponent]),
    );
    final providers = this.providers;
    for (final provider in providers.all) {
      version = math.max(
        version,
        world.queryVersion([TransformComponent, provider.componentType]),
      );
    }
    return version;
  }

  bool _pathsChanged() {
    for (final proxy in _proxies) {
      if (proxy.component.model != proxy.path) return true;
    }
    return false;
  }

  void _rebuild(World world) {
    // What stands from the last build is kept — its instances, its pose,
    // what it knew of its transform's captures — so a rebuild (a pickup
    // taken) makes only what is new and doesn't stop interpolation for a
    // step.
    final knownModels = Map<TransformComponent, _Proxy>.identity();
    final knownShapes = Map<TransformComponent, _ShapeProxy>.identity();
    final knownProvided = <(TransformComponent, Type), _ProviderProxy>{};
    if (identical(world, _world)) {
      for (final f in _proxies) {
        knownModels[f.transform] = f;
      }
      for (final f in _shapeProxies) {
        knownShapes[f.transform] = f;
      }
      for (final f in _providerProxies) {
        knownProvided[(f.transform, f.provider.componentType)] = f;
      }
    } else {
      _seenUpdates = world.updateCount;
    }
    _world = world;
    _structureVersion = _queriesVersion(world);
    _dirty = false;
    _proxies.clear();
    scene.instances.clear();
    scene.batches.clear();
    for (final archetype in world.queryArchetypes(const [
      TransformComponent,
      ModelComponent,
    ])) {
      final transforms = archetype.getColumn(TransformComponent)!;
      final components = archetype.getColumn(ModelComponent)!;
      for (var row = 0; row < archetype.length; row++) {
        final entity = archetype.entityAt(row);
        if (!entity.isActiveInHierarchy) continue;
        final component = components[row] as ModelComponent;
        final path = component.model;
        final model = path.isEmpty ? null : models.get(path);
        final transform = transforms[row] as TransformComponent;
        final player = model == null
            ? null
            : entity.getComponent<AnimationPlayerComponent>();
        final known = knownModels[transform];
        if (known != null && known.fits(component, path, model, player)) {
          known.entity = entity;
          _proxies.add(known);
          scene.instances.addAll(known.instances);
          if (model != null) {
            model.data.bounds.transformInto(gltfToEngine, component.bounds);
          }
          continue;
        }
        final proxy = _Proxy(transform, component, path, model)
          ..entity = entity
          ..carryFrom(known ?? knownShapes[transform]);
        _proxies.add(proxy);
        if (model == null) {
          component.bounds.setEmpty();
          continue;
        }
        model.data.bounds.transformInto(gltfToEngine, component.bounds);
        if (player != null) {
          // Animated: posed every frame, its instances placed by the pose.
          final posed = PosedModel(model);
          proxy
            ..player = player
            ..posed = posed
            ..scratch = PlayerScratch(model.data.nodes.length);
          proxy.instances.addAll(
            scene.addModel(model, Matrix4.identity(), posed: posed),
          );
          continue;
        }
        for (final instance in scene.addModel(model, Matrix4.identity())) {
          proxy.instances.add(instance);
          proxy.locals.add(Matrix4.copy(instance.world));
        }
      }
    }
    _shapeProxies.clear();
    for (final archetype in world.queryArchetypes(const [
      TransformComponent,
      Primitive3DComponent,
    ])) {
      final transforms = archetype.getColumn(TransformComponent)!;
      final column = archetype.getColumn(Primitive3DComponent)!;
      for (var row = 0; row < archetype.length; row++) {
        final entity = archetype.entityAt(row);
        if (!entity.isActiveInHierarchy) continue;
        final transform = transforms[row] as TransformComponent;
        final shape = column[row] as Primitive3DComponent;
        final known = knownShapes[transform];
        if (known != null && identical(known.shape, shape)) {
          known.entity = entity;
          _shapeProxies.add(known);
          final instance = known.instance;
          if (instance != null) scene.instances.add(instance);
          continue;
        }
        // Made at the next follow, with its mesh.
        _shapeProxies.add(
          _ShapeProxy(transform, shape)
            ..entity = entity
            ..carryFrom(known ?? knownModels[transform]),
        );
      }
    }
    // What the kits draw.
    _providerProxies.clear();
    final providers = this.providers;
    _providerVersion = providers.version;
    for (final provider in providers.all) {
      final type = provider.componentType;
      for (final archetype in world.queryArchetypes([
        TransformComponent,
        type,
      ])) {
        final transforms = archetype.getColumn(TransformComponent)!;
        final column = archetype.getColumn(type)!;
        for (var row = 0; row < archetype.length; row++) {
          final entity = archetype.entityAt(row);
          if (!entity.isActiveInHierarchy) continue;
          final transform = transforms[row] as TransformComponent;
          final component = column[row];
          final known = knownProvided[(transform, type)];
          // Kept only while the same provider would build the same: one
          // registered in its place builds afresh.
          final proxy =
              known != null &&
                  identical(known.provider, provider) &&
                  identical(known.component, component) &&
                  known.revision == provider.revisionOfAny(component)
              ? known
              : _build(entity, transform, component, provider, known);
          proxy.entity = entity;
          _providerProxies.add(proxy);
          scene.instances.addAll(proxy.instances);
          scene.batches.addAll(proxy.batches);
        }
      }
    }
    // What is no longer drawn lets go of what it held.
    final kept = Set<_Follower>.identity()
      ..addAll(_proxies)
      ..addAll(_shapeProxies);
    for (final proxy in knownModels.values) {
      if (!kept.contains(proxy)) _releaseModel(proxy);
    }
    for (final proxy in knownShapes.values) {
      if (!kept.contains(proxy)) _releaseShape(proxy);
    }
  }

  /// What [proxy]'s instances were drawn with goes back to the library.
  void _releaseModel(_Proxy proxy) {
    for (final instance in proxy.instances) {
      materials.release(instance.material);
    }
  }

  /// [proxy]'s mesh and material go back to [shapes].
  void _releaseShape(_ShapeProxy proxy) {
    final mesh = proxy.mesh, instance = proxy.instance;
    if (mesh != null) shapes.release(mesh);
    if (instance != null) shapes.release(instance.material);
    proxy
      ..mesh = null
      ..instance = null;
  }

  /// Lets go of every model, material file and map the world's entities do
  /// not draw with — the switched-off ones' are kept — and of the shapes'
  /// meshes and materials nothing draws: what a level left behind leaves
  /// the GPU. Call once the next level is in the world; whatever is drawn
  /// again later is loaded again. Returns how many models and material
  /// files went.
  (int models, int materials) releaseUnused() {
    final world = this.world();
    _refresh(world);
    final modelPaths = <String>{};
    final materialPaths = <String>{};
    for (final archetype in world.queryArchetypes(const [ModelComponent])) {
      final column = archetype.getColumn(ModelComponent)!;
      for (var row = 0; row < archetype.length; row++) {
        final model = column[row] as ModelComponent;
        modelPaths.add(model.model);
        materialPaths.addAll(model.materials.values);
      }
    }
    for (final archetype in world.queryArchetypes(const [
      Primitive3DComponent,
    ])) {
      final column = archetype.getColumn(Primitive3DComponent)!;
      for (var row = 0; row < archetype.length; row++) {
        materialPaths.add((column[row] as Primitive3DComponent).material);
      }
    }
    // What the kits asked for as they built.
    for (final proxy in _providerProxies) {
      modelPaths.addAll(proxy.modelsAsked);
      materialPaths.addAll(proxy.materialsAsked);
    }
    final gone = (
      models.retainOnly(modelPaths),
      materials.retainOnly(materialPaths),
    );
    shapes.releaseUnused();
    return gone;
  }

  /// What [provider] draws for [component] on [entity], placed when next
  /// followed.
  _ProviderProxy _build(
    Entity entity,
    TransformComponent transform,
    Component component,
    RenderProvider<Component> provider,
    _Follower? known,
  ) {
    final proxy = _ProviderProxy(
      transform,
      component,
      provider,
      provider.revisionOfAny(component),
    )..carryFrom(known);
    final out = RenderProviderOutput();
    // Which models and material files it draws with, for [releaseUnused].
    models.asked = proxy.modelsAsked;
    materials.asked = proxy.materialsAsked;
    try {
      provider.buildAny(_providerContext, entity, component, out);
    } on Object catch (error) {
      debugPrint(
        'just_game_engine: ${provider.runtimeType} could not draw '
        '${entity.name ?? entity.id}: $error',
      );
    } finally {
      models.asked = null;
      materials.asked = null;
    }
    for (final (primitive, material, local, shadows) in out.meshes) {
      proxy.instances.add(
        MeshInstance(primitive, material, Matrix4.zero())
          ..castShadows = shadows,
      );
      proxy.locals.add(local);
    }
    for (final (primitive, material, locals, reach, shadows) in out.batches) {
      proxy.batches.add(
        InstanceBatch(primitive, material)
          ..maxDistance = reach
          ..castShadows = shadows,
      );
      proxy.batchLocals.add(locals);
    }
    return proxy;
  }

  /// Brings what the kits draw up to date: built again when a provider
  /// says it changed, and placed where its entity is.
  void _followProviders() {
    // What rebuilt proxies drew before, taken out of the scene in one pass,
    // and what they draw now.
    Set<Object>? stale;
    List<MeshInstance>? instances;
    List<InstanceBatch>? batches;
    for (var i = 0; i < _providerProxies.length; i++) {
      var proxy = _providerProxies[i];
      final revision = proxy.provider.revisionOfAny(proxy.component);
      if (revision != proxy.revision) {
        (stale ??= Set.identity())
          ..addAll(proxy.instances)
          ..addAll(proxy.batches);
        final entity = proxy.entity!;
        proxy = _providerProxies[i] = _build(
          entity,
          proxy.transform,
          proxy.component,
          proxy.provider,
          proxy,
        )..entity = entity;
        (instances ??= []).addAll(proxy.instances);
        (batches ??= []).addAll(proxy.batches);
      }
      _poseOf(proxy, _scratch);
      final moved = !_same(_scratch, proxy.world);
      if (moved) proxy.world.setFrom(_scratch);
      for (var k = 0; k < proxy.instances.length; k++) {
        final instance = proxy.instances[k]..visible = true;
        if (moved) {
          instance.world.setProduct(proxy.world, proxy.locals[k]);
          instance.markMoved();
        }
      }
      for (var k = 0; k < proxy.batches.length; k++) {
        final batch = proxy.batches[k]..visible = true;
        if (moved) batch.setInstances(proxy.placeBatch(k));
      }
    }
    if (stale == null) return;
    scene.instances
      ..removeWhere(stale.contains)
      ..addAll(instances!);
    scene.batches
      ..removeWhere(stale.contains)
      ..addAll(batches!);
  }

  /// Shows again what the editor's aids hid for the last view: the next
  /// view may be a plain one, and in the same frame nothing else shows it.
  void _showHidden() {
    for (final instance in _hiddenInstances) {
      instance.visible = true;
    }
    for (final batch in _hiddenBatches) {
      batch.visible = true;
    }
    _hiddenInstances.clear();
    _hiddenBatches.clear();
  }

  /// The editor's aids, for the view being drawn: what it hides, a slice,
  /// the view mode, and the selection's outline. Nothing for a game, or a
  /// plain view.
  void _applyAids() {
    scene.overlays.clear();
    final aids = this.aids;
    if (!_aided || aids == null) {
      renderer
        ..viewMode = RenderViewMode.lit
        ..clipPlane = null;
      return;
    }
    final slice = aids.sliceY;
    renderer
      ..viewMode = aids.viewMode
      // Up is -Y: nothing where -y is past -slice.
      ..clipPlane = slice == null ? null : (0, -1, 0, -slice);
    final filter = aids.drawFilter;
    // Wholly above the slice: its lowest point (largest Y) above it.
    bool sliced(Aabb3 b) => slice != null && b.max.y < slice;
    void hide(Entity? entity, Iterable<MeshInstance> instances) {
      final shown = entity == null || filter == null || filter(entity);
      for (final instance in instances) {
        if (instance.visible && (!shown || sliced(instance.bounds))) {
          instance.visible = false;
          _hiddenInstances.add(instance);
        }
      }
    }

    for (final p in _proxies) {
      hide(p.entity, p.instances);
    }
    for (final p in _shapeProxies) {
      final instance = p.instance;
      if (instance != null) hide(p.entity, [instance]);
    }
    for (final p in _providerProxies) {
      hide(p.entity, p.instances);
      final entity = p.entity;
      final shown = entity == null || filter == null || filter(entity);
      for (final batch in p.batches) {
        if (batch.visible && (!shown || sliced(batch.bounds))) {
          batch.visible = false;
          _hiddenBatches.add(batch);
        }
      }
    }

    final picked = aids.highlighted?.call();
    if (picked == null) return;
    final selected = Set<Entity>.identity()..addAll(picked);
    if (selected.isEmpty) return;
    final c = aids.highlightColor;
    void outline(Iterable<MeshInstance> instances) {
      for (final instance in instances) {
        if (!instance.visible) continue;
        scene.overlays
          ..add(OverlayDraw(instance.primitive, instance.world, color: c))
          // Faint through what stands in front of it.
          ..add(
            OverlayDraw(
              instance.primitive,
              instance.world,
              color: (c.$1, c.$2, c.$3, c.$4 * 0.3),
              xray: true,
            ),
          );
      }
    }

    for (final p in _proxies) {
      if (selected.contains(p.entity)) outline(p.instances);
    }
    for (final p in _shapeProxies) {
      final instance = p.instance;
      if (instance != null && selected.contains(p.entity)) outline([instance]);
    }
    for (final p in _providerProxies) {
      if (selected.contains(p.entity)) outline(p.instances);
    }
  }

  /// Brings each shape's instance up to date: its mesh when its sizes (or,
  /// for a texture tiled per metre, its entity's scale) changed, its
  /// material when its look did, and where it is.
  void _followShapes() {
    final refresh = shapes.revision != _shapeRevision;
    _shapeRevision = shapes.revision;
    for (final proxy in _shapeProxies) {
      final shape = proxy.shape;
      final scale = proxy.transform.scale;
      // Its values against the last frame's: plain numbers, nothing made.
      final sizes = proxy.sizes..begin();
      shape.writeShapeValues(sizes);
      final reshaped = sizes.end();
      final look = proxy.look..begin();
      shape.writeMaterialValues(look);
      var restyled = look.end();
      final overrides = proxy.entity
          ?.getComponent<MaterialOverrides3DComponent>();
      final overridesKey = overrides == null
          ? 0
          : Object.hash(identityHashCode(overrides), overrides.revision);
      if (overridesKey != proxy.overridesKey) {
        proxy.overridesKey = overridesKey;
        restyled = true;
      }
      final metres = shapes.tilesInMetres(shape);
      var instance = proxy.instance;
      if (reshaped ||
          metres != proxy.metres ||
          (metres &&
              (scale.x != proxy.sx ||
                  scale.y != proxy.sy ||
                  scale.z != proxy.sz))) {
        proxy
          ..metres = metres
          ..sx = scale.x
          ..sy = scale.y
          ..sz = scale.z;
        // The mesh it had goes as soon as no other shape draws it.
        final mesh = shapes.meshFor(shape, scale), was = proxy.mesh;
        if (!identical(mesh, was)) {
          if (mesh != null) shapes.hold(mesh);
          if (was != null) shapes.release(was);
          proxy.mesh = mesh;
        }
        if (mesh != null) {
          if (instance == null) {
            final made = _materialOf(shape, overrides);
            shapes.hold(made);
            instance = proxy.instance = MeshInstance(
              mesh,
              made,
              Matrix4.zero(),
            );
            restyled = false;
            scene.instances.add(instance);
          } else {
            instance.primitive = mesh;
          }
        }
      }
      if (instance == null) continue;
      if (refresh || restyled) {
        final made = _materialOf(shape, overrides), was = instance.material;
        if (!identical(made, was)) {
          shapes
            ..hold(made)
            ..release(was);
          instance.material = made;
        }
      }
      instance
        ..visible = shape.visible && proxy.mesh != null
        ..castShadows = shape.castShadows;
      _poseOf(proxy, _scratch);
      if (!_same(_scratch, instance.world)) {
        instance.world.setFrom(_scratch);
        instance.markMoved();
      }
    }
    shapes.endFrame();
  }

  /// [shape]'s material, with [overrides]' values on top: read only when a
  /// material is made, which most frames make none of.
  GpuMaterial _materialOf(
    Primitive3DComponent shape,
    MaterialOverrides3DComponent? overrides,
  ) => shapes.materialFor(
    shape,
    overrides: overrides?.values ?? const <String, Object>{},
  );

  void _follow() {
    for (final proxy in _proxies) {
      _applyMaterials(proxy);
      final visible = proxy.component.visible;
      final shadows = proxy.component.castShadows;
      final posed = proxy.posed;
      if (posed != null) {
        // Sampled and skinned only when its pose changed (an idle or held
        // model does not), placed only when it or its entity moved.
        final reposed = samplePlayer(
          proxy.player!,
          posed.model,
          posed.pose,
          proxy.scratch!,
          alpha: _alpha,
          skipUnchanged: true,
        );
        if (reposed) posed.update();
        _poseOf(proxy, _scratch);
        final moved = !_same(_scratch, proxy.world);
        if (moved) proxy.world.setFrom(_scratch);
        if (reposed || moved) {
          posed.place(
            _root
              ..setFrom(proxy.world)
              ..multiply(gltfToEngine),
          );
        }
        for (final instance in proxy.instances) {
          instance
            ..visible = visible
            ..castShadows = shadows;
        }
        continue;
      }
      _poseOf(proxy, _scratch);
      final moved = !_same(_scratch, proxy.world);
      if (moved) proxy.world.setFrom(_scratch);
      for (var i = 0; i < proxy.instances.length; i++) {
        final instance = proxy.instances[i]
          ..visible = visible
          ..castShadows = shadows;
        if (moved) {
          instance.world.setProduct(proxy.world, proxy.locals[i]);
          instance.markMoved();
        }
      }
    }
  }

  /// [proxy]'s material files, where its component names them: swapped
  /// in for its own once read — with its entity's [MaterialOverrides3DComponent] on
  /// top — and its own back where they go.
  void _applyMaterials(_Proxy proxy) {
    final model = proxy.model;
    if (model == null) return;
    final wanted = proxy.component.materials;
    final drawn = proxy.wanted;
    if (wanted.isEmpty && drawn.isEmpty) return;
    final overrides = proxy.entity
        ?.getComponent<MaterialOverrides3DComponent>();
    final overridesKey = overrides == null
        ? 0
        : Object.hash(identityHashCode(overrides), overrides.revision);
    // As last swapped in, compared in place: nothing made while nothing
    // changed.
    if (proxy.libraryRevision == materials.revision &&
        proxy.overridesKey == overridesKey &&
        _sameEntries(wanted, drawn)) {
      return;
    }
    proxy
      ..libraryRevision = materials.revision
      ..overridesKey = overridesKey;
    drawn
      ..clear()
      ..addAll(wanted);
    final values = overrides?.values ?? const <String, Object>{};
    final named = model.data.materials;
    for (final instance in proxy.instances) {
      final index = instance.primitive.material;
      final path = index == null
          ? wanted['*']
          : wanted[index < named.length ? named[index].name : ''] ??
                wanted['#$index'] ??
                wanted['*'];
      final material =
          (path == null ? null : materials.gpuOf(path, overrides: values)) ??
          model.materialOf(instance.primitive);
      final was = instance.material;
      if (identical(material, was)) continue;
      // One made for the entity's own values goes once nothing draws it.
      materials
        ..hold(material)
        ..release(was);
      instance.material = material;
    }
  }

  static bool _sameEntries(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final MapEntry(:key, :value) in a.entries) {
      if (b[key] != value) return false;
    }
    return true;
  }

  /// Once per fixed update (however many views draw a frame): whose
  /// previous pose was captured in it, so is the update's start.
  void _checkCaptures(World world) {
    final updates = world.updateCount;
    if (updates == _seenUpdates) return;
    _seenUpdates = updates;
    for (final f in _proxies) {
      f.check();
    }
    for (final f in _shapeProxies) {
      f.check();
    }
    for (final f in _providerProxies) {
      f.check();
    }
  }

  /// Where [f]'s entity is drawn, into [out]: between its previous pose
  /// and its pose when the previous one is fresh, else where it is.
  void _poseOf(_Follower f, Matrix4 out) {
    if (f.fresh) {
      f.transform.interpolatedToWorldInto(out, _alpha);
    } else {
      f.transform.localToWorldInto(out);
    }
  }

  static bool _same(Matrix4 a, Matrix4 b) {
    final x = a.storage, y = b.storage;
    for (var i = 0; i < 16; i++) {
      if (x[i] != y[i]) return false;
    }
    return true;
  }

  void _extractLights(World world) {
    final sun = scene.sun;
    var suns = 0;
    var count = 0;
    for (final archetype in world.queryArchetypes(const [
      TransformComponent,
      Light3DComponent,
    ])) {
      final transforms = archetype.getColumn(TransformComponent)!;
      final lights = archetype.getColumn(Light3DComponent)!;
      for (var row = 0; row < archetype.length; row++) {
        if (!archetype.entityAt(row).isActiveInHierarchy) continue;
        final light = lights[row] as Light3DComponent;
        (transforms[row] as TransformComponent).localToWorldInto(_scratch);
        final m = _scratch.storage;
        if (light.kind == Light3DKind.directional) {
          // The first sun wins; the renderer has one.
          if (suns++ > 0) continue;
          sun
            ..enabled = true
            ..color = _sunColor.of(light.color)
            ..intensity = light.intensity;
          sun.direction
            ..setValues(m[8], m[9], m[10])
            ..normalize();
          continue;
        }
        if (count == _lightPool.length) {
          _lightPool.add(PunctualLight(type: LightType.point));
          _lightColors.add(_LinearColor());
        }
        final color = _lightColors[count].of(light.color);
        final p = _lightPool[count++]
          ..type = light.kind == Light3DKind.spot
              ? LightType.spot
              : LightType.point
          ..color = color
          ..intensity = light.intensity
          ..range = light.range > 0 ? light.range : null
          ..innerConeAngle = light.innerConeAngle
          ..outerConeAngle = light.outerConeAngle;
        p.position.setValues(m[12], m[13], m[14]);
        p.direction
          ..setValues(m[8], m[9], m[10])
          ..normalize();
      }
    }
    scene.lights
      ..clear()
      ..addAll(_lightPool.take(count));
    // With no lights at all, a default sun keeps models readable.
    if (suns == 0) {
      sun.enabled = count == 0;
      if (count == 0) {
        sun
          ..color = (1.0, 1.0, 1.0)
          ..intensity = 3.0;
        sun.direction
          ..setValues(0.3, 1, 0.5)
          ..normalize();
      }
    }
  }

  // Per renderer: an Environment is mutable, and the engine keeps no state
  // shared across engines.
  final Environment _defaults = Environment();

  // The environment's colours made linear, worked out again only when one
  // changes.
  final _LinearColor _zenith = _LinearColor(),
      _horizon = _LinearColor(),
      _ground = _LinearColor(),
      _ambientSky = _LinearColor(),
      _ambientGround = _LinearColor(),
      _background = _LinearColor(),
      _fogColor = _LinearColor();

  void _extractEnvironment(World world) {
    final env = scene.environment;
    for (final archetype in world.queryArchetypes(const [
      EnvironmentComponent,
    ])) {
      final column = archetype.getColumn(EnvironmentComponent)!;
      for (var row = 0; row < archetype.length; row++) {
        if (!archetype.entityAt(row).isActiveInHierarchy) continue;
        final c = column[row] as EnvironmentComponent;
        env
          // Off: nothing mirrors the map, and the hemisphere lights the
          // scene (_lightFromMap) while a skybox still shows.
          ..reflections = c.reflections ? c.reflectionStrength : 0
          ..skybox = c.skybox.isNotEmpty
          ..skyboxBlur = c.skyboxBlur
          ..sky = c.sky
          ..zenith = _zenith.of(c.zenith)
          ..horizon = _horizon.of(c.horizon)
          ..ground = _ground.of(c.ground)
          ..ambientSky = _ambientSky.of(c.ambientSky)
          ..ambientGround = _ambientGround.of(c.ambientGround)
          ..exposure = c.exposure
          ..clearColor = _background.of(c.background)
          ..fogColor = _fogColor.of(c.fogColor)
          ..fogDensity = c.fog ? c.fogDensity : 0
          ..fogStart = c.fogStart;
        _updateMap(c);
        _lightFromMap(hemisphere: !c.reflections);
        return;
      }
    }
    _updateMap(null);
    env
      ..sky = _defaults.sky
      ..zenith = _defaults.zenith
      ..horizon = _defaults.horizon
      ..ground = _defaults.ground
      ..ambientSky = _defaults.ambientSky
      ..ambientGround = _defaults.ambientGround
      ..exposure = _defaults.exposure
      ..clearColor = _defaults.clearColor
      ..fogDensity = 0;
  }

  // The environment map: what it was last asked to be built from (a skybox,
  // or the gradient sky's colours), which request that was, and whether
  // this renderer is still in use when it arrives.
  String _mapSkybox = '';
  bool _mapGradient = false;
  (double, double, double)? _mapZenith, _mapHorizon, _mapGround;
  int _mapAsked = 0;
  bool _disposed = false;
  bool _mapFailed = false;

  // The map's own diffuse light, kept while the hemisphere's stands in for
  // it (reflections off, a skybox shown).
  GpuEnvironmentMap? _litMap;
  Float32List? _mapLight;
  bool _hemisphereLit = false;

  /// Lights the scene from the map's own surroundings, or — [hemisphere],
  /// reflections being off — from the two ambient colours, as it would be
  /// with no map: the map's diffuse light is written as the hemisphere's
  /// (exact: a hemisphere is linear in the normal), so the map serves only
  /// as the sky.
  void _lightFromMap({required bool hemisphere}) {
    final env = scene.environment;
    final map = env.map;
    if (map == null) return;
    if (!identical(map, _litMap)) {
      _litMap = map;
      _mapLight = Float32List.fromList(map.sh);
      _hemisphereLit = false;
    }
    if (hemisphere) {
      _writeHemisphere(map.sh, env.ambientSky, env.ambientGround);
    } else if (_hemisphereLit) {
      map.sh.setAll(0, _mapLight!);
    }
    _hemisphereLit = hemisphere;
  }

  /// The shaders' hemisphere light, `mix(ground, sky, 0.5 - 0.5 n.y)`, as
  /// nine spherical-harmonic coefficients into [sh]: only the constant and
  /// the n.y terms.
  static void _writeHemisphere(
    Float32List sh,
    (double, double, double) sky,
    (double, double, double) ground,
  ) {
    // Over the shaders' basis constants for Y00 and Y1-1 (n.y).
    const k0 = 0.5 / 0.282095, k1 = -0.5 / 0.488603;
    sh
      ..fillRange(0, sh.length, 0)
      ..[0] = k0 * (sky.$1 + ground.$1)
      ..[1] = k0 * (sky.$2 + ground.$2)
      ..[2] = k0 * (sky.$3 + ground.$3)
      ..[3] = k1 * (sky.$1 - ground.$1)
      ..[4] = k1 * (sky.$2 - ground.$2)
      ..[5] = k1 * (sky.$3 - ground.$3);
  }

  /// A file changed on disk: the material files and maps, the shapes'
  /// textures and the skybox read from it are read again — what they were
  /// is drawn until they arrive. (A model is read again by
  /// [Graphics3DModels.reload].)
  void reload(String path) {
    materials.reload(path);
    shapes.reloadTexture(path);
    // Built again at the next frame, from the new file.
    if (path.isNotEmpty && path == _mapSkybox) _mapSkybox = '';
  }

  /// Starts building the environment map [c] asks for, when it asks for a
  /// different one: from its skybox, or from the gradient sky. It is built
  /// on another isolate and takes over when it is ready; until then the
  /// hemisphere light stands in.
  void _updateMap(EnvironmentComponent? c) {
    final env = scene.environment;
    final skybox = c == null || !_gpu ? '' : c.skybox;
    final gradient = c != null && _gpu && skybox.isEmpty && c.reflections;
    // Asked for as it was: nothing to do, and nothing made to find that out.
    if (skybox == _mapSkybox &&
        gradient == _mapGradient &&
        (!gradient ||
            (env.zenith == _mapZenith &&
                env.horizon == _mapHorizon &&
                env.ground == _mapGround))) {
      return;
    }
    _mapSkybox = skybox;
    _mapGradient = gradient;
    final asked = ++_mapAsked;
    if (skybox.isEmpty && !gradient) {
      env.map = null;
      return;
    }
    final z = _mapZenith = env.zenith;
    final h = _mapHorizon = env.horizon;
    final g = _mapGround = env.ground;
    Future<EnvironmentMapData> build() async {
      if (skybox.isNotEmpty) {
        final image = await compute(
          decodeRadianceHdr,
          await models.read(skybox),
        );
        return EnvironmentMapData.fromEquirect(image);
      }
      return EnvironmentMapData.fromGradient(z, h, g);
    }

    unawaited(
      build().then(
        (data) {
          if (_disposed || asked != _mapAsked) return;
          scene.environment.map = GpuEnvironmentMap.upload(
            renderer.device,
            data,
          );
        },
        onError: (Object error) {
          if (_mapFailed) return;
          _mapFailed = true;
          debugPrint('just_game_engine: no environment map ($skybox): $error');
        },
      ),
    );
  }

  void _drawNote(Canvas canvas, Size size, String reason) {
    if (_noteText != reason) {
      _noteText = reason;
      _note = TextPainter(
        text: TextSpan(
          text: '3D is not available here.\n$reason',
          style: const TextStyle(
            color: Color(0xFFE0E0E0),
            fontSize: 13,
            height: 1.4,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      );
    }
    final note = _note!..layout(maxWidth: math.max(1, size.width - 32));
    final box = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: note.width + 24,
      height: note.height + 16,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, const Radius.circular(6)),
      Paint()..color = const Color(0xCC202024),
    );
    note.paint(canvas, box.topLeft + const Offset(12, 8));
  }

  /// The models drawn, for tests: path → instance count.
  @visibleForTesting
  Map<String, int> get debugInstances => {
    for (final p in _proxies) p.path: p.instances.length,
  };

  /// The models drawn, for tests: every instance of every one.
  @visibleForTesting
  List<MeshInstance> get debugModelInstances => [
    for (final p in _proxies) ...p.instances,
  ];

  /// The shapes drawn, for tests: each one's instance (null while it has
  /// no triangles).
  @visibleForTesting
  List<MeshInstance?> get debugShapeInstances => [
    for (final p in _shapeProxies) p.instance,
  ];

  /// The GPU models in use.
  Iterable<GpuModel> get modelsInUse sync* {
    for (final p in _proxies) {
      final model = p.path.isEmpty ? null : models.get(p.path);
      if (model != null) yield model;
    }
  }
}

/// Something drawn where an entity's transform is, and whether that
/// transform's previous pose is the last fixed update's start.
abstract class _Follower {
  _Follower(this.transform) : captures = transform.captureCount;

  final TransformComponent transform;

  /// Whose transform it is.
  Entity? entity;

  /// The transform's capture count at the last update seen.
  int captures;

  /// Whether its previous pose was captured in the last update, so it is
  /// drawn between that pose and its pose.
  bool fresh = false;

  /// Learns from [other], an earlier follower of the same transform.
  void carryFrom(_Follower? other) {
    if (other == null) return;
    captures = other.captures;
    fresh = other.fresh;
  }

  /// After an update: whether it captured its previous pose in it.
  void check() {
    final count = transform.captureCount;
    fresh = count != captures;
    captures = count;
  }
}

/// One entity's model in the scene.
final class _Proxy extends _Follower {
  _Proxy(super.transform, this.component, this.path, this.model);

  final ModelComponent component;

  /// The path it was built for; a change means a rebuild.
  final String path;

  /// The model it was built from: null while it loads.
  final GpuModel? model;

  /// Whether it still shows [component] as it would be built now: for the
  /// same path, model and player.
  bool fits(
    ModelComponent component,
    String path,
    GpuModel? model,
    AnimationPlayerComponent? player,
  ) =>
      identical(component, this.component) &&
      path == this.path &&
      identical(model, this.model) &&
      identical(player, this.player);

  /// The entity's transform when last followed; zero forces the first.
  final Matrix4 world = Matrix4.zero();
  final List<MeshInstance> instances = [];

  /// The material files last swapped in (empty while it draws its own),
  /// the library's revision then, and its entity's
  /// [MaterialOverrides3DComponent] then (0 for none).
  final Map<String, String> wanted = {};
  int libraryRevision = -1;
  int overridesKey = 0;

  /// Entity space from each instance's primitive.
  final List<Matrix4> locals = [];

  /// An animated model's player, pose and blending scratch.
  AnimationPlayerComponent? player;
  PosedModel? posed;
  PlayerScratch? scratch;
}

/// What a [RenderProvider] drew for one component.
final class _ProviderProxy extends _Follower {
  _ProviderProxy(super.transform, this.component, this.provider, this.revision);

  final Component component;
  final RenderProvider<Component> provider;

  /// [provider]'s revision of [component] when it was built.
  final Object? revision;

  /// The entity's transform when last followed; zero forces the first.
  final Matrix4 world = Matrix4.zero();

  final List<MeshInstance> instances = [];

  /// Entity space from each instance.
  final List<Matrix4> locals = [];

  final List<InstanceBatch> batches = [];

  /// Entity space from each copy of each batch.
  final List<List<Matrix4>> batchLocals = [];

  // Each batch's copies in the world, made once and written in place.
  final List<List<Matrix4>> _batchWorlds = [];

  /// The models and material files its provider asked for as it built.
  final Set<String> modelsAsked = {};
  final Set<String> materialsAsked = {};

  /// Batch [k]'s copies where [world] puts the entity now.
  List<Matrix4> placeBatch(int k) {
    while (_batchWorlds.length <= k) {
      _batchWorlds.add([]);
    }
    final locals = batchLocals[k], worlds = _batchWorlds[k];
    while (worlds.length < locals.length) {
      worlds.add(Matrix4.zero());
    }
    if (worlds.length > locals.length) worlds.length = locals.length;
    for (var i = 0; i < locals.length; i++) {
      worlds[i].setProduct(world, locals[i]);
    }
    return worlds;
  }
}

/// A view's surface, and the render it last drew in.
final class _Surface {
  _Surface(this.surface, this.drawn);

  final GpuSurface surface;
  int drawn;
}

/// One entity's shape in the scene.
final class _ShapeProxy extends _Follower {
  _ShapeProxy(super.transform, this.shape);

  final Primitive3DComponent shape;

  /// Its instance, once it has a mesh.
  MeshInstance? instance;

  /// Its mesh, null for none (an outline of fewer than three points).
  GpuPrimitive? mesh;

  /// Its entity's [MaterialOverrides3DComponent] as last drawn; 0 for none.
  int overridesKey = 0;

  // What its mesh and material were made from.
  final ShapeValues sizes = ShapeValues();
  final ShapeValues look = ShapeValues();
  bool metres = false;
  double sx = 0, sy = 0, sz = 0;
}

/// An sRGB colour as linear RGB, worked out again only when the colour
/// changes.
final class _LinearColor {
  double _r = -1, _g = -1, _b = -1;
  (double, double, double) _value = (0, 0, 0);

  /// [c] as linear RGB.
  (double, double, double) of(Color c) {
    if (c.r != _r || c.g != _g || c.b != _b) {
      _r = c.r;
      _g = c.g;
      _b = c.b;
      _value = (_toLinear(_r), _toLinear(_g), _toLinear(_b));
    }
    return _value;
  }
}

double _toLinear(double v) =>
    v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();

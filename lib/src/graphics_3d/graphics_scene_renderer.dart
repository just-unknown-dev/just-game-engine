import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show compute, debugPrint, visibleForTesting;
import 'package:flutter/painting.dart';
import 'package:just_dart/just_dart.dart' show Aabb3, JustMatrix4, Matrix4;
import 'package:just_graphics_engine/assets.dart';
import 'package:just_graphics_engine/gpu.dart';
import 'package:just_graphics_engine/renderer.dart';

import '../core/core.dart';
import '../ecs/components/components.dart';
import '../ecs/ecs.dart';
import '../subsystems/rendering/rendering.dart';
import 'animation_system.dart';
import 'graphics_components.dart';
import 'graphics_models.dart';
import 'graphics_shapes.dart';
import 'material_library.dart';
import 'render_providers.dart';
import 'shapes/primitive_3d.dart';

/// What an editor shows in its views of the scene beyond what the game
/// draws: what it hides, the selection's outline, a view mode and a slice.
/// Set by the editor (`GraphicsSceneRenderer.aids`), never by a game, and
/// left out of the [plainViews] — the game's own camera seen in the editor.
final class SceneEditorAids {
  /// Whether [entity] is drawn; null draws everything. Hidden and isolated
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
/// material from [shapes].
/// It then renders into a texture at the viewport's size in physical pixels
/// times [renderScale] and draws that texture over the viewport.
///
/// Between fixed updates an entity is drawn the frame's interpolation of the
/// way from its previous pose to its pose, when whatever moves it captured
/// that previous pose in the last update ([TransformComponent.captureCount]:
/// physics bodies and characters). Anything else is drawn where it is: a
/// transform only gameplay writes has a previous pose that may be stale.
///
/// Without a GPU ([unsupportedReason] set) it still keeps the scene and the
/// models' bounds up to date, and draws a short note instead of the image.
final class GraphicsSceneRenderer extends SceneRenderer {
  /// Draws [engine]'s world with [renderer], models from [models].
  GraphicsSceneRenderer({
    required this.engine,
    required this.renderer,
    required this.models,
    this.unsupportedReason,
  }) {
    models.listeners.add(_onModelLoaded);
  }

  /// Whose world is drawn.
  final Engine engine;

  /// What draws it.
  final Renderer3D renderer;

  /// Where models come from.
  final GraphicsModels models;

  /// Why there is no GPU to draw with, or null when there is one.
  final String? unsupportedReason;

  /// The scene as last extracted from the world.
  final RenderScene scene = RenderScene();

  /// What an editor adds to its views; null in a game.
  SceneEditorAids? aids;

  // Whether the aids apply to the view being drawn.
  bool _aided = false;

  /// What kits draw (terrain, scatter, tiles): read from the engine's
  /// [RenderProviders].
  RenderProviders get providers => RenderProviders.of(engine.world.context);

  late final RenderProviderContext _providerContext = RenderProviderContext(
    uploader: renderer.uploader,
    models: models,
    shapes: shapes,
  );

  /// The shapes' meshes and materials.
  late final GraphicsShapes shapes = GraphicsShapes(
    renderer.uploader,
    models.read,
    inUse: _shapesInUse,
    library: materials,
  );

  /// The material files shapes and models are drawn with
  /// ([Primitive3D.material], [ModelComponent.materials]).
  late final MaterialLibrary materials = MaterialLibrary(
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
  // of one surface would overwrite each other's images.
  final Map<FrameView, GpuSurface> _surfaces = Map.identity();

  GpuSurface _surfaceFor(FrameView view) {
    final known = _surfaces[view];
    if (known != null) return known;
    // The game's view, an editor's (as many as it splits into) and its
    // preview of the game's camera.
    if (_surfaces.length >= 8) _surfaces.remove(_surfaces.keys.first);
    return _surfaces[view] = renderer.device.createSurface(1, 1);
  }

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
  int _structureVersion = -1;
  int _seenUpdates = -1;
  bool _dirty = true;
  Object? _failure;
  TextPainter? _note;
  String? _noteText;

  bool get _gpu => unsupportedReason == null && _failure == null;

  void _onModelLoaded(String path) => _dirty = true;

  /// Stops listening to [models]; call once it is no longer drawn.
  void dispose() {
    _disposed = true;
    models.listeners.remove(_onModelLoaded);
  }

  @override
  void render(Canvas canvas, FrameView view) {
    final size = view.viewportSize;
    if (size.isEmpty) return;
    if (aids?.skippedViews.contains(view) ?? false) return;
    update(view);
    if (!_gpu && !renderWithoutGpu) {
      _drawNote(canvas, size, _failure?.toString() ?? unsupportedReason!);
      return;
    }
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

  /// Brings [scene] and the render view up to date with the world and
  /// [view]. [render] calls it; tests may call it alone.
  void update(FrameView view) {
    final world = engine.world;
    if (!identical(world, _world) ||
        _queriesVersion(world) != _structureVersion ||
        // Registering a provider changes what is drawn, no entity changed.
        providers.version != _providerVersion ||
        _dirty ||
        _pathsChanged()) {
      _rebuild(world);
    }
    _alpha = view.interpolation.clamp(0.0, 1.0);
    final aids = this.aids;
    _aided = aids != null && !aids.plainViews.contains(view);
    _checkCaptures(world);
    _follow();
    _followShapes();
    _followProviders();
    _applyAids();
    _extractLights(world);
    _extractEnvironment(world);

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
      world.queryVersion(const [TransformComponent, Primitive3D]),
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
      Primitive3D,
    ])) {
      final transforms = archetype.getColumn(TransformComponent)!;
      final column = archetype.getColumn(Primitive3D)!;
      for (var row = 0; row < archetype.length; row++) {
        final entity = archetype.entityAt(row);
        if (!entity.isActiveInHierarchy) continue;
        final transform = transforms[row] as TransformComponent;
        final shape = column[row] as Primitive3D;
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
      for (final archetype in world.queryArchetypes([TransformComponent, type])) {
        final transforms = archetype.getColumn(TransformComponent)!;
        final column = archetype.getColumn(type)!;
        for (var row = 0; row < archetype.length; row++) {
          final entity = archetype.entityAt(row);
          if (!entity.isActiveInHierarchy) continue;
          final transform = transforms[row] as TransformComponent;
          final component = column[row];
          final known = knownProvided[(transform, type)];
          final proxy =
              known != null &&
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
    try {
      provider.buildAny(_providerContext, entity, component, out);
    } on Object catch (error) {
      debugPrint(
        'just_game_engine: ${provider.runtimeType} could not draw '
        '${entity.name ?? entity.id}: $error',
      );
    }
    for (final (primitive, material, local, shadows) in out.meshes) {
      proxy.instances.add(
        MeshInstance(primitive, material, Matrix4.zero())..castShadows = shadows,
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
    for (var i = 0; i < _providerProxies.length; i++) {
      var proxy = _providerProxies[i];
      final revision = proxy.provider.revisionOfAny(proxy.component);
      if (revision != proxy.revision) {
        for (final instance in proxy.instances) {
          scene.instances.remove(instance);
        }
        for (final batch in proxy.batches) {
          scene.batches.remove(batch);
        }
        final entity = proxy.entity!;
        proxy = _providerProxies[i] = _build(
          entity,
          proxy.transform,
          proxy.component,
          proxy.provider,
          proxy,
        )..entity = entity;
        scene.instances.addAll(proxy.instances);
        scene.batches.addAll(proxy.batches);
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
        if (moved) {
          batch.setInstances([
            for (final local in proxy.batchLocals[k])
              Matrix4.zero()..setProduct(proxy.world, local),
          ]);
        }
      }
    }
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
        if (!shown || sliced(instance.bounds)) instance.visible = false;
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
        if (!shown || sliced(batch.bounds)) batch.visible = false;
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
          ..sz = scale.z
          ..mesh = shapes.meshFor(shape, scale);
        final mesh = proxy.mesh;
        if (mesh != null) {
          if (instance == null) {
            instance = proxy.instance = MeshInstance(
              mesh,
              shapes.materialFor(shape),
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
      if (refresh || restyled) instance.material = shapes.materialFor(shape);
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

  void _follow() {
    for (final proxy in _proxies) {
      _applyMaterials(proxy);
      final visible = proxy.component.visible;
      final shadows = proxy.component.castShadows;
      final posed = proxy.posed;
      if (posed != null) {
        samplePlayer(
          proxy.player!,
          posed.model,
          posed.pose,
          proxy.scratch!,
          alpha: _alpha,
        );
        posed.update();
        _poseOf(proxy, _root);
        posed.place(_root..multiply(gltfToEngine));
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
  /// in for its own once read, and its own back where they go.
  void _applyMaterials(_Proxy proxy) {
    final model = proxy.model;
    if (model == null) return;
    final wanted = proxy.component.materials;
    if (wanted.isEmpty && proxy.materialsKey == null) return;
    final key = wanted.isEmpty
        ? null
        : (
            materials.revision,
            Object.hashAllUnordered([
              for (final e in wanted.entries) Object.hash(e.key, e.value),
            ]),
          );
    if (key == proxy.materialsKey) return;
    proxy.materialsKey = key;
    final named = model.data.materials;
    for (final instance in proxy.instances) {
      final index = instance.primitive.material;
      final path = index == null
          ? wanted['*']
          : wanted[index < named.length ? named[index].name : ''] ??
                wanted['#$index'] ??
                wanted['*'];
      instance.material =
          (path == null ? null : materials.gpuOf(path)) ??
          model.materialOf(instance.primitive);
    }
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
      LightComponent,
    ])) {
      final transforms = archetype.getColumn(TransformComponent)!;
      final lights = archetype.getColumn(LightComponent)!;
      for (var row = 0; row < archetype.length; row++) {
        if (!archetype.entityAt(row).isActiveInHierarchy) continue;
        final light = lights[row] as LightComponent;
        (transforms[row] as TransformComponent).localToWorldInto(_scratch);
        final m = _scratch.storage;
        if (light.kind == LightKind.directional) {
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
        final colour = _lightColors[count].of(light.color);
        final p = _lightPool[count++]
          ..type = light.kind == LightKind.spot
              ? LightType.spot
              : LightType.point
          ..color = colour
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
          ..reflections = c.reflectionStrength
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

  /// The material files last swapped in, and the library as it was then;
  /// null while it draws its own.
  Object? materialsKey;

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
}

/// One entity's shape in the scene.
final class _ShapeProxy extends _Follower {
  _ShapeProxy(super.transform, this.shape);

  final Primitive3D shape;

  /// Its instance, once it has a mesh.
  MeshInstance? instance;

  /// Its mesh, null for none (an outline of fewer than three points).
  GpuPrimitive? mesh;

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

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show compute, debugPrint, visibleForTesting;
import 'package:flutter/painting.dart';
import 'package:just_dart/just_dart.dart' show JustMatrix4, Matrix4;
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
import 'shapes/primitive_3d.dart';

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

  /// The shapes' meshes and materials.
  late final GraphicsShapes shapes = GraphicsShapes(
    renderer.uploader,
    models.read,
    inUse: _shapesInUse,
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
    if (_surfaces.length >= 4) _surfaces.remove(_surfaces.keys.first);
    return _surfaces[view] = renderer.device.createSurface(1, 1);
  }

  final RenderView _view = RenderView();
  final Matrix4 _scratch = Matrix4.identity();
  final Matrix4 _root = Matrix4.identity();
  double _alpha = 1;
  final List<_Proxy> _proxies = [];
  final List<_ShapeProxy> _shapeProxies = [];
  int _shapeRevision = -1;
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
        _dirty ||
        _pathsChanged()) {
      _rebuild(world);
    }
    _alpha = view.interpolation.clamp(0.0, 1.0);
    _checkCaptures(world);
    _follow();
    _followShapes();
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

  /// The largest version of the queries [_rebuild] reads.
  static int _queriesVersion(World world) => math.max(
    world.queryVersion(const [TransformComponent, ModelComponent]),
    world.queryVersion(const [TransformComponent, Primitive3D]),
  );

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
    if (identical(world, _world)) {
      for (final f in _proxies) {
        knownModels[f.transform] = f;
      }
      for (final f in _shapeProxies) {
        knownShapes[f.transform] = f;
      }
    } else {
      _seenUpdates = world.updateCount;
    }
    _world = world;
    _structureVersion = _queriesVersion(world);
    _dirty = false;
    _proxies.clear();
    scene.instances.clear();
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
          _proxies.add(known);
          scene.instances.addAll(known.instances);
          if (model != null) {
            model.data.bounds.transformInto(gltfToEngine, component.bounds);
          }
          continue;
        }
        final proxy = _Proxy(transform, component, path, model)
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
        if (!archetype.entityAt(row).isActiveInHierarchy) continue;
        final transform = transforms[row] as TransformComponent;
        final shape = column[row] as Primitive3D;
        final known = knownShapes[transform];
        if (known != null && identical(known.shape, shape)) {
          _shapeProxies.add(known);
          final instance = known.instance;
          if (instance != null) scene.instances.add(instance);
          continue;
        }
        // Made at the next follow, with its mesh.
        _shapeProxies.add(
          _ShapeProxy(transform, shape)
            ..carryFrom(known ?? knownModels[transform]),
        );
      }
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
      final metres = shape.tileInMetres && shape.texture.isNotEmpty;
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

  /// Entity space from each instance's primitive.
  final List<Matrix4> locals = [];

  /// An animated model's player, pose and blending scratch.
  AnimationPlayerComponent? player;
  PosedModel? posed;
  PlayerScratch? scratch;
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

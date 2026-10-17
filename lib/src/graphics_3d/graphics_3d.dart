import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:just_graphics_engine/gpu.dart';
import 'package:just_graphics_engine/renderer.dart';

import '../core/core.dart';
import '../subsystems/assets/assets.dart';
import '../subsystems/timeline/timeline.dart';
import 'animation_system.dart';
import 'graphics_components.dart';
import 'graphics_definitions.dart';
import 'graphics_models.dart';
import 'graphics_scene_renderer.dart';
import 'shapes/shape_components.dart';
import 'shapes/shape_definitions.dart';
import 'skeletal_animation_target.dart';
import 'skeletal_clip_track.dart';

/// 3-D graphics for an engine. Give one to the engine and its 3-D
/// components — [ModelComponent], [LightComponent],
/// [EnvironmentComponent], [AnimationPlayerComponent], [SocketComponent]
/// and the shapes from [Cube3D] to [Polygon3D] — are saved, loaded,
/// offered in the editor's 3-D scenes and drawn:
///
/// ```dart
/// Engine(config: EngineConfig(graphics3D: Graphics3D()));
/// ```
///
/// with Flutter GPU switched on in each platform's runner (see the README).
///
/// A game without one is 2-D only: it makes no GPU device and loads no
/// shaders, and a scene holding 3-D components fails to load, saying so.
///
/// As the engine is made it registers the components, and how animator
/// graphs and timelines play clips on a model's skeleton. As the engine
/// initializes it makes the GPU device and the renderer
/// (just_graphics_engine), loads models for the asset manager
/// ([AssetType.model]), adds a [GraphicsSceneRenderer] to the engine's
/// frame and an [AnimationSystem3D] to its world.
///
/// Where Flutter GPU can't draw — the web, Impeller turned off, Android on
/// OpenGL ES, a plain `flutter test` — the game runs anyway: scenes and
/// models load (models for their bounds), the 3-D view shows a short note,
/// [unsupportedReason] says why and [onUnsupported] hears it once.
final class Graphics3D implements RefreshableExtension, EngineService {
  /// 3-D graphics drawn with [device], or with the platform's GPU when that
  /// is null, at [renderScale] of the physical resolution.
  Graphics3D({
    GpuDevice? device,
    this.renderScale = 1.0,
    this.onUnsupported,
    bool? keepEdges,
  }) : _device = device,
       keepEdges = keepEdges ?? kDebugMode;

  /// Registers the 3-D components into [context], so scenes holding them
  /// load and save — for tools that read and write 3-D scenes without
  /// drawing them. Giving the engine a [Graphics3D] does this already.
  static void registerSchemas(EngineContext context) {
    context.definitions
      ..registerAll(GraphicsSchemas.all, ifAbsent: true)
      ..registerAll(ShapeSchemas.all, ifAbsent: true);
    _registerPlayback(context);
  }

  // Animator graphs and timelines play on a model's skeleton.
  static void _registerPlayback(EngineContext context) {
    context.animationTargets.register(const SkeletalAnimationTarget());
    context.trackKinds.register(
      SkeletalClipTrack.kindId,
      SkeletalClipTrack.fromJson,
      offer: const TimelineTrackOffer('Skeletal clips', SkeletalClipTrack.new),
    );
  }

  final GpuDevice? _device;

  /// Fraction of the physical resolution rendered; see
  /// [GraphicsSceneRenderer.renderScale].
  final double renderScale;

  /// Told once, as the engine initializes, why 3-D is not drawn here.
  final void Function(String reason)? onUnsupported;

  /// Whether meshes keep their edges for lines over the scene (an editor's
  /// wireframe and selection outline): on in a debug build, where an
  /// editor runs, off in a release, which never draws them.
  final bool keepEdges;

  Engine? _engine;
  Renderer3D? _renderer;
  GraphicsModels? _models;
  GraphicsSceneRenderer? _scene;
  AnimationSystem3D? _animations;
  GraphicsModelLoader? _loader;
  String? _unsupportedReason;

  /// Why 3-D is not drawn, or null when it is (or the engine has not
  /// initialized yet).
  String? get unsupportedReason => _unsupportedReason;

  /// Whether there is a GPU to draw with.
  bool get isSupported => _unsupportedReason == null;

  /// Whether the engine started it: [renderer], [models] and
  /// [sceneRenderer] are there.
  bool get isStarted => _models != null;

  /// The renderer; throws before the engine initializes.
  Renderer3D get renderer => _renderer ?? (throw StateError(_notStarted));

  /// The engine's models; throws before the engine initializes.
  GraphicsModels get models => _models ?? (throw StateError(_notStarted));

  /// What draws the engine's world; throws before the engine initializes.
  GraphicsSceneRenderer get sceneRenderer =>
      _scene ?? (throw StateError(_notStarted));

  static const String _notStarted =
      'Graphics3D has not started: give it to the engine '
      '(EngineConfig(graphics3D: ...)) and initialize the engine.';

  // ── ContextExtension ──────────────────────────────────────────────────

  /// `graphics_3d`: what the engine knows it by, as an extension and as a
  /// service.
  @override
  String get id => 'graphics_3d';

  /// Registers the 3-D components, and how animator graphs and timelines
  /// play clips on a skeleton ([registerSchemas]).
  @override
  void install(EngineContext context) => registerSchemas(context);

  /// Registers the 3-D components' definitions and playback again, after a
  /// hot reload.
  @override
  void refresh(EngineContext context) {
    context.definitions
      ..refresh(GraphicsSchemas.all)
      ..refresh(ShapeSchemas.all);
    _registerPlayback(context);
  }

  // ── EngineService ─────────────────────────────────────────────────────

  /// Makes the GPU device (or, without one, a null device), the renderer
  /// and the models; registers the model loader with the asset manager;
  /// adds a [GraphicsSceneRenderer] to the engine's frame and an
  /// [AnimationSystem3D] to its world.
  @override
  Future<void> start(ServiceContext context) async {
    final engine = _engine = context.engine;
    String? reason;
    var renderer = await Renderer3D.tryCreate(
      device: _device,
      onUnsupported: (r) => reason = r,
    );
    if (renderer == null) {
      final why = _unsupportedReason = reason ?? 'There is no GPU device.';
      debugPrint('just_game_engine: 3D is off. $why');
      // Draws nothing, but scenes and models still load.
      renderer = await Renderer3D.create(
        NullGpuDevice(shaders: rendererNullShaders),
      );
      onUnsupported?.call(why);
    }
    _renderer = renderer..uploader.keepEdges = keepEdges;
    final models = _models = GraphicsModels(
      engine.assets.bundle,
      renderer.uploader,
    );
    engine.assets.registerLoader(
      AssetType.model,
      _loader = GraphicsModelLoader(models),
    );
    models.listeners.add(_modelReloaded);
    final scene = _scene = GraphicsSceneRenderer(
      engine: engine,
      renderer: renderer,
      models: models,
      unsupportedReason: _unsupportedReason,
    )..renderScale = renderScale;
    engine.rendering.addSceneRenderer(scene);
    engine.world.addSystem(_animations = AnimationSystem3D(models));
  }

  /// A model was loaded again: the engine's `ModelAsset` takes the new
  /// file, then 3-D physics rebuilds the colliders made from it.
  Future<void> _modelReloaded(String path) async {
    final engine = _engine;
    if (engine == null) return;
    final asset = engine.assets.get<GraphicsModelAsset>(path);
    if (asset != null) {
      try {
        await asset.reload();
      } catch (e) {
        debugPrint('just_game_engine: reloading "$path" failed ($e)');
        return;
      }
    }
    if (!identical(_engine, engine)) return;
    engine.physics3D?.reloadModel(path);
  }

  /// Takes out what [start] put in — the scene renderer, the animation
  /// system, the model loader — and lets go of the renderer and the
  /// models: [isStarted] is false again.
  @override
  Future<void> stop() async {
    final engine = _engine;
    final scene = _scene;
    if (scene != null) {
      engine?.rendering.removeSceneRenderer(scene);
      scene.dispose();
    }
    final animations = _animations;
    if (animations != null && engine?.isDisposed == false) {
      engine?.world.removeSystem(animations);
    }
    final loader = _loader;
    if (loader != null) {
      engine?.assets.unregisterLoader(AssetType.model, loader);
    }
    _models?.listeners.remove(_modelReloaded);
    _scene = null;
    _animations = null;
    _loader = null;
    _models = null;
    _renderer = null;
    _engine = null;
  }
}

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:just_graphics_engine/gpu.dart';
import 'package:just_graphics_engine/renderer.dart';

import '../../ecs/ecs.dart';
import '../../assets/assets.dart';
import '../../services/services.dart';
import '../../timeline/timeline.dart';
import 'animation_3d_system.dart';
import 'model_components.dart';
import 'graphics_3d_definitions.dart';
import 'lighting/lighting_3d_definitions.dart';
import 'materials/material_3d_definitions.dart';
import 'graphics_3d_models.dart';
import 'graphics_3d_scene_renderer.dart';
import 'shapes/shape_3d_components.dart';
import 'shapes/shape_3d_definitions.dart';
import 'skeletal_animation_target.dart';
import 'skeletal_clip_track.dart';
import '../../animation/animation_context.dart';

/// 3-D graphics for an engine. Give one to the engine and its 3-D
/// components — [ModelComponent], [Light3DComponent],
/// [EnvironmentComponent], [AnimationPlayerComponent], [SocketComponent]
/// and the shapes from [Cube3DComponent] to [Polygon3DComponent] — are saved, loaded,
/// offered in the editor's 3-D scenes and drawn:
///
/// ```dart
/// Engine(config: EngineConfig(services: [Graphics3D()]));
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
/// ([AssetType.model]), adds a [Graphics3DSceneRenderer] to the engine's
/// frame and an [Animation3DSystem] to its world.
///
/// Where Flutter GPU can't draw — the web, Impeller turned off, Android on
/// OpenGL ES, a plain `flutter test` — the game runs anyway: scenes and
/// models load (models for their bounds), the 3-D view shows a short note,
/// [unsupportedReason] says why and [onUnsupported] hears it once.
final class Graphics3D implements RefreshableExtension, SceneCacheService {
  /// 3-D graphics drawn with [device], or with the platform's GPU when that
  /// is null, at [renderScale] of the physical resolution.
  Graphics3D({
    GpuDevice? device,
    this.renderScale = 1.0,
    this.onUnsupported,
    bool? keepEdges,
  }) : _device = device,
       keepEdges = keepEdges ?? kDebugMode;

  /// Registers the 3-D components into [context], with the field type the
  /// material overrides are saved through, so scenes holding them load and
  /// save — for tools that read and write 3-D scenes without drawing them.
  /// Giving the engine a [Graphics3D] does this already.
  static void registerDefinitions(EngineContext context) {
    context.fieldTypes.registerAll(
      Material3DDefinitions.fieldTypes,
      ifAbsent: true,
    );
    context.definitions.registerAll(_definitions, ifAbsent: true);
    _registerPlayback(context);
  }

  // Every 3-D graphics component, in the order an editor lists them.
  static List<ComponentDefinition> get _definitions => [
    Graphics3DDefinitions.model,
    ...Material3DDefinitions.all,
    ...Lighting3DDefinitions.all,
    Graphics3DDefinitions.animationPlayer,
    Graphics3DDefinitions.socket,
    ...Shape3DDefinitions.all,
  ];

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
  /// [Graphics3DSceneRenderer.renderScale].
  final double renderScale;

  /// Told once, as the engine initializes, why 3-D is not drawn here.
  final void Function(String reason)? onUnsupported;

  /// Whether meshes keep their edges for lines over the scene (an editor's
  /// wireframe and selection outline): on in a debug build, where an
  /// editor runs, off in a release, which never draws them.
  final bool keepEdges;

  GameEngine? _engine;
  Renderer3D? _renderer;
  Graphics3DModels? _models;
  Graphics3DSceneRenderer? _scene;
  Animation3DSystem? _animations;
  Graphics3DModelLoader? _loader;
  String? _unsupportedReason;

  /// Why 3-D is not drawn, or null when it is (or the engine has not
  /// initialized yet).
  String? get unsupportedReason => _unsupportedReason;

  /// Whether there is a GPU to draw with.
  bool get isSupported => _unsupportedReason == null;

  /// Whether the engine started it: [renderer], [models] and
  /// [sceneRenderer] are there.
  bool get isStarted => _models != null;

  /// Lets go of the models, 3-D material files and maps nothing in the
  /// engine's world draws with ([Graphics3DSceneRenderer.releaseUnused]);
  /// `Engine.releaseUnused` asks, after a level change. Nothing before the
  /// engine starts it.
  @override
  void releaseUnused() => _scene?.releaseUnused();

  /// The renderer; throws before the engine initializes.
  Renderer3D get renderer => _renderer ?? (throw StateError(_notStarted));

  /// The engine's models; throws before the engine initializes.
  Graphics3DModels get models => _models ?? (throw StateError(_notStarted));

  /// What draws the engine's world; throws before the engine initializes.
  Graphics3DSceneRenderer get sceneRenderer =>
      _scene ?? (throw StateError(_notStarted));

  static const String _notStarted =
      'Graphics3D has not started: give it to the engine '
      '(EngineConfig(services: [Graphics3D()])) and initialize the engine.';

  // ── ContextExtension ──────────────────────────────────────────────────

  /// `graphics_3d`: what the engine knows it by, as an extension and as a
  /// service.
  @override
  String get id => 'graphics_3d';

  /// Registers the 3-D components, and how animator graphs and timelines
  /// play clips on a skeleton ([registerDefinitions]).
  @override
  void install(EngineContext context) => registerDefinitions(context);

  /// Registers the 3-D components' definitions and playback again, after a
  /// hot reload.
  @override
  void refresh(EngineContext context) {
    context.fieldTypes.registerAll(
      Material3DDefinitions.fieldTypes,
      ifAbsent: true,
    );
    context.definitions.refresh(_definitions);
    _registerPlayback(context);
  }

  // ── EngineService ─────────────────────────────────────────────────────

  /// Makes the GPU device (or, without one, a null device), the renderer
  /// and the models; registers the model loader with the asset manager;
  /// adds a [Graphics3DSceneRenderer] to the engine's frame and an
  /// [Animation3DSystem] to its world.
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
      // Draws nothing, but scenes and models still load. It keeps no log
      // (a whole session would grow it), and decodes no texture nothing
      // will draw.
      renderer = await Renderer3D.create(
        NullGpuDevice(shaders: rendererNullShaders, record: false),
      );
      renderer.uploader.decodeTextures = false;
      onUnsupported?.call(why);
    }
    _renderer = renderer..uploader.keepEdges = keepEdges;
    final models = _models = Graphics3DModels(
      engine.assets.bundle,
      renderer.uploader,
    );
    engine.assets.registerLoader(
      AssetType.model,
      _loader = Graphics3DModelLoader(models),
    );
    context.context.graphics3DModels = models;
    models.reloadListeners.add(_modelReloaded);
    final scene = _scene = Graphics3DSceneRenderer(
      world: () => engine.world,
      renderer: renderer,
      models: models,
      unsupportedReason: _unsupportedReason,
      frame: () => engine.rendering.drawingFrame,
    )..renderScale = renderScale;
    engine.rendering.addSceneRenderer(scene);
    engine.world.addSystem(_animations = Animation3DSystem(models));
  }

  /// A model [Graphics3DModels.reload] asked for has loaded again: the
  /// engine's `ModelAsset` takes the new file, then 3-D physics rebuilds
  /// the colliders made from it — once a reload.
  Future<void> _modelReloaded(String path) async {
    final engine = _engine;
    if (engine == null) return;
    final asset = engine.assets.get<Graphics3DModelAsset>(path);
    if (asset != null) {
      try {
        await asset.reload();
      } catch (e) {
        debugPrint('just_game_engine: reloading "$path" failed ($e)');
        return;
      }
    }
    if (!identical(_engine, engine)) return;
    engine.assets.notifyReloaded(path);
  }

  /// Takes out what [start] put in — the scene renderer, the animation
  /// system, the model loader — and lets go of the renderer and the
  /// models, the GPU models they hold among them: [isStarted] is false
  /// again.
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
    final models = _models;
    if (models != null) {
      models.reloadListeners.remove(_modelReloaded);
      if (identical(engine?.context.graphics3DModels, models)) {
        engine?.context.graphics3DModels = null;
      }
      // The model assets the engine still holds keep the models: their GPU
      // side goes now.
      models.clear();
    }
    _scene = null;
    _animations = null;
    _loader = null;
    _models = null;
    _renderer = null;
    _engine = null;
  }
}

/// The engine's 3-D graphics.
extension EngineGraphics3D on GameEngine {
  /// The [Graphics3D] given in `EngineConfig.services`, or null for a 2-D
  /// game. Its renderer, models and scene renderer are there once the
  /// engine has initialized; [Graphics3D.unsupportedReason] says why
  /// nothing is drawn where Flutter GPU can't.
  Graphics3D? get graphics3D => maybeService<Graphics3D>();
}

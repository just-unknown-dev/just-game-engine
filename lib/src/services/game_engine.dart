/// What a service sees of the engine it runs in.
library;

import 'package:just_audio_engine/just_audio_engine.dart' show AudioEngine;
import 'package:just_inputs/just_inputs.dart' show InputService;

import '../assets/asset_manager.dart';
import '../camera/camera_engine.dart';
import '../ecs/ecs.dart';
import '../rendering/rendering_engine.dart';
import 'engine_service.dart';

/// The engine as an [EngineService] sees it ([ServiceContext.engine]): its
/// world, context, assets, rendering, camera, input and audio, and its other
/// services. `Engine` implements it.
///
/// It names only what sits below the services, so `Graphics3D` and
/// `Physics3D` use their engine through it and import nothing of `Engine`,
/// which wires them in. A service that needs more of its engine (its clock,
/// music or storage) casts: `context.engine as Engine`.
abstract interface class GameEngine {
  /// What the engine knows: component definitions, loaders, registries and
  /// the state packages keep per engine.
  EngineContext get context;

  /// The ECS world the game runs in, reading from [context].
  World get world;

  /// Loads, caches and releases the game's images, audio, text and models.
  AssetManager get assets;

  /// Draws the game.
  RenderingEngine get rendering;

  /// The output camera and the brain that drives it. Throws an
  /// `EngineNotReadyError` until the engine is initialized.
  CameraEngine get camera;

  /// The game's input: devices, the input asset, players. Throws an
  /// `EngineNotReadyError` until the engine is initialized.
  InputService get input;

  /// Sound and music. Throws an `EngineNotReadyError` until the engine is
  /// initialized.
  AudioEngine get audio;

  /// Whether the engine is ready: initialized, running or paused.
  bool get isInitialized;

  /// Whether the engine has been disposed — true from the first moment of
  /// its disposal.
  bool get isDisposed;

  /// The services the engine runs, this one among them.
  ServiceHost get services;

  /// The service of type [T]. Throws a [StateError] saying how to add it
  /// when the engine has none.
  T service<T extends EngineService>();

  /// The service of type [T], or null.
  T? maybeService<T extends EngineService>();
}

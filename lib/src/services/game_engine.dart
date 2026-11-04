/// What a service sees of the engine it runs in.
library;

import '../assets/asset_manager.dart';
import '../ecs/ecs.dart';
import '../rendering/rendering_engine.dart';
import 'engine_service.dart';

/// The engine as an [EngineService] sees it ([ServiceContext.engine]): its
/// world, context, assets and rendering, and its other services. `Engine`
/// implements it.
///
/// It is all `Graphics3D` and `Physics3D` use of their engine, so they sit
/// below `Engine`, which wires them in, and import none of it. A service
/// that needs more of its engine casts: `context.engine as Engine`.
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

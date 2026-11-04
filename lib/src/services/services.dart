/// Services: what a game adds to its engine, started and stopped with it
/// (`EngineService`, `ServiceHost`), and the engine as a service sees it
/// (`GameEngine`).
library;

export 'engine_service.dart'
    show EngineService, SceneCacheService, ServiceContext, ServiceHost;
export 'game_engine.dart';

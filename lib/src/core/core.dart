/// Core Engine Systems
///
/// This library exports all core engine components including the main engine,
/// game loop, time management, and system coordination.
library;

export 'engine.dart';
export 'engine_config.dart';
export 'register_default_systems.dart';
export '../ecs/base/engine_context.dart';
export 'engine_plugin.dart';
export 'game_layers.dart';
export 'game_widget.dart';
export 'engine_service.dart' show EngineService, ServiceContext, ServiceHost;
export 'game_loop.dart';
export 'time_manager.dart';
export 'system_manager.dart';
export 'lifecycle.dart';
export 'compute_helper.dart';
export '../foundation/world_axes.dart';
export '../foundation/dimensions.dart';
export '../foundation/easing.dart';

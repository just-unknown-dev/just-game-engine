/// Shared abstract contracts between the ECS layer and subsystems.
///
/// Both ECS systems and subsystem implementations import from here,
/// ensuring the dependency arrow points towards abstractions.
library;

export 'game_camera.dart';
export 'rendering_interfaces.dart';

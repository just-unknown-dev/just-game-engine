library;

import '../../ecs.dart';
import '../../../math/vector3.dart';

/// Marks an entity as a checkpoint / respawn point.
///
/// Attach this to a trigger-zone entity.  The [CheckpointSystem] scans all
/// player entities (tagged with the [playerTag]) and activates the nearest
/// checkpoint the player overlaps.
///
/// Usage:
/// ```dart
/// world.createEntity([
///   TransformComponent(position: Vector3.fromXY(400, 300)),
///   CheckpointComponent(respawnPosition: Vector3.fromXY(400, 260)),
/// ]);
/// ```
class CheckpointComponent extends Component {
  /// World-space position the player is moved to on respawn.
  Vector3 respawnPosition;

  /// Activation radius in world units.
  final double radius;

  /// Whether this checkpoint has already been activated.
  bool isActivated;

  /// Create a checkpoint component.
  CheckpointComponent({
    required this.respawnPosition,
    this.radius = 48.0,
    this.isActivated = false,
  });

  @override
  String toString() =>
      'Checkpoint(pos: $respawnPosition, activated: $isActivated)';
}

library;

import '../../../ecs/ecs.dart';

/// Marks an entity as a camera follow target.
///
/// Used by [CameraFollowSystem] to drive the camera toward this entity's
/// [TransformComponent] position each frame.
///
/// ```dart
/// world.addComponent(player, CameraFollowComponent());
/// world.addComponent(player, CameraFollowComponent(
///   lookaheadDistance: 120,
///   deadZoneWidth: 20,
///   deadZoneHeight: 15,
/// ));
/// ```
///
/// When multiple entities carry a [CameraFollowComponent],
/// [CameraFollowSystem] picks the one with the **lowest** [priority] value
/// as the single follow target.  If two or more entities share the same
/// lowest priority the system switches to multi-target mode and zooms to fit
/// all of them.
class CameraFollowComponent extends Component {
  /// Whether this component is active.
  bool enabled;

  /// Lookahead distance (world units) in the entity's movement direction.
  ///
  /// Requires a [VelocityComponent] on the same entity for the direction to
  /// be computed; otherwise no lookahead is applied.
  double lookaheadDistance;

  /// Horizontal half-extents of the dead zone (world units).
  ///
  /// The camera only starts moving when the entity drifts more than this
  /// amount horizontally from the current camera position.
  double deadZoneWidth;

  /// Vertical half-extents of the dead zone (world units).
  double deadZoneHeight;

  /// Lower values take precedence; entities with the same lowest priority
  /// trigger multi-target mode.
  int priority;

  CameraFollowComponent({
    this.enabled = true,
    this.lookaheadDistance = 80.0,
    this.deadZoneWidth = 0.0,
    this.deadZoneHeight = 0.0,
    this.priority = 0,
  });

  @override
  String toString() => 'CameraFollow(enabled: $enabled, priority: $priority)';
}

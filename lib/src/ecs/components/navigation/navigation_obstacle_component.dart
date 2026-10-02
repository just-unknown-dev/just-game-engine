library;

import '../../ecs.dart';

/// Marks an entity as a static obstacle for `FlowFieldSystem` pathfinding —
/// rasterized into the walkability grid as a circle of [radius] centered on
/// the entity's `TransformComponent.position`.
///
/// Deliberately a separate opt-in component rather than "any static
/// `PhysicsBodyComponent`": some static bodies (e.g. the player's own,
/// immovable-by-design body) must *not* become obstacles — the player is the
/// pathfinding target, and marking its own cell unwalkable would break the
/// field.
class NavigationObstacleComponent extends Component {
  /// Radius of the blocked circle, in world units: grid cells whose centres
  /// lie within it are unwalkable.
  final double radius;

  /// An obstacle of [radius] world units around the entity's position.
  NavigationObstacleComponent({required this.radius});
}

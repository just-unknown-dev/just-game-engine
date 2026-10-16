/// Marks an entity as hittable by the ray casts of `RaycastSystem`.
library;

import '../../ecs.dart';

/// Marks an entity as participating in ray-cast queries and defines its
/// circular collision shape.
///
/// Add this component to any entity that should be hittable by rays.
///
/// ```dart
/// entity.addComponent(RaycastColliderComponent(radius: 14.0, tag: 'enemy'));
/// ```
class RaycastColliderComponent extends Component {
  /// Collision radius in world units (used for circle colliders).
  double radius;

  /// Width for AABB colliders (0 = use [radius] as circle).
  double width;

  /// Height for AABB colliders (0 = use [radius] as circle).
  double height;

  /// Optional semantic tag used for filtering ray queries (e.g. `'enemy'`).
  String? tag;

  /// Whether this collider blocks `RaycastSystem.hasLineOfSight`. Ray casts
  /// and traces hit it either way.
  bool isBlocker;

  /// Whether rays can bounce off this surface.
  bool isReflective;

  /// Energy coefficient applied to the reflected ray's distance (0–1).
  double reflectivity;

  /// A collider that blocks line of sight and does not reflect: a circle
  /// of [radius], or a box when [width] or [height] is set. With none of
  /// the three above 0 — the defaults — no ray hits it.
  RaycastColliderComponent({
    this.radius = 0,
    this.width = 0,
    this.height = 0,
    this.tag,
    this.isBlocker = true,
    this.isReflective = false,
    this.reflectivity = 0.8,
  });
}

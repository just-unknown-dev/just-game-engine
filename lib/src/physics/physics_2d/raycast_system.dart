/// Ray Casting
///
/// Provides ray-based spatial queries for hit detection and line-of-sight
/// checks against [RaycastColliderComponent]s.
///
/// Core types:
/// - [Ray]                      — origin + direction + max-distance descriptor
/// - [RaycastColliderComponent] — ECS component that marks an entity as hittable
/// - [RaycastHit]               — single intersection result
/// - [RaycastSystem]            — ECS system exposing [RaycastSystem.raycast],
///   [RaycastSystem.raycastAll] and [RaycastSystem.hasLineOfSight]
///
/// Multi-bounce traces off reflective colliders are `RayTracer`'s.
library;

import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:just_physics_engine/just_physics_engine.dart' show Ray;

import '../../ecs/ecs.dart';
import 'raycast_collider_component.dart';

// ===========================================================================
// RaycastHit
// ===========================================================================

/// The result of a single ray–entity intersection.
class RaycastHit {
  /// The entity that was intersected.
  final Entity entity;

  /// World-space point at which the ray entered the collider.
  final Offset point;

  /// Distance from the ray's origin to [point] (world units).
  final double distance;

  /// Outward surface normal at [point] (points away from the entity centre,
  /// length ≈ 1).
  final Offset normal;

  /// A hit on [entity] at [point], [distance] along the ray, with surface
  /// normal [normal].
  const RaycastHit({
    required this.entity,
    required this.point,
    required this.distance,
    required this.normal,
  });

  @override
  String toString() =>
      'RaycastHit(entity=${entity.name}, '
      'dist=${distance.toStringAsFixed(1)}, '
      'point=(${point.dx.toStringAsFixed(1)}, ${point.dy.toStringAsFixed(1)}))';
}

// ===========================================================================
// RaycastSystem
// ===========================================================================

/// ECS system that provides ray-vs-collider intersection tests against every
/// entity that has a [TransformComponent] and a [RaycastColliderComponent]
/// and is active in the hierarchy.
///
/// This system performs **no automatic per-frame work** — it is a pure query
/// API called on-demand (e.g. when a bullet is fired). Each query walks the
/// colliders' columns and makes nothing for a collider it misses.
///
/// Usage:
/// ```dart
/// final raycastSys = RaycastSystem();
/// world.addSystem(raycastSys);
///
/// final ray = Ray(origin: playerPos, direction: aimDir);
/// final hit = raycastSys.raycast(ray, filterTag: 'enemy');
/// if (hit != null) { /* apply damage */ }
/// ```
class RaycastSystem extends System {
  @override
  List<Type> get requiredComponents => const [
    TransformComponent,
    RaycastColliderComponent,
  ];

  /// This system is query-only; no per-frame logic is required.
  @override
  void update(double deltaTime) {}

  /// How far short of its end a line of sight still counts a blocker: a
  /// collider whose edge is exactly at the end does not block it.
  static const double _losEpsilon = 1e-6;

  // The last hit's normal, from [_intersect].
  double _nx = 0, _ny = 0;

  // ── Geometry ───────────────────────────────────────────────────────────

  /// The smallest `t` (0 to [maxDist]) at which the ray from ([ox], [oy])
  /// along the unit ([dx], [dy]) enters [collider] centred at ([cx], [cy])
  /// — or, starting inside it, leaves it — with the outward normal there in
  /// [_nx], [_ny]; -1 on a miss, and always for a collider with no size at
  /// all, which has nothing to hit.
  ///
  /// A circle when the collider has a radius and no width or height,
  /// otherwise an axis-aligned box (a missing side its radius either way).
  double _intersect(
    double ox,
    double oy,
    double dx,
    double dy,
    double cx,
    double cy,
    RaycastColliderComponent collider,
    double maxDist,
  ) {
    final radius = collider.radius;
    final width = collider.width, height = collider.height;
    // No radius, width or height: a point, not a shape.
    if (radius <= 0 && width <= 0 && height <= 0) return -1;

    if (radius > 0 && width == 0 && height == 0) {
      // Circle: (o + d·t − c)² = r², with |d| = 1.
      final ocx = ox - cx, ocy = oy - cy;
      final b = 2.0 * (ocx * dx + ocy * dy);
      final c = ocx * ocx + ocy * ocy - radius * radius;
      final discriminant = b * b - 4.0 * c;
      if (discriminant < 0) return -1;
      final sqrtD = math.sqrt(discriminant);
      final t0 = (-b - sqrtD) / 2.0;
      final t1 = (-b + sqrtD) / 2.0;
      // The nearer entry; the exit when the origin is inside.
      final t = t0 >= 0 ? t0 : (t1 >= 0 ? t1 : -1.0);
      if (t < 0 || t > maxDist) return -1;
      _nx = (ox + dx * t - cx) / radius;
      _ny = (oy + dy * t - cy) / radius;
      return t;
    }

    // Box, by the slab method.
    final halfW = width > 0 ? width / 2 : radius;
    final halfH = height > 0 ? height / 2 : radius;
    final left = cx - halfW, right = cx + halfW;
    final top = cy - halfH, bottom = cy + halfH;
    // A ray parallel to a pair of sides never crosses them: it is between
    // them all along or never. (Dividing by its zero component instead gave
    // 0 × ∞ = NaN for a ray running exactly along a side, and the far side.)
    var txMin = double.negativeInfinity, txMax = double.infinity;
    if (dx.abs() > 1e-12) {
      txMin = (left - ox) / dx;
      txMax = (right - ox) / dx;
      if (txMin > txMax) {
        final tmp = txMin;
        txMin = txMax;
        txMax = tmp;
      }
    } else if (ox < left || ox > right) {
      return -1;
    }
    var tyMin = double.negativeInfinity, tyMax = double.infinity;
    if (dy.abs() > 1e-12) {
      tyMin = (top - oy) / dy;
      tyMax = (bottom - oy) / dy;
      if (tyMin > tyMax) {
        final tmp = tyMin;
        tyMin = tyMax;
        tyMax = tmp;
      }
    } else if (oy < top || oy > bottom) {
      return -1;
    }
    // No overlap of the slab intervals: a miss.
    if (txMin > tyMax || tyMin > txMax) return -1;
    final tEnter = math.max(txMin, tyMin);
    final tExit = math.min(txMax, tyMax);
    if (tExit < 0) return -1; // Behind the ray.
    // Entering when the ray starts outside, leaving when it starts inside.
    final t = tEnter >= 0 ? tEnter : tExit;
    if (t > maxDist) return -1;
    // The normal of the side entered.
    if (tEnter == txMin) {
      _nx = dx > 0 ? -1.0 : 1.0;
      _ny = 0.0;
    } else {
      _nx = 0.0;
      _ny = dy > 0 ? -1.0 : 1.0;
    }
    return t;
  }

  /// Whether ([px], [py]) is inside [collider] centred at ([cx], [cy]) —
  /// its edge counts as inside.
  static bool _contains(
    double px,
    double py,
    double cx,
    double cy,
    RaycastColliderComponent collider,
  ) {
    final radius = collider.radius;
    final width = collider.width, height = collider.height;
    if (radius <= 0 && width <= 0 && height <= 0) return false;
    if (radius > 0 && width == 0 && height == 0) {
      final x = px - cx, y = py - cy;
      return x * x + y * y <= radius * radius;
    }
    final halfW = width > 0 ? width / 2 : radius;
    final halfH = height > 0 ? height / 2 : radius;
    return (px - cx).abs() <= halfW && (py - cy).abs() <= halfH;
  }

  // ── Public query API ───────────────────────────────────────────────────

  /// Cast [ray] and return the **closest** hit entity, or `null` if no entity
  /// is intersected within `ray.maxDistance`.
  ///
  /// [filterTag] — when non-null only entities whose [RaycastColliderComponent.tag]
  /// matches are considered.
  RaycastHit? raycast(Ray ray, {String? filterTag}) {
    final ox = ray.origin.dx, oy = ray.origin.dy;
    final dx = ray.direction.dx, dy = ray.direction.dy;
    final maxDist = ray.maxDistance;
    RaycastHit? closest;
    for (final archetype in world.queryArchetypes(requiredComponents)) {
      final transforms = archetype.getColumn(TransformComponent)!;
      final colliders = archetype.getColumn(RaycastColliderComponent)!;
      for (var row = 0; row < transforms.length; row++) {
        final collider = colliders[row] as RaycastColliderComponent;
        if (filterTag != null && collider.tag != filterTag) continue;
        final entity = archetype.entityAt(row);
        if (!entity.isActiveInHierarchy) continue;
        final centre = (transforms[row] as TransformComponent).position;
        final t = _intersect(
          ox,
          oy,
          dx,
          dy,
          centre.x,
          centre.y,
          collider,
          maxDist,
        );
        if (t < 0 || (closest != null && t >= closest.distance)) continue;
        closest = RaycastHit(
          entity: entity,
          point: Offset(ox + dx * t, oy + dy * t),
          distance: t,
          normal: Offset(_nx, _ny),
        );
      }
    }
    return closest;
  }

  /// Cast [ray] and return **all** intersected entities, sorted nearest-first.
  ///
  /// [filterTag] behaves the same as in [raycast].
  List<RaycastHit> raycastAll(Ray ray, {String? filterTag}) {
    final ox = ray.origin.dx, oy = ray.origin.dy;
    final dx = ray.direction.dx, dy = ray.direction.dy;
    final maxDist = ray.maxDistance;
    final hits = <RaycastHit>[];
    for (final archetype in world.queryArchetypes(requiredComponents)) {
      final transforms = archetype.getColumn(TransformComponent)!;
      final colliders = archetype.getColumn(RaycastColliderComponent)!;
      for (var row = 0; row < transforms.length; row++) {
        final collider = colliders[row] as RaycastColliderComponent;
        if (filterTag != null && collider.tag != filterTag) continue;
        final entity = archetype.entityAt(row);
        if (!entity.isActiveInHierarchy) continue;
        final centre = (transforms[row] as TransformComponent).position;
        final t = _intersect(
          ox,
          oy,
          dx,
          dy,
          centre.x,
          centre.y,
          collider,
          maxDist,
        );
        if (t < 0) continue;
        hits.add(
          RaycastHit(
            entity: entity,
            point: Offset(ox + dx * t, oy + dy * t),
            distance: t,
            normal: Offset(_nx, _ny),
          ),
        );
      }
    }
    hits.sort((a, b) => a.distance.compareTo(b.distance));
    return hits;
  }

  /// Returns `true` if there is **no** blocking collider between [from] and
  /// [to] (line-of-sight / LOS check).
  ///
  /// Only colliders that block ([RaycastColliderComponent.isBlocker]) count,
  /// and only where they stand between the two points: a collider round
  /// [from] (the viewer's own) or round [to] (the target's) is looked
  /// through, as is one whose edge is exactly at [to]. [ignoreTag] —
  /// colliders with this tag are skipped too; [ignore] — and these
  /// entities'. The same point twice sees itself.
  bool hasLineOfSight(
    Offset from,
    Offset to, {
    String? ignoreTag,
    Set<Entity>? ignore,
  }) {
    final maxDist = (to - from).distance;
    if (maxDist == 0) return true; // Nothing lies between a point and itself.
    final ox = from.dx, oy = from.dy;
    final dx = (to.dx - ox) / maxDist, dy = (to.dy - oy) / maxDist;
    final reach = maxDist - _losEpsilon;
    for (final archetype in world.queryArchetypes(requiredComponents)) {
      final transforms = archetype.getColumn(TransformComponent)!;
      final colliders = archetype.getColumn(RaycastColliderComponent)!;
      for (var row = 0; row < transforms.length; row++) {
        final collider = colliders[row] as RaycastColliderComponent;
        if (!collider.isBlocker) continue;
        if (ignoreTag != null && collider.tag == ignoreTag) continue;
        final entity = archetype.entityAt(row);
        if (!entity.isActiveInHierarchy) continue;
        if (ignore != null && ignore.contains(entity)) continue;
        final centre = (transforms[row] as TransformComponent).position;
        final cx = centre.x, cy = centre.y;
        // The viewer's own collider, or the target's.
        if (_contains(ox, oy, cx, cy, collider) ||
            _contains(to.dx, to.dy, cx, cy, collider)) {
          continue;
        }
        final t = _intersect(ox, oy, dx, dy, cx, cy, collider, reach);
        if (t >= 0) return false;
      }
    }
    return true;
  }
}

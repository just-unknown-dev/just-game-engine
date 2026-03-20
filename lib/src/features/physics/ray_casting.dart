/// Ray Casting and Ray Tracing
///
/// Provides ray-based spatial queries for hit detection, line-of-sight checks,
/// and multi-bounce ray tracing with surface reflections.
///
/// Core types:
/// - [Ray]                      — origin + direction + max-distance descriptor
/// - [RaycastColliderComponent] — ECS component that marks an entity as hittable
/// - [RaycastHit]               — single intersection result
/// - [RaycastSystem]            — ECS system exposing [castRay] / [castRayAll]
/// - [RayTrace] / [RayTracer]   — multi-bounce reflected trace
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ecs/ecs.dart';
import '../ecs/components/components.dart';

// ===========================================================================
// Ray
// ===========================================================================

/// A ray in 2-D world space with an origin, normalised direction, and maximum
/// travel distance.
class Ray {
  /// Starting point in world space.
  final Offset origin;

  /// Normalised direction vector (always length 1).
  final Offset direction;

  /// Maximum travel distance (world units). The ray ignores anything farther.
  final double maxDistance;

  /// Creates a ray from an [origin] toward [direction].
  ///
  /// [direction] is normalised automatically; passing [Offset.zero] falls back
  /// to the positive-x axis so no division-by-zero can occur.
  Ray({
    required this.origin,
    required Offset direction,
    this.maxDistance = 2000.0,
  }) : direction = _normalise(direction);

  /// Convenience constructor — builds a ray from [from] aimed at [to].
  ///
  /// If [maxDistance] is omitted the distance between the two points is used.
  factory Ray.fromPoints(Offset from, Offset to, {double? maxDistance}) {
    final delta = to - from;
    return Ray(
      origin: from,
      direction: delta,
      maxDistance: maxDistance ?? delta.distance,
    );
  }

  /// Returns the world-space point at parameter [t] (world units along the ray).
  Offset at(double t) => origin + direction * t;

  static Offset _normalise(Offset v) {
    final len = v.distance;
    return len > 1e-9 ? v / len : const Offset(1, 0);
  }
}

// ===========================================================================
// RaycastColliderComponent
// ===========================================================================

/// Marks an entity as participating in ray-cast queries and defines its
/// circular collision shape.
///
/// Add this component to any entity that should be hittable by rays.
///
/// ```dart
/// entity.addComponent(RaycastColliderComponent(radius: 14.0, tag: 'enemy'));
/// ```
class RaycastColliderComponent extends Component {
  /// Collision radius in world units.
  double radius;

  /// Optional semantic tag used for filtering ray queries (e.g. `'enemy'`).
  String? tag;

  /// When `true` the ray terminates on this surface.  When `false` the hit is
  /// recorded but the ray continues through.
  bool isBlocker;

  /// Whether rays can bounce off this surface.
  bool isReflective;

  /// Energy coefficient applied to the reflected ray's distance (0–1).
  double reflectivity;

  RaycastColliderComponent({
    required this.radius,
    this.tag,
    this.isBlocker = true,
    this.isReflective = false,
    this.reflectivity = 0.8,
  });
}

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
/// entity that has a [TransformComponent] and a [RaycastColliderComponent].
///
/// This system performs **no automatic per-frame work** — it is a pure query
/// API called on-demand (e.g. when a bullet is fired).
///
/// Usage:
/// ```dart
/// final raycastSys = RaycastSystem();
/// world.addSystem(raycastSys);
///
/// final ray = Ray(origin: playerPos, direction: aimDir);
/// final hit = raycastSys.castRay(ray, filterTag: 'enemy');
/// if (hit != null) { /* apply damage */ }
/// ```
class RaycastSystem extends System {
  @override
  List<Type> get requiredComponents => [
    TransformComponent,
    RaycastColliderComponent,
  ];

  /// This system is query-only; no per-frame logic is required.
  @override
  void update(double deltaTime) {}

  // ── Geometry helpers ───────────────────────────────────────────────────────

  /// Analytic ray–circle intersection.
  ///
  /// Returns the smallest positive `t` at which [ray] enters the circle
  /// centred at [centre] with the given [radius], or `null` on a miss or if
  /// the intersection lies beyond [maxDist].
  double? _rayCircle({
    required Offset origin,
    required Offset dir, // must be normalised
    required Offset centre,
    required double radius,
    required double maxDist,
  }) {
    // Vector from circle centre to ray origin
    final oc = origin - centre;

    // Quadratic coefficients (a = 1 because dir is normalised)
    final b = 2.0 * (oc.dx * dir.dx + oc.dy * dir.dy);
    final c = oc.dx * oc.dx + oc.dy * oc.dy - radius * radius;
    final discriminant = b * b - 4.0 * c;

    if (discriminant < 0) return null; // no intersection

    final sqrtD = math.sqrt(discriminant);
    final t0 = (-b - sqrtD) / 2.0;
    final t1 = (-b + sqrtD) / 2.0;

    // Prefer the nearer entry point; fall back to exit if origin is inside
    final tMin = (t0 >= 0) ? t0 : ((t1 >= 0) ? t1 : null);
    if (tMin == null || tMin > maxDist) return null;
    return tMin;
  }

  // ── Public query API ───────────────────────────────────────────────────────

  /// Cast [ray] and return the **closest** hit entity, or `null` if no entity
  /// is intersected within [ray.maxDistance].
  ///
  /// [filterTag] — when non-null only entities whose [RaycastColliderComponent.tag]
  /// matches are considered.
  RaycastHit? castRay(Ray ray, {String? filterTag}) {
    RaycastHit? closest;

    forEach((entity) {
      final collider = entity.getComponent<RaycastColliderComponent>()!;
      if (filterTag != null && collider.tag != filterTag) return;

      final centre = entity.getComponent<TransformComponent>()!.position;
      final t = _rayCircle(
        origin: ray.origin,
        dir: ray.direction,
        centre: centre,
        radius: collider.radius,
        maxDist: ray.maxDistance,
      );
      if (t == null) return;

      if (closest == null || t < closest!.distance) {
        final hitPoint = ray.at(t);
        final dist = collider.radius > 0 ? collider.radius : 1.0;
        final normal = (hitPoint - centre) / dist;
        closest = RaycastHit(
          entity: entity,
          point: hitPoint,
          distance: t,
          normal: normal,
        );
      }
    });

    return closest;
  }

  /// Cast [ray] and return **all** intersected entities, sorted nearest-first.
  ///
  /// [filterTag] behaves the same as in [castRay].
  List<RaycastHit> castRayAll(Ray ray, {String? filterTag}) {
    final hits = <RaycastHit>[];

    forEach((entity) {
      final collider = entity.getComponent<RaycastColliderComponent>()!;
      if (filterTag != null && collider.tag != filterTag) return;

      final centre = entity.getComponent<TransformComponent>()!.position;
      final t = _rayCircle(
        origin: ray.origin,
        dir: ray.direction,
        centre: centre,
        radius: collider.radius,
        maxDist: ray.maxDistance,
      );
      if (t == null) return;

      final hitPoint = ray.at(t);
      final dist = collider.radius > 0 ? collider.radius : 1.0;
      final normal = (hitPoint - centre) / dist;
      hits.add(
        RaycastHit(
          entity: entity,
          point: hitPoint,
          distance: t,
          normal: normal,
        ),
      );
    });

    hits.sort((a, b) => a.distance.compareTo(b.distance));
    return hits;
  }

  /// Returns `true` if there is **no** blocking collider between [from] and
  /// [to] (line-of-sight / LOS check).
  ///
  /// [ignoreTag] — entities with this tag are skipped (e.g. ignore the
  /// shooter's own collider).
  bool hasLineOfSight(Offset from, Offset to, {String? ignoreTag}) {
    final ray = Ray.fromPoints(from, to);
    final maxDist = (to - from).distance;

    bool blocked = false;
    forEach((entity) {
      if (blocked) return;
      final collider = entity.getComponent<RaycastColliderComponent>()!;
      if (ignoreTag != null && collider.tag == ignoreTag) return;
      if (!collider.isBlocker) return;

      final centre = entity.getComponent<TransformComponent>()!.position;
      final t = _rayCircle(
        origin: ray.origin,
        dir: ray.direction,
        centre: centre,
        radius: collider.radius,
        maxDist: maxDist,
      );
      if (t != null) blocked = true;
    });

    return !blocked;
  }
}

// ===========================================================================
// RayTrace / RayTracer
// ===========================================================================

/// A single path segment of a multi-bounce ray trace.
class RayTraceSegment {
  /// World-space start of this segment.
  final Offset from;

  /// World-space end of this segment (the hit point, or the ray terminus if
  /// [hit] is `null`).
  final Offset to;

  /// The intersection result at [to], or `null` if the ray missed everything.
  final RaycastHit? hit;

  const RayTraceSegment({required this.from, required this.to, this.hit});
}

/// Complete result of a [RayTracer.trace] call.
///
/// Contains every path segment produced during the multi-bounce trace.
class RayTrace {
  /// Ordered list of path segments (first = initial ray, last = final bounce
  /// or miss).
  final List<RayTraceSegment> segments;

  const RayTrace({required this.segments});

  /// Convenience: all non-null [RaycastHit]s across all segments.
  List<RaycastHit> get hits =>
      segments.map((s) => s.hit).whereType<RaycastHit>().toList();

  /// Total path length across all segments (world units).
  double get totalLength =>
      segments.fold(0.0, (sum, s) => sum + (s.to - s.from).distance);
}

/// Performs multi-bounce ray tracing against [RaycastColliderComponent] entities
/// that have [RaycastColliderComponent.isReflective] set to `true`.
///
/// Each bounce reflects the ray's direction around the surface normal and
/// multiplies the remaining distance budget by [RaycastColliderComponent.reflectivity].
///
/// Example:
/// ```dart
/// final tracer = RayTracer(raycastSystem: raycastSys, maxBounces: 3);
/// final trace = tracer.trace(Ray(origin: origin, direction: dir));
/// for (final seg in trace.segments) {
///   drawBeam(seg.from, seg.to, hitPoint: seg.hit?.point);
/// }
/// ```
class RayTracer {
  /// The [RaycastSystem] used to query each ray segment.
  final RaycastSystem raycastSystem;

  /// Maximum number of reflection bounces (0 = no bounces).
  final int maxBounces;

  /// Minimum surface reflectivity required to produce a bounce (0–1).
  final double minReflectivity;

  RayTracer({
    required this.raycastSystem,
    this.maxBounces = 3,
    this.minReflectivity = 0.1,
  });

  /// Trace [ray] through the world, bouncing off reflective surfaces.
  ///
  /// [filterTag] — when non-null only entities with a matching
  /// [RaycastColliderComponent.tag] are considered at each segment.
  RayTrace trace(Ray ray, {String? filterTag}) {
    final segments = <RayTraceSegment>[];
    var currentRay = ray;

    for (int bounce = 0; bounce <= maxBounces; bounce++) {
      final hit = raycastSystem.castRay(currentRay, filterTag: filterTag);

      if (hit == null) {
        // Ray reached max distance without hitting anything.
        segments.add(
          RayTraceSegment(
            from: currentRay.origin,
            to: currentRay.at(currentRay.maxDistance),
          ),
        );
        break;
      }

      segments.add(
        RayTraceSegment(from: currentRay.origin, to: hit.point, hit: hit),
      );

      final collider = hit.entity.getComponent<RaycastColliderComponent>()!;

      // Terminate if the surface is non-reflective or we've used all bounces.
      if (!collider.isReflective ||
          collider.reflectivity < minReflectivity ||
          bounce == maxBounces) {
        break;
      }

      // Reflect direction: r = d - 2(d·n)n
      final d = currentRay.direction;
      final n = hit.normal;
      final dDotN = d.dx * n.dx + d.dy * n.dy;
      final reflected = d - Offset(n.dx * 2.0 * dDotN, n.dy * 2.0 * dDotN);

      // Advance the origin slightly past the hit point to avoid self-intersection.
      currentRay = Ray(
        origin: hit.point + reflected * 1.0,
        direction: reflected,
        maxDistance: currentRay.maxDistance * collider.reflectivity,
      );
    }

    return RayTrace(segments: segments);
  }
}

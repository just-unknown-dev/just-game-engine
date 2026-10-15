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
import 'package:just_physics_engine/just_physics_engine.dart' show Ray;

import '../../ecs.dart';
import '../../components/components.dart';

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
  List<Type> get requiredComponents => const [
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

  /// Ray–AABB (axis-aligned bounding box) intersection using the slab method.
  ///
  /// Returns the smallest positive `t` at which [origin]+[dir]*t enters [rect],
  /// or `null` on a miss or if the intersection lies beyond [maxDist].
  /// Also writes the outward surface normal into [outNormal].
  double? _rayAABB({
    required Offset origin,
    required Offset dir,
    required Rect rect,
    required double maxDist,
    required List<Offset> outNormal,
  }) {
    // A ray parallel to a pair of sides never crosses them: it is between
    // them all along or never. (Dividing by its zero component instead gave
    // 0 × ∞ = NaN for a ray running exactly along a side, and the far side.)
    var txMin = double.negativeInfinity, txMax = double.infinity;
    if (dir.dx.abs() > 1e-12) {
      txMin = (rect.left - origin.dx) / dir.dx;
      txMax = (rect.right - origin.dx) / dir.dx;
      if (txMin > txMax) {
        final tmp = txMin;
        txMin = txMax;
        txMax = tmp;
      }
    } else if (origin.dx < rect.left || origin.dx > rect.right) {
      return null;
    }

    var tyMin = double.negativeInfinity, tyMax = double.infinity;
    if (dir.dy.abs() > 1e-12) {
      tyMin = (rect.top - origin.dy) / dir.dy;
      tyMax = (rect.bottom - origin.dy) / dir.dy;
      if (tyMin > tyMax) {
        final tmp = tyMin;
        tyMin = tyMax;
        tyMax = tmp;
      }
    } else if (origin.dy < rect.top || origin.dy > rect.bottom) {
      return null;
    }

    // No overlap of the slab intervals → miss.
    if (txMin > tyMax || tyMin > txMax) return null;

    final tEnter = math.max(txMin, tyMin);
    final tExit = math.min(txMax, tyMax);
    if (tExit < 0) return null; // AABB is behind the ray

    // Use tEnter if positive (ray starts outside), else tExit (ray starts inside).
    final t = tEnter >= 0 ? tEnter : tExit;
    if (t > maxDist) return null;

    // Determine surface normal from which slab was entered.
    if (tEnter == txMin) {
      outNormal.add(Offset(dir.dx > 0 ? -1.0 : 1.0, 0.0));
    } else {
      outNormal.add(Offset(0.0, dir.dy > 0 ? -1.0 : 1.0));
    }
    return t;
  }

  /// Unified ray–collider test.
  ///
  /// Tests the ray against the entity's [RaycastColliderComponent] using the
  /// appropriate geometry (circle for non-zero radius, AABB for [width]/[height]).
  /// Returns `(t, normal)` or `null` on miss — always for a collider with
  /// no size at all, which has nothing to hit.
  ({double t, Offset normal})? _intersect({
    required Offset origin,
    required Offset dir,
    required Offset centre,
    required RaycastColliderComponent collider,
    required double maxDist,
  }) {
    // No radius, width or height: a point, not a shape.
    if (collider.radius <= 0 && collider.width <= 0 && collider.height <= 0) {
      return null;
    }

    // Circle collider (default).
    if (collider.radius > 0 && collider.width == 0 && collider.height == 0) {
      final t = _rayCircle(
        origin: origin,
        dir: dir,
        centre: centre,
        radius: collider.radius,
        maxDist: maxDist,
      );
      if (t == null) return null;
      final hitPoint = origin + dir * t;
      final normal = (hitPoint - centre) / collider.radius;
      return (t: t, normal: normal);
    }

    // AABB collider.
    final halfW = collider.width > 0 ? collider.width / 2 : collider.radius;
    final halfH = collider.height > 0 ? collider.height / 2 : collider.radius;
    final rect = Rect.fromCenter(
      center: centre,
      width: halfW * 2,
      height: halfH * 2,
    );
    final normalBuf = <Offset>[];
    final t = _rayAABB(
      origin: origin,
      dir: dir,
      rect: rect,
      maxDist: maxDist,
      outNormal: normalBuf,
    );
    if (t == null) return null;
    return (t: t, normal: normalBuf.first);
  }

  // ── Public query API ───────────────────────────────────────────────────────

  /// Cast [ray] and return the **closest** hit entity, or `null` if no entity
  /// is intersected within `ray.maxDistance`.
  ///
  /// [filterTag] — when non-null only entities whose [RaycastColliderComponent.tag]
  /// matches are considered.
  RaycastHit? castRay(Ray ray, {String? filterTag}) {
    RaycastHit? closest;

    forEach((entity) {
      final collider = entity.getComponent<RaycastColliderComponent>()!;
      if (filterTag != null && collider.tag != filterTag) return;

      final centre = entity.getComponent<TransformComponent>()!.position;
      final result = _intersect(
        origin: ray.origin,
        dir: ray.direction,
        centre: centre.toOffset(),
        collider: collider,
        maxDist: ray.maxDistance,
      );
      if (result == null) return;

      if (closest == null || result.t < closest!.distance) {
        closest = RaycastHit(
          entity: entity,
          point: ray.at(result.t),
          distance: result.t,
          normal: result.normal,
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
      final result = _intersect(
        origin: ray.origin,
        dir: ray.direction,
        centre: centre.toOffset(),
        collider: collider,
        maxDist: ray.maxDistance,
      );
      if (result == null) return;

      hits.add(
        RaycastHit(
          entity: entity,
          point: ray.at(result.t),
          distance: result.t,
          normal: result.normal,
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
      final result = _intersect(
        origin: ray.origin,
        dir: ray.direction,
        centre: centre.toOffset(),
        collider: collider,
        maxDist: maxDist,
      );
      if (result != null) blocked = true;
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

  /// A segment from [from] to [to]; [hit] is null when it ended without
  /// hitting anything.
  const RayTraceSegment({required this.from, required this.to, this.hit});
}

/// Complete result of a [RayTracer.trace] call.
///
/// Contains every path segment produced during the multi-bounce trace.
class RayTrace {
  /// Ordered list of path segments (first = initial ray, last = final bounce
  /// or miss).
  final List<RayTraceSegment> segments;

  /// A trace made of [segments], first to last.
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

  /// A tracer over [raycastSystem]'s colliders that bounces at most 3 times,
  /// and only off surfaces with a reflectivity of 0.1 or more.
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

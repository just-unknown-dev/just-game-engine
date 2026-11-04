/// Multi-bounce ray traces off reflective [RaycastColliderComponent]s.
library;

import 'package:flutter/painting.dart';
import 'package:just_physics_engine/just_physics_engine.dart' show Ray;

import 'raycast_collider_component.dart';
import 'raycast_system.dart';

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
/// goes on with what is left of the ray's length — its distance budget less
/// the distance to the hit — times [RaycastColliderComponent.reflectivity];
/// the trace ends when nothing is left.
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

  /// How far past a hit point a bounce starts, so it does not hit the same
  /// surface again at once.
  static const double bounceOffset = 1.0;

  /// Trace [ray] through the world, bouncing off reflective surfaces.
  ///
  /// [filterTag] — when non-null only entities with a matching
  /// [RaycastColliderComponent.tag] are considered at each segment.
  RayTrace trace(Ray ray, {String? filterTag}) {
    final segments = <RayTraceSegment>[];
    var currentRay = ray;

    for (int bounce = 0; bounce <= maxBounces; bounce++) {
      final hit = raycastSystem.raycast(currentRay, filterTag: filterTag);

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

      // What is left of the ray, dimmed by the surface; the step past the
      // hit point counts against it.
      final remaining =
          (currentRay.maxDistance - hit.distance) * collider.reflectivity -
          bounceOffset;
      if (remaining <= 0) break;

      // Reflect direction: r = d - 2(d·n)n
      final d = currentRay.direction;
      final n = hit.normal;
      final dDotN = d.dx * n.dx + d.dy * n.dy;
      final reflected = d - Offset(n.dx * 2.0 * dDotN, n.dy * 2.0 * dDotN);

      // Advance the origin slightly past the hit point to avoid self-intersection.
      currentRay = Ray(
        origin: hit.point + reflected * bounceOffset,
        direction: reflected,
        maxDistance: remaining,
      );
    }

    return RayTrace(segments: segments);
  }
}

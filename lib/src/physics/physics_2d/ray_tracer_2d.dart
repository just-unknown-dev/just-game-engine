/// Multi-bounce rays through the 2-D physics: a beam that reflects off the
/// colliders whose [Collider2DComponent.reflectivity] is above 0.
library;

import 'dart:ui';

import '../../ecs/ecs.dart';
import 'physics_2d_components.dart';
import 'physics_2d_queries.dart';

/// One straight stretch of a [RayTrace2D]: from where the ray set off to
/// what it hit, or to where it ran out.
final class RayTrace2DSegment {
  /// A stretch from [from] to [to]; [hit] is null when it ended without
  /// hitting anything.
  const RayTrace2DSegment({required this.from, required this.to, this.hit});

  /// Where it starts, in world space.
  final Offset from;

  /// Where it ends, in world space: the hit point, or where the ray ran out
  /// when [hit] is null.
  final Offset to;

  /// What it hit at [to]; null when it hit nothing.
  final Physics2DHit? hit;

  /// How long it is, in world units.
  double get length => (to - from).distance;
}

/// What [RayTracer2D.trace] found: the ray's path, stretch by stretch.
final class RayTrace2D {
  /// A trace made of [segments], first to last.
  const RayTrace2D(this.segments);

  /// The stretches of the path in order: the first is the ray as cast, the
  /// last ends on what absorbed it or where it ran out.
  final List<RayTrace2DSegment> segments;

  /// Everything the ray hit, in order.
  List<Physics2DHit> get hits => [for (final segment in segments) ?segment.hit];

  /// The length of the whole path, in world units.
  double get totalLength =>
      segments.fold(0.0, (sum, segment) => sum + segment.length);
}

/// Traces a ray through the 2-D physics world, bouncing it off reflective
/// colliders.
///
/// Each stretch is one [Physics2DQueries.raycast], so a trace hits exactly
/// what the physics ray hits — the same bodies, layers (`layerMask`),
/// sensors (`includeSensors`) and entity to look through (`ignore`), on
/// every stretch. What a hit does next is the hit collider's
/// [Collider2DComponent.reflectivity], set in the inspector and saved with
/// the scene:
///
/// - 0, the default, absorbs the ray: the trace ends there. So does a body
///   with no [Collider2DComponent] (a character, a body made outside the
///   ECS).
/// - Above 0 (and at least [minReflectivity]), the ray is mirrored about
///   the surface's normal and goes on with what was left of its length,
///   times the reflectivity, less [bounceOffset].
///
/// The trace ends when the ray hits nothing, when nothing of its length is
/// left, or after [maxBounces] bounces.
///
/// ```dart
/// final tracer = RayTracer2D(world.getSystem<Physics2DSystem>()!.queries);
/// final trace = tracer.trace(muzzle, aim, maxDistance: 800, ignore: turret);
/// for (final segment in trace.segments) {
///   drawBeam(segment.from, segment.to); // a RayRenderable, say
/// }
/// ```
final class RayTracer2D {
  /// A tracer over [queries] that bounces at most [maxBounces] times, off
  /// colliders whose reflectivity is above 0 and at least
  /// [minReflectivity].
  RayTracer2D(this.queries, {this.maxBounces = 3, this.minReflectivity = 0})
    : assert(maxBounces >= 0, 'maxBounces is $maxBounces');

  /// The physics queries each stretch is cast with — usually
  /// `Physics2DSystem.queries`.
  final Physics2DQueries queries;

  /// The most bounces a trace makes (0: none, a plain ray cast).
  final int maxBounces;

  /// The least reflectivity a surface needs to bounce a ray; a duller one
  /// absorbs it. 0, the default, bounces off every surface above 0.
  final double minReflectivity;

  /// How far past a hit point a bounce starts, so it does not hit the same
  /// surface again at once. It counts against what is left of the ray.
  static const double bounceOffset = 1.0;

  /// How much of a ray [hit] sends back: the hit collider's
  /// [Collider2DComponent.reflectivity], 0 for a body with none.
  static double reflectivityOf(Physics2DHit hit) =>
      hit.entity?.getComponent<Collider2DComponent>()?.reflectivity ?? 0;

  /// Traces a ray from [origin] along [direction], [maxDistance] long,
  /// bouncing it off reflective colliders. [layerMask], [ignore] and
  /// [includeSensors] are [Physics2DQueries.raycast]'s, applied to every
  /// stretch. A zero [direction] or a [maxDistance] of 0 or less traces
  /// nothing.
  RayTrace2D trace(
    Offset origin,
    Offset direction, {
    double maxDistance = 2000,
    int layerMask = 0xFFFF,
    Entity? ignore,
    bool includeSensors = false,
  }) {
    final segments = <RayTrace2DSegment>[];
    if (direction == Offset.zero || maxDistance <= 0) {
      return RayTrace2D(segments);
    }
    var from = origin;
    var along = direction / direction.distance;
    var length = maxDistance;
    for (var bounce = 0; ; bounce++) {
      final hit = queries.raycast(
        from,
        along,
        maxDistance: length,
        layerMask: layerMask,
        ignore: ignore,
        includeSensors: includeSensors,
      );
      if (hit == null) {
        segments.add(RayTrace2DSegment(from: from, to: from + along * length));
        break;
      }
      segments.add(RayTrace2DSegment(from: from, to: hit.point, hit: hit));
      final reflectivity = reflectivityOf(hit);
      if (bounce == maxBounces ||
          reflectivity <= 0 ||
          reflectivity < minReflectivity) {
        break;
      }
      // What is left of the ray, dimmed by the surface; the step past the
      // hit point counts against it.
      final left = (length - hit.distance) * reflectivity - bounceOffset;
      if (left <= 0) break;
      // Mirrored about the normal: r = d − 2(d·n)n, kept a unit vector.
      final n = hit.normal;
      final dot = along.dx * n.dx + along.dy * n.dy;
      final mirrored = along - n * (2 * dot);
      if (mirrored == Offset.zero) break;
      along = mirrored / mirrored.distance;
      from = hit.point + along * bounceOffset;
      length = left;
    }
    return RayTrace2D(segments);
  }
}

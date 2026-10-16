/// Rays and overlaps against the 2-D bodies, answering in entities — the
/// same questions, named the same, as the 3-D `Physics3DQueries`.
library;

import 'dart:ui';

import 'package:just_physics_engine/just_physics_engine.dart';

import '../../ecs.dart';
import 'physics_system.dart';

/// What a 2-D query hit.
final class PhysicsHit2D {
  /// A hit on [body] ([entity]'s) at [point].
  const PhysicsHit2D({
    required this.entity,
    required this.body,
    required this.point,
    required this.normal,
    required this.distance,
    required this.fraction,
  });

  /// The entity hit; null for a body no [PhysicsSystem] made.
  final Entity? entity;

  /// The body hit.
  final PhysicsBody body;

  /// Where.
  final Offset point;

  /// The surface's normal there, facing the query.
  final Offset normal;

  /// How far along the query it is.
  final double distance;

  /// [distance] as a fraction of the query's length.
  final double fraction;

  @override
  String toString() => 'PhysicsHit2D(${entity?.name ?? body} at $point)';
}

/// Rays, sweeps and overlaps against the bodies [system] keeps in
/// [physics]. Each takes the layers it sees (`layerMask`, bit `n` for layer
/// `n`), an entity to look through (`ignore`, the asker itself, say), and
/// whether sensors count.
///
/// ```dart
/// final queries = Physics2DQueries(engine.physics, world.getSystem<PhysicsSystem>()!);
/// final hit = queries.raycast(eyes, const Offset(1, 0), maxDistance: 300, ignore: guard);
/// if (hit?.entity?.hasTag('player') ?? false) chase();
/// ```
final class Physics2DQueries {
  /// Queries of [physics]'s bodies, which [system] made.
  Physics2DQueries(this.physics, this.system);

  /// The physics engine queried.
  final PhysicsEngine physics;

  /// What made the bodies, and knows their entities.
  final PhysicsSystem system;

  /// The first thing a ray from [origin] along [direction] hits within
  /// [maxDistance], or null.
  PhysicsHit2D? raycast(
    Offset origin,
    Offset direction, {
    double maxDistance = 2000,
    int layerMask = 0xFFFF,
    Entity? ignore,
    bool includeSensors = false,
  }) {
    final all = raycastAll(
      origin,
      direction,
      maxDistance: maxDistance,
      layerMask: layerMask,
      ignore: ignore,
      includeSensors: includeSensors,
    );
    return all.isEmpty ? null : all.first;
  }

  /// Everything a ray from [origin] along [direction] hits within
  /// [maxDistance], nearest first.
  List<PhysicsHit2D> raycastAll(
    Offset origin,
    Offset direction, {
    double maxDistance = 2000,
    int layerMask = 0xFFFF,
    Entity? ignore,
    bool includeSensors = false,
  }) {
    if (direction == Offset.zero || maxDistance <= 0) return const [];
    final ray = Ray(
      origin: origin,
      direction: direction,
      maxDistance: maxDistance,
    );
    return [
      for (final hit in physics.castRayAll(ray, exclude: _exclude(ignore)))
        if (_passes(hit.body, layerMask, includeSensors))
          PhysicsHit2D(
            entity: system.entityForBody(hit.body),
            body: hit.body,
            point: hit.point,
            normal: hit.normal,
            distance: hit.distance,
            fraction: hit.distance / maxDistance,
          ),
    ];
  }

  /// The first thing a circle of [radius] swept from [origin] along
  /// [direction] hits within [maxDistance], or null (a thick bullet, a
  /// character feeling its way).
  PhysicsHit2D? circleCast(
    Offset origin,
    double radius,
    Offset direction, {
    double maxDistance = 2000,
    int layerMask = 0xFFFF,
    Entity? ignore,
    bool includeSensors = false,
  }) {
    if (direction == Offset.zero || maxDistance <= 0) return null;
    final motion = direction / direction.distance * maxDistance;
    final exclude = {..._exclude(ignore)};
    // Bodies that do not pass are looked through, one at a time.
    while (true) {
      final hit = physics.castCircle(origin, radius, motion, exclude: exclude);
      if (hit == null) return null;
      if (_passes(hit.body, layerMask, includeSensors)) {
        return PhysicsHit2D(
          entity: system.entityForBody(hit.body),
          body: hit.body,
          point: hit.point,
          normal: hit.normal,
          distance: hit.distance,
          fraction: hit.distance / maxDistance,
        );
      }
      exclude.add(hit.body);
    }
  }

  /// The entities whose bodies a circle at [center] of [radius] overlaps.
  List<Entity> overlapCircle(
    Offset center,
    double radius, {
    int layerMask = 0xFFFF,
    Entity? ignore,
    bool includeSensors = false,
  }) => _entities(
    physics.queryCircle(center, radius),
    layerMask,
    ignore,
    includeSensors,
  );

  /// The entities whose bodies overlap [rect].
  List<Entity> overlapBox(
    Rect rect, {
    int layerMask = 0xFFFF,
    Entity? ignore,
    bool includeSensors = false,
  }) => _entities(physics.queryAABB(rect), layerMask, ignore, includeSensors);

  Set<PhysicsBody> _exclude(Entity? ignore) {
    final body = ignore == null ? null : system.bodyOf(ignore);
    return body == null ? const {} : {body};
  }

  static bool _passes(PhysicsBody body, int layerMask, bool includeSensors) =>
      (body.categoryBits & layerMask) != 0 &&
      (includeSensors || !body.isSensor);

  List<Entity> _entities(
    List<PhysicsBody> bodies,
    int layerMask,
    Entity? ignore,
    bool includeSensors,
  ) {
    final seen = <Entity>{};
    for (final body in bodies) {
      if (!_passes(body, layerMask, includeSensors)) continue;
      final entity = system.entityForBody(body);
      if (entity != null && !identical(entity, ignore)) seen.add(entity);
    }
    return seen.toList();
  }
}

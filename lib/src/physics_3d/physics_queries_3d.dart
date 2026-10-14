import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_physics_engine/physics_3d.dart';

import 'physics_system_3d.dart';

/// A query's hit, with the entity whose body it hit.
final class PhysicsHit3D {
  /// A hit on [body] ([entity]'s) at [point].
  PhysicsHit3D({
    required this.entity,
    required this.body,
    required this.point,
    required this.normal,
    required this.distance,
    required this.fraction,
    this.depth = 0,
  });

  /// The entity hit; null for a body no [PhysicsSystem3D] made.
  final Entity? entity;

  /// The body hit.
  final int body;

  /// Where.
  final Vector3 point;

  /// The surface's normal there, facing the query.
  final Vector3 normal;

  /// How far along the ray or sweep, in metres.
  final double distance;

  /// How far along, 0–1.
  final double fraction;

  /// A sweep that started inside, or an overlap: how deep.
  final double depth;

  @override
  String toString() => 'PhysicsHit3D(${entity?.name ?? body} at $point)';
}

/// Rays, sweeps and overlaps against a [PhysicsWorld3D], answered in
/// entities. `Physics3D.queries` is one.
///
/// Before the system has made its world (no 3-D body yet) every query
/// finds nothing.
///
/// Every query takes a layer mask (one bit per layer; all by default),
/// an entity to pass over (the one asking, say), and whether sensors count
/// (not by default).
final class Physics3DQueries {
  /// Queries on [system]'s world, naming entities through it.
  Physics3DQueries(this.system);

  /// Steps the world asked, and knows which entity owns which body.
  final PhysicsSystem3D system;

  /// The world, or null while the system has none yet.
  PhysicsWorld3D? get _world => system.hasWorld ? system.physics : null;

  QueryFilter3D _filter(int layerMask, Entity? ignore, bool sensors) =>
      QueryFilter3D(
        layerMask: layerMask,
        ignoreBody: ignore == null ? 0 : _bodyOf(ignore),
        includeSensors: sensors,
      );

  int _bodyOf(Entity entity) {
    final body = system.bodyOf(entity);
    if (body != 0) return body;
    final character = system.characterOf(entity);
    final world = _world;
    return character == 0 || world == null ? 0 : world.characterBody(character);
  }

  List<PhysicsHit3D> _hits(List<QueryHit3D> hits, double length) => [
    for (final h in hits)
      PhysicsHit3D(
        entity: system.entityOf(h.body),
        body: h.body,
        point: h.point,
        normal: h.normal,
        distance: h.fraction * length,
        fraction: h.fraction,
        depth: h.depth,
      ),
  ];

  static Vector3 _along(Vector3 direction, double length) {
    final d = Vector3.copy(direction);
    if (d.normalize() == 0) d.setValues(0, 1, 0);
    return d..scale(length);
  }

  /// The first thing a ray from [origin] along [direction] hits within
  /// [maxDistance], or null.
  PhysicsHit3D? raycast(
    Vector3 origin,
    Vector3 direction, {
    double maxDistance = 1000,
    int layerMask = 0xFFFF,
    Entity? ignore,
    bool includeSensors = false,
  }) {
    final world = _world;
    if (world == null) return null;
    final hits = world.raycast(
      origin,
      _along(direction, maxDistance),
      filter: _filter(layerMask, ignore, includeSensors),
    );
    return hits.isEmpty ? null : _hits(hits, maxDistance).first;
  }

  /// Everything a ray hits within [maxDistance], nearest first.
  List<PhysicsHit3D> raycastAll(
    Vector3 origin,
    Vector3 direction, {
    double maxDistance = 1000,
    int layerMask = 0xFFFF,
    Entity? ignore,
    bool includeSensors = false,
  }) {
    final world = _world;
    if (world == null) return const [];
    return _hits(
      world.raycast(
        origin,
        _along(direction, maxDistance),
        filter: _filter(layerMask, ignore, includeSensors),
        allHits: true,
      ),
      maxDistance,
    );
  }

  /// The first thing a sphere of [radius] swept from [origin] along
  /// [direction] hits within [maxDistance], or null (a camera keeping out
  /// of walls, a thick bullet).
  PhysicsHit3D? sphereCast(
    Vector3 origin,
    double radius,
    Vector3 direction, {
    double maxDistance = 1000,
    int layerMask = 0xFFFF,
    Entity? ignore,
    bool includeSensors = false,
  }) => shapeCast(
    SphereShape3D(radius),
    origin,
    Quaternion.identity(),
    direction,
    maxDistance: maxDistance,
    layerMask: layerMask,
    ignore: ignore,
    includeSensors: includeSensors,
  );

  /// The first thing [shape] swept from [position] and [rotation] along
  /// [direction] hits within [maxDistance], or null.
  PhysicsHit3D? shapeCast(
    Shape3D shape,
    Vector3 position,
    Quaternion rotation,
    Vector3 direction, {
    double maxDistance = 1000,
    int layerMask = 0xFFFF,
    Entity? ignore,
    bool includeSensors = false,
  }) {
    final world = _world;
    if (world == null) return null;
    final hits = world.shapeCast(
      shape,
      position,
      rotation,
      _along(direction, maxDistance),
      filter: _filter(layerMask, ignore, includeSensors),
    );
    return hits.isEmpty ? null : _hits(hits, maxDistance).first;
  }

  /// The entities whose bodies a sphere at [center] overlaps.
  List<Entity> overlapSphere(
    Vector3 center,
    double radius, {
    int layerMask = 0xFFFF,
    Entity? ignore,
    bool includeSensors = false,
  }) => overlap(
    SphereShape3D(radius),
    center,
    Quaternion.identity(),
    layerMask: layerMask,
    ignore: ignore,
    includeSensors: includeSensors,
  );

  /// The entities whose bodies a box of [halfExtents] at [center] overlaps.
  List<Entity> overlapBox(
    Vector3 center,
    Vector3 halfExtents, {
    Quaternion? rotation,
    int layerMask = 0xFFFF,
    Entity? ignore,
    bool includeSensors = false,
  }) => overlap(
    BoxShape3D(halfExtents.x, halfExtents.y, halfExtents.z),
    center,
    rotation ?? Quaternion.identity(),
    layerMask: layerMask,
    ignore: ignore,
    includeSensors: includeSensors,
  );

  /// The entities whose bodies [shape] at [position] and [rotation]
  /// overlaps.
  List<Entity> overlap(
    Shape3D shape,
    Vector3 position,
    Quaternion rotation, {
    int layerMask = 0xFFFF,
    Entity? ignore,
    bool includeSensors = false,
  }) {
    final world = _world;
    if (world == null) return const [];
    final seen = <Entity>{};
    for (final hit in world.overlap(
      shape,
      position,
      rotation,
      filter: _filter(layerMask, ignore, includeSensors),
    )) {
      final entity = system.entityOf(hit.body);
      if (entity != null) seen.add(entity);
    }
    return seen.toList();
  }
}

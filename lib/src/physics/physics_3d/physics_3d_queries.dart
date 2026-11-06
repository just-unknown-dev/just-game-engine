import 'package:just_physics_engine/physics_3d.dart';

import '../../ecs/ecs.dart';
import 'physics_3d_system.dart';

/// A query's hit, with the entity whose body it hit.
final class Physics3DHit {
  /// A hit on [body] ([entity]'s) at [point].
  Physics3DHit({
    required this.entity,
    required this.body,
    required this.point,
    required this.normal,
    required this.distance,
    required this.fraction,
    this.depth = 0,
  });

  /// The entity hit; null for a body no [Physics3DSystem] made.
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
  String toString() => 'Physics3DHit(${entity?.name ?? body} at $point)';
}

/// Rays, sweeps and overlaps against a [Physics3DWorld], answered in
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
  final Physics3DSystem system;

  /// The world, or null while the system has none yet.
  Physics3DWorld? get _world => system.hasWorld ? system.physics : null;

  Query3DFilter _filter(int layerMask, Entity? ignore, bool sensors) =>
      Query3DFilter(
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

  List<Physics3DHit> _hits(List<Query3DHit> hits, double length) => [
    for (final h in hits)
      Physics3DHit(
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
  Physics3DHit? raycast(
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
  List<Physics3DHit> raycastAll(
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
  Physics3DHit? sphereCast(
    Vector3 origin,
    double radius,
    Vector3 direction, {
    double maxDistance = 1000,
    int layerMask = 0xFFFF,
    Entity? ignore,
    bool includeSensors = false,
  }) => shapeCast(
    Sphere3DShape(radius),
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
  Physics3DHit? shapeCast(
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
    Sphere3DShape(radius),
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
    Box3DShape(halfExtents.x, halfExtents.y, halfExtents.z),
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

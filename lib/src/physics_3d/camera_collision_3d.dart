import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:just_game_engine/just_game_engine.dart';

import 'physics_queries_3d.dart';
import 'physics_system_3d.dart';

/// Keeps a virtual camera out of walls: on the same entity as an
/// `OrbitFollowComponent` (or any body stage), it pulls the camera in
/// towards its target when something solid is between them, and eases it
/// back out once the way is clear.
class CameraCollision3D extends Component {
  /// Collision for a camera.
  CameraCollision3D({
    this.radius = 0.2,
    this.minDistance = 0.3,
    this.recover = 0.35,
    this.layerMask = 0xFFFF,
    Vector3? offset,
  }) : offset = offset ?? Vector3(0, -1.5, 0);

  /// How thick the camera is, in metres: it keeps this far from a wall.
  double radius;

  /// The nearest it comes to the point it looks from.
  double minDistance;

  /// Seconds to ease back out once clear; pulling in is immediate.
  double recover;

  /// The physics layers that block it.
  int layerMask;

  /// Where it looks from, from the target, when the camera has no orbit
  /// pivot to say (-Y is up).
  Vector3 offset;
}

/// Finalizes a [CameraCollision3D] camera: a sphere cast from the point
/// the camera circles to where the body stage put it, the target's own
/// body ignored. Registered by `Physics3D`.
class CameraCollisionStage extends CameraStage<CameraCollision3D> {
  /// Stateless; one serves every camera.
  const CameraCollisionStage();

  @override
  CameraStagePhase get phase => CameraStagePhase.finalize;

  @override
  CameraState apply(
    CameraStageContext context,
    CameraCollision3D collision,
    CameraState state,
    double dt,
  ) {
    final target = context.targetPosition3;
    final system = context.world.getSystem<PhysicsSystem3D>();
    if (target == null || system == null) return state;
    final pivot = context.entity.getComponent<OrbitFollowComponent>()?.pivot ?? collision.offset;
    final from = Vector3(target.x + pivot.x, target.y + pivot.y, target.z + pivot.z);
    final to = Vector3(state.position.dx, state.position.dy, state.z);
    final dir = to - from;
    final length = dir.length;
    if (length < 1e-6) return state;
    dir.scale(1 / length);

    var q = context.memory.extra[CameraCollisionStage] as Physics3DQueries?;
    if (q == null || !identical(q.system, system)) {
      q = Physics3DQueries(system);
      context.memory.extra[CameraCollisionStage] = q;
    }
    final hit = q.sphereCast(
      from,
      collision.radius,
      dir,
      maxDistance: length,
      layerMask: collision.layerMask,
      ignore: context.target,
    );
    final clear = hit == null ? length : math.max(collision.minDistance, math.min(length, hit.distance));

    // In at once, out gently.
    final key = (CameraCollisionStage, #distance);
    final last = context.memory.extra[key] as double?;
    final double distance;
    if (last == null || context.snap || clear <= last) {
      distance = clear;
    } else {
      distance = last + (clear - last) * CameraStage.damp(collision.recover, dt);
    }
    context.memory.extra[key] = distance;
    if (distance >= length - 1e-9) return state;
    final at = from + dir * distance;
    return state.copyWith(position: Offset(at.x, at.y), z: at.z);
  }
}

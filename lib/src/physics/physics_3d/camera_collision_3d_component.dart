import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:just_dart/just_dart.dart';

import '../../camera/camera_rig_3d_components.dart';
import '../../ecs/ecs.dart';
import '../../camera/camera_stage.dart';
import '../../camera/camera_state.dart';
import 'physics_3d_queries.dart';
import 'physics_3d_system.dart';

/// Keeps a virtual camera out of walls: on the same entity as an
/// `OrbitFollowComponent` (or any body stage), it pulls the camera in
/// towards its target when something solid is between them, and eases it
/// back out once the way is clear.
class CameraCollision3DComponent extends Component {
  /// Collision for a camera.
  CameraCollision3DComponent({
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

/// Finalizes a [CameraCollision3DComponent] camera: a sphere cast from the point
/// the camera circles to where the body stage put it, the target's own
/// body ignored. Registered by `Physics3D`.
class CameraCollision3DStage extends CameraStage<CameraCollision3DComponent> {
  /// Stateless; one serves every camera.
  const CameraCollision3DStage();

  @override
  CameraStagePhase get phase => CameraStagePhase.finalize;

  @override
  CameraState apply(
    CameraStageContext context,
    CameraCollision3DComponent collision,
    CameraState state,
    double dt,
  ) {
    final target = context.targetPosition3;
    final system = context.world.getSystem<Physics3DSystem>();
    if (target == null || system == null) return state;
    final pivot =
        context.entity.getComponent<OrbitFollowComponent>()?.pivot ??
        collision.offset;
    final from = Vector3(
      target.x + pivot.x,
      target.y + pivot.y,
      target.z + pivot.z,
    );
    final to = Vector3(state.position.dx, state.position.dy, state.z);
    final dir = to - from;
    final length = dir.length;
    if (length < 1e-6) return state;
    dir.scale(1 / length);

    var q = context.memory.extra[CameraCollision3DStage] as Physics3DQueries?;
    if (q == null || !identical(q.system, system)) {
      q = Physics3DQueries(system);
      context.memory.extra[CameraCollision3DStage] = q;
    }
    final hit = q.sphereCast(
      from,
      collision.radius,
      dir,
      maxDistance: length,
      layerMask: collision.layerMask,
      ignore: context.target,
    );
    final clear = hit == null
        ? length
        : math.max(collision.minDistance, math.min(length, hit.distance));

    // In at once, out gently.
    final key = (CameraCollision3DStage, #distance);
    final last = context.memory.extra[key] as double?;
    final double distance;
    if (last == null || context.snap || clear <= last) {
      distance = clear;
    } else {
      distance =
          last + (clear - last) * CameraStage.damp(collision.recover, dt);
    }
    context.memory.extra[key] = distance;
    if (distance >= length - 1e-9) return state;
    final at = from + dir * distance;
    return state.copyWith(position: Offset(at.x, at.y), z: at.z);
  }
}

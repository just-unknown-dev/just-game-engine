library;

import '../../ecs.dart';
import '../../../math/vector3.dart';

/// Transform component — position, rotation, and scale in 3-D world space.
///
/// The x/y axes map to the 2-D screen plane; z carries depth for future 3-D
/// rendering and is ignored by the current Canvas-based renderer.
///
/// All mutation methods operate in-place on the mutable [Vector3] fields to
/// avoid per-frame GC allocations.
class TransformComponent extends Component {
  /// World-space position (x, y, z).  z defaults to 0 for 2-D entities.
  Vector3 position;

  /// Position captured at the start of the previous physics step.
  /// Always a **separate** [Vector3] object — never an alias of [position].
  /// Used by [RenderSystem] to lerp towards [position] when rendering between
  /// physics ticks (sub-frame render interpolation).
  Vector3 prevPosition;

  /// Scale factors (x, y, z).  z defaults to 1.  2-D rendering uses x and y.
  Vector3 scale;

  /// Z-axis rotation in radians (the standard 2-D rotation).
  double rotation;

  /// X-axis rotation in radians (pitch).  Defaults to 0; ignored by 2-D renderer.
  double rotationX;

  /// Y-axis rotation in radians (yaw).  Defaults to 0; ignored by 2-D renderer.
  double rotationY;

  /// Rotation captured at the start of the previous physics step.
  double prevRotation;

  /// Create a transform component.
  TransformComponent({
    Vector3? position,
    this.rotation = 0.0,
    this.rotationX = 0.0,
    this.rotationY = 0.0,
    Vector3? scale,
  }) : position = Vector3.copy(position ?? Vector3.zero()),
       prevPosition = Vector3.copy(position ?? Vector3.zero()),
       scale = scale ?? Vector3(1.0, 1.0, 1.0),
       prevRotation = rotation;

  // ── Mutation helpers (all in-place — zero allocations) ──────────────────

  /// Translate by [delta].
  void translate(Vector3 delta) => position.add(delta);

  /// Translate by [dir] scaled by [dt].  Hot-path variant — zero allocations.
  void translateScaled(Vector3 dir, double dt) => position.addScaled(dir, dt);

  /// Set x/y position from raw doubles.  2-D fast path; z is unchanged.
  void setPositionXY(double x, double y) {
    position.x = x;
    position.y = y;
  }

  /// Set x/y/z position from raw doubles.
  void setPositionXYZ(double x, double y, double z) =>
      position.setValues(x, y, z);

  /// Translate by raw x/y offsets.  2-D fast path; z is unchanged.
  void translateXY(double dx, double dy) {
    position.x += dx;
    position.y += dy;
  }

  /// Translate by raw x/y/z offsets.
  void translateXYZ(double dx, double dy, double dz) {
    position.x += dx;
    position.y += dy;
    position.z += dz;
  }

  /// Rotate around the Z-axis by [angle] radians.
  void rotate(double angle) => rotation += angle;

  @override
  String toString() =>
      'Transform(pos: $position, rot: ($rotationX, $rotationY, $rotation), '
      'scale: $scale)';
}

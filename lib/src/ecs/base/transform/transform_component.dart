library;

import '../../ecs.dart';
import 'package:just_dart/just_dart.dart';

/// Transform component — where an entity is in the world: position,
/// rotation and scale, in 3-D.
///
/// A 2-D entity is simply a 3-D one that lies in the z plane and turns only
/// about Z: it uses [position] x/y, [angle] and [scale] x/y, and pays nothing
/// for the third dimension (see [isPlanar]). Axes are [WorldAxes]: +X right,
/// +Y down, +Z into the screen.
///
/// This is always the **world** transform. An entity with a parent keeps
/// its offset from that parent in its `ParentComponent`, and the hierarchy
/// keeps the two in step.
///
/// ## Rotation
///
/// Rotation is held as Euler angles in radians — [eulerX], [eulerY] and
/// [angle] (about Z) — in the one convention `q = qY · qX · qZ` (see
/// [Quaternion]). A quaternion is derived from them on demand
/// ([rotationInto]); [setRotation] goes the other way, choosing the Euler
/// triple nearest the current one so values stay continuous. Setting
/// [angle] is a plain field write: the 2-D hot path does no trigonometry.
///
/// All mutation methods work in place — no per-frame allocations.
class TransformComponent extends Component {
  /// World-space position (x, y, z). z is 0 for 2-D entities.
  Vector3 position;

  /// Position captured at the start of the previous physics step.
  /// Always a **separate** [Vector3] object — never an alias of [position].
  /// Used by [RenderSystem] to lerp towards [position] when rendering between
  /// physics ticks (sub-frame render interpolation).
  Vector3 prevPosition;

  /// Scale factors (x, y, z). z is 1 for 2-D entities.
  Vector3 scale;

  double _ex;
  double _ey;
  double _ez;

  final Quaternion _q = Quaternion.identity();
  bool _qStale = true;

  /// [angle] captured at the start of the previous physics step.
  double prevAngle;

  /// The full rotation captured by [capturePrevious] — kept up to date only
  /// while the transform is not [isPlanar] (a 2-D entity uses [prevAngle]).
  /// [previousRotationInto] reads the right one either way.
  final Quaternion prevRotation = Quaternion.identity();

  bool _prevPlanar = true;
  int _captures = 0;

  /// Create a transform.
  ///
  /// [euler] (radians, x/y/z) sets all three rotation angles and wins over
  /// [angle], which sets only the turn about Z.
  TransformComponent({
    Vector3? position,
    double angle = 0.0,
    Vector3? euler,
    Vector3? scale,
  }) : position = Vector3.copy(position ?? Vector3.zero()),
       prevPosition = Vector3.copy(position ?? Vector3.zero()),
       scale = scale ?? Vector3(1.0, 1.0, 1.0),
       _ex = euler?.x ?? 0.0,
       _ey = euler?.y ?? 0.0,
       _ez = euler?.z ?? angle,
       prevAngle = euler?.z ?? angle;

  // ── Rotation: 2-D ───────────────────────────────────────────────────────

  /// Rotation about Z in radians — the 2-D rotation. Positive is clockwise
  /// on screen.
  double get angle => _ez;
  set angle(double value) {
    _ez = value;
    _qStale = true;
  }

  /// Rotate around the Z-axis by [delta] radians.
  void rotate(double delta) {
    _ez += delta;
    _qStale = true;
  }

  // ── Rotation: 3-D ───────────────────────────────────────────────────────

  /// Rotation about X in radians (applied after Z, before Y).
  double get eulerX => _ex;
  set eulerX(double value) {
    _ex = value;
    _qStale = true;
  }

  /// Rotation about Y in radians (applied last).
  double get eulerY => _ey;
  set eulerY(double value) {
    _ey = value;
    _qStale = true;
  }

  /// Whether the entity only turns about Z — true for every 2-D entity.
  /// Planar transforms take the 2-D fast paths everywhere.
  bool get isPlanar => _ex == 0.0 && _ey == 0.0;

  /// Set all three Euler angles (radians).
  void setEuler(double x, double y, double z) {
    _ex = x;
    _ey = y;
    _ez = z;
    _qStale = true;
  }

  /// Write the Euler angles (radians) into [out].
  void eulerInto(Vector3 out) => out.setValues(_ex, _ey, _ez);

  /// Write the rotation as a quaternion into [out].
  void rotationInto(Quaternion out) {
    _syncQuaternion();
    out.setFrom(_q);
  }

  /// Set the rotation from a quaternion. The Euler angles become the
  /// equivalent triple nearest the current ones, so an angle past 180°
  /// keeps counting instead of jumping.
  void setRotation(Quaternion rotation) {
    _q.setFrom(rotation);
    _q.normalize();
    _scratch.setValues(_ex, _ey, _ez);
    _q.eulerInto(_scratch, hint: _scratch);
    // A rotation that is 2-D up to rounding stays exactly 2-D.
    _ex = _scratch.x.abs() < 1e-12 ? 0.0 : _scratch.x;
    _ey = _scratch.y.abs() < 1e-12 ? 0.0 : _scratch.y;
    _ez = _scratch.z;
    _qStale = false;
  }

  void _syncQuaternion() {
    if (!_qStale) return;
    if (isPlanar) {
      _q.setRotationZ(_ez);
    } else {
      _q.setEuler(_ex, _ey, _ez);
    }
    _qStale = false;
  }

  static final Vector3 _scratch = Vector3.zero();

  // ── Physics sync ────────────────────────────────────────────────────────

  /// Remember the current pose as the previous one, for render
  /// interpolation between physics steps.
  void capturePrevious() {
    prevPosition.setFrom(position);
    prevAngle = _ez;
    _prevPlanar = isPlanar;
    if (!_prevPlanar) rotationInto(prevRotation);
    _captures++;
  }

  /// Like [capturePrevious], but with [rotation] as the previous rotation
  /// instead of the current one: for a system that moves the entity while
  /// gameplay turns it before the step (a character mover), so the
  /// previous rotation is the one it kept from the end of the last step.
  void capturePreviousWithRotation(Quaternion rotation) {
    prevPosition.setFrom(position);
    prevRotation
      ..setFrom(rotation)
      ..normalize();
    _scratch.setValues(_ex, _ey, _ez);
    prevRotation.eulerInto(_scratch, hint: _scratch);
    prevAngle = _scratch.z;
    _prevPlanar = false;
    _captures++;
  }

  /// How many times the previous pose has been captured ([capturePrevious]
  /// and [capturePreviousWithRotation]).
  ///
  /// A renderer that sees it change over a fixed update knows the previous
  /// pose is where that update started, so drawing between the two is
  /// right. One that stays the same — a transform only gameplay writes —
  /// has a previous pose that may be long out of date.
  int get captureCount => _captures;

  /// Write the rotation the previous pose was captured with into [out],
  /// whether the transform was [isPlanar] then or not.
  void previousRotationInto(Quaternion out) {
    if (_prevPlanar) {
      out.setRotationZ(prevAngle);
    } else {
      out.setFrom(prevRotation);
    }
  }

  /// Write the pose [alpha] of the way from the previous pose to this one
  /// as a matrix into [out] — what a renderer draws between fixed updates.
  /// Scale is not interpolated. [alpha] 1 is [localToWorldInto].
  void interpolatedToWorldInto(Matrix4 out, double alpha) {
    if (alpha >= 1.0) {
      localToWorldInto(out);
      return;
    }
    final p = prevPosition;
    final at = _scratch
      ..setValues(
        p.x + (position.x - p.x) * alpha,
        p.y + (position.y - p.y) * alpha,
        p.z + (position.z - p.z) * alpha,
      );
    if (_prevPlanar && isPlanar) {
      out.setFromPlanarTrs(
        at.x,
        at.y,
        at.z,
        prevAngle + (_ez - prevAngle) * alpha,
        scale.x,
        scale.y,
        scale.z,
      );
      return;
    }
    final turn = _scratchTurn;
    previousRotationInto(turn);
    _syncQuaternion();
    turn.setSlerp(turn, _q, alpha);
    out.setFromTrs(at, turn, scale);
  }

  static final Quaternion _scratchTurn = Quaternion.identity();

  /// Set the 2-D pose — x, y and the turn about Z — as a 2-D physics step
  /// reports it. z and the X/Y rotations are left alone.
  void setPlanarPose(double x, double y, double angle) {
    position.x = x;
    position.y = y;
    _ez = angle;
    _qStale = true;
  }

  // ── Matrices ────────────────────────────────────────────────────────────

  /// Write this transform as a matrix (scale, then rotate, then translate)
  /// into [out].
  void localToWorldInto(Matrix4 out) {
    if (isPlanar) {
      out.setFromPlanarTrs(
        position.x,
        position.y,
        position.z,
        _ez,
        scale.x,
        scale.y,
        scale.z,
      );
    } else {
      _syncQuaternion();
      out.setFromTrs(position, _q, scale);
    }
  }

  // ── Position helpers (all in place — zero allocations) ──────────────────

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

  @override
  String toString() =>
      'Transform(pos: $position, rot: ($_ex, $_ey, $_ez), scale: $scale)';
}

library;

import 'dart:math' as math;

import 'package:just_dart/just_dart.dart';

import 'transform_component.dart';
import 'parent_component.dart';

/// How a child's world transform follows from its parent's and its own
/// local one — and back.
///
/// ## The rule
///
/// With the parent's world transform `(pP, qP, sP)` and the child's local
/// one `(pL, qL, sL)`:
///
/// ```text
/// position  pC = pP + qP · (sP ⊙ pL)
/// rotation  qC = qP · D(qL)
/// scale     sC = sP ⊙ sL
/// ```
///
/// `D` mirrors a rotation by the signs of the parent's scale, so a parent
/// flipped with a negative scale (a character facing left) mirrors its
/// children exactly. Positions are always exact. When the parent's scale is
/// uneven *and* the child is turned relative to it, the true result would be
/// skewed, which a transform cannot hold; the skew is dropped — the same
/// compromise as Unity's `lossyScale`. Every other case is exact, and
/// [localFromWorld] is the exact inverse of [composeWorld] in all of them.
///
/// Nothing here allocates. A parent and child that both turn only about Z
/// take a 2-D path with one sin/cos.
///
/// Internal to the engine's transform hierarchy (not exported): its scratch
/// values are shared, so a call must not start inside another.
abstract final class HierarchyMath {
  static final Quaternion _qa = Quaternion.identity();
  static final Quaternion _qb = Quaternion.identity();
  static final Vector3 _v = Vector3.zero();

  /// Below this a parent's scale on an axis counts as zero.
  static const double zeroScale = 1e-12;

  /// Set [child]'s world transform from [parent]'s and [link]'s local one.
  static void composeWorld(
    TransformComponent parent,
    ParentComponent link,
    TransformComponent child,
  ) {
    final a = parent.isPlanar ? parent.angle : 0.0;
    composeWorldWith(parent, link, child, math.cos(a), math.sin(a));
  }

  /// [composeWorld], given the cosine and sine of [parent]'s angle — worked
  /// out once for all of a parent's children. They are only read when
  /// [parent] is planar.
  static void composeWorldWith(
    TransformComponent parent,
    ParentComponent link,
    TransformComponent child,
    double c,
    double s,
  ) {
    final sP = parent.scale;
    final pL = link.localPosition;
    final sL = link.localScale;
    final rL = link.localRotation;

    // Position: pP + qP · (sP ⊙ pL).
    final vx = sP.x * pL.x, vy = sP.y * pL.y, vz = sP.z * pL.z;
    final pP = parent.position;
    if (parent.isPlanar) {
      child.position.setValues(
        pP.x + c * vx - s * vy,
        pP.y + s * vx + c * vy,
        pP.z + vz,
      );
    } else {
      parent.rotationInto(_qa);
      _v.setValues(vx, vy, vz);
      _qa.rotateInto(_v, _v);
      child.position.setValues(pP.x + _v.x, pP.y + _v.y, pP.z + _v.z);
    }

    // Rotation: qP · D(qL).
    if (parent.isPlanar && rL.isPlanar) {
      child.setEuler(0.0, 0.0, parent.angle + _flipZ(sP) * rL.z);
    } else {
      parent.rotationInto(_qa);
      rL.quaternionInto(_qb);
      _mirror(_qb, sP);
      _qb.premultiply(_qa);
      child.setRotation(_qb);
    }

    // Scale: sP ⊙ sL.
    child.scale.setValues(sP.x * sL.x, sP.y * sL.y, sP.z * sL.z);
  }

  /// Set [link]'s local transform so that [composeWorld] would give
  /// [child]'s current world transform under [parent].
  ///
  /// Returns false when the parent's scale is zero on some axis: nothing
  /// local can reproduce the child there, so that axis's local position is
  /// 0 and its local scale copies the child's.
  static bool localFromWorld(
    TransformComponent parent,
    TransformComponent child,
    ParentComponent link,
  ) {
    final a = parent.isPlanar ? parent.angle : 0.0;
    return localFromWorldWith(parent, child, link, math.cos(a), math.sin(a));
  }

  /// [localFromWorld], given the cosine and sine of [parent]'s angle. They
  /// are only read when [parent] is planar.
  static bool localFromWorldWith(
    TransformComponent parent,
    TransformComponent child,
    ParentComponent link,
    double c,
    double s,
  ) {
    final sP = parent.scale;
    final pP = parent.position;
    final pC = child.position;
    var exact = true;

    // Position: (qP⁻¹ · (pC − pP)) ⊘ sP.
    var dx = pC.x - pP.x, dy = pC.y - pP.y, dz = pC.z - pP.z;
    if (parent.isPlanar) {
      final rx = c * dx + s * dy;
      final ry = -s * dx + c * dy;
      dx = rx;
      dy = ry;
    } else {
      parent.rotationInto(_qa);
      _qa.conjugate();
      _v.setValues(dx, dy, dz);
      _qa.rotateInto(_v, _v);
      dx = _v.x;
      dy = _v.y;
      dz = _v.z;
    }
    final pL = link.localPosition;
    final sL = link.localScale;
    final sC = child.scale;
    if (sP.x.abs() < zeroScale) {
      pL.x = 0.0;
      sL.x = sC.x;
      exact = false;
    } else {
      pL.x = dx / sP.x;
      sL.x = sC.x / sP.x;
    }
    if (sP.y.abs() < zeroScale) {
      pL.y = 0.0;
      sL.y = sC.y;
      exact = false;
    } else {
      pL.y = dy / sP.y;
      sL.y = sC.y / sP.y;
    }
    if (sP.z.abs() < zeroScale) {
      pL.z = 0.0;
      sL.z = sC.z;
      exact = false;
    } else {
      pL.z = dz / sP.z;
      sL.z = sC.z / sP.z;
    }

    // Rotation: D(qP⁻¹ · qC).
    if (parent.isPlanar && child.isPlanar) {
      link.localRotation.setValues(
        0.0,
        0.0,
        _flipZ(sP) * (child.angle - parent.angle),
      );
    } else {
      parent.rotationInto(_qa);
      _qa.conjugate();
      child.rotationInto(_qb);
      _qb.premultiply(_qa);
      _mirror(_qb, sP);
      link.localRotation.setFromQuaternion(_qb);
    }
    return exact;
  }

  /// −1 when [s] mirrors a turn about Z (x and y scales of opposite sign).
  static double _flipZ(Vector3 s) => (s.x < 0) != (s.y < 0) ? -1.0 : 1.0;

  /// Conjugate [q] by the sign matrix of [s]: `F · R(q) · F`. Its own
  /// inverse.
  static void _mirror(Quaternion q, Vector3 s) {
    final fx = s.x < 0 ? -1.0 : 1.0;
    final fy = s.y < 0 ? -1.0 : 1.0;
    final fz = s.z < 0 ? -1.0 : 1.0;
    final det = fx * fy * fz;
    q.x *= det * fx;
    q.y *= det * fy;
    q.z *= det * fz;
  }
}

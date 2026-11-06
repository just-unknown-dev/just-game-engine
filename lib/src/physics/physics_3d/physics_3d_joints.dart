/// The joints side of `Physics3DSystem`.
library;

import 'dart:typed_data';

import 'package:just_physics_engine/physics_3d.dart';
import 'package:meta/meta.dart' show internal;

import '../../ecs/ecs.dart';
import 'physics_3d_components.dart';

/// The [Joint3DComponent]s side of `Physics3DSystem`, which owns one and
/// keeps them each update between bringing the bodies up to date and
/// stepping — the 3-D twin of the 2-D system's joints.
///
/// A joint is made once both its bodies exist — or its own and the world,
/// with no connected body — and made again when a setting changes. When a
/// body is made again (a new shape or scale) the physics engine takes its
/// joints with it: the joint is made again as it was, holding the second
/// body where it first did, not where the bodies have drifted to. A joint
/// whose connected body is its own entity's joins nothing.
@internal
final class Physics3DJoints {
  /// Joints in the world [physics] gives, between the bodies [bodyOf]
  /// names.
  Physics3DJoints(this._physics, this._bodyOf);

  final Physics3DWorld Function() _physics;
  final int Function(Entity entity) _bodyOf;

  final Map<Joint3DComponent, _JointLink> _joints = Map.identity();
  final Float64List _jointNow = Float64List(_JointLink._capacity);
  final Quaternion _q = Quaternion.identity();

  /// The joint components, by type, that make a joint.
  static const List<Type> types = [
    FixedJoint3DComponent,
    PointJoint3DComponent,
    HingeJoint3DComponent,
    SliderJoint3DComponent,
    DistanceJoint3DComponent,
    SixDofJoint3DComponent,
  ];

  /// Brings the links up to date with [world] at structure [version]: new
  /// joint components are linked, and the joints of those gone are taken
  /// down.
  void refresh(World world, int version) {
    for (final type in types) {
      for (final archetype in world.queryArchetypes([
        TransformComponent,
        type,
      ])) {
        final ids = archetype.entityIds;
        final comps = archetype.getColumn(type)!;
        for (var row = 0; row < ids.length; row++) {
          final entity = archetype.entityAt(row);
          final comp = comps[row] as Joint3DComponent;
          final link = _joints[comp] ??= _JointLink(entity, comp);
          link.version = version;
        }
      }
    }
    // Destroyed, or no longer carrying the components.
    _joints.removeWhere((_, link) {
      if (link.version == version) return false;
      _removeJoint(link);
      return true;
    });
  }

  /// Makes, makes again and takes down [world]'s joints to match their
  /// components and bodies.
  void sync(World world) {
    for (final link in _joints.values) {
      final comp = link.comp;
      final a = link.entity.isActiveInHierarchy ? _bodyOf(link.entity) : 0;
      int? b = 0;
      Entity? other;
      if (!comp.connectedBody.isNone) {
        other = comp.connectedBody.resolve(world, link.entity);
        // Its own entity is no other body (a target of Self, or a tag it
        // carries itself): a joint from a body to itself joins nothing.
        b = other == null || identical(other, link.entity)
            ? null
            : _bodyOf(other);
        if (b == 0) b = null;
      }
      if (a == 0 || b == null) {
        _removeJoint(link);
        link.heldB = null;
        continue;
      }
      if (link.joint != 0) {
        if (!link.madeFrom(comp, _jointNow) || !identical(link.other, other)) {
          // Changed: made again from where the bodies are now.
          _removeJoint(link);
          link.heldB = null;
        } else if (link.bodyA != a || link.bodyB != b) {
          // A body was made again (a new shape or scale) and the physics
          // engine took the joint with it: made again as it was, holding
          // the second body where it did — not where the bodies have
          // drifted to.
          _removeJoint(link);
        }
      }
      final physics = _physics();
      if (link.joint == 0) {
        final settings = _settings(world, link.entity, comp, b, link, other);
        final joint = physics.createJoint(a, b, settings);
        if (joint == 0) continue;
        link
          ..joint = joint
          ..bodyA = a
          ..bodyB = b
          ..other = other
          ..remember(comp)
          ..enabled = true
          ..motor = settings.motorState
          ..motorTarget = settings.motorTarget;
        comp.joint = joint;
      }
      if (comp.enabled != link.enabled) {
        physics.setJointEnabled(link.joint, link.enabled = comp.enabled);
      }
      var motor = Motor3DState.off;
      var target = 0.0;
      if (comp is HingeJoint3DComponent) {
        motor = comp.motor;
        target = comp.motorTarget;
      } else if (comp is SliderJoint3DComponent) {
        motor = comp.motor;
        target = comp.motorTarget;
      }
      if (motor != link.motor || target != link.motorTarget) {
        physics.setJointMotor(
          link.joint,
          link.motor = motor,
          link.motorTarget = target,
        );
      }
    }
  }

  /// Writes each hinge's angle and slider's position after the step.
  void readBack() {
    if (_joints.isEmpty) return;
    final physics = _physics();
    for (final link in _joints.values) {
      if (link.joint == 0) continue;
      switch (link.comp) {
        case HingeJoint3DComponent h:
          h.angle = physics.jointValue(link.joint);
        case SliderJoint3DComponent s:
          s.position = physics.jointValue(link.joint);
        default:
      }
    }
  }

  /// Takes every joint down — unless the world is gone already
  /// ([worldGone]) — and forgets every component.
  void removeAll({required bool worldGone}) {
    if (!worldGone) {
      for (final link in _joints.values) {
        _removeJoint(link);
      }
    }
    _joints.clear();
  }

  /// [comp]'s settings, in world space as the bodies are now. Where it
  /// holds the second body ([other]'s, [bodyB]; 0 for the world) is
  /// [link]'s [_JointLink.heldB] when it has one, and kept there for the
  /// next time.
  Joint3DSettings _settings(
    World world,
    Entity entity,
    Joint3DComponent comp,
    int bodyB,
    _JointLink link,
    Entity? other,
  ) {
    final transform = entity.getComponent<TransformComponent>()!;
    final pointA = _worldPoint(transform, comp.anchor);
    final pointB = comp is DistanceJoint3DComponent
        ? null
        : _heldPoint(link, pointA, bodyB == 0 ? null : other);
    Vector3 axisOf(Vector3 local) {
      transform.rotationInto(_q);
      final out = Vector3.copy(local);
      _q.rotate(out);
      if (out.lengthSquared < 1e-12) out.setValues(1, 0, 0);
      out.normalize();
      return out;
    }

    switch (comp) {
      case HingeJoint3DComponent h:
        final axis = axisOf(h.axis);
        return Joint3DSettings(
          kind: Joint3DKind.hinge,
          pointA: pointA,
          pointB: pointB,
          axis: axis,
          normal: _perpendicular(axis),
          hasLimits: h.useLimits,
          limitMin: h.minAngle,
          limitMax: h.maxAngle,
          maxFriction: h.friction,
          motorState: h.motor,
          motorTarget: h.motorTarget,
          motorMaxForce: h.motorMaxTorque,
        );
      case SliderJoint3DComponent s:
        final axis = axisOf(s.axis);
        return Joint3DSettings(
          kind: Joint3DKind.slider,
          pointA: pointA,
          pointB: pointB,
          axis: axis,
          normal: _perpendicular(axis),
          hasLimits: s.useLimits,
          limitMin: s.minPosition,
          limitMax: s.maxPosition,
          maxFriction: s.friction,
          motorState: s.motor,
          motorTarget: s.motorTarget,
          motorMaxForce: s.motorMaxForce,
        );
      case DistanceJoint3DComponent d:
        final otherTransform = bodyB == 0
            ? null
            : other?.getComponent<TransformComponent>();
        final pointB = otherTransform == null
            ? Vector3.copy(d.connectedAnchor)
            : _worldPoint(otherTransform, d.connectedAnchor);
        return Joint3DSettings(
          kind: Joint3DKind.distance,
          pointA: pointA,
          pointB: pointB,
          hasLimits: true,
          limitMin: d.minDistance,
          limitMax: d.maxDistance,
          springFrequency: d.springFrequency,
          springDamping: d.springDamping,
        );
      case SixDofJoint3DComponent x:
        return Joint3DSettings(
          kind: Joint3DKind.sixDof,
          pointA: pointA,
          pointB: pointB,
          axis: axisOf(x.axis),
          normal: axisOf(x.normal),
          sixDofModes: x.modes,
          sixDofMin: [
            x.translationMin.x,
            x.translationMin.y,
            x.translationMin.z,
            x.rotationMin.x,
            x.rotationMin.y,
            x.rotationMin.z,
          ],
          sixDofMax: [
            x.translationMax.x,
            x.translationMax.y,
            x.translationMax.z,
            x.rotationMax.x,
            x.rotationMax.y,
            x.rotationMax.z,
          ],
        );
      default:
        return Joint3DSettings(kind: comp.kind, pointA: pointA, pointB: pointB);
    }
  }

  /// Where [link] holds its second body, in world space: as it first did,
  /// in [other]'s space (the world's, held to the world), once it has been
  /// made; [pointA] the first time, remembered for the next.
  Vector3 _heldPoint(_JointLink link, Vector3 pointA, Entity? other) {
    final t = other?.getComponent<TransformComponent>();
    final held = link.heldB;
    if (held != null) {
      if (t == null) return Vector3.copy(held);
      final out = Vector3.copy(held);
      t.rotationInto(_q);
      _q.rotate(out);
      return out..add(t.position);
    }
    final local = Vector3.copy(pointA);
    if (t != null) {
      local.sub(t.position);
      t.rotationInto(_q);
      _q.conjugate();
      _q.rotate(local);
    }
    link.heldB = local;
    return Vector3.copy(pointA);
  }

  Vector3 _worldPoint(TransformComponent transform, Vector3 local) {
    final out = Vector3(
      local.x * transform.scale.x,
      local.y * transform.scale.y,
      local.z * transform.scale.z,
    );
    transform.rotationInto(_q);
    _q.rotate(out);
    out.add(transform.position);
    return out;
  }

  static Vector3 _perpendicular(Vector3 axis) {
    final helper = axis.x.abs() < 0.9 ? Vector3(1, 0, 0) : Vector3(0, 1, 0);
    final out = axis.cross(helper);
    out.normalize();
    return out;
  }

  void _removeJoint(_JointLink link) {
    if (link.joint == 0) return;
    // Gone already when one of its bodies was destroyed: a no-op then.
    _physics().destroyJoint(link.joint);
    link.joint = 0;
    link.comp.joint = 0;
  }
}

/// A joint component, and the physics engine's joint.
final class _JointLink {
  _JointLink(this.entity, this.comp);

  final Entity entity;
  final Joint3DComponent comp;
  int version = -1;
  int joint = 0;

  /// The bodies it holds, and the entity of the second (null: the world).
  int bodyA = 0, bodyB = 0;
  Entity? other;

  /// Where it holds the second body, in that body's space (the world's,
  /// held to the world), from when it was first made.
  Vector3? heldB;

  bool enabled = true;
  Motor3DState motor = Motor3DState.off;
  double motorTarget = 0;

  // What it was made from, but its motor and on/off switch (those are
  // changed on the live joint): compared field by field each step, with
  // nothing built.
  Joint3DKind? _kind;
  EntityTarget? _target;
  final Float64List _made = Float64List(_capacity);
  int _count = -1;

  static const int _capacity = 40;

  /// Whether [c] asks for the joint as it was made; [now] is scratch room
  /// for its settings.
  bool madeFrom(Joint3DComponent c, Float64List now) {
    if (_kind != c.kind || _target != c.connectedBody) return false;
    final n = _write(c, now);
    if (n != _count) return false;
    for (var i = 0; i < n; i++) {
      final x = now[i], y = _made[i];
      if (x != y && !(x.isNaN && y.isNaN)) return false;
    }
    return true;
  }

  void remember(Joint3DComponent c) {
    _kind = c.kind;
    _target = c.connectedBody;
    _count = _write(c, _made);
  }

  /// [c]'s settings as numbers into [out]; how many. Written out in full,
  /// with no closure: it runs for every joint every step.
  static int _write(Joint3DComponent c, Float64List out) {
    var n = _put3(out, 0, c.anchor);
    switch (c) {
      case HingeJoint3DComponent h:
        n = _put3(out, n, h.axis);
        out[n++] = h.useLimits ? 1 : 0;
        out[n++] = h.minAngle;
        out[n++] = h.maxAngle;
        out[n++] = h.friction;
        out[n++] = h.motorMaxTorque;
      case SliderJoint3DComponent s:
        n = _put3(out, n, s.axis);
        out[n++] = s.useLimits ? 1 : 0;
        out[n++] = s.minPosition;
        out[n++] = s.maxPosition;
        out[n++] = s.friction;
        out[n++] = s.motorMaxForce;
      case DistanceJoint3DComponent d:
        n = _put3(out, n, d.connectedAnchor);
        out[n++] = d.minDistance;
        out[n++] = d.maxDistance;
        out[n++] = d.springFrequency;
        out[n++] = d.springDamping;
      case SixDofJoint3DComponent x:
        n = _put3(out, n, x.axis);
        n = _put3(out, n, x.normal);
        final modes = x.modes;
        out[n++] = modes.length.toDouble();
        for (var i = 0; i < modes.length && i < 6; i++) {
          out[n++] = modes[i].index.toDouble();
        }
        n = _put3(out, n, x.translationMin);
        n = _put3(out, n, x.translationMax);
        n = _put3(out, n, x.rotationMin);
        n = _put3(out, n, x.rotationMax);
      default:
    }
    return n;
  }

  static int _put3(Float64List out, int n, Vector3 v) {
    out[n] = v.x;
    out[n + 1] = v.y;
    out[n + 2] = v.z;
    return n + 3;
  }
}

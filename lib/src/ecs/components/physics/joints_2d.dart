library;

import 'dart:ui' show Offset;

import '../../ecs.dart';

/// What a joint holds its entity's body to — in step with the 3-D
/// `Joint3D`. The joint is on one entity (A, which has a body: a
/// [RigidBody2D] and a [Collider2D]) and names the other ([connectedBody],
/// B). `PhysicsJointBindingSystem` makes it once both bodies exist, and
/// again when a setting changes.
abstract class Joint2D extends Component {
  /// A joint to [connectedBody].
  Joint2D({
    this.connectedBody = EntityTarget.none,
    this.anchor = Offset.zero,
    this.connectedAnchor = Offset.zero,
    this.collideConnected = false,
    this.enabled = true,
  });

  /// The other body's entity — by name or by tag.
  EntityTarget connectedBody;

  /// Where on this entity the joint holds, in its own space.
  Offset anchor;

  /// Where on the other entity it holds, in that entity's space.
  Offset connectedAnchor;

  /// Whether the two bodies still collide with each other.
  bool collideConnected;

  /// Whether the joint acts.
  bool enabled;
}

/// Keeps two bodies a set distance apart, springily.
class DistanceJoint2D extends Joint2D {
  /// A distance joint [length] long.
  DistanceJoint2D({
    super.connectedBody,
    super.anchor,
    super.connectedAnchor,
    super.collideConnected,
    super.enabled,
    this.length = 48.0,
    this.stiffness = 80.0,
    this.damping = 0.25,
  });

  /// How far apart the anchors are kept.
  double length;

  /// How stiff the spring holding them there is.
  double stiffness;

  /// How much the spring's swing is damped.
  double damping;
}

/// Holds two bodies rigidly together (Box2D calls it a weld).
class FixedJoint2D extends Joint2D {
  /// A fixed joint.
  FixedJoint2D({
    super.connectedBody,
    super.anchor,
    super.connectedAnchor,
    super.collideConnected,
    super.enabled,
  });
}

/// Lets two bodies slide along one axis: a drawer, a piston, a lift (Box2D
/// calls it prismatic).
class SliderJoint2D extends Joint2D {
  /// A slider along [axis].
  SliderJoint2D({
    super.connectedBody,
    super.anchor,
    super.connectedAnchor,
    super.collideConnected,
    super.enabled,
    this.axis = const Offset(1, 0),
    this.useLimits = false,
    this.minPosition = -20.0,
    this.maxPosition = 20.0,
    this.enableMotor = false,
    this.motorSpeed = 0.0,
    this.motorMaxForce = 200.0,
  });

  /// The axis it slides along, in this entity's space.
  Offset axis;

  /// Whether it slides only between [minPosition] and [maxPosition].
  bool useLimits;

  /// The limits along [axis].
  double minPosition, maxPosition;

  /// Whether a motor drives it at [motorSpeed].
  bool enableMotor;

  /// The motor's speed along [axis].
  double motorSpeed;

  /// The most force the motor uses.
  double motorMaxForce;
}

/// A wheel on a suspension along [axis].
class WheelJoint2D extends Joint2D {
  /// A wheel joint.
  WheelJoint2D({
    super.connectedBody,
    super.anchor,
    super.connectedAnchor,
    super.collideConnected,
    super.enabled,
    this.axis = const Offset(0, 1),
    this.stiffness = 45.0,
    this.damping = 0.65,
    this.enableMotor = true,
    this.motorSpeed = 12.0,
    this.motorMaxTorque = 250.0,
  });

  /// The suspension's axis, in this entity's space.
  Offset axis;

  /// How stiff the suspension is.
  double stiffness;

  /// How much the suspension's swing is damped.
  double damping;

  /// Whether a motor turns the wheel at [motorSpeed].
  bool enableMotor;

  /// The motor's speed, radians per second.
  double motorSpeed;

  /// The most torque the motor uses.
  double motorMaxTorque;
}

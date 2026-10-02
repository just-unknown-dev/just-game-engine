import 'package:flutter/painting.dart';
import '../../../ecs.dart';

/// Wheel suspension + motor joint data component.
/// Editor registration lives in WheelJointEditorComponent.
class WheelJointComponent extends Component {
  /// A wheel, the entity named [targetEntityName], sprung along +Y (down)
  /// at stiffness 45 and damping 0.65, its motor on at speed 12 with max
  /// torque 250; none is made while the name is empty.
  WheelJointComponent({
    this.targetEntityName = '',
    this.suspensionAxis = const Offset(0, 1),
    this.stiffness = 45.0,
    this.damping = 0.65,
    this.enableMotor = true,
    this.motorSpeed = 12.0,
    this.maxMotorTorque = 250.0,
    this.collideConnected = false,
  });

  /// Name of the entity whose body is the wheel; this entity's body is the
  /// chassis, and the joint is anchored at this entity's position. Both
  /// need a physics body. Empty, or naming no switched-on entity: no joint.
  String targetEntityName;

  /// The direction the wheel travels on its suspension, in world space.
  /// Normalised when the joint is made; +X when it has no length.
  Offset suspensionAxis;

  /// Suspension stiffness: the spring's frequency in hertz on the Box2D
  /// backend; without native wheel joints (the physics engine's Dart wheel
  /// joint), force per world unit of stretch.
  double stiffness;

  /// Suspension damping: a damping ratio (1 = critical) on the Box2D
  /// backend; without native wheel joints, force per unit of closing
  /// speed.
  double damping;

  /// Whether the motor drives the wheel towards [motorSpeed].
  bool enableMotor;

  /// The wheel's spin relative to the chassis that the motor drives
  /// towards, in radians per second — on both backends: without native
  /// wheel joints the physics engine's Dart wheel joint spins the wheel
  /// the same way.
  double motorSpeed;

  /// Most torque the motor may apply to reach [motorSpeed].
  double maxMotorTorque;

  /// Whether the wheel and chassis should still collide with each other.
  /// Not passed to the physics engine yet; a change only makes the joint
  /// again.
  bool collideConnected;
}

import 'package:flutter/painting.dart';
import '../../../ecs.dart';

/// Wheel suspension + motor joint data component.
/// Editor registration lives in WheelJointEditorComponent.
class WheelJointComponent extends Component {
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

  String targetEntityName;
  Offset suspensionAxis;
  double stiffness;
  double damping;
  bool enableMotor;
  double motorSpeed;
  double maxMotorTorque;
  bool collideConnected;
}

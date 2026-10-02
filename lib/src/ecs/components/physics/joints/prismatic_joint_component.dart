import 'package:flutter/painting.dart';
import '../../../ecs.dart';

/// Prismatic/slider joint data component.
/// Editor registration lives in PrismaticJointEditorComponent.
///
/// Acts on the Dart physics backend (and where Box2D falls back to it).
/// With native Box2D running, just_physics_engine cannot make a prismatic
/// joint yet: the joint does nothing there, and a debug build says so once.
class PrismaticJointComponent extends Component {
  /// A slider along +X to the entity named [targetEntityName], with its
  /// limit (±20 world units) and motor (max force 200) both off; none is
  /// made while the name is empty.
  PrismaticJointComponent({
    this.targetEntityName = '',
    this.axis = const Offset(1, 0),
    this.enableLimit = false,
    this.lowerTranslation = -20.0,
    this.upperTranslation = 20.0,
    this.enableMotor = false,
    this.motorSpeed = 0.0,
    this.maxMotorForce = 200.0,
    this.collideConnected = false,
  });

  /// Name of the entity whose body slides against this entity's body; both
  /// need a physics body. Empty, or naming no switched-on entity: no joint.
  String targetEntityName;

  /// The direction the bodies may slide along, in world space. Normalised
  /// when the joint is made; +X when it has no length.
  Offset axis;

  /// Whether the slide is kept between [lowerTranslation] and
  /// [upperTranslation].
  bool enableLimit;

  /// Least offset of the target's body from this one along [axis], in
  /// world units, while [enableLimit] is on.
  double lowerTranslation;

  /// Greatest offset of the target's body from this one along [axis], in
  /// world units, while [enableLimit] is on.
  double upperTranslation;

  /// Whether a motor drives the slide towards [motorSpeed].
  bool enableMotor;

  /// Speed the motor drives the target's body along [axis], relative to
  /// this one, in world units per second; negative runs the other way.
  double motorSpeed;

  /// Most force the motor may apply to reach [motorSpeed].
  double maxMotorForce;

  /// Whether the two jointed bodies should still collide with each other.
  /// Not passed to the physics engine yet; a change only makes the joint
  /// again.
  bool collideConnected;
}

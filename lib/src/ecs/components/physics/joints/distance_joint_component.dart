import 'package:flutter/painting.dart';
import '../../../ecs.dart';

/// Distance/spring joint data component.
/// Editor registration lives in DistanceJointEditorComponent.
class DistanceJointComponent extends Component {
  /// A joint 48 world units long, with a spring of stiffness 80 and
  /// damping 0.25, to the entity named [targetEntityName]; none is made
  /// while that is empty.
  DistanceJointComponent({
    this.targetEntityName = '',
    this.localAnchorA = Offset.zero,
    this.localAnchorB = Offset.zero,
    this.length = 48.0,
    this.stiffness = 80.0,
    this.damping = 0.25,
    this.collideConnected = false,
  });

  /// Name of the entity whose body is joined to this entity's body; both
  /// need a physics body. Empty, or naming no switched-on entity: no joint.
  String targetEntityName;

  /// Where the joint holds this entity's body, in the body's local space.
  /// Saved, but not passed to the physics engine yet: the joint holds the
  /// bodies by their centres.
  Offset localAnchorA;

  /// Where the joint holds the target's body, in its local space. Not
  /// passed to the physics engine yet, like [localAnchorA].
  Offset localAnchorB;

  /// Distance kept between the two bodies, in world units.
  double length;

  /// Spring stiffness; 0 holds [length] rigidly. The Dart physics backend
  /// reads it as force per world unit of stretch, the Box2D backend as the
  /// spring's frequency in hertz — but just_physics_engine does not switch
  /// the native spring on yet, so on native Box2D the joint holds [length]
  /// rigidly whatever this is.
  double stiffness;

  /// Spring damping. The Dart backend reads it as force per unit of
  /// closing speed, the Box2D backend as a damping ratio (1 = critical).
  double damping;

  /// Whether the two jointed bodies should still collide with each other.
  /// Not passed to the physics engine yet; a change only makes the joint
  /// again.
  bool collideConnected;
}

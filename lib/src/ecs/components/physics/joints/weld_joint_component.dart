import 'package:flutter/painting.dart';
import '../../../ecs.dart';

/// Rigid weld joint data component.
/// Editor registration lives in WeldJointEditorComponent.
class WeldJointComponent extends Component {
  /// A weld to the entity named [targetEntityName]; none is made while that
  /// is empty.
  WeldJointComponent({
    this.targetEntityName = '',
    this.localAnchorA = Offset.zero,
    this.localAnchorB = Offset.zero,
    this.collideConnected = false,
  });

  /// Name of the entity whose body is welded to this entity's body; both
  /// need a physics body. Empty, or naming no switched-on entity: no joint.
  String targetEntityName;

  /// Where the weld holds this entity's body, in the body's local space.
  /// Saved, and a change makes the joint again, but not passed to the
  /// physics engine yet: the bodies are held as they were when welded.
  Offset localAnchorA;

  /// Where the weld holds the target's body, in its local space. Saved,
  /// and a change makes the joint again, but not passed to the physics
  /// engine yet, like [localAnchorA].
  Offset localAnchorB;

  /// Whether the two welded bodies should still collide with each other.
  /// Not passed to the physics engine yet; a change only makes the joint
  /// again.
  bool collideConnected;
}

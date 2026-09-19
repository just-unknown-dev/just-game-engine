import 'package:flutter/painting.dart';
import '../../../ecs.dart';

/// Distance/spring joint data component.
/// Editor registration lives in DistanceJointEditorComponent.
class DistanceJointComponent extends Component {
  DistanceJointComponent({
    this.targetEntityName = '',
    this.localAnchorA = Offset.zero,
    this.localAnchorB = Offset.zero,
    this.length = 48.0,
    this.stiffness = 80.0,
    this.damping = 0.25,
    this.collideConnected = false,
  });

  String targetEntityName;
  Offset localAnchorA;
  Offset localAnchorB;
  double length;
  double stiffness;
  double damping;
  bool collideConnected;
}

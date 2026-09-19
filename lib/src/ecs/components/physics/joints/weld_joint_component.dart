import 'package:flutter/painting.dart';
import '../../../ecs.dart';

/// Rigid weld joint data component.
/// Editor registration lives in WeldJointEditorComponent.
class WeldJointComponent extends Component {
  WeldJointComponent({
    this.targetEntityName = '',
    this.localAnchorA = Offset.zero,
    this.localAnchorB = Offset.zero,
    this.collideConnected = false,
  });

  String targetEntityName;
  Offset localAnchorA;
  Offset localAnchorB;
  bool collideConnected;
}

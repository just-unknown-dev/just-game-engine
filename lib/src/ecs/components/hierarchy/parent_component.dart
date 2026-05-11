library;

import '../../ecs.dart';
import 'package:just_dart/just_dart.dart';

/// Parent-child component - Hierarchy relationships
class ParentComponent extends Component {
  /// Parent entity ID (null if root)
  EntityId? parentId;

  /// Local offset from parent in 3-D space.
  Vector3 localOffset;

  /// Local rotation offset (Z-axis).
  double localRotation;

  /// Create a parent component
  ParentComponent({
    this.parentId,
    Vector3? localOffset,
    this.localRotation = 0.0,
  }) : localOffset = localOffset ?? Vector3.zero();

  @override
  String toString() => 'Parent($parentId)';
}

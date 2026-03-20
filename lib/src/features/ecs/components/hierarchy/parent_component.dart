library;

import 'package:flutter/material.dart';

import '../../ecs.dart';

/// Parent-child component - Hierarchy relationships
class ParentComponent extends Component {
  /// Parent entity ID (null if root)
  EntityId? parentId;

  /// Local offset from parent
  Offset localOffset;

  /// Local rotation offset
  double localRotation;

  /// Create a parent component
  ParentComponent({
    this.parentId,
    this.localOffset = Offset.zero,
    this.localRotation = 0.0,
  });

  @override
  String toString() => 'Parent($parentId)';
}

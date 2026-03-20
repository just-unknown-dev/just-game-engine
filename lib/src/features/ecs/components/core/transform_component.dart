library;

import 'package:flutter/material.dart';

import '../../ecs.dart';

/// Transform component - Position, rotation, and scale
class TransformComponent extends Component {
  /// Entity position
  Offset position;

  /// Entity rotation (radians)
  double rotation;

  /// Entity scale
  double scale;

  /// Create a transform component
  TransformComponent({
    this.position = Offset.zero,
    this.rotation = 0.0,
    this.scale = 1.0,
  });

  /// Move by offset
  void translate(Offset offset) {
    position += offset;
  }

  /// Rotate by angle
  void rotate(double angle) {
    rotation += angle;
  }

  @override
  String toString() =>
      'Transform(pos: $position, rot: $rotation, scale: $scale)';
}

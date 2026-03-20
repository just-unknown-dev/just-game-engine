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

  /// Move by [direction] scaled by [dt] using a single Offset allocation.
  void translateScaled(Offset direction, double dt) {
    position = Offset(
      position.dx + direction.dx * dt,
      position.dy + direction.dy * dt,
    );
  }

  /// Set position from raw doubles — avoids [Offset] boxing in hot paths.
  void setPositionXY(double x, double y) {
    position = Offset(x, y);
  }

  /// Translate by raw doubles — avoids [Offset] boxing in hot paths.
  void translateXY(double dx, double dy) {
    position = Offset(position.dx + dx, position.dy + dy);
  }

  /// Rotate by angle
  void rotate(double angle) {
    rotation += angle;
  }

  @override
  String toString() =>
      'Transform(pos: $position, rot: $rotation, scale: $scale)';
}

/// Abstract camera contract.
///
/// ECS systems depend on this rather than the concrete [Camera] class,
/// keeping the ECS layer decoupled from the camera subsystem implementation.
library;

import 'package:flutter/material.dart';

/// Minimal camera interface consumed by ECS render systems.
abstract interface class GameCamera {
  /// Camera position in world space.
  Offset get position;

  /// Viewport size (set by the rendering system each frame).
  Size get viewportSize;
  set viewportSize(Size size);

  /// Apply the camera's view transform to [canvas].
  void applyTransform(Canvas canvas, Size size);

  /// Return the axis-aligned visible area in world space.
  Rect getVisibleBounds();
}

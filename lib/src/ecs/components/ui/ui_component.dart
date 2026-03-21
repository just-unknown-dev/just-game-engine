/// UI base component.
library;

import 'package:flutter/material.dart';

import '../../ecs.dart';

/// Base UI component for ECS-driven interface elements.
class UIComponent extends Component {
  /// UI element size in logical pixels.
  Size size;

  /// Whether this UI element is visible.
  bool visible;

  /// Whether this UI element can receive input.
  bool enabled;

  /// Optional local layer hint for UI ordering.
  int layer;

  /// Create a base UI component.
  UIComponent({
    required this.size,
    this.visible = true,
    this.enabled = true,
    this.layer = 0,
  });

  /// World-space bounds helper for hit testing.
  Rect boundsAt(Offset position) {
    return Rect.fromCenter(
      center: position,
      width: size.width,
      height: size.height,
    );
  }

  /// True if [point] is inside this element when centered at [position].
  bool containsPoint(Offset point, Offset position) {
    return boundsAt(position).contains(point);
  }

  @override
  String toString() =>
      'UI(size: ${size.width}x${size.height}, visible: $visible, enabled: $enabled)';
}

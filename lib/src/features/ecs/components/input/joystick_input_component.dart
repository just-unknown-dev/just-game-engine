library;

import 'package:flutter/material.dart';

import '../../ecs.dart';

/// Joystick placement behavior for input components.
enum JoystickInputLayout {
  /// Joystick base is anchored to a fixed position.
  fixed,

  /// Joystick base appears where touch/drag begins.
  floating,
}

/// Axis lock mode for joystick input.
enum JoystickInputAxis {
  /// Allow movement on both axes.
  both,

  /// Allow movement on horizontal axis only.
  horizontal,

  /// Allow movement on vertical axis only.
  vertical,
}

/// Joystick input component for ECS-driven touch controls.
class JoystickInputComponent extends Component {
  /// Normalized movement direction in range [-1, 1].
  Offset direction;

  /// Current joystick base position in screen space.
  Offset basePosition;

  /// Current joystick thumb position in screen space.
  Offset thumbPosition;

  /// Active pointer id controlling this joystick.
  int? pointerId;

  /// Whether the joystick is actively being dragged.
  bool isActive;

  /// Joystick base radius in logical pixels.
  double radius;

  /// Dead-zone threshold in logical pixels.
  double deadZone;

  /// Fixed or floating joystick behavior.
  JoystickInputLayout layout;

  /// Axis lock mode.
  JoystickInputAxis axis;

  /// Create a joystick input component.
  JoystickInputComponent({
    this.direction = Offset.zero,
    this.basePosition = Offset.zero,
    this.thumbPosition = Offset.zero,
    this.pointerId,
    this.isActive = false,
    this.radius = 64,
    this.deadZone = 8,
    this.layout = JoystickInputLayout.floating,
    this.axis = JoystickInputAxis.both,
  });

  /// True if the joystick currently has meaningful input.
  bool get hasInput => direction.distance > 0.001;

  /// Reset runtime state to neutral.
  void reset() {
    direction = Offset.zero;
    pointerId = null;
    isActive = false;
    thumbPosition = basePosition;
  }

  /// Update normalized direction from a raw delta vector.
  void setDirectionFromDelta(Offset delta) {
    if (delta.distance <= deadZone) {
      direction = Offset.zero;
      return;
    }

    var normalized = Offset(
      (delta.dx / radius).clamp(-1.0, 1.0),
      (delta.dy / radius).clamp(-1.0, 1.0),
    );

    switch (axis) {
      case JoystickInputAxis.both:
        break;
      case JoystickInputAxis.horizontal:
        normalized = Offset(normalized.dx, 0);
      case JoystickInputAxis.vertical:
        normalized = Offset(0, normalized.dy);
    }

    direction = normalized;
  }

  @override
  String toString() =>
      'JoystickInput(active: $isActive, dir: $direction, layout: $layout, axis: $axis)';
}

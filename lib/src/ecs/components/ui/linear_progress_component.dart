/// UI linear progress component.
library;

import 'package:flutter/material.dart';

import 'ui_component.dart';

/// Linear UI progress bar component data.
class LinearProgressComponent extends UIComponent {
  /// Progress value in range 0..1.
  double progress;

  /// Fill color for progressed area.
  Color progressColor;

  /// Track/background color.
  Color trackColor;

  /// Optional border color.
  Color? borderColor;

  /// Corner radius for the bar shape.
  double borderRadius;

  /// Create a linear progress UI component.
  LinearProgressComponent({
    required super.size,
    double initialProgress = 0,
    this.progressColor = const Color(0xFF64B5F6),
    this.trackColor = const Color(0xFF263238),
    this.borderColor,
    this.borderRadius = 6,
    super.visible,
    super.enabled = false,
    super.layer,
  }) : progress = initialProgress.clamp(0.0, 1.0);

  /// Set progress with clamping.
  void setProgress(double value) {
    progress = value.clamp(0.0, 1.0);
  }

  @override
  String toString() =>
      'UILinearProgress(${(progress * 100).toStringAsFixed(1)}%)';
}

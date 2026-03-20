/// UI circular progress component.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'ui_component.dart';

/// Circular UI progress bar component data.
class CircularProgressComponent extends UIComponent {
  /// Progress value in range 0..1.
  double progress;

  /// Stroke width of the circular progress track and arc.
  double strokeWidth;

  /// Progress arc color.
  Color progressColor;

  /// Track/background color.
  Color trackColor;

  /// Start angle in radians for the arc origin.
  double startAngle;

  /// Whether the arc grows clockwise.
  bool clockwise;

  /// Create a circular progress UI component.
  CircularProgressComponent({
    required double radius,
    double initialProgress = 0,
    this.strokeWidth = 6,
    this.progressColor = const Color(0xFF80CBC4),
    this.trackColor = const Color(0xFF2D3B3B),
    this.startAngle = -math.pi / 2,
    this.clockwise = true,
    super.visible,
    super.enabled = false,
    super.layer,
  }) : progress = initialProgress.clamp(0.0, 1.0),
       super(size: Size(radius * 2, radius * 2));

  /// Radius derived from component size.
  double get radius => size.width / 2;

  /// Set progress with clamping.
  void setProgress(double value) {
    progress = value.clamp(0.0, 1.0);
  }

  @override
  String toString() =>
      'UICircularProgress(${(progress * 100).toStringAsFixed(1)}%)';
}

library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../ecs.dart';

/// Velocity component - Linear velocity
class VelocityComponent extends Component {
  /// Velocity vector
  Offset velocity;

  /// Maximum speed (0 = unlimited)
  double maxSpeed;

  /// Create a velocity component
  VelocityComponent({this.velocity = Offset.zero, this.maxSpeed = 0.0});

  /// Get current speed
  double get speed => velocity.distance;

  /// Set velocity from angle and magnitude
  void setFromAngle(double angle, double magnitude) {
    velocity = Offset(magnitude * math.cos(angle), magnitude * math.sin(angle));
  }

  /// Clamp velocity to max speed
  void clampToMaxSpeed() {
    if (maxSpeed > 0 && speed > maxSpeed) {
      velocity = velocity / speed * maxSpeed;
    }
  }

  @override
  String toString() => 'Velocity($velocity)';
}

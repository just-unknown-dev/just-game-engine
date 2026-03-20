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

  /// Add a scaled vector using a single Offset allocation.
  void addScaled(Offset force, double dt) {
    velocity = Offset(velocity.dx + force.dx * dt, velocity.dy + force.dy * dt);
  }

  /// Multiply velocity in-place by [factor] using a single Offset allocation.
  void scale(double factor) {
    velocity = Offset(velocity.dx * factor, velocity.dy * factor);
  }

  /// Set velocity from raw doubles — avoids [Offset] boxing in hot paths.
  void setVelocityXY(double vx, double vy) {
    velocity = Offset(vx, vy);
  }

  @override
  String toString() => 'Velocity($velocity)';
}

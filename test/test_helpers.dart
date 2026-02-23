// Test helper file with simpler/mock implementations for testing
import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// Helper to create a basic circle renderable for tests
CircleRenderable createTestCircle({
  double radius = 10,
  Color? fillColor,
  int layer = 0,
  bool visible = true,
  double opacity = 1.0,
  Offset position = Offset.zero,
}) {
  return CircleRenderable(
    radius: radius,
    fillColor: fillColor ?? Colors.blue,
    layer: layer,
    visible: visible,
    opacity: opacity,
    position: position,
  );
}

/// Helper to create a particle emitter for testing
ParticleEmitter createTestEmitter({
  int maxParticles = 100,
  double emissionRate = 10,
  double particleLifetime = 1.0,
  Offset position = Offset.zero,
}) {
  return ParticleEmitter(
    maxParticles: maxParticles,
    emissionRate: emissionRate,
    particleLifetime: particleLifetime,
    position: position,
  );
}

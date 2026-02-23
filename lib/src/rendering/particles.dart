/// Particle System
///
/// Efficient particle effects system for visual effects like explosions, fire, smoke, etc.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../rendering/renderable.dart';

/// Particle emitter that creates and manages particles
class ParticleEmitter extends Renderable {
  /// Maximum number of particles
  final int maxParticles;

  /// Particles per second
  double emissionRate;

  /// Particle lifetime in seconds
  final double particleLifetime;

  /// Particle lifetime variation
  final double lifetimeVariation;

  /// Start size
  final double startSize;

  /// End size
  final double endSize;

  /// Size variation
  final double sizeVariation;

  /// Start color
  final Color startColor;

  /// End color
  final Color endColor;

  /// Emission angle in radians
  final double emissionAngle;

  /// Emission spread in radians
  final double emissionSpread;

  /// Speed
  final double speed;

  /// Speed variation
  final double speedVariation;

  /// Gravity
  final Offset gravity;

  /// Whether emitter is active
  bool isEmitting = true;

  /// Duration (null = infinite)
  final double? duration;

  /// Active particles
  final List<Particle> _particles = [];

  /// Time accumulator for emission
  double _emissionAccumulator = 0.0;

  /// Total time elapsed
  double _totalTime = 0.0;

  /// Random number generator
  final math.Random _random = math.Random();

  /// Particle shape
  final ParticleShape shape;

  /// Create a particle emitter
  ParticleEmitter({
    required this.maxParticles,
    this.emissionRate = 10,
    this.particleLifetime = 1.0,
    this.lifetimeVariation = 0.2,
    this.startSize = 5.0,
    this.endSize = 1.0,
    this.sizeVariation = 1.0,
    this.startColor = Colors.white,
    this.endColor = Colors.transparent,
    this.emissionAngle = 0.0,
    this.emissionSpread = math.pi * 2,
    this.speed = 100.0,
    this.speedVariation = 20.0,
    this.gravity = const Offset(0, 100),
    this.duration,
    this.shape = ParticleShape.circle,
    super.position,
    super.layer,
    super.zOrder,
  }) : assert(maxParticles > 0),
       assert(emissionRate >= 0),
       assert(particleLifetime > 0);

  /// Update the emitter
  void update(double deltaTime) {
    _totalTime += deltaTime;

    // Check if emission should stop
    if (duration != null && _totalTime >= duration!) {
      isEmitting = false;
    }

    // Emit new particles
    if (isEmitting) {
      _emissionAccumulator += deltaTime * emissionRate;
      while (_emissionAccumulator >= 1.0 && _particles.length < maxParticles) {
        _emitParticle();
        _emissionAccumulator -= 1.0;
      }
    }

    // Update existing particles
    _particles.removeWhere((particle) {
      particle.update(deltaTime, gravity);
      return particle.isDead;
    });
  }

  /// Emit a single particle
  void _emitParticle() {
    // Random angle within spread
    final angle = emissionAngle + (_random.nextDouble() - 0.5) * emissionSpread;

    // Random speed
    final particleSpeed =
        speed + (_random.nextDouble() - 0.5) * speedVariation * 2;

    // Random lifetime
    final lifetime =
        particleLifetime + (_random.nextDouble() - 0.5) * lifetimeVariation * 2;

    // Random size
    final size = startSize + (_random.nextDouble() - 0.5) * sizeVariation * 2;

    // Create velocity vector
    final velocity = Offset(
      math.cos(angle) * particleSpeed,
      math.sin(angle) * particleSpeed,
    );

    _particles.add(
      Particle(
        position: position,
        velocity: velocity,
        lifetime: lifetime,
        startSize: size,
        endSize: endSize,
        startColor: startColor,
        endColor: endColor,
        shape: shape,
      ),
    );
  }

  @override
  void render(Canvas canvas, Size size) {
    for (final particle in _particles) {
      particle.render(canvas);
    }
  }

  @override
  Rect? getBounds() {
    // Calculate approximate bounds based on particles
    if (_particles.isEmpty) return null;

    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;

    for (final particle in _particles) {
      minX = math.min(minX, particle.position.dx);
      minY = math.min(minY, particle.position.dy);
      maxX = math.max(maxX, particle.position.dx);
      maxY = math.max(maxY, particle.position.dy);
    }

    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  /// Get active particle count
  int get particleCount => _particles.length;

  /// Reset the emitter
  void reset() {
    _particles.clear();
    _emissionAccumulator = 0.0;
    _totalTime = 0.0;
    isEmitting = true;
  }

  /// Burst emit particles
  void burst(int count) {
    for (int i = 0; i < count && _particles.length < maxParticles; i++) {
      _emitParticle();
    }
  }
}

/// Individual particle
class Particle {
  /// Current position
  Offset position;

  /// Velocity
  Offset velocity;

  /// Maximum lifetime
  final double lifetime;

  /// Current age
  double age = 0.0;

  /// Start size
  final double startSize;

  /// End size
  final double endSize;

  /// Start color
  final Color startColor;

  /// End color
  final Color endColor;

  /// Particle shape
  final ParticleShape shape;

  /// Create a particle
  Particle({
    required this.position,
    required this.velocity,
    required this.lifetime,
    required this.startSize,
    required this.endSize,
    required this.startColor,
    required this.endColor,
    required this.shape,
  });

  /// Update particle
  void update(double deltaTime, Offset gravity) {
    age += deltaTime;

    // Apply gravity
    velocity += gravity * deltaTime;

    // Update position
    position += velocity * deltaTime;
  }

  /// Check if particle is dead
  bool get isDead => age >= lifetime;

  /// Get normalized life (0.0 to 1.0)
  double get normalizedLife => (age / lifetime).clamp(0.0, 1.0);

  /// Get current size
  double get currentSize {
    return ui.lerpDouble(startSize, endSize, normalizedLife) ?? startSize;
  }

  /// Get current color
  Color get currentColor {
    return Color.lerp(startColor, endColor, normalizedLife) ?? startColor;
  }

  /// Render the particle
  void render(Canvas canvas) {
    final paint = Paint()
      ..color = currentColor
      ..style = PaintingStyle.fill;

    final size = currentSize;

    switch (shape) {
      case ParticleShape.circle:
        canvas.drawCircle(position, size / 2, paint);
        break;

      case ParticleShape.square:
        canvas.drawRect(
          Rect.fromCenter(center: position, width: size, height: size),
          paint,
        );
        break;

      case ParticleShape.triangle:
        final path = Path()
          ..moveTo(position.dx, position.dy - size / 2)
          ..lineTo(position.dx + size / 2, position.dy + size / 2)
          ..lineTo(position.dx - size / 2, position.dy + size / 2)
          ..close();
        canvas.drawPath(path, paint);
        break;

      case ParticleShape.star:
        _drawStar(canvas, position, size / 2, paint);
        break;
    }
  }

  /// Draw a star shape
  void _drawStar(Canvas canvas, Offset center, double radius, Paint paint) {
    const points = 5;
    final path = Path();

    for (int i = 0; i < points * 2; i++) {
      final angle = (i * math.pi / points) - math.pi / 2;
      final r = i % 2 == 0 ? radius : radius / 2;
      final x = center.dx + r * math.cos(angle);
      final y = center.dy + r * math.sin(angle);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    path.close();
    canvas.drawPath(path, paint);
  }
}

/// Particle shape enum
enum ParticleShape { circle, square, triangle, star }

/// Predefined particle effects
class ParticleEffects {
  /// Create an explosion effect
  static ParticleEmitter explosion({
    required Offset position,
    int particleCount = 50,
    Color color = Colors.orange,
  }) {
    return ParticleEmitter(
      maxParticles: particleCount,
      emissionRate: 1000, // Burst immediately
      particleLifetime: 1.0,
      lifetimeVariation: 0.3,
      startSize: 8.0,
      endSize: 2.0,
      sizeVariation: 3.0,
      startColor: color,
      endColor: color.withValues(alpha: 0),
      emissionAngle: 0,
      emissionSpread: math.pi * 2,
      speed: 150,
      speedVariation: 50,
      gravity: const Offset(0, 100),
      duration: 0.1, // Emit for 0.1 seconds
      position: position,
      shape: ParticleShape.circle,
    );
  }

  /// Create a fire effect
  static ParticleEmitter fire({required Offset position}) {
    return ParticleEmitter(
      maxParticles: 100,
      emissionRate: 50,
      particleLifetime: 1.0,
      lifetimeVariation: 0.3,
      startSize: 6.0,
      endSize: 2.0,
      sizeVariation: 2.0,
      startColor: Colors.yellow,
      endColor: Colors.red.withValues(alpha: 0),
      emissionAngle: -math.pi / 2,
      emissionSpread: math.pi / 6,
      speed: 80,
      speedVariation: 20,
      gravity: const Offset(0, -50),
      position: position,
      shape: ParticleShape.circle,
    );
  }

  /// Create a smoke effect
  static ParticleEmitter smoke({required Offset position}) {
    return ParticleEmitter(
      maxParticles: 50,
      emissionRate: 20,
      particleLifetime: 2.0,
      lifetimeVariation: 0.5,
      startSize: 5.0,
      endSize: 15.0,
      sizeVariation: 3.0,
      startColor: Colors.grey.withValues(alpha: 0.8),
      endColor: Colors.grey.withValues(alpha: 0),
      emissionAngle: -math.pi / 2,
      emissionSpread: math.pi / 4,
      speed: 30,
      speedVariation: 10,
      gravity: const Offset(0, -20),
      position: position,
      shape: ParticleShape.circle,
    );
  }

  /// Create a sparkle effect
  static ParticleEmitter sparkle({required Offset position}) {
    return ParticleEmitter(
      maxParticles: 30,
      emissionRate: 15,
      particleLifetime: 0.8,
      lifetimeVariation: 0.2,
      startSize: 4.0,
      endSize: 0.5,
      sizeVariation: 1.0,
      startColor: Colors.white,
      endColor: Colors.yellow.withValues(alpha: 0),
      emissionAngle: 0,
      emissionSpread: math.pi * 2,
      speed: 40,
      speedVariation: 20,
      gravity: Offset.zero,
      position: position,
      shape: ParticleShape.star,
    );
  }

  /// Create a rain effect
  static ParticleEmitter rain({required Offset position, double width = 800}) {
    return ParticleEmitter(
      maxParticles: 200,
      emissionRate: 100,
      particleLifetime: 2.0,
      lifetimeVariation: 0.3,
      startSize: 2.0,
      endSize: 1.0,
      sizeVariation: 0.5,
      startColor: Colors.lightBlue.withValues(alpha: 0.6),
      endColor: Colors.lightBlue.withValues(alpha: 0),
      emissionAngle: math.pi / 2,
      emissionSpread: 0.1,
      speed: 300,
      speedVariation: 50,
      gravity: const Offset(0, 200),
      position: position,
      shape: ParticleShape.circle,
    );
  }

  /// Create a snow effect
  static ParticleEmitter snow({required Offset position}) {
    return ParticleEmitter(
      maxParticles: 100,
      emissionRate: 30,
      particleLifetime: 5.0,
      lifetimeVariation: 1.0,
      startSize: 4.0,
      endSize: 4.0,
      sizeVariation: 2.0,
      startColor: Colors.white.withValues(alpha: 0.9),
      endColor: Colors.white.withValues(alpha: 0),
      emissionAngle: math.pi / 2,
      emissionSpread: 0.2,
      speed: 50,
      speedVariation: 20,
      gravity: const Offset(0, 20),
      position: position,
      shape: ParticleShape.circle,
    );
  }
}

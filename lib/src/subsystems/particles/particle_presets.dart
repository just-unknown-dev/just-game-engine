part of 'particles.dart';

/// Ready-made particle effect factories.
///
/// All methods return a fully configured [ParticleEmitter] ready to add to
/// your scene.
///
/// ## Usage
/// ```dart
/// // Via RenderingEngine (auto-updated every frame)
/// engine.rendering.addManagedEmitter(
///   ParticleEffects.fire(position: player.position),
/// );
///
/// // Via ECS
/// world.addComponent(entity, ParticleEmitterComponent(
///   emitter: ParticleEffects.portal(position: Offset(400, 300)),
/// ));
/// ```
class ParticleEffects {
  ParticleEffects._();

  // ═══════════════════════════════════════════════════════════════════════════
  // Classic presets (upgraded with forces)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Omnidirectional burst of particles — suitable for hits, impacts, and
  /// explosions.
  ///
  /// Emits [particleCount] particles in 0.1 seconds then stops.
  static ParticleEmitter explosion({
    required Offset position,
    int particleCount = 50,
    Color color = Colors.orange,
  }) {
    return ParticleEmitter(
      position: position,
      maxParticles: particleCount,
      emissionRate: 1000,
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
      duration: 0.1,
      forces: [GravityForce(const Offset(0, 100)), DragForce(coefficient: 0.1)],
    );
  }

  /// Continuous upward fire effect.
  static ParticleEmitter fire({required Offset position}) {
    return ParticleEmitter(
      position: position,
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
      forces: [
        GravityForce(const Offset(0, -50)),
        WindForce(
          direction: const Offset(1, 0),
          strength: 10,
          turbulence: 20,
          frequency: 1.5,
        ),
        DragForce(coefficient: 0.05),
      ],
    );
  }

  /// Slow-rising smoke plume.
  static ParticleEmitter smoke({required Offset position}) {
    return ParticleEmitter(
      position: position,
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
      forces: [
        GravityForce(const Offset(0, -20)),
        WindForce(direction: const Offset(1, 0), strength: 5, turbulence: 5),
        DragForce(coefficient: 0.03),
      ],
    );
  }

  /// Magical twinkling sparkle burst.
  static ParticleEmitter sparkle({required Offset position}) {
    return ParticleEmitter(
      position: position,
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
      angularVelocity: math.pi,
      angularVelocityVariation: math.pi,
      renderer: StarParticleRenderer(),
      forces: [DragForce(coefficient: 0.08)],
    );
  }

  /// Falling rain effect.  [position] should be at the top of the screen.
  static ParticleEmitter rain({required Offset position, double width = 800}) {
    return ParticleEmitter(
      position: position,
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
      renderer: LineParticleRenderer(strokeWidth: 1.5),
      forces: [
        GravityForce(const Offset(0, 200)),
        WindForce(direction: const Offset(1, 0), strength: 15, turbulence: 5),
      ],
    );
  }

  /// Gently drifting snowfall.
  static ParticleEmitter snow({required Offset position}) {
    return ParticleEmitter(
      position: position,
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
      forces: [
        GravityForce(const Offset(0, 20)),
        NoiseForce(strength: 15, scale: 0.005, speed: 0.3),
        DragForce(coefficient: 0.02),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // New presets
  // ═══════════════════════════════════════════════════════════════════════════

  /// Swirling portal vortex effect — particles spiral inward with cyan-to-
  /// purple color transition.
  static ParticleEmitter portal({required Offset position}) {
    return ParticleEmitter(
      position: position,
      maxParticles: 120,
      emissionRate: 60,
      particleLifetime: 1.8,
      lifetimeVariation: 0.4,
      startSize: 6.0,
      endSize: 1.0,
      sizeVariation: 2.0,
      startColor: const Color(0xFF00E5FF), // cyan
      endColor: const Color(0x007B1FA2), // purple transparent
      emissionAngle: 0,
      emissionSpread: math.pi * 2,
      speed: 120,
      speedVariation: 40,
      angularVelocity: 3.0,
      angularVelocityVariation: 1.0,
      forces: [
        VortexForce(center: position, strength: 200, radius: 180),
        AttractorForce(center: position, strength: 80, radius: 200),
        DragForce(coefficient: 0.04),
      ],
    );
  }

  /// Arcane magic aura — softly glowing orbs with noise-driven paths.
  ///
  /// [color] defaults to a vivid magenta; pass any color to match the spell
  /// type.
  static ParticleEmitter magic({
    required Offset position,
    Color color = const Color(0xFFE040FB),
  }) {
    return ParticleEmitter(
      position: position,
      maxParticles: 60,
      emissionRate: 25,
      particleLifetime: 2.0,
      lifetimeVariation: 0.5,
      startSize: 8.0,
      endSize: 1.0,
      sizeVariation: 3.0,
      startColor: color,
      endColor: color.withValues(alpha: 0),
      emissionAngle: 0,
      emissionSpread: math.pi * 2,
      speed: 30,
      speedVariation: 15,
      forces: [
        AttractorForce(center: position, strength: 40, radius: 120),
        NoiseForce(strength: 120, scale: 0.01, speed: 0.6),
        DragForce(coefficient: 0.06),
      ],
    );
  }

  /// Blood / impact splatter — heavy gravity, floor bounce.
  ///
  /// [boundsBottom] defines the Y coordinate of the floor; defaults to 600.
  static ParticleEmitter bloodSplatter({
    required Offset position,
    int count = 30,
    double boundsBottom = 600,
  }) {
    return ParticleEmitter(
      position: position,
      maxParticles: count,
      emissionRate: 1000,
      particleLifetime: 1.2,
      lifetimeVariation: 0.3,
      startSize: 5.0,
      endSize: 3.0,
      sizeVariation: 2.0,
      startColor: const Color(0xFFB71C1C),
      endColor: const Color(0x88B71C1C),
      emissionAngle: -math.pi / 2,
      emissionSpread: math.pi * 1.2,
      speed: 180,
      speedVariation: 80,
      duration: 0.05,
      forces: [
        GravityForce(const Offset(0, 400)),
        BoundaryForce(
          bounds: Rect.fromLTRB(-10000, -10000, 10000, boundsBottom),
          behavior: ParticleBoundaryBehavior.bounce,
          restitution: 0.4,
        ),
        DragForce(coefficient: 0.05),
      ],
    );
  }

  /// Dust puff kicked up by a footstep or landing.
  ///
  /// [direction] biases the spread: `1.0` = right-facing, `-1.0` = left.
  static ParticleEmitter dustKick({
    required Offset position,
    double direction = 1.0,
  }) {
    final angle = direction >= 0 ? -math.pi * 0.7 : -math.pi * 0.3;
    return ParticleEmitter(
      position: position,
      maxParticles: 25,
      emissionRate: 1000,
      particleLifetime: 0.6,
      lifetimeVariation: 0.2,
      startSize: 8.0,
      endSize: 2.0,
      sizeVariation: 3.0,
      startColor: const Color(0xAAD2B48C), // tan
      endColor: const Color(0x00D2B48C),
      emissionAngle: angle,
      emissionSpread: math.pi * 0.5,
      speed: 100,
      speedVariation: 40,
      duration: 0.05,
      forces: [GravityForce(const Offset(0, 60)), DragForce(coefficient: 0.15)],
    );
  }

  /// Electric sparks — high-speed noise-driven particles rendered as streaks.
  static ParticleEmitter electricSparks({required Offset position}) {
    return ParticleEmitter(
      position: position,
      maxParticles: 80,
      emissionRate: 60,
      particleLifetime: 0.5,
      lifetimeVariation: 0.2,
      startSize: 3.0,
      endSize: 1.0,
      sizeVariation: 1.0,
      startColor: const Color(0xFFFFFF00),
      endColor: const Color(0x0000BFFF),
      emissionAngle: 0,
      emissionSpread: math.pi * 2,
      speed: 250,
      speedVariation: 100,
      renderer: LineParticleRenderer(strokeWidth: 2.0),
      forces: [
        NoiseForce(strength: 200, scale: 0.015, speed: 2.0),
        DragForce(coefficient: 0.12),
      ],
    );
  }

  /// Water splash — arcing droplets that bounce off a floor.
  static ParticleEmitter waterSplash({
    required Offset position,
    double floorY = 400,
  }) {
    return ParticleEmitter(
      position: position,
      maxParticles: 60,
      emissionRate: 1000,
      particleLifetime: 1.0,
      lifetimeVariation: 0.3,
      startSize: 4.0,
      endSize: 1.0,
      sizeVariation: 1.5,
      startColor: const Color(0xFF29B6F6),
      endColor: const Color(0x0029B6F6),
      emissionAngle: -math.pi / 2,
      emissionSpread: math.pi * 0.8,
      speed: 200,
      speedVariation: 80,
      duration: 0.05,
      forces: [
        GravityForce(const Offset(0, 300)),
        BoundaryForce(
          bounds: Rect.fromLTRB(-10000, -10000, 10000, floorY),
          behavior: ParticleBoundaryBehavior.bounce,
          restitution: 0.3,
        ),
        DragForce(coefficient: 0.06),
      ],
    );
  }

  /// Healing aura — green particles that rise gently from the target.
  static ParticleEmitter healAura({required Offset position}) {
    return ParticleEmitter(
      position: position,
      maxParticles: 40,
      emissionRate: 20,
      particleLifetime: 1.5,
      lifetimeVariation: 0.5,
      startSize: 6.0,
      endSize: 1.0,
      sizeVariation: 2.0,
      startColor: const Color(0xFF69F0AE),
      endColor: const Color(0x0069F0AE),
      emissionAngle: 0,
      emissionSpread: math.pi * 2,
      speed: 25,
      speedVariation: 10,
      forces: [
        GravityForce(const Offset(0, -30)),
        AttractorForce(
          center: position + const Offset(0, -60),
          strength: 30,
          radius: 80,
        ),
        NoiseForce(strength: 20, scale: 0.01),
        DragForce(coefficient: 0.04),
      ],
    );
  }

  /// Confetti burst — colorful rotating squares falling with drag.
  ///
  /// Sub-emitter example: [subEmitters] can be used to spawn smaller confetti
  /// on death for extra density.
  static ParticleEmitter confetti({required Offset position, int count = 80}) {
    return ParticleEmitter(
      position: position,
      maxParticles: count,
      emissionRate: 800,
      particleLifetime: 2.5,
      lifetimeVariation: 0.8,
      startSize: 10.0,
      endSize: 5.0,
      sizeVariation: 4.0,
      startColor: Colors.red,
      endColor: Colors.blue.withValues(alpha: 0.5),
      emissionAngle: -math.pi / 2,
      emissionSpread: math.pi,
      speed: 250,
      speedVariation: 100,
      duration: 0.1,
      angularVelocity: math.pi * 2,
      angularVelocityVariation: math.pi * 4,
      renderer: SquareParticleRenderer(),
      effect: _ConfettiEffect(),
      forces: [
        GravityForce(const Offset(0, 120)),
        DragForce(coefficient: 0.08),
        WindForce(direction: const Offset(1, 0), strength: 20, turbulence: 15),
      ],
    );
  }

  /// Lava embers rising from molten rock.
  static ParticleEmitter lavaEmbers({required Offset position}) {
    return ParticleEmitter(
      position: position,
      maxParticles: 60,
      emissionRate: 30,
      particleLifetime: 2.0,
      lifetimeVariation: 0.6,
      startSize: 5.0,
      endSize: 1.0,
      sizeVariation: 2.0,
      startColor: const Color(0xFFFF6F00), // amber
      endColor: const Color(0x00FF3D00), // deep orange transparent
      emissionAngle: -math.pi / 2,
      emissionSpread: math.pi / 3,
      speed: 60,
      speedVariation: 30,
      forces: [
        GravityForce(const Offset(0, -40)),
        WindForce(
          direction: const Offset(1, 0),
          strength: 8,
          turbulence: 12,
          frequency: 0.8,
        ),
        DragForce(coefficient: 0.04),
        NoiseForce(strength: 30, scale: 0.008),
      ],
    );
  }
}

// ─── Internal confetti effect ─────────────────────────────────────────────────

/// Randomizes the start color of each confetti square to create a rainbow look.
class _ConfettiEffect extends ParticleEffect {
  static const _colors = [
    Color(0xFFF44336), // red
    Color(0xFFFF9800), // orange
    Color(0xFFFFEB3B), // yellow
    Color(0xFF4CAF50), // green
    Color(0xFF2196F3), // blue
    Color(0xFF9C27B0), // purple
    Color(0xFFE91E63), // pink
    Color(0xFF00BCD4), // cyan
  ];

  final math.Random _random = math.Random();

  @override
  void onSpawn(Particle particle, ParticleEmitter emitter) {
    final c = _colors[_random.nextInt(_colors.length)];
    particle.startColor = c;
    particle.endColor = c.withValues(alpha: 0);
    // Store the initial random tint index, not required but demo for customData
    particle.customData = c;
  }
}

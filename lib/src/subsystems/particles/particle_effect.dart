part of 'particles.dart';

/// Base class for custom particle behaviors.
///
/// Extend [ParticleEffect] and override any combination of [onSpawn],
/// [onUpdate], and [onDeath] to implement fully custom particle logic.
///
/// Assign an instance to [ParticleEmitter.effect] to activate it.
///
/// ## Example — Spiral orbit effect
/// ```dart
/// class SpiralEffect extends ParticleEffect {
///   @override
///   void onSpawn(Particle particle, ParticleEmitter emitter) {
///     // Store the initial angle in customData
///     particle.customData = math.atan2(
///       particle.position.dy - emitter.position.dy,
///       particle.position.dx - emitter.position.dx,
///     );
///   }
///
///   @override
///   void onUpdate(Particle p, double dt, List<ParticleForce> forces) {
///     // Advance angle and tighten radius over lifetime
///     final angle = (p.customData as double) + dt * math.pi;
///     p.customData = angle;
///     final radius = p.startSize * (1 - p.normalizedLife) * 40;
///     p.position = Offset(
///       p.position.dx + math.cos(angle) * radius * dt,
///       p.position.dy + math.sin(angle) * radius * dt,
///     );
///     super.onUpdate(p, dt, forces); // still apply normal forces
///   }
/// }
/// ```
abstract class ParticleEffect {
  const ParticleEffect();

  /// Called immediately after a particle is spawned and initialized.
  ///
  /// Use this to write initial custom state into [Particle.customData],
  /// override the velocity/rotation, or apply an initial offset.
  void onSpawn(Particle particle, ParticleEmitter emitter) {}

  /// Called every tick to advance [particle] by [dt] seconds.
  ///
  /// The default implementation delegates to [Particle.update] which applies
  /// all [forces] and integrates position + rotation.
  ///
  /// Override to replace or augment particle physics.  Call `super.onUpdate`
  /// to retain normal force integration.
  void onUpdate(Particle particle, double dt, List<ParticleForce> forces) {
    particle.update(dt, forces);
  }

  /// Called just before a particle is returned to the pool (age >= lifetime).
  ///
  /// Use this to trigger secondary effects, sounds, or sub-emitter bursts
  /// (though the preferred way for the latter is [SubEmitterConfig]).
  void onDeath(Particle particle, ParticleEmitter emitter) {}
}

/// Advanced Particle System
///
/// Modular, high-performance particle effects system.
///
/// ## Architecture
/// The particle library (`particle_emitter.dart`) is split into focused
/// part-files:
///
/// - [Particle]             — per-particle simulation state (particle.dart)
/// - [ParticleRenderer]     — pluggable rendering strategies (particle_renderer.dart)
/// - [ParticleForce]        — composable physics forces (particle_force.dart)
/// - [ParticleEffect]       — custom spawn / update / death hooks (particle_effect.dart)
/// - [SubEmitterConfig]     — child-emitter triggers (sub_emitter_config.dart)
/// - [ParticleEmitter]      — the main emitter class (particle_emitter.dart)
/// - [ParticleEffects]      — 15 ready-made effect presets (particle_effects.dart)
///
/// ## Quick-start
/// ```dart
/// // On an entity; ParticleSystem updates it, RenderSystem draws it:
/// world.createEntityWithComponents([
///   TransformComponent(position: Vector3(100, 200, 0)),
///   ParticleEmitterComponent(
///     emitter: ParticleEffects.fire(position: Vector3.zero()),
///     syncPositionFromTransform: true,
///   ),
/// ]);
/// ```
library;

export 'particle_emitter.dart';
export 'particle_emitter_component.dart';
export 'particle_system.dart';

/// Advanced Particle System
///
/// Modular, high-performance particle effects system.
///
/// ## Architecture
/// This library is split into focused part-files:
///
/// - [Particle]             â€” per-particle simulation state (particle_data.dart)
/// - [ParticleRenderer]     â€” pluggable rendering strategies (particle_renderer.dart)
/// - [ParticleForce]        â€” composable physics forces (particle_force.dart)
/// - [ParticleEffect]       â€” custom spawn / update / death hooks (particle_effect.dart)
/// - [SubEmitterConfig]     â€” child-emitter triggers (sub_emitter_config.dart)
/// - [ParticleEmitter]      â€” the main emitter class (particle_emitter.dart)
/// - [ParticleEffects]      â€” 15 ready-made effect presets (particle_presets.dart)
///
/// ## Quick-start
/// ```dart
/// // Fire-and-forget via RenderingEngine:
/// engine.rendering.addManagedEmitter(
///   ParticleEffects.explosion(position: hitPosition),
/// );
///
/// // Via ECS (auto position-sync):
/// world.addComponent(entity, ParticleEmitterComponent(
///   emitter: ParticleEffects.fire(position: Offset.zero),
///   syncPositionFromTransform: true,
/// ));
/// ```
library;

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../rendering/impl/renderable.dart';

part 'particle_data.dart';
part 'particle_renderer.dart';
part 'particle_force.dart';
part 'particle_effect.dart';
part 'sub_emitter_config.dart';
part 'particle_emitter.dart';
part 'particle_presets.dart';

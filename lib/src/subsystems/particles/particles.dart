/// Advanced Particle System
///
/// Modular, high-performance particle effects system.
///
/// ## Architecture
/// This library is split into focused part-files:
///
/// - [Particle]             — per-particle simulation state (particle_data.dart)
/// - [ParticleRenderer]     — pluggable rendering strategies (particle_renderer.dart)
/// - [ParticleForce]        — composable physics forces (particle_force.dart)
/// - [ParticleEffect]       — custom spawn / update / death hooks (particle_effect.dart)
/// - [SubEmitterConfig]     — child-emitter triggers (sub_emitter_config.dart)
/// - [ParticleEmitter]      — the main emitter class (particle_emitter.dart)
/// - [ParticleEffects]      — 15 ready-made effect presets (particle_presets.dart)
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
import 'package:just_memory/just_memory.dart';
import '../rendering/impl/renderable.dart';
import 'package:just_dart/just_dart.dart';

part 'particle_data.dart';
part 'particle_renderer.dart';
part 'particle_force.dart';
part 'particle_effect.dart';
part 'sub_emitter_config.dart';
part 'particle_emitter.dart';
part 'particle_presets.dart';

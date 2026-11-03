/// Deterministic Effects System
///
/// Tick-based property effects that are fully reproducible from their integer
/// tick parameter alone. Designed to support networked multiplayer where all
/// peers must converge to identical simulation state.
///
/// ## Design contract
///
/// * Effects advance via integer `(prevElapsed, currElapsed)` pairs — no
///   floating-point delta time accumulation.
/// * [DeterministicEffect.applyTick] is a **pure delta** call: it computes
///   the difference in the eased value between `prevElapsed` and `currElapsed`
///   and adds that delta to the target component. Two effects on the same
///   entity stack additively.
/// * Fast-forward: calling `applyTick(ctx, 0, 50)` produces the same net
///   result as 50 individual `(k, k+1)` calls — enabling late-join reconnect.
/// * All effect state required to reconstruct mid-flight effects is included
///   in [EffectSnapshot] for lock-step snapshots or prediction rollback.
///
/// ## Usage
///
/// ```dart
/// final effectSystem = EffectSystem();
/// world.addSystem(effectSystem);
///
/// // Schedule a move followed by a shake:
/// effectSystem.scheduleEffect(
///   entity: myEntity,
///   effect: SequenceEffect(children: [
///     MoveEffect(to: Vector3(200, 100, 0), durationTicks: 60),
///     ShakeEffect(amplitude: 6, durationTicks: 20),
///   ]),
/// );
/// ```
library;

import 'dart:math' as math;
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../foundation/easings.dart';
import '../ecs/ecs.dart';
import '../rendering/renderable_component.dart';
import 'effect_component.dart';
import 'package:just_dart/just_dart.dart';

import 'effect_handle.dart';
import 'effect_context.dart';
import 'effect_player.dart';
import 'deterministic_effect.dart';

export 'effect_handle.dart';
export 'effect_context.dart';
export 'effect_player.dart';
export 'deterministic_effect.dart';
export 'effect_component.dart';

part 'easing_type.dart';

part 'built_in/move_effect.dart';
part 'built_in/scale_effect.dart';
part 'built_in/rotate_effect.dart';
part 'built_in/fade_effect.dart';
part 'built_in/color_tint_effect.dart';
part 'built_in/sequence_effect.dart';
part 'built_in/parallel_effect.dart';
part 'built_in/delay_effect.dart';
part 'built_in/repeat_effect.dart';
part 'built_in/shake_effect.dart';
part 'built_in/path_effect.dart';

part 'networking/effect_runtime.dart';
part 'networking/effect_snapshot.dart';
part 'networking/effect_serializer.dart';
part 'networking/effect_binary_codec.dart';

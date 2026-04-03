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
/// final effectSystem = EffectSystemECS();
/// world.addSystem(effectSystem);
///
/// // Schedule a move followed by a shake:
/// effectSystem.scheduleEffect(
///   entity: myEntity,
///   effect: SequenceEffect([
///     MoveEffect(to: Offset(200, 100), durationTicks: 60),
///     ShakeEffect(amplitude: 6, durationTicks: 20),
///   ]),
/// );
/// ```
library;

import 'dart:math' as math;
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../ecs/ecs.dart';
import '../../ecs/components/core/transform_component.dart';
import '../../ecs/components/rendering/renderable_component.dart';
import '../../ecs/components/effects/effect_component.dart';

import 'base/effect_handle.dart';
import 'base/effect_context.dart';
import 'base/effect_player.dart';
import 'base/deterministic_effect.dart';

export 'base/effect_handle.dart';
export 'base/effect_context.dart';
export 'base/effect_player.dart';
export 'base/deterministic_effect.dart';
export '../../ecs/components/effects/effect_component.dart';

part 'base/easing_type.dart';

part 'impl/move_effect.dart';
part 'impl/scale_effect.dart';
part 'impl/rotate_effect.dart';
part 'impl/fade_effect.dart';
part 'impl/color_tint_effect.dart';
part 'impl/sequence_effect.dart';
part 'impl/parallel_effect.dart';
part 'impl/delay_effect.dart';
part 'impl/repeat_effect.dart';
part 'impl/shake_effect.dart';
part 'impl/path_effect.dart';

part 'networking/effect_runtime.dart';
part 'networking/effect_snapshot.dart';
part 'networking/effect_serializer.dart';
part 'networking/effect_binary_codec.dart';

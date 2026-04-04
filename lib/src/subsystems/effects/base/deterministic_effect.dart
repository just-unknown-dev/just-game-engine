library;

import 'package:flutter/foundation.dart';

import 'effect_context.dart';

/// Abstract base for all deterministic tick-driven effects.
///
/// ## Delta-based additive application
///
/// [applyTick] receives absolute elapsed-tick counts `prevElapsed` and
/// `currElapsed` (both clamped to `[0, durationTicks]` by [EffectPlayer]).
/// Implementations compute the **delta** between the eased value at
/// `prevElapsed / durationTicks` and at `currElapsed / durationTicks`, then
/// **add** that delta to the target component field.
///
/// This means two effects that target the same property accumulate their
/// contributions: two [MoveEffect]s running simultaneously move the entity
/// by the vector sum of both displacements.
///
/// ## Determinism guarantee
///
/// Given the same `(durationTicks, params, prevElapsed, currElapsed)` inputs,
/// [applyTick] produces the same mutation regardless of platform, frame rate,
/// or wall-clock time. Reproducibility derives from integer tick arithmetic;
/// the only floating-point operation is the easing curve evaluation.
///
/// ## Fast-forward (reconnect)
///
/// Passing a large `currElapsed` (e.g., `(0, 50)`) to [applyTick] produces
/// the same cumulative delta as 50 individual `(k, k+1)` calls. This lets a
/// reconnecting client catch up to the current server tick in a single call.
///
/// ## Serialization
///
/// Every concrete subtype must implement [toJson] and expose [effectType].
/// The [EffectSerializer] uses [effectType] as the discriminator key and
/// invokes a registered factory to round-trip the effect. Runtime-captured
/// baselines (e.g., the entity's position when the effect started) should also
/// be included so mid-flight effects restore correctly after a snapshot.
abstract class DeterministicEffect {
  /// Duration of this effect in fixed game-loop ticks.
  ///
  /// One tick == one fixed-timestep update. At 60 UPS, 60 ticks = 1 second.
  final int durationTicks;

  /// When `true`, [EffectPlayer] resets and replays this effect indefinitely.
  bool loop;

  /// Called once when a non-looping effect reaches [durationTicks].
  VoidCallback? onComplete;

  /// Called at the boundary of each completed loop iteration when [loop] is
  /// `true`. Fire custom logic (sound, spawn) at each repeat.
  VoidCallback? onLoopComplete;

  DeterministicEffect({
    required this.durationTicks,
    this.loop = false,
    this.onComplete,
    this.onLoopComplete,
  }) : assert(durationTicks >= 1, 'durationTicks must be ≥ 1');

  // ── Core interface ────────────────────────────────────────────────────

  /// Apply the effect delta covering ticks `prevElapsed` → `currElapsed`.
  ///
  /// Both values are clamped to `[0, durationTicks]` before this call.
  ///
  /// Subclass contract:
  /// 1. On the **first** call (`prevElapsed == 0`), capture the entity's
  ///    current component value as the effect's "from" baseline.
  /// 2. Compute `prevT = prevElapsed / durationTicks` and
  ///    `currT = currElapsed / durationTicks`.
  /// 3. Evaluate the easing function at both points and apply the delta.
  void applyTick(EffectContext ctx, int prevElapsed, int currElapsed);

  /// Reset mutable state so the effect can be replayed by [EffectPlayer]
  /// on loop restart.
  ///
  /// Subclasses that capture a runtime baseline must clear it here.
  @mustCallSuper
  void reset() {}

  // ── Helpers for subclasses ────────────────────────────────────────────

  /// Normalised progress for [elapsed] ticks in `[0.0, 1.0]`.
  @protected
  double tAt(int elapsed) =>
      durationTicks > 0 ? (elapsed / durationTicks).clamp(0.0, 1.0) : 1.0;

  // ── Serialization ─────────────────────────────────────────────────────

  /// Unique string discriminator used by [EffectSerializer].
  ///
  /// Must be stable (do not rename without a migration path).
  String get effectType;

  /// Encode this effect's parameters to a JSON-compatible map.
  ///
  /// The `'type'` key is added by [EffectSerializer.encodeEffect]; subclasses
  /// must **not** include it here. Include captured runtime baselines so
  /// [EffectSerializer.decodeEffect] can restore mid-flight effects.
  Map<String, dynamic> toJson();
}

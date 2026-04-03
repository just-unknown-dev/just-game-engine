library;

import 'effect_context.dart';
import 'effect_handle.dart';
import 'deterministic_effect.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Internal entry record
// ─────────────────────────────────────────────────────────────────────────────

/// Internal state for one scheduled effect within an [EffectPlayer].
class _EffectEntry {
  final EffectHandle handle;
  final DeterministicEffect effect;

  /// Absolute game-loop tick when this effect should begin.
  int startTick;

  /// Ticks of this effect already applied (0 → durationTicks).
  int processedElapsed = 0;

  _EffectEntry({
    required this.handle,
    required this.effect,
    required this.startTick,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// EffectPlayer
// ─────────────────────────────────────────────────────────────────────────────

/// Per-entity deterministic effect queue.
///
/// Owned by [EffectComponent]. [EffectSystemECS] calls [advanceTo] once per
/// game-loop tick, passing the current absolute tick number. The player
/// computes each effect's relative elapsed count and calls
/// [DeterministicEffect.applyTick] with `(prevElapsed, currElapsed)`.
///
/// ### Additive stacking
/// All active effects on the same entity run in registration order every tick.
/// Their component deltas accumulate additively: two overlapping [MoveEffect]s
/// result in a position that is the sum of both displacements.
///
/// ### Fast-forward
/// If `advanceTo` is called with a large `currentTick` jump (e.g. for a
/// reconnecting client catching up), each effect receives a wide
/// `(prevElapsed, currElapsed)` range. Because [DeterministicEffect.applyTick]
/// is defined to be equivalent whether called once wide or many times narrow,
/// the result is identical.
class EffectPlayer {
  final List<_EffectEntry> _entries = [];

  /// Number of active (non-cancelled) effects in the queue.
  int get activeCount =>
      _entries.fold(0, (n, e) => n + (e.handle.isCancelled ? 0 : 1));

  /// `true` when the internal entry list is empty (all effects done or none added).
  bool get isEmpty => _entries.isEmpty;

  // ── Mutation ───────────────────────────────────────────────────────────

  /// Enqueue [effect] to begin at [startTick].
  ///
  /// Returns an [EffectHandle] for later cancellation. The effect's first
  /// `applyTick(ctx, 0, 1)` is invoked on the tick where
  /// `currentTick - startTick == 1`.
  EffectHandle add(DeterministicEffect effect, int startTick) {
    final handle = EffectHandle.create(
      effectType: effect.effectType,
      startTick: startTick,
    );
    _entries.add(
      _EffectEntry(handle: handle, effect: effect, startTick: startTick),
    );
    return handle;
  }

  /// Cancel the effect associated with [handle].
  ///
  /// The entry is removed on the next [advanceTo] call.
  void cancel(EffectHandle handle) {
    handle.cancel();
    _entries.removeWhere((e) => e.handle.id == handle.id);
  }

  /// Cancel and remove all active effects.
  void cancelAll() {
    for (final e in _entries) {
      e.handle.cancel();
    }
    _entries.clear();
  }

  // ── Tick advance ────────────────────────────────────────────────────────

  /// Advance all active effects to [currentTick].
  ///
  /// For each live entry:
  /// - Skips entries whose [startTick] is still in the future.
  /// - Computes `targetElapsed = currentTick - startTick`, clamped to
  ///   `[0, durationTicks]`.
  /// - Calls [DeterministicEffect.applyTick] for the elapsed range since the
  ///   last advance.
  /// - Fires [DeterministicEffect.onComplete] and removes completed
  ///   non-looping entries.
  /// - Resets and re-queues looping entries from [currentTick].
  void advanceTo(int currentTick, EffectContext ctx) {
    int writeIdx = 0;
    for (int i = 0; i < _entries.length; i++) {
      final entry = _entries[i];

      // Drop cancelled entries.
      if (entry.handle.isCancelled) continue;

      final relativeElapsed = currentTick - entry.startTick;
      if (relativeElapsed <= 0) {
        // Effect not yet started — preserve.
        _entries[writeIdx++] = entry;
        continue;
      }

      final targetElapsed = relativeElapsed.clamp(
        0,
        entry.effect.durationTicks,
      );
      if (targetElapsed > entry.processedElapsed) {
        entry.effect.applyTick(ctx, entry.processedElapsed, targetElapsed);
        entry.processedElapsed = targetElapsed;
      }

      final isDone = entry.processedElapsed >= entry.effect.durationTicks;
      if (!isDone) {
        _entries[writeIdx++] = entry;
      } else if (entry.effect.loop) {
        entry.effect.onLoopComplete?.call();
        entry.effect.reset();
        entry.startTick = currentTick;
        entry.processedElapsed = 0;
        _entries[writeIdx++] = entry;
      } else {
        entry.effect.onComplete?.call();
        // Entry is not written — it is dropped.
      }
    }
    _entries.length = writeIdx;
  }

  // ── Serialization ────────────────────────────────────────────────────────

  /// Snapshot all active effects to a JSON-compatible list.
  ///
  /// Pass the resulting list to [fromJson] on another [EffectPlayer] (or
  /// after a reconnect) to restore mid-flight state.
  List<Map<String, dynamic>> toJson(
    Map<String, dynamic> Function(DeterministicEffect) encode,
  ) {
    return [
      for (final e in _entries)
        if (!e.handle.isCancelled)
          {
            'startTick': e.startTick,
            'processedElapsed': e.processedElapsed,
            'effect': encode(e.effect),
          },
    ];
  }

  /// Restore from a previously captured [toJson] snapshot.
  ///
  /// Existing effects are cleared. After restore, the next [advanceTo] call
  /// continues from [processedElapsed] without re-applying already-processed
  /// ticks.
  void fromJson(
    List<dynamic> json,
    DeterministicEffect Function(Map<String, dynamic>) decode,
    int restoredAtTick,
  ) {
    cancelAll();
    for (final raw in json.cast<Map<String, dynamic>>()) {
      final effect = decode(raw['effect'] as Map<String, dynamic>);
      final startTick = raw['startTick'] as int;
      final handle = EffectHandle.create(
        effectType: effect.effectType,
        startTick: startTick,
      );
      final entry = _EffectEntry(
        handle: handle,
        effect: effect,
        startTick: startTick,
      );
      entry.processedElapsed = raw['processedElapsed'] as int;
      _entries.add(entry);
    }
  }
}

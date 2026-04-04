part of '../effect_system.dart';

// ─────────────────────────────────────────────────────────────────────────────
// EffectRuntime interface
// ─────────────────────────────────────────────────────────────────────────────

/// Pluggable multiplayer coordination interface for deterministic effects.
///
/// [EffectSystemECS] implements this interface directly (used for both
/// single-player and lock-step multiplayer). For client-side prediction with
/// rollback use [PredictionEffectRuntime] instead.
///
/// ```dart
/// // Lock-step (default) — use EffectSystemECS directly:
/// final effectSystem = world.getSystem<EffectSystemECS>()!;
/// effectSystem.scheduleEffect(
///   entity: e,
///   effect: MoveEffect(to: Offset(300, 0), durationTicks: 60),
///   startTick: serverTick, // same on all peers → same result
/// );
/// ```
abstract interface class EffectRuntime {
  /// Current absolute tick count managed by this runtime.
  int get currentTick;

  /// Schedule [effect] on [entity] starting at [startTick].
  ///
  /// * [startTick] defaults to `currentTick` — the effect fires on the
  ///   next [EffectSystemECS.update] when `currentTick - startTick > 0`.
  /// * Pass a future tick to pre-schedule effects received from a server.
  /// * Pass a past server tick to fast-forward the effect to its current
  ///   state (reconnect / late-join scenario).
  EffectHandle scheduleEffect({
    required Entity entity,
    required DeterministicEffect effect,
    int? startTick,
  });

  /// Cancel [handle]'s effect on [entity].
  void cancelEffect(Entity entity, EffectHandle handle);

  /// Capture a full snapshot of all active effects and the current tick.
  ///
  /// Send this to a joining peer or store for rollback.
  EffectSnapshot snapshotState();

  /// Restore state from [snapshot] on the given [world].
  ///
  /// Re-populates [EffectPlayer]s so [EffectSystemECS] continues from the
  /// correct tick without re-applying already-processed deltas.
  void restoreSnapshot(EffectSnapshot snapshot, World world);
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared base
// ─────────────────────────────────────────────────────────────────────────────

/// Shared scheduling logic for [EffectRuntime] implementations.
///
/// [EffectSystemECS] implements [EffectRuntime] directly; this abstract base
/// is used only by [PredictionEffectRuntime].
abstract class _EffectRuntimeBase implements EffectRuntime {
  @override
  EffectHandle scheduleEffect({
    required Entity entity,
    required DeterministicEffect effect,
    int? startTick,
  }) {
    var comp = entity.getComponent<EffectComponent>();
    if (comp == null) {
      comp = EffectComponent();
      entity.addComponent(comp);
    }
    return comp.player.add(effect, startTick ?? currentTick);
  }

  @override
  void cancelEffect(Entity entity, EffectHandle handle) {
    entity.getComponent<EffectComponent>()?.player.cancel(handle);
  }

  @override
  EffectSnapshot snapshotState() {
    throw UnimplementedError(
      'Override snapshotState() in a subclass that has World access.',
    );
  }

  @override
  void restoreSnapshot(EffectSnapshot snapshot, World world) {
    throw UnimplementedError(
      'Override restoreSnapshot() in a subclass that has World access.',
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Prediction + rollback runtime (documented stub)
// ─────────────────────────────────────────────────────────────────────────────

/// [EffectRuntime] for **client-side prediction with rollback**.
///
/// Applies effects optimistically on the local client and stores a log of
/// scheduled entries within a rollback window. When the server sends an
/// authoritative correction the client can [rollbackTo] that tick, cancel
/// post-correction effects, and re-queue them for fast-forward.
///
/// **This is a well-documented stub.** Before shipping:
/// 1. Override [snapshotState] / [restoreSnapshot] with your authoritative
///    component-snapshot system.
/// 2. Wire [rollbackTo] from your server-correction message handler.
/// 3. Call [advanceTick] each physics frame to keep [currentTick] in sync
///    (instead of relying on [EffectSystemECS] to drive the counter).
class PredictionEffectRuntime extends _EffectRuntimeBase {
  /// Maximum number of past ticks retained in the rollback log.
  final int rollbackWindowTicks;

  int _currentTick = 0;

  /// Per-tick log: key = startTick, value = effects scheduled at that tick.
  final Map<int, List<_RollbackEntry>> _log = {};

  PredictionEffectRuntime({this.rollbackWindowTicks = 120});

  @override
  int get currentTick => _currentTick;

  /// Advance the internal tick counter by one.
  ///
  /// In a standalone prediction setup call this each physics frame instead of
  /// relying on [EffectSystemECS.update] to drive the counter.
  void advanceTick() {
    _currentTick++;
    _pruneLog();
  }

  @override
  EffectHandle scheduleEffect({
    required Entity entity,
    required DeterministicEffect effect,
    int? startTick,
  }) {
    final handle = super.scheduleEffect(
      entity: entity,
      effect: effect,
      startTick: startTick,
    );
    final tick = startTick ?? _currentTick;
    _log
        .putIfAbsent(tick, () => [])
        .add(
          _RollbackEntry(entityId: entity.id, handle: handle, effect: effect),
        );
    return handle;
  }

  /// Roll back to [targetTick]: cancel post-correction effects and re-queue
  /// them so [EffectSystemECS] fast-forwards on the next update.
  ///
  /// **Caller responsibility:** restore authoritative component snapshots
  /// (position, health, …) before calling this.
  void rollbackTo(int targetTick, World world) {
    for (final entry in _log.entries) {
      if (entry.key > targetTick) {
        for (final rb in entry.value) {
          rb.handle.cancel();
        }
      }
    }
    for (final entry in _log.entries) {
      if (entry.key > targetTick) {
        for (final rb in entry.value) {
          final entity = world.getEntity(rb.entityId);
          if (entity == null || !entity.isAlive) continue;
          rb.effect.reset();
          super.scheduleEffect(
            entity: entity,
            effect: rb.effect,
            startTick: rb.handle.startTick,
          );
        }
      }
    }
    _currentTick = targetTick;
  }

  void _pruneLog() {
    final cutoff = _currentTick - rollbackWindowTicks;
    _log.removeWhere((tick, _) => tick < cutoff);
  }
}

/// Internal rollback log entry.
class _RollbackEntry {
  final EntityId entityId;
  final EffectHandle handle;
  final DeterministicEffect effect;
  const _RollbackEntry({
    required this.entityId,
    required this.handle,
    required this.effect,
  });
}

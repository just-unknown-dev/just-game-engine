library;

import 'dart:typed_data';

import '../../ecs.dart';
import '../../systems/system_priorities.dart';
import '../../../subsystems/effects/effects.dart';

/// ECS system that drives all [EffectComponent]s each fixed-timestep tick.
///
/// Register this system once per world. It also implements [EffectRuntime] —
/// the primary API for scheduling and cancelling effects from game code and
/// networking layers.
///
/// ```dart
/// final effectSystem = EffectSystemECS();
/// world.addSystem(effectSystem);
///
/// // Schedule an effect (start on next tick):
/// effectSystem.scheduleEffect(
///   entity: enemy,
///   effect: SequenceEffect([
///     ShakeEffect(amplitude: 6, durationTicks: 15),
///     FadeEffect(to: 0.0, durationTicks: 30),
///   ]),
/// );
///
/// // Multiplayer: schedule at a specific server tick
/// effectSystem.scheduleEffect(
///   entity: player,
///   effect: MoveEffect(to: Offset(400, 0), durationTicks: 60),
///   startTick: serverTick,
/// );
/// ```
class EffectSystemECS extends System implements EffectRuntime {
  int _currentTick = 0;

  // ── System overrides ────────────────────────────────────────────────────

  @override
  List<Type> get requiredComponents => [EffectComponent];

  @override
  int get priority => SystemPriorities.effects;

  @override
  void update(double deltaTime) {
    _currentTick++;
    for (final entity in entities) {
      final comp = entity.getComponent<EffectComponent>();
      if (comp == null || comp.player.isEmpty) continue;
      final ctx = EffectContext(entity: entity, currentTick: _currentTick);
      comp.player.advanceTo(_currentTick, ctx);
    }
  }

  // ── EffectRuntime ───────────────────────────────────────────────────────

  @override
  int get currentTick => _currentTick;

  /// Schedule [effect] on [entity].
  ///
  /// * [startTick] defaults to [currentTick] — fires on the **next** update
  ///   when `currentTick - startTick > 0`.
  /// * Pass a future tick for pre-scheduled effects (e.g. server-dictated).
  /// * Pass a past tick for fast-forward on reconnect; [EffectPlayer.advanceTo]
  ///   will apply the accumulated delta in the first update.
  ///
  /// An [EffectComponent] is auto-created on [entity] if absent.
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
    return comp.player.add(effect, startTick ?? _currentTick);
  }

  @override
  void cancelEffect(Entity entity, EffectHandle handle) {
    entity.getComponent<EffectComponent>()?.player.cancel(handle);
  }

  // ── Snapshot / restore ──────────────────────────────────────────────────

  @override
  EffectSnapshot snapshotState() {
    final serializer = EffectSerializer();
    final entityEffects = <EntityId, List<Map<String, dynamic>>>{};
    for (final entity in entities) {
      final comp = entity.getComponent<EffectComponent>()!;
      if (!comp.player.isEmpty) {
        entityEffects[entity.id] = comp.player.toJson(serializer.encodeEffect);
      }
    }
    return EffectSnapshot(tick: _currentTick, entityEffects: entityEffects);
  }

  /// Restore all active effects from [snapshot] onto entities in [world].
  ///
  /// Existing [EffectComponent]s are cleared and repopulated. Use this for
  /// late-join reconnect, scene restore from save state, or after a rollback
  /// in a prediction runtime.
  @override
  void restoreSnapshot(EffectSnapshot snapshot, World world) {
    _currentTick = snapshot.tick;
    final serializer = EffectSerializer();
    for (final entry in snapshot.entityEffects.entries) {
      final entity = world.getEntity(entry.key);
      if (entity == null || !entity.isAlive) continue;
      var comp = entity.getComponent<EffectComponent>();
      if (comp == null) {
        comp = EffectComponent();
        entity.addComponent(comp);
      }
      comp.player.fromJson(entry.value, serializer.decodeEffect, _currentTick);
    }
  }

  // ── Serialisation helpers ────────────────────────────────────────────────

  /// Encode current state as a compact byte array.
  ///
  /// Suitable for sending to a connecting peer over the network.
  Uint8List snapshotToBytes() => EffectBinaryCodec.encode(snapshotState());

  /// Restore state from a byte array produced by [snapshotToBytes].
  void restoreFromBytes(Uint8List bytes, World world) =>
      restoreSnapshot(EffectBinaryCodec.decode(bytes), world);
}

library;

/// A cancellable reference to a scheduled [DeterministicEffect].
///
/// Returned by [EffectRuntime.scheduleEffect] and [EffectPlayer.add].
/// Retain the handle if you need to cancel the effect before it completes.
///
/// ```dart
/// final handle = effectSystem.scheduleEffect(
///   entity: myEntity,
///   effect: MoveEffect(to: Vector3(300, 0, 0), durationTicks: 60),
/// );
///
/// // Later — stop the move prematurely:
/// handle.cancel();
/// ```
class EffectHandle {
  /// Its number within the [EffectPlayer] that made it: counts up from 1
  /// for each player, so the same schedule numbers its handles the same way
  /// every run.
  final int id;

  /// String discriminator matching [DeterministicEffect.effectType].
  final String effectType;

  /// The game-loop tick at which this effect is scheduled to begin.
  final int startTick;

  bool _cancelled = false;

  /// Whether [cancel] has been called on this handle.
  bool get isCancelled => _cancelled;

  /// A live (not cancelled) handle. `EffectPlayer` makes these as it adds
  /// or restores effects; games get them from it rather than making them.
  EffectHandle.create({
    required this.id,
    required this.effectType,
    required this.startTick,
  });

  /// Mark this effect for removal.
  ///
  /// [EffectPlayer.advanceTo] will drop the entry on its next call.
  void cancel() => _cancelled = true;

  @override
  String toString() =>
      'EffectHandle(id: $id, type: $effectType, '
      'start: $startTick, cancelled: $_cancelled)';
}

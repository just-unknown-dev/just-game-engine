library;

/// A cancellable reference to a scheduled [DeterministicEffect].
///
/// Returned by [EffectRuntime.scheduleEffect] and [EffectPlayer.add].
/// Retain the handle if you need to cancel the effect before it completes.
///
/// ```dart
/// final handle = effectSystem.scheduleEffect(
///   entity: myEntity,
///   effect: MoveEffect(to: Offset(300, 0), durationTicks: 60),
/// );
///
/// // Later — stop the move prematurely:
/// handle.cancel();
/// ```
class EffectHandle {
  static int _nextId = 0;

  /// Monotonically increasing session-scoped identifier.
  final int id;

  /// String discriminator matching [DeterministicEffect.effectType].
  final String effectType;

  /// The game-loop tick at which this effect is scheduled to begin.
  final int startTick;

  bool _cancelled = false;

  /// Whether [cancel] has been called on this handle.
  bool get isCancelled => _cancelled;

  EffectHandle.create({required this.effectType, required this.startTick})
    : id = ++_nextId;

  /// Mark this effect for removal.
  ///
  /// [EffectPlayer.advanceTo] will drop the entry on its next call.
  void cancel() => _cancelled = true;

  @override
  String toString() =>
      'EffectHandle(id: $id, type: $effectType, '
      'start: $startTick, cancelled: $_cancelled)';
}

library;

import '../../../ecs/ecs.dart';
import '../../../subsystems/effects/base/effect_player.dart';

/// ECS component that attaches an [EffectPlayer] to an entity.
///
/// Add this component to any entity you want to drive with [DeterministicEffect]s.
/// [EffectSystemECS] queries for this component every tick and advances the
/// [player] with the current absolute tick number.
///
/// You usually never create this manually — [EffectRuntime.scheduleEffect]
/// creates and attaches it automatically if the target entity does not already
/// have one.
///
/// ```dart
/// // Attach manually if you prefer:
/// entity.addComponent(EffectComponent());
/// entity.getComponent<EffectComponent>()!.player.add(
///   MoveEffect(to: Offset(100, 0), durationTicks: 30),
///   effectSystem.currentTick,
/// );
/// ```
class EffectComponent extends Component {
  /// The per-entity effect queue. Do not replace this reference.
  final EffectPlayer player = EffectPlayer();

  EffectComponent();

  @override
  String toString() => 'EffectComponent(active: ${player.activeCount})';
}

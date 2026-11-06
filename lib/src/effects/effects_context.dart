/// What deterministic effects keep per engine: the effect types a snapshot
/// can hold.
library;

import '../ecs/engine_context.dart';
import 'deterministic_effects.dart';

final Object _effectTypesKey = Object();

/// An engine's effect types, on its [EngineContext].
extension ContextEffects on EngineContext {
  /// The deterministic effects a snapshot can hold.
  EffectTypes get effectTypes =>
      slot(_effectTypesKey, () => EffectTypes(withBuiltIns: withBuiltIns));
}

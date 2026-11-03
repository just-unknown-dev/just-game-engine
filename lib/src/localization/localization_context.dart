/// What localization keeps per engine: the game's strings.
library;

import '../ecs/engine_context.dart';
import 'localization_manager.dart';

final class _LocalizationSlot {
  LocalizationManager? manager;
}

final Object _localizationKey = Object();

/// An engine's strings, on its [EngineContext].
extension ContextLocalization on EngineContext {
  /// The game's strings, when it has them. A `GameWidget` showing this
  /// engine provides it to everything drawn over the game through a
  /// `LocalizationScope`; set it before building the widget.
  LocalizationManager? get localization =>
      slot(_localizationKey, _LocalizationSlot.new).manager;
  set localization(LocalizationManager? value) =>
      slot(_localizationKey, _LocalizationSlot.new).manager = value;
}

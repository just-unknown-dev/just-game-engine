/// Central Localization System — public barrel.
///
/// Exports:
/// - [LocalizationManager] — engine-wide locale loader & string resolver
/// - [LocaleStringTable] — in-memory string table for one locale
/// - [StringInterpolator] — `{var}`, `{plural}`, `{select}` processor
/// - [LocalizationScope] — InheritedWidget providing the manager to the tree
///
/// The widgets built on it — `LocalizationBuilder`, `LocalizedText`,
/// `LocaleSelector` — and the `context.t()` / `context.tr()` extension
/// (`L10nContext`) are in `package:just_game_engine/widgets.dart`.
library;

export 'locale_string_table.dart';
export 'string_interpolator.dart';
export 'localization_manager.dart';
// The widgets (LocalizationBuilder, LocalizedText, LocaleSelector) and the
// context.t() extension are in package:just_game_engine/widgets.dart;
// LocalizationScope, which GameWidget provides, stays here.
export 'localization_widget.dart' show LocalizationScope;

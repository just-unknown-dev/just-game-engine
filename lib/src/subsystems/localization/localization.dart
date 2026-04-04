/// Central Localization System — public barrel.
///
/// Exports:
/// - [LocalizationManager] — engine-wide locale loader & string resolver
/// - [LocaleStringTable] — in-memory string table for one locale
/// - [StringInterpolator] — `{var}`, `{plural}`, `{select}` processor
/// - [LocalizationScope] — InheritedWidget providing the manager to the tree
/// - [LocalizationBuilder] — reactive widget rebuilt on locale change
/// - [LocalizedText] — drop-in `Text` replacement for localized strings
/// - [LocaleSelector] — locale-switcher widget
/// - [L10nContext] — `context.t()` / `context.tr()` extension
library;

export 'locale_string_table.dart';
export 'string_interpolator.dart';
export 'localization_manager.dart';
export 'localization_widget.dart';

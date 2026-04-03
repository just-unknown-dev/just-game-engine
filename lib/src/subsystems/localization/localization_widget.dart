/// Flutter widgets for the engine-wide localization system.
library;

import 'package:flutter/widgets.dart';

import 'localization_manager.dart';
import 'string_interpolator.dart';

// ---------------------------------------------------------------------------
// LocalizationScope
// ---------------------------------------------------------------------------

/// Provides a [LocalizationManager] to the widget subtree via
/// [LocalizationScope.of].
///
/// Place this high in your widget tree (above the game canvas):
/// ```dart
/// LocalizationScope(
///   manager: l10n,
///   child: GameWidget(game: myGame),
/// )
/// ```
class LocalizationScope extends InheritedWidget {
  const LocalizationScope({
    super.key,
    required this.manager,
    required super.child,
  });

  final LocalizationManager manager;

  /// Returns the nearest [LocalizationManager] from the tree, or
  /// `LocalizationManager.instance` as a fallback, or `null` if neither is
  /// available.
  static LocalizationManager? maybeOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<LocalizationScope>()
            ?.manager ??
        LocalizationManager.instance;
  }

  /// Like [maybeOf] but asserts that a manager is available.
  static LocalizationManager of(BuildContext context) {
    final m = maybeOf(context);
    assert(
      m != null,
      'No LocalizationScope found in the widget tree and '
      'LocalizationManager.instance is null. '
      'Wrap your widget tree with LocalizationScope or set '
      'LocalizationManager.instance before calling LocalizationScope.of().',
    );
    return m!;
  }

  @override
  bool updateShouldNotify(LocalizationScope oldWidget) =>
      manager != oldWidget.manager;
}

// ---------------------------------------------------------------------------
// LocalizationBuilder
// ---------------------------------------------------------------------------

/// Rebuilds its subtree whenever the active locale changes.
///
/// ```dart
/// LocalizationBuilder(
///   builder: (context, l10n) => Text(l10n.t('ui.start_game')),
/// )
/// ```
///
/// When [manager] is omitted, looks up [LocalizationScope.of(context)].
class LocalizationBuilder extends StatefulWidget {
  const LocalizationBuilder({super.key, required this.builder, this.manager});

  final Widget Function(BuildContext context, LocalizationManager l10n) builder;

  /// Explicit manager — if `null`, resolves from [LocalizationScope].
  final LocalizationManager? manager;

  @override
  State<LocalizationBuilder> createState() => _LocalizationBuilderState();
}

class _LocalizationBuilderState extends State<LocalizationBuilder> {
  LocalizationManager? _manager;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _attach(widget.manager ?? LocalizationScope.maybeOf(context));
  }

  @override
  void didUpdateWidget(LocalizationBuilder old) {
    super.didUpdateWidget(old);
    if (widget.manager != old.manager) {
      _attach(widget.manager ?? LocalizationScope.maybeOf(context));
    }
  }

  void _attach(LocalizationManager? m) {
    if (m == _manager) return;
    _manager?.localeChanged.removeListener(_rebuild);
    _manager = m;
    _manager?.localeChanged.addListener(_rebuild);
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _manager?.localeChanged.removeListener(_rebuild);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = _manager;
    if (m == null) return const SizedBox.shrink();
    return widget.builder(context, m);
  }
}

// ---------------------------------------------------------------------------
// LocalizedText
// ---------------------------------------------------------------------------

/// A [Text] widget that displays a localized string and automatically
/// rebuilds when the locale changes.
///
/// ```dart
/// // Simple key lookup
/// LocalizedText('ui.start_game')
///
/// // With variable interpolation
/// LocalizedText('game.greeting', args: {'name': 'Aria'})
///
/// // Override style
/// LocalizedText('ui.title', style: Theme.of(context).textTheme.headlineMedium)
/// ```
class LocalizedText extends StatelessWidget {
  const LocalizedText(
    this.key_, {
    super.key,
    this.args = const {},
    this.ns,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.softWrap = true,
  });

  /// Localization key.  Named `key_` to avoid shadowing [Widget.key].
  final String key_;

  /// Variable substitution arguments.
  final Map<String, Object?> args;

  /// Restrict lookup to one namespace.
  final String? ns;

  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool softWrap;

  @override
  Widget build(BuildContext context) {
    return LocalizationBuilder(
      builder: (ctx, l10n) => Text(
        l10n.t(key_, args: args, ns: ns),
        style: style,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: overflow,
        softWrap: softWrap,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// LocaleSelector
// ---------------------------------------------------------------------------

/// A widget that renders a locale switcher from a list of supported locales.
///
/// ```dart
/// LocaleSelector(
///   locales: [const Locale('en'), const Locale('fr'), const Locale('de')],
///   labels: {'en': 'English', 'fr': 'Français', 'de': 'Deutsch'},
/// )
/// ```
class LocaleSelector extends StatelessWidget {
  const LocaleSelector({
    super.key,
    required this.locales,
    this.labels = const {},
    this.manager,
    this.onLocaleChanged,
  });

  final List<Locale> locales;

  /// Map of language-code → display name.  Falls back to the language code.
  final Map<String, String> labels;

  final LocalizationManager? manager;

  /// Optional callback when a locale is selected.
  final void Function(Locale)? onLocaleChanged;

  @override
  Widget build(BuildContext context) {
    final m = manager ?? LocalizationScope.maybeOf(context);
    if (m == null) return const SizedBox.shrink();

    return LocalizationBuilder(
      manager: m,
      builder: (ctx, l10n) {
        return Wrap(
          spacing: 8,
          children: locales.map((locale) {
            final tag = locale.languageCode;
            final isActive = l10n.currentLocale.languageCode == tag;
            final label = labels[tag] ?? tag.toUpperCase();

            return GestureDetector(
              onTap: isActive
                  ? null
                  : () {
                      l10n.setLocale(locale);
                      onLocaleChanged?.call(locale);
                    },
              child: Opacity(
                opacity: isActive ? 1.0 : 0.5,
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                    decoration: isActive
                        ? TextDecoration.underline
                        : TextDecoration.none,
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Extension  (BuildContext convenience)
// ---------------------------------------------------------------------------

/// Convenience extension on [BuildContext] for quick string lookups.
///
/// ```dart
/// // Inside a build() method:
/// Text(context.t('ui.start_game'))
/// Text(context.tr('game.hp', {'current': 80, 'max': 100}))
/// ```
extension L10nContext on BuildContext {
  /// Looks up [key] in the nearest [LocalizationScope] (or global instance).
  String t(String key, [Map<String, Object?> args = const {}]) =>
      LocalizationScope.maybeOf(this)?.t(key, args: args) ??
      (args.isEmpty ? key : StringInterpolator.process(key, args));

  /// Looks up [key] with [args].
  String tr(String key, Map<String, Object?> args) => t(key, args);
}

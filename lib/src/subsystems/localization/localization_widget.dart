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
///
/// A `GameWidget` provides one itself, for its engine's manager
/// (`engine.context.localization`), to everything drawn over the game.
class LocalizationScope extends InheritedWidget {
  /// Makes [manager] what [of] and [maybeOf] find anywhere below, in
  /// [child].
  const LocalizationScope({
    super.key,
    required this.manager,
    required super.child,
  });

  /// The manager provided to the subtree. Dependents rebuild when it is
  /// replaced by another, not when its locale changes — that is what
  /// [LocalizationBuilder] is for.
  final LocalizationManager manager;

  /// Returns the nearest [LocalizationManager] from the tree, or `null` if
  /// there is none.
  static LocalizationManager? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<LocalizationScope>()
        ?.manager;
  }

  /// Like [maybeOf] but asserts that a manager is available.
  static LocalizationManager of(BuildContext context) {
    final m = maybeOf(context);
    assert(
      m != null,
      'No LocalizationScope found in the widget tree. Wrap your widget tree '
      'with LocalizationScope, or set engine.context.localization before '
      'building the GameWidget (which then provides one).',
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
  /// Builds with [builder] from [manager] (the nearest [LocalizationScope]'s
  /// when null), again on every locale change; builds nothing while there is
  /// no manager.
  const LocalizationBuilder({super.key, required this.builder, this.manager});

  /// Builds the subtree from the manager; called again whenever the
  /// manager's locale changes.
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
  /// The string for [key_] in the nearest [LocalizationScope]'s current
  /// locale, with [args] filled in and the lookup kept to [ns] when given.
  /// Shows nothing without a scope. The rest are [Text]'s own parameters.
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

  /// Passed to [Text.style]; merged over the ambient [DefaultTextStyle].
  final TextStyle? style;

  /// Passed to [Text.textAlign]; the ambient default when null.
  final TextAlign? textAlign;

  /// Passed to [Text.maxLines]; the ambient default (usually no limit) when
  /// null.
  final int? maxLines;

  /// Passed to [Text.overflow]; the ambient default when null.
  final TextOverflow? overflow;

  /// Passed to [Text.softWrap]: whether lines may break at word boundaries.
  /// True by default.
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
  /// A wrapping row of tappable labels, one per entry of [locales], that
  /// switch [manager] (the nearest [LocalizationScope]'s when null); builds
  /// nothing when there is no manager.
  const LocaleSelector({
    super.key,
    required this.locales,
    this.labels = const {},
    this.manager,
    this.onLocaleChanged,
  });

  /// The locales offered, in order. One shows as active (bold, underlined,
  /// not tappable) when its language code is the current locale's, so two
  /// locales of the same language show as active together.
  final List<Locale> locales;

  /// Map of language-code → display name.  Falls back to the language code
  /// in capitals.
  final Map<String, String> labels;

  /// The manager whose locale is switched; the nearest
  /// [LocalizationScope]'s when null.
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
  /// Looks up [key] in the nearest [LocalizationScope]; without one, gives
  /// [key] itself (with [args] filled in).
  String t(String key, [Map<String, Object?> args = const {}]) =>
      LocalizationScope.maybeOf(this)?.t(key, args: args) ??
      (args.isEmpty ? key : StringInterpolator.process(key, args));

  /// Looks up [key] with [args].
  String tr(String key, Map<String, Object?> args) => t(key, args);
}

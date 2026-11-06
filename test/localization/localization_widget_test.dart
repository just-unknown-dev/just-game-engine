// The localization widgets: LocalizedText follows the manager's locale,
// context.t / context.tr look up and fill in, LocaleSelector lists the
// locales and switches between them, and LocalizationBuilder rebuilds on a
// locale change.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/widgets.dart';

void main() {
  late LocalizationManager l10n;

  setUp(() {
    l10n = LocalizationManager()
      ..registerMap(const Locale('en'), {
        'hi': 'Hello',
        'hp': 'HP {current}/{max}',
      })
      ..registerMap(const Locale('fr'), {
        'hi': 'Salut',
        'hp': 'PV {current}/{max}',
      });
  });
  tearDown(() => l10n.dispose());

  Widget host(Widget child) => MaterialApp(
    home: LocalizationScope(
      manager: l10n,
      child: Scaffold(body: child),
    ),
  );

  testWidgets('LocalizedText follows setLocale', (tester) async {
    await tester.pumpWidget(host(const LocalizedText('hi')));
    expect(find.text('Hello'), findsOneWidget);
    l10n.setLocale(const Locale('fr'));
    await tester.pump();
    expect(find.text('Salut'), findsOneWidget);
    expect(find.text('Hello'), findsNothing);
  });

  testWidgets('context.t and context.tr look up and fill in', (tester) async {
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => Column(
            children: [
              Text(context.t('hi')),
              Text(context.tr('hp', {'current': 80, 'max': 100})),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Hello'), findsOneWidget);
    expect(find.text('HP 80/100'), findsOneWidget);
  });

  testWidgets('without a scope, context.t gives the key back', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(builder: (context) => Text(context.t('menu.start'))),
      ),
    );
    expect(find.text('menu.start'), findsOneWidget);
  });

  testWidgets('LocaleSelector lists the locales and switches', (tester) async {
    Locale? picked;
    await tester.pumpWidget(
      host(
        Column(
          children: [
            LocaleSelector(
              locales: const [Locale('en'), Locale('fr')],
              labels: const {'en': 'English', 'fr': 'Français'},
              onLocaleChanged: (locale) => picked = locale,
            ),
            const LocalizedText('hi'),
          ],
        ),
      ),
    );
    expect(find.text('English'), findsOneWidget);
    expect(find.text('Français'), findsOneWidget);
    await tester.tap(find.text('Français'));
    await tester.pump();
    expect(picked, const Locale('fr'));
    expect(l10n.currentLocale, const Locale('fr'));
    expect(find.text('Salut'), findsOneWidget);
  });

  testWidgets('LocalizationBuilder with no manager builds nothing', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LocalizationBuilder(builder: (_, _) => const Text('shown')),
      ),
    );
    expect(find.text('shown'), findsNothing);
  });
}

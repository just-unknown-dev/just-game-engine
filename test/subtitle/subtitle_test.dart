// Subtitles: a track's active cue, the controller that follows the time
// (and fires only when the cue changes), localized tracks, and the overlay
// that shows and clears the text.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/widgets.dart';

const _track = SubtitleTrack([
  SubtitleCue(start: 0.5, end: 2.0, text: 'First'),
  SubtitleCue(start: 3.0, end: 4.0, text: 'Second'),
]);

void main() {
  group('SubtitleTrack', () {
    test('a cue is active from its start up to, not including, its end', () {
      expect(_track.getActiveCue(0.4), isNull);
      expect(_track.getActiveCue(0.5)?.text, 'First');
      expect(_track.getActiveCue(1.99)?.text, 'First');
      expect(_track.getActiveCue(2.0), isNull);
      expect(_track.getActiveCue(3.5)?.text, 'Second');
      expect(_track.totalDuration, 4.0);
      expect(const SubtitleTrack([]).totalDuration, 0);
    });

    test('a localized track reads its keys once', () {
      final l10n = LocalizationManager()
        ..registerMap(const Locale('en'), {'a': 'Hello'});
      addTearDown(l10n.dispose);
      final track = SubtitleTrack.localized(
        entries: [(start: 0, end: 1, key: 'a')],
        l10n: l10n,
      );
      expect(track.cues.single.text, 'Hello');
    });
  });

  group('SubtitleController', () {
    test('shows each cue inside its window and nothing between', () {
      final controller = SubtitleController(track: _track);
      addTearDown(controller.dispose);
      final heard = <String?>[];
      controller.currentText.addListener(
        () => heard.add(controller.currentText.value),
      );
      for (final t in [0.0, 1.0, 1.5, 2.5, 3.2, 3.8, 5.0]) {
        controller.update(t);
      }
      expect(heard, ['First', null, 'Second', null], reason: 'once a change');
    });

    test('reset clears the text until the next update', () {
      final controller = SubtitleController(track: _track)..update(1);
      addTearDown(controller.dispose);
      controller.reset();
      expect(controller.currentText.value, isNull);
      controller.update(1.2);
      expect(controller.currentText.value, 'First');
    });
  });

  testWidgets('SubtitleOverlay shows and clears the text', (tester) async {
    final controller = SubtitleController(track: _track);
    await tester.pumpWidget(
      MaterialApp(
        home: SubtitleOverlay(
          controller: controller,
          child: const SizedBox.expand(),
        ),
      ),
    );
    expect(find.text('First'), findsNothing);
    controller.update(1);
    await tester.pumpAndSettle();
    expect(find.text('First'), findsOneWidget);
    controller.update(2.5);
    await tester.pumpAndSettle();
    expect(find.text('First'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}

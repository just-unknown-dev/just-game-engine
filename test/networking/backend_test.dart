import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  group('Analytics Service', () {
    test('GameEvent creation and serialization', () {
      final now = DateTime.now().toUtc();
      final event = GameEvent(
        eventName: 'test_event',
        properties: {'score': 100},
        sessionId: 's1',
        playerId: 'p1',
        timestamp: now,
      );

      expect(event.eventName, 'test_event');
      expect(event.properties['score'], 100);

      final json = event.toJson();
      expect(json['event'], 'test_event');
      expect(json['properties']['score'], 100);
      expect(json['session'], 's1');
      expect(json['player'], 'p1');
      expect(json['ts'], now.millisecondsSinceEpoch);
    });

    test('DebugAnalyticsService records events and timers', () async {
      final analytics = DebugAnalyticsService();
      expect(analytics.events, isEmpty);

      await analytics.setUserId('u1');
      await analytics.logEvent(GameEvent(eventName: 'level_start'));

      expect(analytics.events.length, 1);
      expect(analytics.events.first.eventName, 'level_start');
      expect(analytics.events.first.playerId, 'u1');

      await analytics.logCustom('button_clicked', {'btn': 'play'});
      expect(analytics.events.length, 2);
      expect(analytics.events[1].eventName, 'button_clicked');
      expect(analytics.events[1].properties['btn'], 'play');

      // Timer test
      await analytics.logEventStart('level1');
      await Future.delayed(const Duration(milliseconds: 10));
      await analytics.logEventEnd('level1', {'won': true});

      expect(analytics.events.length, 3);
      final timed = analytics.events[2];
      expect(timed.eventName, 'level1');
      expect(timed.properties['won'], true);
      expect(timed.properties['duration_ms'], greaterThanOrEqualTo(10));

      analytics.clearEvents();
      expect(analytics.events, isEmpty);

      // Disabled state
      await analytics.setEnabled(false);
      await analytics.logCustom('ignored_event');
      expect(analytics.events, isEmpty);
    });
  });

  group('Leaderboard Service', () {
    test('LeaderboardEntry creation', () {
      final entry = LeaderboardEntry(
        rank: 1,
        playerId: 'p1',
        displayName: 'Player One',
        score: 9999,
        metadata: {'level': 5},
      );
      expect(entry.rank, 1);
      expect(entry.playerId, 'p1');
      expect(entry.score, 9999);
      expect(entry.metadata['level'], 5);
    });
  });
}

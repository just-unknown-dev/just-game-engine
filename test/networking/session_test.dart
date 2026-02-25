import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  group('SessionManager', () {
    test('SessionManager manages lifecycle and expiry', () {
      final manager = SessionManager();
      expect(manager.state, SessionState.idle);

      final now = DateTime.now().toUtc();
      final session = PlayerSession(
        sessionId: 's1',
        playerId: 'p1',
        displayName: 'Test Player',
        token: 'token123',
        createdAt: now,
        expiresAt: now.add(const Duration(minutes: 60)),
      );

      var stateVar = SessionState.idle;
      manager.onSessionChanged((state, s) {
        stateVar = state;
      });

      manager.createSession(session);
      expect(manager.hasActiveSession, isTrue);
      expect(manager.currentSession?.playerId, 'p1');
      expect(stateVar, SessionState.active);

      manager.expireSession();
      expect(manager.state, SessionState.expired);
      expect(manager.hasActiveSession, isFalse);
      expect(stateVar, SessionState.expired);

      manager.leaveSession();
      expect(manager.state, SessionState.idle);
      expect(manager.currentSession, isNull);
    });

    test('PlayerSession expiry computation', () {
      final past = DateTime.now().toUtc().subtract(const Duration(seconds: 10));
      final future = DateTime.now().toUtc().add(const Duration(seconds: 10));

      final expiredSession = PlayerSession(
        sessionId: 's1',
        playerId: 'p1',
        displayName: 'P1',
        token: 'token',
        createdAt: past.subtract(const Duration(minutes: 10)),
        expiresAt: past,
      );
      expect(expiredSession.isExpired, isTrue);
      expect(expiredSession.timeUntilExpiry, Duration.zero);

      final activeSession = PlayerSession(
        sessionId: 's2',
        playerId: 'p2',
        displayName: 'P2',
        token: 'token',
        createdAt: past,
        expiresAt: future,
      );
      expect(activeSession.isExpired, isFalse);
      expect(activeSession.timeUntilExpiry.inSeconds, greaterThan(0));
    });
  });
}

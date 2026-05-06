library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:games_services/games_services.dart' as gs;

import '../leaderboard_definition.dart';
import '../leaderboard_entry.dart';
import '../leaderboard_provider.dart';

/// [LeaderboardProvider] backed by Google Play Games Services (Android).
///
/// Register on Android builds only:
/// ```dart
/// if (Platform.isAndroid) {
///   engine.leaderboard.registerProvider(PlayGamesLeaderboardProvider());
/// }
/// ```
class PlayGamesLeaderboardProvider implements LeaderboardProvider {
  @override
  Future<void> initialize() async {}

  @override
  Future<void> submitScore(LeaderboardDefinition leaderboard, int score) async {
    final androidId = leaderboard.androidLeaderboardId;
    if (androidId == null || androidId.isEmpty) return;

    Future<void> doSubmit() => gs.Leaderboards.submitScore(
      score: gs.Score(
        androidLeaderboardID: androidId,
        iOSLeaderboardID: '',
        value: score,
      ),
    );

    try {
      await doSubmit();
    } catch (e) {
      if (_isDeferred(e)) return;
      if (_requiresReconnect(e)) {
        await _reconnect();
        try {
          await doSubmit();
        } catch (retryErr) {
          if (_isDeferred(retryErr)) return;
          debugPrint(
            'PlayGamesLeaderboardProvider: submitScore failed after reconnect ($retryErr)',
          );
        }
        return;
      }
      debugPrint('PlayGamesLeaderboardProvider: submitScore failed ($e)');
    }
  }

  @override
  Future<List<LeaderboardEntry>> getTopScores(
    LeaderboardDefinition leaderboard, {
    int limit = 10,
  }) async {
    final androidId = leaderboard.androidLeaderboardId;
    if (androidId == null || androidId.isEmpty) return [];
    try {
      final scores = await gs.Leaderboards.loadLeaderboardScores(
        androidLeaderboardID: androidId,
        iOSLeaderboardID: '',
        scope: gs.PlayerScope.global,
        timeScope: gs.TimeScope.allTime,
        maxResults: limit,
      );
      if (scores == null) return [];
      return scores
          .map(
            (s) => LeaderboardEntry(
              playerId: s.scoreHolder.playerID ?? '',
              displayName: s.scoreHolder.displayName,
              score: s.rawScore,
              rank: s.rank,
            ),
          )
          .toList();
    } catch (e) {
      if (_requiresReconnect(e)) {
        await _reconnect();
      }
      debugPrint('PlayGamesLeaderboardProvider: getTopScores failed ($e)');
      return [];
    }
  }

  @override
  Future<void> showLeaderboard(LeaderboardDefinition leaderboard) async {
    final androidId = leaderboard.androidLeaderboardId;
    if (androidId == null || androidId.isEmpty) return;
    try {
      await gs.Leaderboards.showLeaderboards(
        androidLeaderboardID: androidId,
        iOSLeaderboardID: '',
      );
    } catch (e) {
      if (_requiresReconnect(e)) await _reconnect();
      debugPrint('PlayGamesLeaderboardProvider: showLeaderboard failed ($e)');
    }
  }

  @override
  Future<void> dispose() async {}

  // ── Error helpers ────────────────────────────────────────────────────────

  /// 26505 — Play Games accepted the request and queued it for the next sync.
  static bool _isDeferred(Object e) =>
      e is PlatformException &&
      (e.message?.contains('NETWORK_ERROR_OPERATION_DEFERRED') ?? false);

  /// 26502 — Session token expired; re-sign-in to restore the client state.
  static bool _requiresReconnect(Object e) =>
      e is PlatformException &&
      (e.message?.contains('CLIENT_RECONNECT_REQUIRED') ?? false);

  /// Re-establishes the Play Games session after a CLIENT_RECONNECT_REQUIRED.
  static Future<void> _reconnect() async {
    try {
      await gs.GameAuth.signIn();
      debugPrint('PlayGamesLeaderboardProvider: reconnected');
    } catch (e) {
      debugPrint('PlayGamesLeaderboardProvider: reconnect failed ($e)');
    }
  }
}

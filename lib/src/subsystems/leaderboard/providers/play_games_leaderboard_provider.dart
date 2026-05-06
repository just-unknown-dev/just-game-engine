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
    try {
      await gs.Leaderboards.submitScore(
        score: gs.Score(
          androidLeaderboardID: androidId,
          iOSLeaderboardID: '',
          value: score,
        ),
      );
    } catch (e) {
      if (_isDeferred(e)) return;
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
      debugPrint('PlayGamesLeaderboardProvider: showLeaderboard failed ($e)');
    }
  }

  @override
  Future<void> dispose() async {}

  /// Returns true when Play Games deferred the operation due to a transient
  /// network condition (error 26505: NETWORK_ERROR_OPERATION_DEFERRED).
  ///
  /// This is NOT a failure — the SDK accepted the request and queued it for
  /// the next sync window. Treat it as a silent success.
  static bool _isDeferred(Object e) =>
      e is PlatformException &&
      (e.message?.contains('NETWORK_ERROR_OPERATION_DEFERRED') ?? false);
}

library;

import 'package:flutter/foundation.dart';
import 'package:games_services/games_services.dart' as gs;

import '../leaderboard_definition.dart';
import '../leaderboard_entry.dart';
import '../leaderboard_provider.dart';

/// [LeaderboardProvider] backed by Apple Game Center (iOS / macOS).
///
/// Register on iOS builds only:
/// ```dart
/// if (Platform.isIOS) {
///   engine.leaderboard.registerProvider(GameCenterLeaderboardProvider());
/// }
/// ```
class GameCenterLeaderboardProvider implements LeaderboardProvider {
  @override
  Future<void> initialize() async {}

  @override
  Future<void> submitScore(LeaderboardDefinition leaderboard, int score) async {
    final iosId = leaderboard.iosLeaderboardId;
    if (iosId == null || iosId.isEmpty) return;
    try {
      await gs.Leaderboards.submitScore(
        score: gs.Score(
          androidLeaderboardID: '',
          iOSLeaderboardID: iosId,
          value: score,
        ),
      );
    } catch (e) {
      debugPrint('GameCenterLeaderboardProvider: submitScore failed ($e)');
    }
  }

  @override
  Future<List<LeaderboardEntry>> getTopScores(
    LeaderboardDefinition leaderboard, {
    int limit = 10,
  }) async {
    final iosId = leaderboard.iosLeaderboardId;
    if (iosId == null || iosId.isEmpty) return [];
    try {
      final scores = await gs.Leaderboards.loadLeaderboardScores(
        androidLeaderboardID: '',
        iOSLeaderboardID: iosId,
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
      debugPrint('GameCenterLeaderboardProvider: getTopScores failed ($e)');
      return [];
    }
  }

  @override
  Future<void> showLeaderboard(LeaderboardDefinition leaderboard) async {
    final iosId = leaderboard.iosLeaderboardId;
    if (iosId == null || iosId.isEmpty) return;
    try {
      await gs.Leaderboards.showLeaderboards(
        androidLeaderboardID: '',
        iOSLeaderboardID: iosId,
      );
    } catch (e) {
      debugPrint('GameCenterLeaderboardProvider: showLeaderboard failed ($e)');
    }
  }

  @override
  Future<void> dispose() async {}
}

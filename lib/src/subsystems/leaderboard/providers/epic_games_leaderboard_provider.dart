library;

import 'package:flutter/foundation.dart';

import '../leaderboard_definition.dart';
import '../leaderboard_entry.dart';
import '../leaderboard_provider.dart';

/// [LeaderboardProvider] stub for Epic Online Services.
///
/// The Epic Games SDK is not yet available as a stable Flutter package.
/// This stub satisfies the [LeaderboardProvider] contract and logs a warning
/// when called. Replace with a real implementation once an appropriate
/// Flutter/FFI binding is available.
class EpicGamesLeaderboardProvider implements LeaderboardProvider {
  @override
  Future<void> initialize() async {
    debugPrint('EpicGamesLeaderboardProvider: SDK not yet wired — stub only');
  }

  @override
  Future<void> submitScore(LeaderboardDefinition leaderboard, int score) async {
    debugPrint('EpicGamesLeaderboardProvider: submitScore called but SDK not wired — stub only');
  }

  @override
  Future<List<LeaderboardEntry>> getTopScores(
    LeaderboardDefinition leaderboard, {
    int limit = 10,
  }) async => [];

  @override
  Future<void> showLeaderboard(LeaderboardDefinition leaderboard) async {
    debugPrint('EpicGamesLeaderboardProvider: showLeaderboard called but SDK not wired — stub only');
  }

  @override
  Future<void> dispose() async {}
}

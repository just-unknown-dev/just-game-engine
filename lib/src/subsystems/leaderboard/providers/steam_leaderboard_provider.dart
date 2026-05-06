library;

import 'package:flutter/foundation.dart';

import '../leaderboard_definition.dart';
import '../leaderboard_entry.dart';
import '../leaderboard_provider.dart';

/// [LeaderboardProvider] stub for Steam (Windows / Linux).
///
/// The Steamworks SDK does not have a stable official Flutter package.
/// This stub satisfies the [LeaderboardProvider] contract and logs a warning
/// when called. Replace with a real implementation once a mature
/// Flutter/FFI Steamworks binding is available.
class SteamLeaderboardProvider implements LeaderboardProvider {
  @override
  Future<void> initialize() async {
    debugPrint('SteamLeaderboardProvider: SDK not yet wired — stub only');
  }

  @override
  Future<void> submitScore(LeaderboardDefinition leaderboard, int score) async {
    debugPrint('SteamLeaderboardProvider: submitScore called but SDK not wired — stub only');
  }

  @override
  Future<List<LeaderboardEntry>> getTopScores(
    LeaderboardDefinition leaderboard, {
    int limit = 10,
  }) async => [];

  @override
  Future<void> showLeaderboard(LeaderboardDefinition leaderboard) async {
    debugPrint('SteamLeaderboardProvider: showLeaderboard called but SDK not wired — stub only');
  }

  @override
  Future<void> dispose() async {}
}

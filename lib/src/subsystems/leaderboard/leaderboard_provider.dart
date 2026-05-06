library;

import 'leaderboard_definition.dart';
import 'leaderboard_entry.dart';

/// Contract for platform leaderboard backends
/// (Play Games, Game Center, Steam, Epic Games, etc.).
///
/// Implement this interface and pass an instance to
/// [LeaderboardManager.registerProvider] to connect the engine to a
/// platform leaderboard service.
abstract class LeaderboardProvider {
  Future<void> initialize();

  /// Submits [score] to the specified leaderboard.
  Future<void> submitScore(LeaderboardDefinition leaderboard, int score);

  /// Returns the top [limit] entries for [leaderboard].
  ///
  /// Providers that do not support programmatic reads return an empty list.
  /// Use [showLeaderboard] to display the platform's native UI instead.
  Future<List<LeaderboardEntry>> getTopScores(
    LeaderboardDefinition leaderboard, {
    int limit = 10,
  });

  /// Opens the platform's native leaderboard UI for [leaderboard].
  Future<void> showLeaderboard(LeaderboardDefinition leaderboard);

  Future<void> dispose();
}

/// Default provider — no platform calls, all operations are no-ops.
///
/// Used when no provider has been registered, or in environments where
/// platform services are unavailable (web, unknown desktop, tests).
class NoOpLeaderboardProvider implements LeaderboardProvider {
  @override
  Future<void> initialize() async {}

  @override
  Future<void> submitScore(LeaderboardDefinition leaderboard, int score) async {}

  @override
  Future<List<LeaderboardEntry>> getTopScores(
    LeaderboardDefinition leaderboard, {
    int limit = 10,
  }) async => [];

  @override
  Future<void> showLeaderboard(LeaderboardDefinition leaderboard) async {}

  @override
  Future<void> dispose() async {}
}

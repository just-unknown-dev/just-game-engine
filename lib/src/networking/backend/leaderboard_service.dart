/// Leaderboard Service
///
/// Abstract interface and data models for leaderboard management.
/// Implement [ILeaderboardService] to connect to any backend
/// (Firebase, REST, Nakama, PlayFab, etc.).
library;

// ---------------------------------------------------------------------------
// Data models
// ---------------------------------------------------------------------------

/// A single entry on a leaderboard.
class LeaderboardEntry {
  /// Rank position (1 = first place).
  final int rank;

  /// Unique player identifier.
  final String playerId;

  /// Human-readable display name.
  final String displayName;

  /// The player's numeric score.
  final int score;

  /// Optional avatar URL.
  final String? avatarUrl;

  /// UTC timestamp when this score was submitted.
  final DateTime? achievedAt;

  /// Arbitrary extra data (level, region, character, etc.).
  final Map<String, dynamic> metadata;

  const LeaderboardEntry({
    required this.rank,
    required this.playerId,
    required this.displayName,
    required this.score,
    this.avatarUrl,
    this.achievedAt,
    this.metadata = const {},
  });

  @override
  String toString() =>
      'LeaderboardEntry(rank=$rank, player=$displayName, score=$score)';
}

/// The time window over which a leaderboard aggregates scores.
enum LeaderboardPeriod {
  /// All-time global high scores.
  allTime,

  /// Scores from the current calendar week.
  weekly,

  /// Scores from the current calendar day.
  daily,
}

// ---------------------------------------------------------------------------
// Abstract interface
// ---------------------------------------------------------------------------

/// Backend-agnostic leaderboard service interface.
///
/// Inject a concrete implementation that talks to your preferred backend.
abstract class ILeaderboardService {
  /// Submit [score] for the authenticated player to the board [boardId].
  Future<void> submitScore(String boardId, int score);

  /// Fetch the top [limit] entries from board [boardId].
  Future<List<LeaderboardEntry>> fetchTopScores(
    String boardId, {
    int limit = 10,
    LeaderboardPeriod period = LeaderboardPeriod.allTime,
  });

  /// Fetch the rank and entry for a specific [playerId] on board [boardId].
  /// Returns `null` if the player has no entry on that board.
  Future<LeaderboardEntry?> fetchPlayerRank(String boardId, String playerId);

  /// Fetch entries surrounding [playerId] (neighbourhood / "around me" view).
  Future<List<LeaderboardEntry>> fetchNeighbourhood(
    String boardId,
    String playerId, {
    int radius = 5,
  });

  /// Delete a player's score from board [boardId].
  Future<void> deleteScore(String boardId, String playerId);
}

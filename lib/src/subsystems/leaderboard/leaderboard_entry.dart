library;

/// A single entry returned from a leaderboard query.
class LeaderboardEntry {
  const LeaderboardEntry({
    required this.playerId,
    required this.displayName,
    required this.score,
    required this.rank,
  });

  final String playerId;
  final String displayName;
  final int score;
  final int rank;
}

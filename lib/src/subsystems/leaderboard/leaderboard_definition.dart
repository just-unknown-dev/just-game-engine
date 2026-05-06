library;

/// Defines a leaderboard with its platform-specific IDs.
///
/// Register leaderboards via [LeaderboardManager.define]:
/// ```dart
/// engine.leaderboard.define(const LeaderboardDefinition(
///   id: 'high_score',
///   androidLeaderboardId: 'CgkI_your_android_id',
///   iosLeaderboardId: 'your_ios_leaderboard_id',
/// ));
/// ```
class LeaderboardDefinition {
  const LeaderboardDefinition({
    required this.id,
    this.androidLeaderboardId,
    this.iosLeaderboardId,
    this.steamLeaderboardName,
    this.epicLeaderboardName,
  });

  /// Internal engine key — used when calling [LeaderboardManager] methods.
  final String id;

  /// Google Play Games leaderboard ID (Android).
  final String? androidLeaderboardId;

  /// Apple Game Center leaderboard ID (iOS / macOS).
  final String? iosLeaderboardId;

  /// Steam leaderboard name (Windows / Linux).
  final String? steamLeaderboardName;

  /// Epic Online Services leaderboard name (Windows / macOS).
  final String? epicLeaderboardName;
}

/// Player Profile Service
///
/// Abstract interface and data models for player profiles, friends, and
/// social features. Implement [IPlayerProfileService] to connect to any backend.
library;

// ---------------------------------------------------------------------------
// Data models
// ---------------------------------------------------------------------------

/// A player's public profile.
class PlayerProfile {
  /// Unique player identifier (matches session / auth UID).
  final String playerId;

  /// Publicly visible display name.
  final String displayName;

  /// URL of the player's avatar image.
  final String? avatarUrl;

  /// Short biography or status message.
  final String? bio;

  /// Region / locale (e.g. "eu-west", "en-US").
  final String? region;

  /// Numeric statistics (wins, losses, matches played, XP, etc.).
  final Map<String, num> stats;

  /// List of unlocked achievement IDs.
  final List<String> achievements;

  /// Arbitrary custom data stored by the game.
  final Map<String, dynamic> metadata;

  /// UTC timestamp of the player's last online activity.
  final DateTime? lastSeen;

  const PlayerProfile({
    required this.playerId,
    required this.displayName,
    this.avatarUrl,
    this.bio,
    this.region,
    this.stats = const {},
    this.achievements = const [],
    this.metadata = const {},
    this.lastSeen,
  });

  /// Create a copy of this profile with updated fields.
  PlayerProfile copyWith({
    String? displayName,
    String? avatarUrl,
    String? bio,
    String? region,
    Map<String, num>? stats,
    List<String>? achievements,
    Map<String, dynamic>? metadata,
    DateTime? lastSeen,
  }) {
    return PlayerProfile(
      playerId: playerId,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      bio: bio ?? this.bio,
      region: region ?? this.region,
      stats: stats ?? this.stats,
      achievements: achievements ?? this.achievements,
      metadata: metadata ?? this.metadata,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }

  @override
  String toString() => 'PlayerProfile($playerId, name=$displayName)';
}

/// Relationship state between the local player and another player.
enum FriendStatus {
  /// No relationship.
  none,

  /// The local player has sent a friend request.
  requestSent,

  /// The local player has received a friend request.
  requestReceived,

  /// Mutual friends.
  friends,

  /// The local player has blocked the other player.
  blocked,
}

/// A friend entry with relationship metadata.
class FriendEntry {
  final PlayerProfile profile;
  final FriendStatus status;
  final bool isOnline;

  const FriendEntry({
    required this.profile,
    required this.status,
    this.isOnline = false,
  });
}

// ---------------------------------------------------------------------------
// Abstract interface
// ---------------------------------------------------------------------------

/// Backend-agnostic player profile service.
///
/// Inject a concrete implementation to store and retrieve profiles using
/// your preferred backend (Firebase Firestore, REST API, Supabase, etc.).
abstract class IPlayerProfileService {
  /// Fetch the profile for [playerId]. Returns `null` if not found.
  Future<PlayerProfile?> fetchProfile(String playerId);

  /// Create or fully replace the profile for the authenticated player.
  Future<void> updateProfile(PlayerProfile profile);

  /// Partially update specific fields of [playerId]'s profile.
  Future<void> patchProfile(String playerId, Map<String, dynamic> fields);

  /// Fetch the friend list for [playerId].
  Future<List<FriendEntry>> fetchFriends(String playerId);

  /// Send a friend request from [fromPlayerId] to [toPlayerId].
  Future<void> sendFriendRequest(String fromPlayerId, String toPlayerId);

  /// Accept or decline a friend request from [fromPlayerId].
  Future<void> respondToFriendRequest(
    String fromPlayerId, {
    required bool accept,
  });

  /// Remove a friend relationship between the local player and [playerId].
  Future<void> removeFriend(String playerId);

  /// Increment a named stat by [delta] for [playerId].
  Future<void> incrementStat(String playerId, String statKey, num delta);

  /// Grant an achievement [achievementId] to [playerId].
  Future<void> grantAchievement(String playerId, String achievementId);
}

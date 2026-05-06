library;

/// The platform that authenticated the current user.
enum AuthPlatform { playGames, gameCenter, epicGames, steam, none }

/// A signed-in player returned by an [AuthProvider].
class AuthUser {
  const AuthUser({
    required this.uid,
    required this.displayName,
    required this.platform,
    this.avatarUrl,
  });

  /// Platform-provided player ID (unique per platform).
  final String uid;

  /// Player's display name on the platform.
  final String displayName;

  /// Platform that authenticated this user.
  final AuthPlatform platform;

  /// Optional URL to the player's avatar image.
  final String? avatarUrl;
}

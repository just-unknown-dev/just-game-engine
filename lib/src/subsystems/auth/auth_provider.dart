library;

import 'auth_user.dart';

/// Contract for platform authentication backends
/// (Play Games, Game Center, Steam, Epic Games, etc.).
///
/// Implement this interface and pass an instance to
/// [AuthManager.registerProvider] to connect the engine to a platform
/// identity service.
abstract class AuthProvider {
  Future<void> initialize();

  /// Signs the player in and returns their [AuthUser], or `null` on failure.
  Future<AuthUser?> signIn();

  /// Signs the current player out.
  Future<void> signOut();

  /// Whether a player is currently signed in.
  bool get isSignedIn;

  /// The currently signed-in player, or `null` when not signed in.
  AuthUser? get currentUser;

  Future<void> dispose();
}

/// Default provider — no platform calls, always reports signed out.
///
/// Used when no provider has been registered, or in environments where
/// platform services are unavailable (web, unknown desktop, tests).
class NoOpAuthProvider implements AuthProvider {
  @override
  Future<void> initialize() async {}

  @override
  Future<AuthUser?> signIn() async => null;

  @override
  Future<void> signOut() async {}

  @override
  bool get isSignedIn => false;

  @override
  AuthUser? get currentUser => null;

  @override
  Future<void> dispose() async {}
}

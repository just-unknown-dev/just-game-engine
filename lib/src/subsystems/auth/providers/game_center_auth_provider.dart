library;

import 'package:flutter/foundation.dart';
import 'package:games_services/games_services.dart' as gs;

import '../auth_provider.dart';
import '../auth_user.dart';

/// [AuthProvider] backed by Apple Game Center (iOS / macOS).
///
/// Calls [gs.GameAuth.signIn] and reads the player's alias and ID
/// via [gs.Player]. Falls back to `"Player"` if the name is unavailable.
///
/// Register on iOS builds only:
/// ```dart
/// if (Platform.isIOS) {
///   engine.auth.registerProvider(GameCenterAuthProvider());
/// }
/// ```
class GameCenterAuthProvider implements AuthProvider {
  AuthUser? _currentUser;

  @override
  Future<void> initialize() async {}

  @override
  Future<AuthUser?> signIn() async {
    try {
      await gs.GameAuth.signIn();
      final signedIn = await gs.GameAuth.isSignedIn;
      if (!signedIn) return null;

      String displayName = 'Player';
      String uid = 'game_center_player';

      try {
        final name = await gs.Player.getPlayerName();
        if (name != null && name.isNotEmpty) displayName = name;
      } catch (e) {
        debugPrint('GameCenterAuthProvider: getPlayerName failed ($e)');
      }

      try {
        final id = await gs.Player.getPlayerID();
        if (id != null && id.isNotEmpty) uid = id;
      } catch (e) {
        debugPrint('GameCenterAuthProvider: getPlayerID failed ($e)');
      }

      _currentUser = AuthUser(
        uid: uid,
        displayName: displayName,
        platform: AuthPlatform.gameCenter,
      );
      return _currentUser;
    } catch (e) {
      debugPrint('GameCenterAuthProvider: signIn failed ($e)');
      return null;
    }
  }

  @override
  Future<void> signOut() async {
    _currentUser = null;
  }

  @override
  bool get isSignedIn => _currentUser != null;

  @override
  AuthUser? get currentUser => _currentUser;

  @override
  Future<void> dispose() async {
    _currentUser = null;
  }
}

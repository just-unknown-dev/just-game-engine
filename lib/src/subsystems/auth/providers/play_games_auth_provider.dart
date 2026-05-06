library;

import 'package:flutter/foundation.dart';
import 'package:games_services/games_services.dart' as gs;

import '../auth_provider.dart';
import '../auth_user.dart';

/// [AuthProvider] backed by Google Play Games Services (Android).
///
/// Calls [gs.GameAuth.signIn] and reads the player's display name and ID
/// via [gs.Player]. Falls back to `"Player"` if the name is unavailable.
///
/// Register on Android builds only:
/// ```dart
/// if (Platform.isAndroid) {
///   engine.auth.registerProvider(PlayGamesAuthProvider());
/// }
/// ```
class PlayGamesAuthProvider implements AuthProvider {
  AuthUser? _currentUser;

  @override
  Future<void> initialize() async {}

  @override
  Future<AuthUser?> signIn() async {
    try {
      await gs.GameAuth.signIn();

      // Do NOT use gs.GameAuth.isSignedIn here — it subscribes to a broadcast
      // stream and will hang if the sign-in event was already emitted before
      // the subscription is set up (common for returning users already signed
      // in). If signIn() completes without throwing, the session is active.

      String displayName = 'Player';
      String uid = 'play_games_player';

      try {
        final name = await gs.Player.getPlayerName();
        if (name != null && name.isNotEmpty) displayName = name;
      } catch (e) {
        debugPrint('PlayGamesAuthProvider: getPlayerName failed ($e)');
      }

      try {
        final id = await gs.Player.getPlayerID();
        if (id != null && id.isNotEmpty) uid = id;
      } catch (e) {
        debugPrint('PlayGamesAuthProvider: getPlayerID failed ($e)');
      }

      _currentUser = AuthUser(
        uid: uid,
        displayName: displayName,
        platform: AuthPlatform.playGames,
      );
      debugPrint('PlayGamesAuthProvider: signed in as $displayName ($uid)');
      return _currentUser;
    } catch (e) {
      debugPrint('PlayGamesAuthProvider: signIn failed ($e)');
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

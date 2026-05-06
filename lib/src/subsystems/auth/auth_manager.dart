library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../ecs/ecs.dart';
import 'auth_events.dart';
import 'auth_provider.dart';
import 'auth_user.dart';

/// Manages platform authentication and exposes the signed-in [AuthUser].
///
/// Typical setup:
/// ```dart
/// // Register a platform provider after engine initialization:
/// engine.auth.registerProvider(PlayGamesAuthProvider());
///
/// // Sign in (e.g. at app start):
/// final user = await engine.auth.signIn();
///
/// // Check state at any time:
/// if (engine.auth.isSignedIn) { ... }
/// ```
class AuthManager {
  AuthProvider _provider = NoOpAuthProvider();
  World? _world;

  // ── Setup ─────────────────────────────────────────────────────────────────

  /// Binds the ECS world so sign-in/sign-out events are fired on its event bus.
  /// Called by [Engine] during subsystem initialization.
  void bindWorld(World world) => _world = world;

  /// Replaces the current platform provider.
  ///
  /// The previous provider is disposed and the new one is initialized
  /// immediately. Safe to call at any point after engine initialization.
  void registerProvider(AuthProvider provider) {
    unawaited(_provider.dispose());
    _provider = provider;
    unawaited(_provider.initialize());
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  Future<void> initialize() async {
    try {
      await _provider.initialize();
    } catch (e) {
      debugPrint('AuthManager: provider init failed ($e)');
    }
  }

  void dispose() {
    unawaited(_provider.dispose());
  }

  // ── Auth API ──────────────────────────────────────────────────────────────

  /// Signs the player in via the registered provider.
  ///
  /// Returns the [AuthUser] on success, or `null` on failure / no provider.
  /// Fires [AuthSignedInEvent] on the ECS event bus when successful.
  Future<AuthUser?> signIn() async {
    try {
      final user = await _provider.signIn();
      if (user != null) {
        debugPrint('AuthManager: signed in as ${user.displayName} (${user.platform.name})');
        _world?.events.fire(AuthSignedInEvent(user: user));
      }
      return user;
    } catch (e) {
      debugPrint('AuthManager: signIn failed ($e)');
      return null;
    }
  }

  /// Signs the current player out. Fires [AuthSignedOutEvent] if signed in.
  Future<void> signOut() async {
    if (!_provider.isSignedIn) return;
    try {
      await _provider.signOut();
      _world?.events.fire(AuthSignedOutEvent());
      debugPrint('AuthManager: signed out');
    } catch (e) {
      debugPrint('AuthManager: signOut failed ($e)');
    }
  }

  // ── Query ─────────────────────────────────────────────────────────────────

  /// The currently signed-in player, or `null` when not signed in.
  AuthUser? get currentUser => _provider.currentUser;

  /// Whether a player is currently signed in.
  bool get isSignedIn => _provider.isSignedIn;
}

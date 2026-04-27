/// Firebase subsystem for the Just Game Engine.
///
/// Wraps [FirebaseManager] from `just_firebase` and integrates it into the
/// engine lifecycle.
///
/// Firebase requires platform-specific [FirebaseOptions] that are generated
/// per project, so it cannot be auto-initialized by the engine. Call
/// [initialize] once at app startup, after [Engine.initialize], before
/// any Firebase services are used.
///
/// ```dart
/// await engine.initialize();
/// engine.start();
///
/// // Then initialize Firebase with your project's options:
/// await engine.firebase.initialize(
///   options: DefaultFirebaseOptions.currentPlatform,
/// );
///
/// // Access sub-managers:
/// final user = await engine.firebase.auth.signInAnonymously();
/// final doc  = await engine.firebase.firestore.getDocument('cfg/global');
/// final flag = engine.firebase.remoteConfig.getBool('feature_x');
/// await engine.firebase.analytics.logLevelStart(1);
/// ```
library;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:just_firebase/just_firebase.dart';

/// Engine-level façade that owns the [FirebaseManager] singleton and
/// exposes it through the engine's subsystem API.
///
/// Obtain via [Engine.firebase].
class FirebaseSubsystem {
  // ── State ──────────────────────────────────────────────────────────────────

  bool _initialized = false;

  /// Whether [initialize] has completed successfully.
  bool get isInitialized => _initialized;

  // ── Sub-manager pass-throughs ──────────────────────────────────────────────

  /// Firebase Authentication manager.
  ///
  /// Only available after [initialize].
  JustFirebaseAuth get auth => _assertInit().auth;

  /// Cloud Firestore manager.
  ///
  /// Only available after [initialize] when [JustFirebaseConfig.enableFirestore]
  /// is `true`.
  JustFirestore get firestore => _assertInit().firestore;

  /// Firebase Analytics manager.
  ///
  /// Only available after [initialize] when [JustFirebaseConfig.enableAnalytics]
  /// is `true`.
  JustFirebaseAnalytics get analytics => _assertInit().analytics;

  /// Firebase Remote Config manager.
  ///
  /// Only available after [initialize] when [JustFirebaseConfig.enableRemoteConfig]
  /// is `true`.
  JustRemoteConfig get remoteConfig => _assertInit().remoteConfig;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// Initialises Firebase and all enabled sub-managers.
  ///
  /// Must be called once at app startup with the platform-specific
  /// [options] (typically `DefaultFirebaseOptions.currentPlatform` from the
  /// generated `firebase_options.dart`).
  ///
  /// Subsequent calls are no-ops.
  Future<void> initialize({
    required FirebaseOptions options,
    JustFirebaseConfig config = const JustFirebaseConfig(),
  }) async {
    if (_initialized) return;
    try {
      await FirebaseManager().initialize(options: options, config: config);
      _initialized = true;
      debugPrint('FirebaseSubsystem: initialized');
    } catch (e) {
      debugPrint('FirebaseSubsystem: initialization failed ($e)');
    }
  }

  /// Disposes all Firebase sub-managers and resets the subsystem.
  ///
  /// After calling [dispose], [initialize] must be called again before using
  /// any Firebase service.
  void dispose() {
    if (!_initialized) return;
    FirebaseManager().dispose();
    _initialized = false;
    debugPrint('FirebaseSubsystem: disposed');
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  FirebaseManager _assertInit() {
    assert(
      _initialized,
      'FirebaseSubsystem has not been initialized. '
      'Call engine.firebase.initialize(options: ...) before accessing Firebase services.',
    );
    return FirebaseManager();
  }
}

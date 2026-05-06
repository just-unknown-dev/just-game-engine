library;

import 'package:flutter/foundation.dart';

import '../auth_provider.dart';
import '../auth_user.dart';

/// [AuthProvider] stub for Epic Games Online Services.
///
/// The Epic Games SDK is not yet available as a stable Flutter package.
/// This stub satisfies the [AuthProvider] contract and logs a warning
/// when [signIn] is called. Replace with a real implementation once
/// an appropriate Flutter/FFI binding is available.
class EpicGamesAuthProvider implements AuthProvider {
  @override
  Future<void> initialize() async {
    debugPrint('EpicGamesAuthProvider: SDK not yet wired — stub only');
  }

  @override
  Future<AuthUser?> signIn() async {
    debugPrint('EpicGamesAuthProvider: signIn called but SDK not wired — stub only');
    return null;
  }

  @override
  Future<void> signOut() async {}

  @override
  bool get isSignedIn => false;

  @override
  AuthUser? get currentUser => null;

  @override
  Future<void> dispose() async {}
}

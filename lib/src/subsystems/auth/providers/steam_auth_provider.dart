library;

import 'package:flutter/foundation.dart';

import '../auth_provider.dart';
import '../auth_user.dart';

/// [AuthProvider] stub for Steam (Windows / Linux).
///
/// The Steamworks SDK does not have a stable official Flutter package.
/// This stub satisfies the [AuthProvider] contract and logs a warning
/// when [signIn] is called. Replace with a real implementation once
/// a mature Flutter/FFI Steamworks binding is available.
class SteamAuthProvider implements AuthProvider {
  @override
  Future<void> initialize() async {
    debugPrint('SteamAuthProvider: SDK not yet wired — stub only');
  }

  @override
  Future<AuthUser?> signIn() async {
    debugPrint('SteamAuthProvider: signIn called but SDK not wired — stub only');
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

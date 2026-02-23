/// Session Manager
///
/// Manages the authenticated player session lifecycle — creation, renewal,
/// expiry, and teardown. Replaces the original SessionManager stub.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

/// Current lifecycle state of the session.
enum SessionState {
  /// No active session.
  idle,

  /// Handshake / authentication in progress.
  authenticating,

  /// Session is valid and active.
  active,

  /// Session token has expired; renewal needed.
  expired,

  /// Session encountered an unrecoverable error.
  error,
}

/// Represents a single authenticated player session.
class PlayerSession {
  /// Unique session identifier issued by the backend.
  final String sessionId;

  /// The authenticated player's unique ID.
  final String playerId;

  /// Display name of the player.
  final String displayName;

  /// Bearer / access token for authenticated API requests.
  final String token;

  /// Optional refresh token used to renew [token] without re-authenticating.
  final String? refreshToken;

  /// UTC time when the session was created.
  final DateTime createdAt;

  /// UTC time after which the [token] is no longer valid.
  final DateTime expiresAt;

  /// Arbitrary metadata (avatar URL, region, custom claims, etc.).
  final Map<String, dynamic> metadata;

  PlayerSession({
    required this.sessionId,
    required this.playerId,
    required this.displayName,
    required this.token,
    required this.createdAt,
    required this.expiresAt,
    this.refreshToken,
    this.metadata = const {},
  });

  /// Whether the session token has passed its expiry time.
  bool get isExpired => DateTime.now().toUtc().isAfter(expiresAt);

  /// Remaining valid duration. Returns [Duration.zero] if already expired.
  Duration get timeUntilExpiry {
    final remaining = expiresAt.difference(DateTime.now().toUtc());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  @override
  String toString() => 'PlayerSession(player=$playerId, expired=$isExpired)';
}

// ---------------------------------------------------------------------------
// Manager
// ---------------------------------------------------------------------------

/// Manages the player's authenticated session.
///
/// Holds at most one active [PlayerSession] at a time. Fires
/// [onSessionChanged] whenever the session transitions. Supports
/// auto-renewal via [enableAutoRenewal].
class SessionManager {
  PlayerSession? _session;
  SessionState _state = SessionState.idle;
  Timer? _expiryTimer;
  Timer? _renewalTimer;

  final List<void Function(SessionState state, PlayerSession? session)>
  _onSessionChanged = [];

  bool _initialized = false;

  // ---------------------------------------------------------------------------
  // Accessors
  // ---------------------------------------------------------------------------

  /// The currently active session, or `null` if none.
  PlayerSession? get currentSession => _session;

  /// Whether there is a valid, non-expired session.
  bool get hasActiveSession =>
      _session != null && !_session!.isExpired && _state == SessionState.active;

  /// Current lifecycle state.
  SessionState get state => _state;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Initialise the session manager.
  void initialize() {
    if (_initialized) return;
    _initialized = true;
    debugPrint('SessionManager: initialized');
  }

  // ---------------------------------------------------------------------------
  // Session control
  // ---------------------------------------------------------------------------

  /// Store [session] as the active session and transition to [SessionState.active].
  ///
  /// Schedules an expiry notification and — if [autoRenewBefore] is given —
  /// an auto-renewal trigger that many seconds before expiry.
  void createSession(PlayerSession session, {Duration? autoRenewBefore}) {
    _clearTimers();
    _session = session;
    _setState(SessionState.active);
    debugPrint('SessionManager: session created for ${session.playerId}');
    _scheduleExpiry(session, autoRenewBefore: autoRenewBefore);
  }

  /// Replace the current session with [updated] (e.g. after token refresh).
  void renewSession(PlayerSession updated) {
    _clearTimers();
    _session = updated;
    _setState(SessionState.active);
    debugPrint('SessionManager: session renewed for ${updated.playerId}');
    _scheduleExpiry(updated);
  }

  /// Terminate the current session and return to [SessionState.idle].
  void leaveSession() {
    _clearTimers();
    final player = _session?.playerId;
    _session = null;
    _setState(SessionState.idle);
    debugPrint('SessionManager: session ended for $player');
  }

  /// Manually mark the session as expired.
  void expireSession() {
    _clearTimers();
    _setState(SessionState.expired);
    debugPrint('SessionManager: session expired');
  }

  // ---------------------------------------------------------------------------
  // Callbacks
  // ---------------------------------------------------------------------------

  /// Register a callback invoked on every session state change.
  void onSessionChanged(
    void Function(SessionState state, PlayerSession? session) callback,
  ) {
    _onSessionChanged.add(callback);
  }

  /// Remove a previously registered callback.
  void removeSessionListener(
    void Function(SessionState state, PlayerSession? session) callback,
  ) {
    _onSessionChanged.remove(callback);
  }

  // ---------------------------------------------------------------------------
  // Cleanup
  // ---------------------------------------------------------------------------

  /// Release all resources.
  void dispose() {
    _clearTimers();
    _onSessionChanged.clear();
    _session = null;
    _initialized = false;
    debugPrint('SessionManager: disposed');
  }

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  void _setState(SessionState next) {
    if (_state == next) return;
    _state = next;
    for (final cb in List.of(_onSessionChanged)) {
      cb(_state, _session);
    }
  }

  void _scheduleExpiry(PlayerSession session, {Duration? autoRenewBefore}) {
    final ttl = session.timeUntilExpiry;
    if (ttl == Duration.zero) {
      _setState(SessionState.expired);
      return;
    }

    // Schedule expiry notification.
    _expiryTimer = Timer(ttl, () {
      debugPrint('SessionManager: session token expired');
      _setState(SessionState.expired);
    });

    // Schedule auto-renewal trigger (fires before expiry).
    if (autoRenewBefore != null && ttl > autoRenewBefore) {
      final renewIn = ttl - autoRenewBefore;
      _renewalTimer = Timer(renewIn, () {
        debugPrint('SessionManager: auto-renewal triggered');
        // Emit a special state change so callers can refresh the token.
        for (final cb in List.of(_onSessionChanged)) {
          cb(SessionState.authenticating, _session);
        }
      });
    }
  }

  void _clearTimers() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _renewalTimer?.cancel();
    _renewalTimer = null;
  }
}

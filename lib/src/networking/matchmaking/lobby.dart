/// Lobby
///
/// Manages the pre-game lobby where players gather before a match starts.
/// Handles readiness checks, player slots, and auto-start countdown.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

/// A player entry in the pre-game lobby.
class LobbyPlayer {
  /// Unique player / peer identifier.
  final String playerId;

  /// Display name shown to other players.
  final String displayName;

  /// URL of the player's avatar image (optional).
  final String? avatarUrl;

  /// Whether this player has clicked "Ready".
  bool isReady;

  /// Whether this player is the room host.
  bool isHost;

  /// Arbitrary metadata (skin, rank, region, etc.).
  final Map<String, dynamic> metadata;

  LobbyPlayer({
    required this.playerId,
    required this.displayName,
    this.avatarUrl,
    this.isReady = false,
    this.isHost = false,
    this.metadata = const {},
  });

  @override
  String toString() =>
      'LobbyPlayer($displayName, ready=$isReady, host=$isHost)';
}

/// Current lifecycle state of the lobby.
enum LobbyState {
  /// Accepting players; game has not started.
  open,

  /// No more players may join; waiting for all to be ready.
  locked,

  /// Countdown to game start is in progress.
  starting,

  /// Transitioned to an active [Room]; lobby is done.
  started,
}

/// Manages the pre-game lobby.
///
/// Tracks player readiness, controls access (lock / unlock), and runs an
/// optional countdown before notifying [onLobbyReady].
class Lobby {
  /// Minimum number of players required before the game can start.
  final int minPlayers;

  /// Maximum number of players allowed.
  final int maxPlayers;

  /// Seconds in the auto-start countdown (0 = no auto-start).
  final int countdownSeconds;

  LobbyState _state = LobbyState.open;
  final List<LobbyPlayer> _players = [];
  Timer? _countdownTimer;
  int _remainingSeconds = 0;

  // ---------------------------------------------------------------------------
  // Callbacks
  // ---------------------------------------------------------------------------

  final List<void Function(LobbyPlayer)> _onPlayerJoined = [];
  final List<void Function(LobbyPlayer)> _onPlayerLeft = [];
  final List<void Function(LobbyPlayer)> _onPlayerReadyChanged = [];
  final List<void Function(int secondsRemaining)> _onCountdownTick = [];
  final List<void Function()> _onLobbyReady = [];

  Lobby({this.minPlayers = 2, this.maxPlayers = 8, this.countdownSeconds = 5});

  // ---------------------------------------------------------------------------
  // Accessors
  // ---------------------------------------------------------------------------

  /// Present lobby state.
  LobbyState get state => _state;

  /// Immutable snapshot of current players.
  List<LobbyPlayer> get players => List.unmodifiable(_players);

  /// Number of players currently in the lobby.
  int get playerCount => _players.length;

  /// Whether all players are marked ready.
  bool get allReady => _players.isNotEmpty && _players.every((p) => p.isReady);

  /// Whether the lobby can accept the next player.
  bool get hasRoom => _players.length < maxPlayers;

  /// Remaining countdown seconds (0 when no countdown is running).
  int get remainingSeconds => _remainingSeconds;

  // ---------------------------------------------------------------------------
  // Player management
  // ---------------------------------------------------------------------------

  /// Add [player] to the lobby. Returns `false` if the lobby is full, locked,
  /// or the player is already present.
  bool addPlayer(LobbyPlayer player) {
    if (!hasRoom ||
        _state == LobbyState.locked ||
        _state == LobbyState.starting) {
      return false;
    }
    if (_players.any((p) => p.playerId == player.playerId)) return false;
    _players.add(player);
    for (final cb in List.of(_onPlayerJoined)) {
      cb(player);
    }
    _checkAutoStart();
    return true;
  }

  /// Remove the player with [playerId]. Returns the removed [LobbyPlayer] or
  /// `null` if not found.
  LobbyPlayer? removePlayer(String playerId) {
    final index = _players.indexWhere((p) => p.playerId == playerId);
    if (index == -1) return null;
    final player = _players.removeAt(index);
    for (final cb in List.of(_onPlayerLeft)) {
      cb(player);
    }
    // Cancel countdown if no longer enough players.
    if (_players.length < minPlayers) {
      _cancelCountdown();
    }
    return player;
  }

  // ---------------------------------------------------------------------------
  // Readiness
  // ---------------------------------------------------------------------------

  /// Mark player [playerId] as ready or not-ready.
  void setReady(String playerId, {bool ready = true}) {
    final player = _findPlayer(playerId);
    if (player == null) return;
    player.isReady = ready;
    for (final cb in List.of(_onPlayerReadyChanged)) {
      cb(player);
    }
    _checkAutoStart();
  }

  // ---------------------------------------------------------------------------
  // Lobby control
  // ---------------------------------------------------------------------------

  /// Prevent new players from joining.
  void lockLobby() {
    if (_state != LobbyState.open) return;
    _state = LobbyState.locked;
    debugPrint('Lobby: locked (${_players.length} players)');
    _checkAutoStart();
  }

  /// Re-allow players to join (cancels any active countdown).
  void unlockLobby() {
    if (_state == LobbyState.starting) _cancelCountdown();
    _state = LobbyState.open;
    debugPrint('Lobby: unlocked');
  }

  /// Manually trigger the game-start countdown, bypassing readiness checks.
  void forceStart() => _beginCountdown();

  // ---------------------------------------------------------------------------
  // Callbacks registration
  // ---------------------------------------------------------------------------

  /// Fired when a player joins.
  void onPlayerJoined(void Function(LobbyPlayer) cb) => _onPlayerJoined.add(cb);

  /// Fired when a player leaves.
  void onPlayerLeft(void Function(LobbyPlayer) cb) => _onPlayerLeft.add(cb);

  /// Fired when a player's ready state changes.
  void onPlayerReadyChanged(void Function(LobbyPlayer) cb) =>
      _onPlayerReadyChanged.add(cb);

  /// Fired each second during the countdown with the remaining seconds.
  void onCountdownTick(void Function(int secondsRemaining) cb) =>
      _onCountdownTick.add(cb);

  /// Fired when the countdown reaches zero — game should start now.
  void onLobbyReady(void Function() cb) => _onLobbyReady.add(cb);

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  LobbyPlayer? _findPlayer(String playerId) {
    try {
      return _players.firstWhere((p) => p.playerId == playerId);
    } catch (_) {
      return null;
    }
  }

  void _checkAutoStart() {
    if (_state == LobbyState.starting || _state == LobbyState.started) return;
    if (_players.length >= minPlayers && allReady) {
      if (countdownSeconds > 0) {
        _beginCountdown();
      } else {
        _fireReady();
      }
    }
  }

  void _beginCountdown() {
    if (_state == LobbyState.starting) return;
    _state = LobbyState.starting;
    _remainingSeconds = countdownSeconds;
    debugPrint('Lobby: countdown started ($_remainingSeconds seconds)');
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      for (final cb in List.of(_onCountdownTick)) {
        cb(_remainingSeconds);
      }
      _remainingSeconds--;
      if (_remainingSeconds < 0) {
        timer.cancel();
        _fireReady();
      }
    });
  }

  void _cancelCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _remainingSeconds = 0;
    if (_state == LobbyState.starting) {
      _state = LobbyState.locked;
      debugPrint('Lobby: countdown cancelled');
    }
  }

  void _fireReady() {
    _state = LobbyState.started;
    debugPrint('Lobby: ready — starting game');
    for (final cb in List.of(_onLobbyReady)) {
      cb();
    }
  }

  /// Release all timers and callbacks.
  void dispose() {
    _cancelCountdown();
    _onPlayerJoined.clear();
    _onPlayerLeft.clear();
    _onPlayerReadyChanged.clear();
    _onCountdownTick.clear();
    _onLobbyReady.clear();
    debugPrint('Lobby: disposed');
  }
}

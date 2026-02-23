/// Room
///
/// Defines game room topology, settings, and state management.
/// A [Room] is the authoritative record of who is in a multiplayer session.
library;

import 'lobby.dart';

/// Determines how peers in a [Room] communicate with each other.
enum RoomTopology {
  /// All clients connect to a dedicated server; server is authoritative.
  dedicatedServer,

  /// One client acts as the host; others connect to it directly.
  peerToPeer,
}

/// Lifecycle state of a [Room].
enum RoomState {
  /// Accepting new players.
  waiting,

  /// Game is running; no new players may join.
  inProgress,

  /// Game has concluded.
  finished,

  /// Room is closed / cleaned up.
  closed,
}

/// Immutable configuration supplied when creating a [Room].
class RoomSettings {
  /// Maximum number of players allowed.
  final int maxPlayers;

  /// Network topology for this room.
  final RoomTopology topology;

  /// Private rooms do not appear in public listings and require an invite code.
  final bool isPrivate;

  /// Arbitrary key-value metadata (game mode, map name, etc.).
  final Map<String, dynamic> metadata;

  const RoomSettings({
    this.maxPlayers = 8,
    this.topology = RoomTopology.dedicatedServer,
    this.isPrivate = false,
    this.metadata = const {},
  });
}

/// A multiplayer game room.
///
/// Tracks connected [players], enforces [settings], and fires callbacks
/// when the room state or player roster changes.
class Room {
  /// Unique room identifier (e.g. UUID issued by the server).
  final String id;

  /// Player ID of the room host.
  String hostId;

  /// Immutable room configuration.
  final RoomSettings settings;

  RoomState _state = RoomState.waiting;
  final List<LobbyPlayer> _players = [];

  // ---------------------------------------------------------------------------
  // Callbacks
  // ---------------------------------------------------------------------------

  final List<void Function(LobbyPlayer player)> _onPlayerJoined = [];
  final List<void Function(LobbyPlayer player)> _onPlayerLeft = [];
  final List<void Function(RoomState previous, RoomState next)>
  _onStateChanged = [];

  Room({required this.id, required this.hostId, RoomSettings? settings})
    : settings = settings ?? const RoomSettings();

  // ---------------------------------------------------------------------------
  // Accessors
  // ---------------------------------------------------------------------------

  /// Current lifecycle state of the room.
  RoomState get state => _state;

  /// Immutable view of the current player list.
  List<LobbyPlayer> get players => List.unmodifiable(_players);

  /// Whether the room can accept additional players.
  bool get isFull => _players.length >= settings.maxPlayers;

  /// Number of players currently in the room.
  int get playerCount => _players.length;

  // ---------------------------------------------------------------------------
  // Player management
  // ---------------------------------------------------------------------------

  /// Add [player] to the room. Returns `false` if the room is full or the
  /// player is already present.
  bool addPlayer(LobbyPlayer player) {
    if (isFull || _state != RoomState.waiting) return false;
    if (_players.any((p) => p.playerId == player.playerId)) return false;
    _players.add(player);
    for (final cb in List.of(_onPlayerJoined)) {
      cb(player);
    }
    return true;
  }

  /// Remove the player with [playerId] from the room. Returns the removed
  /// [LobbyPlayer] or `null` if not found.
  LobbyPlayer? removePlayer(String playerId) {
    final index = _players.indexWhere((p) => p.playerId == playerId);
    if (index == -1) return null;
    final player = _players.removeAt(index);
    for (final cb in List.of(_onPlayerLeft)) {
      cb(player);
    }
    // If the host left, promote the next player.
    if (playerId == hostId && _players.isNotEmpty) {
      hostId = _players.first.playerId;
    }
    return player;
  }

  /// Look up a player by ID.
  LobbyPlayer? findPlayer(String playerId) {
    try {
      return _players.firstWhere((p) => p.playerId == playerId);
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // State transitions
  // ---------------------------------------------------------------------------

  /// Transition the room to [next]. Notifies listeners.
  void setState(RoomState next) {
    if (_state == next) return;
    final previous = _state;
    _state = next;
    for (final cb in List.of(_onStateChanged)) {
      cb(previous, next);
    }
  }

  // ---------------------------------------------------------------------------
  // Callbacks registration
  // ---------------------------------------------------------------------------

  /// Register a callback invoked when a player joins.
  void onPlayerJoined(void Function(LobbyPlayer player) callback) =>
      _onPlayerJoined.add(callback);

  /// Register a callback invoked when a player leaves.
  void onPlayerLeft(void Function(LobbyPlayer player) callback) =>
      _onPlayerLeft.add(callback);

  /// Register a callback invoked on room state change.
  void onStateChanged(
    void Function(RoomState previous, RoomState next) callback,
  ) => _onStateChanged.add(callback);

  @override
  String toString() =>
      'Room(id=$id, state=${_state.name}, '
      'players=${_players.length}/${settings.maxPlayers})';
}

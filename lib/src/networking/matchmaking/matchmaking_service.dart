/// Matchmaking Service
///
/// Provides matchmaking, room creation, and room-listing capabilities.
/// The abstract [IMatchmakingService] is backend-agnostic; inject the
/// concrete implementation your server requires.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'room.dart';
import 'lobby.dart';

// ---------------------------------------------------------------------------
// Criteria & Events
// ---------------------------------------------------------------------------

/// Constraints used to find a suitable [Room] for a player.
class MatchmakingCriteria {
  /// Inclusive lower bound of acceptable skill rating (null = no lower bound).
  final double? minSkill;

  /// Inclusive upper bound of acceptable skill rating (null = no upper bound).
  final double? maxSkill;

  /// Preferred server region (e.g. "eu-west", "us-east").
  final String? region;

  /// Game mode identifier (e.g. "deathmatch", "co-op").
  final String? gameMode;

  /// Maximum number of players in the matched room.
  final int maxPlayers;

  const MatchmakingCriteria({
    this.minSkill,
    this.maxSkill,
    this.region,
    this.gameMode,
    this.maxPlayers = 8,
  });
}

/// Type of a [MatchmakingEvent].
enum MatchmakingEventType {
  /// Searching for a match.
  searching,

  /// A suitable room was found and the player is being placed.
  matchFound,

  /// A room was created for the player.
  roomCreated,

  /// The player successfully joined a room.
  joined,

  /// Matchmaking was cancelled by the client.
  cancelled,

  /// Matchmaking failed (timeout, server error, etc.).
  failed,
}

/// Emitted on [IMatchmakingService.events] to describe progress.
class MatchmakingEvent {
  final MatchmakingEventType type;
  final Room? room;
  final String? message;

  const MatchmakingEvent({required this.type, this.room, this.message});

  @override
  String toString() =>
      'MatchmakingEvent(${type.name}, room=${room?.id}, msg=$message)';
}

// ---------------------------------------------------------------------------
// Abstract interface
// ---------------------------------------------------------------------------

/// Abstract matchmaking interface. Implement this to connect to a real
/// matchmaking backend (custom server, Firebase, Nakama, Photon, etc.).
abstract class IMatchmakingService {
  /// Stream of [MatchmakingEvent]s emitted during an active search.
  Stream<MatchmakingEvent> get events;

  /// Begin searching for a match satisfying [criteria].
  Future<void> findMatch(MatchmakingCriteria criteria);

  /// Abort an in-progress search.
  Future<void> cancelSearch();

  /// Create a new room with the given [settings].
  Future<Room> createRoom(RoomSettings settings, LobbyPlayer host);

  /// Join an existing room by its [roomId].
  Future<void> joinRoom(String roomId, LobbyPlayer player);

  /// Leave the current room.
  Future<void> leaveRoom(String playerId);

  /// Fetch a list of public rooms optionally filtered by [gameMode].
  Future<List<Room>> listRooms({String? gameMode});

  /// Look up a specific room by [roomId].
  Future<Room?> getRoom(String roomId);
}

// ---------------------------------------------------------------------------
// In-memory concrete implementation (for local / offline testing)
// ---------------------------------------------------------------------------

/// A simple in-memory [IMatchmakingService] for local development and testing.
///
/// All rooms are stored in-process; connecting remotely requires a server-side
/// implementation of [IMatchmakingService].
class MatchmakingService implements IMatchmakingService {
  final Map<String, Room> _rooms = {};
  final _eventsController = StreamController<MatchmakingEvent>.broadcast();
  bool _searching = false;

  @override
  Stream<MatchmakingEvent> get events => _eventsController.stream;

  @override
  Future<void> findMatch(MatchmakingCriteria criteria) async {
    if (_searching) return;
    _searching = true;
    _eventsController.add(
      const MatchmakingEvent(type: MatchmakingEventType.searching),
    );
    debugPrint('MatchmakingService: searching…');

    // Find a waiting room that matches the criteria.
    final match = _rooms.values.where((room) {
      if (room.state != RoomState.waiting) return false;
      if (room.isFull) return false;
      if (criteria.gameMode != null &&
          room.settings.metadata['gameMode'] != criteria.gameMode) {
        return false;
      }
      if (room.settings.isPrivate) return false;
      return true;
    }).firstOrNull;

    _searching = false;

    if (match != null) {
      _eventsController.add(
        MatchmakingEvent(type: MatchmakingEventType.matchFound, room: match),
      );
      debugPrint('MatchmakingService: match found — room ${match.id}');
    } else {
      _eventsController.add(
        const MatchmakingEvent(
          type: MatchmakingEventType.failed,
          message: 'No suitable room found',
        ),
      );
      debugPrint('MatchmakingService: no match found');
    }
  }

  @override
  Future<void> cancelSearch() async {
    if (!_searching) return;
    _searching = false;
    _eventsController.add(
      const MatchmakingEvent(type: MatchmakingEventType.cancelled),
    );
    debugPrint('MatchmakingService: search cancelled');
  }

  @override
  Future<Room> createRoom(RoomSettings settings, LobbyPlayer host) async {
    final roomId = 'room_${DateTime.now().millisecondsSinceEpoch}';
    final room = Room(id: roomId, hostId: host.playerId, settings: settings);
    host.isHost = true;
    room.addPlayer(host);
    _rooms[roomId] = room;
    _eventsController.add(
      MatchmakingEvent(type: MatchmakingEventType.roomCreated, room: room),
    );
    debugPrint('MatchmakingService: created room $roomId');
    return room;
  }

  @override
  Future<void> joinRoom(String roomId, LobbyPlayer player) async {
    final room = _rooms[roomId];
    if (room == null) {
      throw StateError('Room $roomId not found');
    }
    final joined = room.addPlayer(player);
    if (!joined) {
      throw StateError('Could not join room $roomId (full or in progress)');
    }
    _eventsController.add(
      MatchmakingEvent(type: MatchmakingEventType.joined, room: room),
    );
    debugPrint('MatchmakingService: ${player.displayName} joined room $roomId');
  }

  @override
  Future<void> leaveRoom(String playerId) async {
    for (final room in _rooms.values) {
      final removed = room.removePlayer(playerId);
      if (removed != null) {
        debugPrint(
          'MatchmakingService: ${removed.displayName} left room ${room.id}',
        );
        // Remove empty rooms.
        if (room.playerCount == 0) {
          _rooms.remove(room.id);
          debugPrint('MatchmakingService: empty room ${room.id} removed');
        }
        return;
      }
    }
  }

  @override
  Future<List<Room>> listRooms({String? gameMode}) async {
    return _rooms.values.where((room) {
      if (room.settings.isPrivate) return false;
      if (gameMode != null && room.settings.metadata['gameMode'] != gameMode) {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  Future<Room?> getRoom(String roomId) async => _rooms[roomId];

  /// Release all resources.
  void dispose() {
    _eventsController.close();
    _rooms.clear();
    debugPrint('MatchmakingService: disposed');
  }
}

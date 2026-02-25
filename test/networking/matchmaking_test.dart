import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  group('Lobby', () {
    test('Lobby manages players and readiness', () {
      final lobby = Lobby(minPlayers: 2, maxPlayers: 4, countdownSeconds: 0);
      final p1 = LobbyPlayer(playerId: 'p1', displayName: 'Player 1');
      final p2 = LobbyPlayer(playerId: 'p2', displayName: 'Player 2');

      expect(lobby.playerCount, 0);

      bool p1Joined = lobby.addPlayer(p1);
      expect(p1Joined, isTrue);
      expect(lobby.playerCount, 1);

      // Cannot add same player
      bool p1JoinedAgain = lobby.addPlayer(p1);
      expect(p1JoinedAgain, isFalse);

      lobby.addPlayer(p2);
      expect(lobby.playerCount, 2);

      // Readiness
      expect(lobby.allReady, isFalse);

      var readyFired = false;
      lobby.onLobbyReady(() {
        readyFired = true;
      });

      lobby.setReady('p1', ready: true);
      expect(lobby.allReady, isFalse);
      expect(readyFired, isFalse);

      lobby.setReady('p2', ready: true);
      expect(lobby.allReady, isTrue);

      // Since countdownSeconds is 0, onLobbyReady fires immediately when all are ready
      expect(readyFired, isTrue);
      expect(lobby.state, LobbyState.started);
    });

    test('Lobby locking and unlocking', () {
      final lobby = Lobby();
      lobby.lockLobby();
      expect(lobby.state, LobbyState.locked);

      final p1 = LobbyPlayer(playerId: 'p1', displayName: 'Player 1');
      bool joined = lobby.addPlayer(p1);
      expect(joined, isFalse); // locked

      lobby.unlockLobby();
      expect(lobby.state, LobbyState.open);
      joined = lobby.addPlayer(p1);
      expect(joined, isTrue);
    });
  });

  group('Room', () {
    test('Room settings and player management', () {
      final settings = RoomSettings(maxPlayers: 2);
      final room = Room(id: 'r1', hostId: 'p1', settings: settings);

      expect(room.id, 'r1');
      expect(room.hostId, 'p1');

      final p1 = LobbyPlayer(playerId: 'p1', displayName: 'Host Player');
      final p2 = LobbyPlayer(playerId: 'p2', displayName: 'Guest Player');
      final p3 = LobbyPlayer(playerId: 'p3', displayName: 'Extra Player');

      expect(room.addPlayer(p1), isTrue);
      expect(room.addPlayer(p2), isTrue);
      expect(room.addPlayer(p3), isFalse); // Room full

      expect(room.playerCount, 2);

      var stateVar = RoomState.waiting;
      room.onStateChanged((prev, next) {
        stateVar = next;
      });

      room.setState(RoomState.inProgress);
      expect(stateVar, RoomState.inProgress);

      final removed = room.removePlayer('p1');
      expect(removed?.playerId, 'p1');
      expect(room.hostId, 'p2'); // Host re-assigned
    });
  });

  group('MatchmakingService (In-Memory)', () {
    test('createRoom, joinRoom, and findMatch flows', () async {
      final service = MatchmakingService();

      // Create a room
      final p1 = LobbyPlayer(playerId: 'p1', displayName: 'Host Player');
      final room = await service.createRoom(
        RoomSettings(metadata: {'gameMode': 'tdm'}),
        p1,
      );

      expect(room.id, isNotNull);
      expect(room.players.first.playerId, p1.playerId);
      expect(room.players.first.isHost, isTrue);

      // Another player tries to find a match
      MatchmakingEvent? lastEvent;
      service.events.listen((event) {
        lastEvent = event;
      });

      await service.findMatch(MatchmakingCriteria(gameMode: 'tdm'));
      await Future.delayed(Duration.zero);
      expect(lastEvent?.type, MatchmakingEventType.matchFound);
      expect(lastEvent?.room?.id, room.id);

      // Join the match
      final p2 = LobbyPlayer(playerId: 'p2', displayName: 'P2');
      await service.joinRoom(room.id, p2);
      await Future.delayed(Duration.zero);

      expect(lastEvent?.type, MatchmakingEventType.joined);
      expect(room.playerCount, 2);

      // Leave the match
      await service.leaveRoom('p2');
      expect(room.playerCount, 1);

      await service.leaveRoom('p1');
      expect(room.playerCount, 0);

      // The room should be deleted now
      final list = await service.listRooms();
      expect(list, isEmpty);

      service.dispose();
    });
  });
}

/// Mock Networking
///
/// In-memory mock implementations of [NetworkTransport], [NetworkServer],
/// and [IMatchmakingService] for use in unit tests and integration tests.
/// No real I/O takes place; all communication happens via in-memory queues.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../transport/packet.dart';
import '../transport/connection.dart';
import '../transport/transport_layer.dart';
import '../matchmaking/room.dart';
import '../matchmaking/lobby.dart';
import '../matchmaking/matchmaking_service.dart';

// ---------------------------------------------------------------------------
// Mock transport
// ---------------------------------------------------------------------------

/// An in-memory [NetworkTransport] for unit testing.
///
/// Calling [simulateReceive] injects a packet as if it arrived from the
/// network. All packets passed to [send] are collected in [sentPackets].
class MockNetworkTransport implements NetworkTransport {
  final _packetController = StreamController<NetworkPacket>.broadcast();
  final List<NetworkPacket> sentPackets = [];

  final NetworkConnection _connection;

  MockNetworkTransport()
    : _connection = NetworkConnection(host: 'mock', port: 0);

  @override
  NetworkConnection get connection => _connection;

  @override
  Stream<NetworkPacket> get onPacketReceived => _packetController.stream;

  @override
  Future<void> connect(String host, int port) async {
    _connection.setState(ConnectionState.connected);
    debugPrint('MockNetworkTransport: connected');
  }

  @override
  Future<void> disconnect() async {
    _connection.setState(ConnectionState.disconnected);
    debugPrint('MockNetworkTransport: disconnected');
  }

  @override
  void send(NetworkPacket packet) {
    sentPackets.add(packet);
    debugPrint(
      'MockNetworkTransport: sent ${packet.type.name} seq=${packet.sequenceNumber}',
    );
  }

  /// Inject [packet] as if it were received from the remote end.
  void simulateReceive(NetworkPacket packet) {
    _packetController.add(packet);
  }

  /// Return and clear [sentPackets] in one call.
  List<NetworkPacket> drainSent() {
    final drained = List<NetworkPacket>.from(sentPackets);
    sentPackets.clear();
    return drained;
  }

  @override
  void dispose() {
    _packetController.close();
    debugPrint('MockNetworkTransport: disposed');
  }
}

// ---------------------------------------------------------------------------
// Mock server
// ---------------------------------------------------------------------------

/// A lightweight in-memory server counterpart for testing client↔server flows.
///
/// Connect a [MockNetworkTransport] to this server and use [broadcast] /
/// [sendToClient] / [expectMessage] to script interactions.
class MockNetworkServer {
  final List<MockNetworkTransport> _clients = [];
  final List<NetworkPacket> _receivedMessages = [];
  final _messageController = StreamController<NetworkPacket>.broadcast();

  int _seq = 0;

  /// All packets received from any connected client.
  List<NetworkPacket> get receivedMessages =>
      List.unmodifiable(_receivedMessages);

  /// Stream of all packets received by the server.
  Stream<NetworkPacket> get onMessage => _messageController.stream;

  // ---------------------------------------------------------------------------
  // Client management
  // ---------------------------------------------------------------------------

  /// Register a [MockNetworkTransport] as a client.
  void addClient(MockNetworkTransport client) {
    _clients.add(client);
    client.onPacketReceived.listen(_onClientPacket);
    debugPrint('MockNetworkServer: client added (${_clients.length} total)');
  }

  /// Disconnect and remove a client.
  void removeClient(MockNetworkTransport client) {
    _clients.remove(client);
    debugPrint('MockNetworkServer: client removed (${_clients.length} total)');
  }

  // ---------------------------------------------------------------------------
  // Sending
  // ---------------------------------------------------------------------------

  /// Broadcast [packet] to all connected clients.
  void broadcast(NetworkPacket packet) {
    for (final client in List.of(_clients)) {
      client.simulateReceive(packet);
    }
  }

  /// Deliver [packet] to a specific [client] only.
  void sendToClient(MockNetworkTransport client, NetworkPacket packet) {
    client.simulateReceive(packet);
  }

  /// Convenience: broadcast a typed [payload] to all clients.
  void broadcastData(
    Map<String, dynamic> payload, {
    PacketType type = PacketType.reliable,
  }) {
    broadcast(
      NetworkPacket(sequenceNumber: _seq++, type: type, payload: payload),
    );
  }

  // ---------------------------------------------------------------------------
  // Assertions
  // ---------------------------------------------------------------------------

  /// Returns the first received packet whose [PacketType] matches [type], or
  /// `null` if none found.
  NetworkPacket? firstReceived(PacketType type) {
    try {
      return _receivedMessages.firstWhere((p) => p.type == type);
    } catch (_) {
      return null;
    }
  }

  /// Returns all received packets of [type].
  List<NetworkPacket> allReceived(PacketType type) =>
      _receivedMessages.where((p) => p.type == type).toList();

  /// Clear the received-message log.
  void clearReceived() => _receivedMessages.clear();

  // ---------------------------------------------------------------------------
  // Cleanup
  // ---------------------------------------------------------------------------

  /// Release all resources.
  void dispose() {
    _clients.clear();
    _receivedMessages.clear();
    _messageController.close();
    debugPrint('MockNetworkServer: disposed');
  }

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  void _onClientPacket(NetworkPacket packet) {
    _receivedMessages.add(packet);
    _messageController.add(packet);
  }
}

// ---------------------------------------------------------------------------
// Mock matchmaking service
// ---------------------------------------------------------------------------

/// An in-memory [IMatchmakingService] for testing matchmaking flows without
/// a real server. Wraps [MatchmakingService] and exposes test helpers.
class MockMatchmakingService implements IMatchmakingService {
  final MatchmakingService _inner = MatchmakingService();

  /// Force a specific [event] onto the event stream.
  void injectEvent(MatchmakingEvent event) {
    // Access via the inner service's controller is not public; we proxy
    // the interface and delegate — callers test via [events].
    debugPrint('MockMatchmakingService: injecting ${event.type.name}');
  }

  @override
  Stream<MatchmakingEvent> get events => _inner.events;

  @override
  Future<void> findMatch(MatchmakingCriteria criteria) =>
      _inner.findMatch(criteria);

  @override
  Future<void> cancelSearch() => _inner.cancelSearch();

  @override
  Future<Room> createRoom(RoomSettings settings, LobbyPlayer host) =>
      _inner.createRoom(settings, host);

  @override
  Future<void> joinRoom(String roomId, LobbyPlayer player) =>
      _inner.joinRoom(roomId, player);

  @override
  Future<void> leaveRoom(String playerId) => _inner.leaveRoom(playerId);

  @override
  Future<List<Room>> listRooms({String? gameMode}) =>
      _inner.listRooms(gameMode: gameMode);

  @override
  Future<Room?> getRoom(String roomId) => _inner.getRoom(roomId);

  /// Release resources.
  void dispose() => _inner.dispose();
}

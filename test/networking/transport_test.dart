import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

import 'dart:async';

class DummyTransport implements NetworkTransport {
  final _connection = NetworkConnection(host: 'dummy', port: 1234);
  final _packetController = StreamController<NetworkPacket>.broadcast();
  int disconnectCount = 0;
  List<NetworkPacket> sentPackets = [];

  @override
  NetworkConnection get connection => _connection;

  @override
  Stream<NetworkPacket> get onPacketReceived => _packetController.stream;

  @override
  Future<void> connect(String host, int port) async {
    _connection.setState(ConnectionState.connected);
  }

  @override
  Future<void> disconnect() async {
    disconnectCount++;
    _connection.setState(ConnectionState.disconnected);
  }

  @override
  void send(NetworkPacket packet) {
    sentPackets.add(packet);
  }

  @override
  void dispose() {
    _packetController.close();
  }

  void receive(NetworkPacket packet) {
    _packetController.add(packet);
  }
}

void main() {
  group('Transport Layer', () {
    test('NetworkPacket serializes and deserializes', () {
      final now = DateTime.now().toUtc();
      final packet = NetworkPacket(
        sequenceNumber: 1,
        type: PacketType.reliable,
        payload: {'hello': 'world'},
        priority: PacketPriority.high,
        channelId: 'chat',
        senderId: 'player1',
        timestamp: now,
      );

      final json = packet.toJson();
      final decoded = NetworkPacket.fromJson(json);

      expect(decoded.sequenceNumber, 1);
      expect(decoded.type, PacketType.reliable);
      expect(decoded.payload, {'hello': 'world'});
      expect(decoded.priority, PacketPriority.high);
      expect(decoded.channelId, 'chat');
      expect(decoded.senderId, 'player1');
      expect(
        decoded.timestamp.millisecondsSinceEpoch,
        now.millisecondsSinceEpoch,
      );
    });

    test('NetworkConnection tracks state changes', () {
      final conn = NetworkConnection(host: 'local', port: 8080);
      expect(conn.state, ConnectionState.disconnected);
      expect(conn.isConnected, false);

      final states = <ConnectionState>[];
      conn.onStateChanged((prev, next) {
        states.add(next);
      });

      conn.setState(ConnectionState.connecting);
      expect(conn.isBusy, true);

      conn.setState(ConnectionState.connected);
      expect(conn.isConnected, true);

      expect(states, [ConnectionState.connecting, ConnectionState.connected]);
    });

    test('NetworkManager handles generic transport and handlers', () async {
      final transport = DummyTransport();
      final manager = NetworkManager();

      manager.initialize(transport);
      expect(manager.connectionState, ConnectionState.disconnected);

      await manager.connect('test', 1234);
      expect(manager.isConnected, true);

      int reliableCount = 0;
      manager.on(PacketType.reliable, (packet) {
        reliableCount++;
      });

      transport.receive(
        NetworkPacket(
          sequenceNumber: 0,
          type: PacketType.reliable,
          payload: {},
        ),
      );

      // Wait a microtask loop for stream
      await Future.delayed(Duration.zero);
      expect(reliableCount, 1);

      manager.sendData(
        {'foo': 'bar'},
        type: PacketType.unreliable,
        channelId: 'test_chan',
      );
      expect(transport.sentPackets.length, 1);
      expect(transport.sentPackets[0].type, PacketType.unreliable);
      expect(transport.sentPackets[0].payload['foo'], 'bar');

      await manager.disconnect();
      expect(transport.disconnectCount, 1);

      manager.dispose();
    });
  });
}

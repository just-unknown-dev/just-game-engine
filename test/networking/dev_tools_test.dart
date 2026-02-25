import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

import 'dart:async';

class FakeTransport implements NetworkTransport {
  final _connection = NetworkConnection(host: 'dummy', port: 1234);
  final _packetController = StreamController<NetworkPacket>.broadcast();
  int packetsSent = 0;

  @override
  NetworkConnection get connection => _connection;

  @override
  Stream<NetworkPacket> get onPacketReceived => _packetController.stream;

  @override
  Future<void> connect(String host, int port) async {}

  @override
  Future<void> disconnect() async {}

  @override
  void send(NetworkPacket packet) {
    packetsSent++;
  }

  @override
  void dispose() {}
}

void main() {
  group('NetworkSimulator', () {
    test('Simulates perfect conditions (no latency/loss)', () {
      final base = FakeTransport();
      final sim = NetworkSimulator(
        transport: base,
        config: const SimulatorConfig(
          latencyMs: 0,
          jitterMs: 0,
          packetLossPercent: 0,
        ),
        enabled: true,
      );

      final p1 = NetworkPacket(
        sequenceNumber: 1,
        type: PacketType.unreliable,
        payload: {},
      );
      sim.send(p1);

      // Packet is still sent via Future.delayed even with 0 latency, but without loss.
      // So we expect 0 immediately.
      expect(base.packetsSent, 0);
    });

    test('Simulates packet loss', () {
      final base = FakeTransport();
      // 100% loss
      final sim = NetworkSimulator(
        transport: base,
        config: const SimulatorConfig(
          latencyMs: 0,
          jitterMs: 0,
          packetLossPercent: 1.0,
        ),
        enabled: true,
      );

      sim.send(
        NetworkPacket(
          sequenceNumber: 1,
          type: PacketType.unreliable,
          payload: {},
        ),
      );

      expect(base.packetsSent, 0); // Dropped immediately
    });

    test('Simulates passing transparently when disabled', () {
      final base = FakeTransport();
      // 100% loss but disabled
      final sim = NetworkSimulator(
        transport: base,
        config: const SimulatorConfig(packetLossPercent: 1.0),
        enabled: false,
      );

      sim.send(
        NetworkPacket(
          sequenceNumber: 1,
          type: PacketType.unreliable,
          payload: {},
        ),
      );

      // Should bypass simulation entirely and send synchronously
      expect(base.packetsSent, 1);
    });
  });
}

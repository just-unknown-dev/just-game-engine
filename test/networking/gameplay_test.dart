import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:flutter/foundation.dart';
import 'dart:ui';
import 'dart:async';

class MockNetworkTransport implements NetworkTransport {
  final _connection = NetworkConnection(host: 'local', port: 1234);
  final _packetController = StreamController<NetworkPacket>.broadcast();
  final List<NetworkPacket> sentPackets = [];

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

  void simulateReceive(NetworkPacket packet) {
    _packetController.add(packet);
  }
}

void main() {
  group('Multiplayer Prediction', () {
    test('InputSnapshot stores input data', () {
      final now = DateTime.now();
      final snapshot = InputSnapshot(
        sequenceNumber: 1,
        timestamp: now,
        inputVector: Offset(1, 0),
        deltaTime: 0.016,
        extras: {'jump': true},
      );
      expect(snapshot.sequenceNumber, 1);
      expect(snapshot.timestamp, now);
      expect(snapshot.inputVector, Offset(1, 0));
      expect(snapshot.deltaTime, 0.016);
      expect(snapshot.extras['jump'], true);
    });

    test('PredictionState applies and resets', () {
      final state = PredictionState(
        position: Offset.zero,
        velocity: Offset.zero,
      );
      state.position = Offset(10, 5);
      state.velocity = Offset(1, 1);
      state.lastAppliedSeq = 42;
      expect(state.position, Offset(10, 5));
      expect(state.velocity, Offset(1, 1));
      expect(state.lastAppliedSeq, 42);
    });

    test('ClientPrediction buffering and reconciliation', () {
      final prediction = ClientPrediction(
        initialPosition: Offset.zero,
        movementFunction: (pos, vel, input, dt) => (pos + input * 10 * dt, vel),
        maxPendingInputs: 3,
      );

      // Frame 1
      prediction.applyInput(Offset(1, 0), 1.0);
      expect(prediction.position, Offset(10, 0));
      expect(prediction.pendingCount, 1);

      // Frame 2
      prediction.applyInput(Offset(1, 0), 1.0);
      expect(prediction.position, Offset(20, 0));
      expect(prediction.pendingCount, 2);

      // Reconcile frame 1 (server acked seq=0 with position(9,0))
      // It should drop seq=0, keep seq=1, and re-apply seq=1 on top of (9,0)
      prediction.reconcile(0, Offset(9, 0));
      expect(prediction.pendingCount, 1);
      expect(prediction.position, Offset(19, 0)); // 9 + 10*1.0

      prediction.reset(Offset.zero);
      expect(prediction.position, Offset.zero);
      expect(prediction.pendingCount, 0);
    });
  });

  group('Network Sync', () {
    late NetworkManager manager;
    late MockNetworkTransport transport;
    late LagCompensator lagCompensator;
    late NetworkSyncManager syncManager;

    setUp(() {
      transport = MockNetworkTransport();
      manager = NetworkManager();
      manager.initialize(transport);
      lagCompensator = LagCompensator(
        interpolationDelayMs: 0,
      ); // No delay for easier testing
      syncManager = NetworkSyncManager(
        networkManager: manager,
        lagCompensator: lagCompensator,
      );
      syncManager.initialize();
    });

    tearDown(() {
      syncManager.dispose();
      manager.dispose();
    });

    test('SyncedTransform serializes and deserializes', () {
      final now = DateTime.now().toUtc();
      final transform = SyncedTransform(
        objectId: 'obj1',
        position: Offset(1, 2),
        rotation: 0.5,
        scale: Offset(2, 2),
        velocity: Offset(0.1, 0.2),
        sequenceNumber: 7,
        timestamp: now,
      );
      final json = transform.toJson();
      final fromJson = SyncedTransform.fromJson(json);
      expect(fromJson.objectId, 'obj1');
      expect(fromJson.position, Offset(1, 2));
      expect(fromJson.rotation, 0.5);
      expect(fromJson.scale, Offset(2, 2));
      expect(fromJson.velocity, Offset(0.1, 0.2));
      expect(fromJson.sequenceNumber, 7);
      expect(
        fromJson.timestamp.millisecondsSinceEpoch,
        now.millisecondsSinceEpoch,
      );
    });

    test('NetworkSyncManager tracks and sends local objects', () {
      var currentPos = Offset(5, 5);
      syncManager.registerLocalObject(
        'player',
        () => SyncedTransform(
          objectId: 'player',
          position: currentPos,
          sequenceNumber: 0,
        ),
      );

      syncManager.forceSend(
        SyncedTransform(
          objectId: 'player',
          position: currentPos,
          sequenceNumber: 0,
        ),
      );
      expect(transport.sentPackets, isNotEmpty);
      final sent = transport.sentPackets.last;
      expect(sent.type, PacketType.unreliable);
      expect(sent.channelId, 'transforms');
      expect(sent.payload['transform']['id'], 'player');
      expect(sent.payload['transform']['px'], 5.0);

      syncManager.unregisterLocalObject('player');
    });

    test(
      'NetworkSyncManager receives and interpolates remote objects',
      () async {
        final remoteTransform = SyncedTransform(
          objectId: 'enemy',
          position: Offset(100, 100),
          sequenceNumber: 1,
        );

        var callbackFired = false;
        syncManager.onRemoteUpdate((transform) {
          expect(transform.objectId, 'enemy');
          expect(transform.position, Offset(100, 100));
          callbackFired = true;
        });

        transport.simulateReceive(
          NetworkPacket(
            sequenceNumber: 0,
            type: PacketType.unreliable,
            channelId: 'transforms',
            payload: {'transform': remoteTransform.toJson()},
          ),
        );

        await Future.delayed(Duration.zero);

        expect(callbackFired, isTrue);

        final remote = syncManager.getRemoteTransform('enemy');
        expect(remote, isNotNull);
        expect(remote!.position, Offset(100, 100));

        final interpolated = syncManager.getInterpolatedRemoteStates();
        expect(interpolated.containsKey('enemy'), isTrue);
        expect(interpolated['enemy']!.position, Offset(100, 100));
      },
    );
  });

  group('Lag Compensation', () {
    test('ObjectState lerp interpolates values', () {
      final a = ObjectState(
        objectId: 'o',
        position: Offset(0, 0),
        rotation: 0,
        scale: Offset(1, 1),
        velocity: Offset.zero,
      );
      final b = ObjectState(
        objectId: 'o',
        position: Offset(10, 10),
        rotation: 1,
        scale: Offset(2, 2),
        velocity: Offset(1, 1),
      );
      final mid = a.lerp(b, 0.5);
      expect(mid.position, Offset(5, 5));
      expect(mid.rotation, closeTo(0.5, 1e-6));
      expect(mid.scale, Offset(1.5, 1.5));
      expect(mid.velocity, Offset(0.5, 0.5));
    });

    test('SnapshotBuffer manages capacity and ordering', () {
      final buffer = SnapshotBuffer(capacity: 2);
      final now = DateTime.now();

      final s1 = StateSnapshot(
        sequenceNumber: 1,
        timestamp: now,
        objectStates: {},
      );
      final s2 = StateSnapshot(
        sequenceNumber: 2,
        timestamp: now.add(Duration(seconds: 1)),
        objectStates: {},
      );
      final s3 = StateSnapshot(
        sequenceNumber: 3,
        timestamp: now.add(Duration(seconds: 2)),
        objectStates: {},
      );

      buffer.record(s1);
      buffer.record(s2);
      expect(buffer.length, 2);

      buffer.record(s3);
      expect(buffer.length, 2);
      expect(buffer.snapshots.first.sequenceNumber, 2); // s1 was evicted

      // Check bracketing
      final bracket = buffer.bracketing(now.add(Duration(milliseconds: 1500)));
      expect(bracket, isNotNull);
      expect(bracket!.$1.sequenceNumber, 2);
      expect(bracket.$2.sequenceNumber, 3);

      // Check closest
      final close = buffer.closest(now.add(Duration(milliseconds: 1000)));
      expect(close?.sequenceNumber, 2);

      buffer.clear();
      expect(buffer.isEmpty, isTrue);
    });

    test('LagCompensator interpolates between snapshots', () {
      final compensator = LagCompensator(interpolationDelayMs: 100);
      final now = DateTime.now().toUtc();

      compensator.recordSnapshot(
        StateSnapshot(
          sequenceNumber: 1,
          timestamp: now.subtract(Duration(milliseconds: 200)),
          objectStates: {
            'obj': ObjectState(objectId: 'obj', position: Offset(0, 0)),
          },
        ),
      );

      compensator.recordSnapshot(
        StateSnapshot(
          sequenceNumber: 2,
          timestamp: now,
          objectStates: {
            'obj': ObjectState(objectId: 'obj', position: Offset(100, 0)),
          },
        ),
      );

      // Target time is now - 100ms, exactly halfway between the two snapshots
      final states = compensator.interpolate(
        now.subtract(Duration(milliseconds: 100)),
      );
      expect(states.length, 1);
      expect(states['obj'], isNotNull);
      expect(states['obj']!.position.dx, closeTo(50, 0.1));

      // Rewind to past point
      final rewind = compensator.rewindToTime(
        now.subtract(Duration(milliseconds: 200)),
      );
      expect(rewind?.sequenceNumber, 1);
    });
  });
}

/// Network Sync Manager
///
/// Synchronises object transforms (position, rotation, scale, velocity)
/// between peers via the [NetworkManager]. Supports configurable sync rate,
/// dirty-checking, and smooth interpolation for received remote transforms.
library;

import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../transport/packet.dart';
import '../transport/transport_layer.dart';
import 'lag_compensation.dart';

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

/// The full transform of a synced game object, transmitted as a packet payload.
class SyncedTransform {
  /// Unique identifier of the game object this transform belongs to.
  final String objectId;

  /// World-space position.
  final Offset position;

  /// Rotation in radians.
  final double rotation;

  /// Scale factor (x, y).
  final Offset scale;

  /// Current velocity (used for dead-reckoning on the receiver side).
  final Offset velocity;

  /// The sequence number of the packet carrying this transform.
  final int sequenceNumber;

  /// UTC timestamp when this transform was sampled.
  final DateTime timestamp;

  SyncedTransform({
    required this.objectId,
    required this.position,
    this.rotation = 0,
    this.scale = const Offset(1, 1),
    this.velocity = Offset.zero,
    required this.sequenceNumber,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now().toUtc();

  /// Serialise to JSON for packet payload.
  Map<String, dynamic> toJson() => {
    'id': objectId,
    'px': position.dx,
    'py': position.dy,
    'r': rotation,
    'sx': scale.dx,
    'sy': scale.dy,
    'vx': velocity.dx,
    'vy': velocity.dy,
    'seq': sequenceNumber,
    'ts': timestamp.millisecondsSinceEpoch,
  };

  /// Deserialise from a packet payload entry.
  factory SyncedTransform.fromJson(Map<String, dynamic> json) {
    return SyncedTransform(
      objectId: json['id'] as String,
      position: Offset(
        (json['px'] as num).toDouble(),
        (json['py'] as num).toDouble(),
      ),
      rotation: (json['r'] as num).toDouble(),
      scale: Offset(
        (json['sx'] as num).toDouble(),
        (json['sy'] as num).toDouble(),
      ),
      velocity: Offset(
        (json['vx'] as num).toDouble(),
        (json['vy'] as num).toDouble(),
      ),
      sequenceNumber: (json['seq'] as num).toInt(),
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (json['ts'] as num).toInt(),
        isUtc: true,
      ),
    );
  }

  // Convert to an [ObjectState] for use with [LagCompensator].
  ObjectState toObjectState() => ObjectState(
    objectId: objectId,
    position: position,
    rotation: rotation,
    scale: scale,
    velocity: velocity,
  );

  @override
  String toString() =>
      'SyncedTransform(id=$objectId, pos=$position, seq=$sequenceNumber)';
}

// ---------------------------------------------------------------------------
// Sync manager
// ---------------------------------------------------------------------------

/// Manages transform synchronisation for all registered game objects.
///
/// **Local objects** (owned by this client) are tracked for dirty-checking
/// and their transforms are broadcast when they change.
///
/// **Remote objects** (owned by other clients) have their incoming transforms
/// stored and can be retrieved for rendering via [getRemoteTransform] or
/// via the [LagCompensator] for smooth interpolation.
class NetworkSyncManager {
  final NetworkManager _networkManager;
  final LagCompensator _lagCompensator;

  /// How many times per second transforms are sent to the server.
  final double syncRate;

  bool _initialized = false;
  Timer? _syncTimer;
  int _seq = 0;

  // objectId -> last sent transform
  final Map<String, SyncedTransform> _localTransforms = {};
  // objectId -> last received remote transform
  final Map<String, SyncedTransform> _remoteTransforms = {};
  // objectId -> getter callback (supplied by the game)
  final Map<String, SyncedTransform Function()> _localGetters = {};

  /// Callbacks fired when a remote transform update arrives.
  final List<void Function(SyncedTransform transform)> _onRemoteUpdate = [];

  NetworkSyncManager({
    required NetworkManager networkManager,
    LagCompensator? lagCompensator,
    this.syncRate = 20,
  }) : _networkManager = networkManager,
       _lagCompensator = lagCompensator ?? LagCompensator();

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Start the sync manager. Registers a packet handler and starts the timer.
  void initialize() {
    if (_initialized) return;
    _initialized = true;

    // Listen for transform packets from remote peers.
    _networkManager.on(PacketType.unreliable, _handleTransformPacket);
    _networkManager.on(PacketType.reliable, _handleTransformPacket);

    // Start the outbound sync timer.
    final intervalMs = (1000 / syncRate).round();
    _syncTimer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      _sendDirtyTransforms();
    });

    debugPrint(
      'NetworkSyncManager: initialized at ${syncRate.toStringAsFixed(1)} Hz',
    );
  }

  // ---------------------------------------------------------------------------
  // Object registration
  // ---------------------------------------------------------------------------

  /// Register a local object for syncing. [getter] is called each sync-tick
  /// to sample the current transform. If the transform changed since the last
  /// send it is broadcast.
  void registerLocalObject(String objectId, SyncedTransform Function() getter) {
    _localGetters[objectId] = getter;
    debugPrint('NetworkSyncManager: registered local object "$objectId"');
  }

  /// Unregister a local object; it will no longer be broadcast.
  void unregisterLocalObject(String objectId) {
    _localGetters.remove(objectId);
    _localTransforms.remove(objectId);
    debugPrint('NetworkSyncManager: unregistered local object "$objectId"');
  }

  // ---------------------------------------------------------------------------
  // Remote transform access
  // ---------------------------------------------------------------------------

  /// Return the latest received transform for a remote [objectId], or `null`.
  SyncedTransform? getRemoteTransform(String objectId) =>
      _remoteTransforms[objectId];

  /// Return interpolated states for all known remote objects (uses the
  /// internal [LagCompensator]).
  Map<String, ObjectState> getInterpolatedRemoteStates() =>
      _lagCompensator.interpolate();

  // ---------------------------------------------------------------------------
  // Manual send
  // ---------------------------------------------------------------------------

  /// Immediately broadcast [transform] regardless of dirty-checking.
  void forceSend(SyncedTransform transform) {
    _sendTransform(transform, PacketType.unreliable);
  }

  // ---------------------------------------------------------------------------
  // Callbacks
  // ---------------------------------------------------------------------------

  /// Register a callback fired whenever a remote transform packet arrives.
  void onRemoteUpdate(void Function(SyncedTransform transform) callback) {
    _onRemoteUpdate.add(callback);
  }

  // ---------------------------------------------------------------------------
  // Cleanup
  // ---------------------------------------------------------------------------

  /// Stop syncing and release resources.
  void dispose() {
    _syncTimer?.cancel();
    _syncTimer = null;
    _networkManager.off(PacketType.unreliable, _handleTransformPacket);
    _networkManager.off(PacketType.reliable, _handleTransformPacket);
    _localGetters.clear();
    _localTransforms.clear();
    _remoteTransforms.clear();
    _onRemoteUpdate.clear();
    _lagCompensator.dispose();
    _initialized = false;
    debugPrint('NetworkSyncManager: disposed');
  }

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  void _sendDirtyTransforms() {
    for (final entry in _localGetters.entries) {
      final objectId = entry.key;
      final current = entry.value();
      final last = _localTransforms[objectId];

      // Dirty check: only send if position or rotation changed.
      if (last != null &&
          last.position == current.position &&
          last.rotation == current.rotation) {
        continue;
      }

      final t = SyncedTransform(
        objectId: objectId,
        position: current.position,
        rotation: current.rotation,
        scale: current.scale,
        velocity: current.velocity,
        sequenceNumber: _seq++,
      );

      _localTransforms[objectId] = t;
      _sendTransform(t, PacketType.unreliable);
    }
  }

  void _sendTransform(SyncedTransform transform, PacketType type) {
    _networkManager.sendData(
      {'transform': transform.toJson()},
      type: type,
      channelId: 'transforms',
    );
  }

  void _handleTransformPacket(NetworkPacket packet) {
    if (packet.channelId != 'transforms') return;
    final raw = packet.payload['transform'];
    if (raw is! Map<String, dynamic>) return;

    try {
      final transform = SyncedTransform.fromJson(raw);

      // Ignore packets for our own local objects.
      if (_localGetters.containsKey(transform.objectId)) return;

      _remoteTransforms[transform.objectId] = transform;

      // Feed into lag compensator for smooth interpolation.
      _lagCompensator.recordSnapshot(
        StateSnapshot(
          sequenceNumber: transform.sequenceNumber,
          timestamp: transform.timestamp,
          objectStates: {transform.objectId: transform.toObjectState()},
        ),
      );

      for (final cb in List.of(_onRemoteUpdate)) {
        cb(transform);
      }
    } catch (e) {
      debugPrint('NetworkSyncManager: failed to parse transform — $e');
    }
  }
}

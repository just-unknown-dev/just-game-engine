/// Network Debugger
///
/// Collects and exposes real-time network statistics. Listens to
/// [NetworkManager] events and emits periodic [NetworkStats] snapshots.
/// Intended for use in debug / development overlays.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../transport/packet.dart';
import '../transport/transport_layer.dart';

// ---------------------------------------------------------------------------
// Stats snapshot
// ---------------------------------------------------------------------------

/// A point-in-time snapshot of network performance metrics.
class NetworkStats {
  /// Average round-trip latency in milliseconds.
  final int pingMs;

  /// Total packets sent since the last [reset].
  final int packetsSent;

  /// Total packets received since the last [reset].
  final int packetsReceived;

  /// Packets dropped (simulated or detected via sequence gaps).
  final int packetsDropped;

  /// Total bytes received since last [reset].
  final int bytesReceived;

  /// Total bytes sent since last [reset].
  final int bytesSent;

  /// Total number of reconnect events since last [reset].
  final int reconnects;

  /// UTC time this snapshot was captured.
  final DateTime capturedAt;

  /// Estimated packet loss ratio ∈ [0.0, 1.0].
  double get packetLossRatio {
    final total = packetsSent + packetsDropped;
    return total > 0 ? packetsDropped / total : 0.0;
  }

  const NetworkStats({
    this.pingMs = 0,
    this.packetsSent = 0,
    this.packetsReceived = 0,
    this.packetsDropped = 0,
    this.bytesReceived = 0,
    this.bytesSent = 0,
    this.reconnects = 0,
    required this.capturedAt,
  });

  /// Format a human-readable report string.
  String formatReport() {
    return 'NetworkStats @ ${capturedAt.toIso8601String()}\n'
        '  ping:      ${pingMs}ms\n'
        '  sent:      $packetsSent packets / ${_formatBytes(bytesSent)}\n'
        '  received:  $packetsReceived packets / ${_formatBytes(bytesReceived)}\n'
        '  dropped:   $packetsDropped (${(packetLossRatio * 100).toStringAsFixed(1)}%)\n'
        '  reconnects: $reconnects';
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)}MB';
  }

  @override
  String toString() => formatReport();
}

// ---------------------------------------------------------------------------
// Debugger
// ---------------------------------------------------------------------------

/// Monitors a [NetworkManager] and accumulates [NetworkStats] in real time.
///
/// Emits a new [NetworkStats] snapshot on [statsStream] every
/// [emitIntervalMs] milliseconds.
///
/// **Debug / profile only.** Automatically disables itself in release builds.
class NetworkDebugger {
  final NetworkManager _networkManager;

  /// How often (ms) to emit a stats snapshot on [statsStream].
  final int emitIntervalMs;

  bool _initialized = false;
  Timer? _emitTimer;
  final _statsController = StreamController<NetworkStats>.broadcast();

  // Accumulators (reset on [reset]).
  int _packetsSent = 0;
  int _packetsReceived = 0;
  int _packetsDropped = 0;
  int _bytesReceived = 0;
  int _bytesSent = 0;
  int _reconnects = 0;
  int _lastSeqReceived = -1;

  NetworkDebugger({
    required NetworkManager networkManager,
    this.emitIntervalMs = 1000,
  }) : _networkManager = networkManager;

  /// Stream of periodic [NetworkStats] snapshots. Only emits in debug/profile.
  Stream<NetworkStats> get statsStream => _statsController.stream;

  /// Most recent stats values (convenience for polling instead of streaming).
  NetworkStats get currentStats => _buildSnapshot();

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Start listening and emitting stats.
  void initialize() {
    if (_initialized) return;
    if (kReleaseMode) {
      debugPrint('NetworkDebugger: disabled in release mode');
      return;
    }
    _initialized = true;

    // Track inbound packets.
    for (final type in PacketType.values) {
      _networkManager.on(type, _onPacketReceived);
    }

    _emitTimer = Timer.periodic(
      Duration(milliseconds: emitIntervalMs),
      (_) => _emit(),
    );

    debugPrint('NetworkDebugger: initialized (emit every ${emitIntervalMs}ms)');
  }

  /// Reset all accumulators.
  void reset() {
    _packetsSent = 0;
    _packetsReceived = 0;
    _packetsDropped = 0;
    _bytesReceived = 0;
    _bytesSent = 0;
    _reconnects = 0;
    _lastSeqReceived = -1;
    debugPrint('NetworkDebugger: stats reset');
  }

  // ---------------------------------------------------------------------------
  // Manual recording (call from NetworkManager wrappers if needed)
  // ---------------------------------------------------------------------------

  /// Record that a packet was sent with [payloadSizeBytes].
  void recordSent(int payloadSizeBytes) {
    if (kReleaseMode) return;
    _packetsSent++;
    _bytesSent += payloadSizeBytes;
  }

  /// Record a reconnect event.
  void recordReconnect() {
    if (kReleaseMode) return;
    _reconnects++;
  }

  // ---------------------------------------------------------------------------
  // Cleanup
  // ---------------------------------------------------------------------------

  /// Stop emitting and release resources.
  void dispose() {
    _emitTimer?.cancel();
    _emitTimer = null;
    _statsController.close();
    _initialized = false;
    debugPrint('NetworkDebugger: disposed');
  }

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  void _onPacketReceived(NetworkPacket packet) {
    _packetsReceived++;

    // Estimate payload size from JSON encoding.
    try {
      final est = packet.toJson().toString().length;
      _bytesReceived += est;
    } catch (_) {}

    // Detect gaps in sequence numbers as a proxy for packet loss.
    if (_lastSeqReceived >= 0 && packet.sequenceNumber > _lastSeqReceived + 1) {
      _packetsDropped += packet.sequenceNumber - _lastSeqReceived - 1;
    }
    if (packet.sequenceNumber > _lastSeqReceived) {
      _lastSeqReceived = packet.sequenceNumber;
    }
  }

  void _emit() {
    if (!_statsController.hasListener) return;
    _statsController.add(_buildSnapshot());
  }

  NetworkStats _buildSnapshot() => NetworkStats(
    pingMs: _networkManager.latencyMs,
    packetsSent: _packetsSent,
    packetsReceived: _packetsReceived,
    packetsDropped: _packetsDropped,
    bytesReceived: _bytesReceived,
    bytesSent: _bytesSent,
    reconnects: _reconnects,
    capturedAt: DateTime.now().toUtc(),
  );
}

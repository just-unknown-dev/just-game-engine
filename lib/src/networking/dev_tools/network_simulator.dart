/// Network Simulator
///
/// A [NetworkTransport] decorator that injects artificial latency, jitter,
/// and packet loss for local network condition testing.
/// Only active in debug/profile builds; in release mode it passes through
/// transparently.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../transport/packet.dart';
import '../transport/connection.dart';
import '../transport/transport_layer.dart';

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

/// Network-simulation parameters.
class SimulatorConfig {
  /// Base one-way artificial latency in milliseconds.
  final int latencyMs;

  /// Maximum additional random jitter in milliseconds (0 = no jitter).
  final int jitterMs;

  /// Probability ∈ [0.0, 1.0] that any outbound packet is silently dropped.
  final double packetLossPercent;

  /// If > 0, the simulated outbound bandwidth cap in bytes per second.
  /// Excess packets are queued until bandwidth is available.
  final int bandwidthLimitBytesPerSecond;

  const SimulatorConfig({
    this.latencyMs = 50,
    this.jitterMs = 10,
    this.packetLossPercent = 0.02,
    this.bandwidthLimitBytesPerSecond = 0,
  });

  /// A config that simulates excellent conditions (fast fibre).
  static const excellent = SimulatorConfig(
    latencyMs: 10,
    jitterMs: 2,
    packetLossPercent: 0.001,
  );

  /// A config that simulates a typical mobile connection.
  static const mobile = SimulatorConfig(
    latencyMs: 80,
    jitterMs: 30,
    packetLossPercent: 0.03,
  );

  /// A config that simulates a congested/poor connection.
  static const poor = SimulatorConfig(
    latencyMs: 300,
    jitterMs: 120,
    packetLossPercent: 0.15,
  );

  @override
  String toString() =>
      'SimulatorConfig(latency=${latencyMs}ms, jitter=${jitterMs}ms, '
      'loss=${(packetLossPercent * 100).toStringAsFixed(1)}%)';
}

// ---------------------------------------------------------------------------
// Simulator
// ---------------------------------------------------------------------------

/// Wraps any [NetworkTransport] and intercepts [send] calls, applying
/// artificial network conditions defined by [config].
///
/// **Debug/profile only.** In release builds [enabled] is forced to `false`
/// and all packets pass through immediately with no overhead.
class NetworkSimulator implements NetworkTransport {
  final NetworkTransport _inner;
  SimulatorConfig config;

  bool _enabled;
  final _random = math.Random();

  NetworkSimulator({
    required NetworkTransport transport,
    SimulatorConfig? config,
    bool enabled = true,
  }) : _inner = transport,
       config = config ?? const SimulatorConfig(),
       // Force disabled in release mode.
       _enabled = kReleaseMode ? false : enabled;

  /// Whether the simulator is currently applying artificial conditions.
  bool get enabled => _enabled;

  /// Enable or disable simulation at runtime.
  /// Has no effect in release builds.
  set enabled(bool value) {
    if (kReleaseMode) return;
    _enabled = value;
    debugPrint('NetworkSimulator: ${value ? "enabled" : "disabled"} — $config');
  }

  // ---------------------------------------------------------------------------
  // NetworkTransport delegation
  // ---------------------------------------------------------------------------

  @override
  NetworkConnection get connection => _inner.connection;

  @override
  Stream<NetworkPacket> get onPacketReceived => _inner.onPacketReceived;

  @override
  Future<void> connect(String host, int port) => _inner.connect(host, port);

  @override
  Future<void> disconnect() => _inner.disconnect();

  @override
  void send(NetworkPacket packet) {
    if (!_enabled) {
      _inner.send(packet);
      return;
    }

    // Packet loss.
    if (_random.nextDouble() < config.packetLossPercent) {
      debugPrint(
        'NetworkSimulator: dropped packet seq=${packet.sequenceNumber}',
      );
      return;
    }

    // Artificial latency + jitter.
    final delay = config.latencyMs + (_random.nextInt(config.jitterMs + 1));

    Future.delayed(Duration(milliseconds: delay), () {
      _inner.send(packet);
    });
  }

  @override
  void dispose() {
    _inner.dispose();
    debugPrint('NetworkSimulator: disposed');
  }
}

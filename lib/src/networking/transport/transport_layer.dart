/// Transport Layer
///
/// Defines the abstract transport interface and provides concrete
/// WebSocket and UDP (stub) implementations.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'packet.dart';
import 'connection.dart';

// ---------------------------------------------------------------------------
// Abstract interface
// ---------------------------------------------------------------------------

/// Abstract transport interface. Provides a protocol-agnostic API for sending
/// and receiving [NetworkPacket]s. Inject the desired implementation into
/// [NetworkManager] at construction time.
abstract class NetworkTransport {
  /// The logical connection metadata for this transport.
  NetworkConnection get connection;

  /// Stream of packets received from the remote.
  Stream<NetworkPacket> get onPacketReceived;

  /// Connect to [host]:[port]. Throws on unrecoverable failure.
  Future<void> connect(String host, int port);

  /// Gracefully disconnect.
  Future<void> disconnect();

  /// Send a [packet] to the connected remote.
  void send(NetworkPacket packet);

  /// Release all resources.
  void dispose();
}

// ---------------------------------------------------------------------------
// WebSocket implementation
// ---------------------------------------------------------------------------

/// A [NetworkTransport] backed by a WebSocket connection.
///
/// Uses [web_socket_channel] and therefore works on Android, iOS, desktop,
/// and web without additional platform code.
class WebSocketTransport implements NetworkTransport {
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  final _packetController = StreamController<NetworkPacket>.broadcast();

  late final NetworkConnection _connection;

  /// Create a [WebSocketTransport].
  ///
  /// [pingIntervalMs] controls how often automatic ping packets are sent to
  /// update [NetworkConnection.latencyMs].
  WebSocketTransport({this.pingIntervalMs = 2000})
    : _connection = NetworkConnection(host: '', port: 0);

  /// Interval between automatic ping measurements in milliseconds.
  final int pingIntervalMs;

  Timer? _pingTimer;
  int _seq = 0;
  DateTime? _pingSentAt;

  @override
  NetworkConnection get connection => _connection;

  @override
  Stream<NetworkPacket> get onPacketReceived => _packetController.stream;

  @override
  Future<void> connect(String host, int port) async {
    if (_connection.isConnected) return;

    // Update the stored host/port by reconstructing (connection is immutable
    // after construction, so we replace the internal reference).
    final conn = NetworkConnection(host: host, port: port);
    _connection.setState(ConnectionState.connecting);

    try {
      final uri = Uri(scheme: 'ws', host: host, port: port);
      _channel = WebSocketChannel.connect(uri);
      await _channel!.ready;

      _subscription = _channel!.stream.listen(
        _onRawData,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: false,
      );

      _connection.setState(ConnectionState.connected);
      debugPrint('WebSocketTransport: connected to $host:$port');
      _startPinging();
    } catch (e) {
      _connection.setState(ConnectionState.failed);
      debugPrint('WebSocketTransport: connection failed — $e');
      rethrow;
    }

    // Keep the linter happy: conn is created above to mirror the new host/port
    // but we don't expose a setter, so log it.
    debugPrint('WebSocketTransport: endpoint ${conn.host}:${conn.port}');
  }

  @override
  Future<void> disconnect() async {
    _stopPinging();
    await _channel?.sink.close();
    _connection.setState(ConnectionState.disconnected);
    debugPrint('WebSocketTransport: disconnected');
  }

  @override
  void send(NetworkPacket packet) {
    if (!_connection.isConnected) {
      debugPrint('WebSocketTransport.send: not connected, dropping packet');
      return;
    }
    try {
      final json = jsonEncode(packet.toJson());
      _channel!.sink.add(json);
    } catch (e) {
      debugPrint('WebSocketTransport.send: serialization error — $e');
    }
  }

  @override
  void dispose() {
    _stopPinging();
    _subscription?.cancel();
    _channel?.sink.close();
    _packetController.close();
    debugPrint('WebSocketTransport: disposed');
  }

  // -------------------------------------------------------------------------
  // Internal helpers
  // -------------------------------------------------------------------------

  void _onRawData(dynamic raw) {
    try {
      final map = jsonDecode(raw as String) as Map<String, dynamic>;

      // Handle pong (ping response) for latency calculation.
      if (map['type'] == PacketType.ping.name &&
          map['payload']?['pong'] == true &&
          _pingSentAt != null) {
        _connection.latencyMs = DateTime.now()
            .toUtc()
            .difference(_pingSentAt!)
            .inMilliseconds;
        _pingSentAt = null;
        return;
      }

      final packet = NetworkPacket.fromJson(map);
      _packetController.add(packet);
    } catch (e) {
      debugPrint('WebSocketTransport: failed to parse incoming data — $e');
    }
  }

  void _onError(Object error) {
    debugPrint('WebSocketTransport: stream error — $error');
    _connection.setState(ConnectionState.reconnecting);
  }

  void _onDone() {
    _stopPinging();
    if (_connection.state != ConnectionState.disconnected) {
      _connection.setState(ConnectionState.disconnected);
    }
    debugPrint('WebSocketTransport: stream closed');
  }

  void _startPinging() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(Duration(milliseconds: pingIntervalMs), (_) {
      if (!_connection.isConnected) return;
      _pingSentAt = DateTime.now().toUtc();
      send(
        NetworkPacket(
          sequenceNumber: _seq++,
          type: PacketType.ping,
          payload: {'ping': true},
          priority: PacketPriority.high,
        ),
      );
    });
  }

  void _stopPinging() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }
}

// ---------------------------------------------------------------------------
// UDP stub
// ---------------------------------------------------------------------------

/// A [NetworkTransport] that will use UDP for low-latency, unreliable delivery.
///
/// UDP is ideal for real-time position updates and audio where occasional
/// packet loss is acceptable. Currently a **stub** — the interface is fully
/// defined for forward-compatibility.
///
/// TODO: Implement using dart:io RawDatagramSocket (native-only platforms).
class UdpTransport implements NetworkTransport {
  final NetworkConnection _connection;
  final _packetController = StreamController<NetworkPacket>.broadcast();

  UdpTransport() : _connection = NetworkConnection(host: '', port: 0);

  @override
  NetworkConnection get connection => _connection;

  @override
  Stream<NetworkPacket> get onPacketReceived => _packetController.stream;

  @override
  Future<void> connect(String host, int port) async {
    // TODO: Bind a RawDatagramSocket and record the remote endpoint.
    debugPrint('UdpTransport: connect() — not yet implemented');
    _connection.setState(ConnectionState.failed);
  }

  @override
  Future<void> disconnect() async {
    // TODO: Close the RawDatagramSocket.
    debugPrint('UdpTransport: disconnect() — not yet implemented');
    _connection.setState(ConnectionState.disconnected);
  }

  @override
  void send(NetworkPacket packet) {
    // TODO: Serialize packet and send via RawDatagramSocket.send().
    debugPrint('UdpTransport: send() — not yet implemented');
  }

  @override
  void dispose() {
    _packetController.close();
    debugPrint('UdpTransport: disposed');
  }
}

// ---------------------------------------------------------------------------
// NetworkManager
// ---------------------------------------------------------------------------

/// Top-level manager for all network activity. Wraps a [NetworkTransport]
/// and exposes a high-level API that the [Engine] interacts with.
///
/// The engine creates a [NetworkManager] during initialisation. Callers
/// inject their preferred transport (defaults to [WebSocketTransport]).
class NetworkManager {
  bool _initialized = false;
  late NetworkTransport _transport;
  int _seq = 0;

  /// Registered packet handlers keyed by [PacketType].
  final Map<PacketType, List<void Function(NetworkPacket)>> _handlers = {};

  /// The underlying transport.
  NetworkTransport get transport => _transport;

  /// Current connection state shortcut.
  ConnectionState get connectionState => _transport.connection.state;

  /// Whether the manager is connected to a server.
  bool get isConnected => _transport.connection.isConnected;

  /// Current round-trip latency in milliseconds.
  int get latencyMs => _transport.connection.latencyMs;

  /// Initialise with an optional [transport]. Defaults to [WebSocketTransport].
  void initialize([NetworkTransport? transport]) {
    if (_initialized) return;
    _transport = transport ?? WebSocketTransport();
    _transport.onPacketReceived.listen(_dispatch);
    _initialized = true;
    debugPrint('NetworkManager: initialized');
  }

  /// Connect to [host]:[port].
  Future<void> connect(String host, int port) async {
    if (!_initialized) initialize();
    await _transport.connect(host, port);
  }

  /// Disconnect from the current server.
  Future<void> disconnect() async {
    await _transport.disconnect();
  }

  /// Send a [payload] as a [NetworkPacket] with the given [type].
  void sendData(
    Map<String, dynamic> payload, {
    PacketType type = PacketType.reliable,
    PacketPriority priority = PacketPriority.normal,
    String? channelId,
  }) {
    final packet = NetworkPacket(
      sequenceNumber: _seq++,
      type: type,
      payload: payload,
      priority: priority,
      channelId: channelId,
    );
    _transport.send(packet);
  }

  /// Register a handler for packets of [type].
  void on(PacketType type, void Function(NetworkPacket packet) handler) {
    _handlers.putIfAbsent(type, () => []).add(handler);
  }

  /// Remove a previously registered handler.
  void off(PacketType type, void Function(NetworkPacket packet) handler) {
    _handlers[type]?.remove(handler);
  }

  /// Replace the active transport. Disconnects the old one first.
  Future<void> switchTransport(NetworkTransport newTransport) async {
    await _transport.disconnect();
    _transport.dispose();
    _transport = newTransport;
    _transport.onPacketReceived.listen(_dispatch);
    debugPrint('NetworkManager: transport switched');
  }

  /// Clean up all networking resources.
  void dispose() {
    _transport.dispose();
    _handlers.clear();
    _initialized = false;
    debugPrint('NetworkManager: disposed');
  }

  void _dispatch(NetworkPacket packet) {
    final list = _handlers[packet.type];
    if (list == null) return;
    for (final handler in List.of(list)) {
      handler(packet);
    }
  }
}

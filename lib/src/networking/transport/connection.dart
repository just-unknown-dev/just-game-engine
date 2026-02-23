/// Network Connection
///
/// Represents and tracks the state of a single network connection.
/// Used by transport implementations to surface connection events and metrics.
library;

/// Current state of a [NetworkConnection].
enum ConnectionState {
  /// Not connected to any server.
  disconnected,

  /// Attempting to establish a connection.
  connecting,

  /// Fully connected and ready to exchange packets.
  connected,

  /// Lost connection; attempting to restore.
  reconnecting,

  /// Connection attempt failed unrecoverably.
  failed,
}

/// Represents a single network connection including its metadata and metrics.
class NetworkConnection {
  /// Remote host address (IP or hostname).
  final String host;

  /// Remote port number.
  final int port;

  /// Current lifecycle state of this connection.
  ConnectionState _state;

  /// Round-trip latency in milliseconds (updated by ping packets).
  int latencyMs;

  /// Estimated packet loss as a value between 0.0 and 1.0.
  double packetLoss;

  /// Number of successful reconnects.
  int reconnectCount;

  /// UTC timestamp of when the connection was first established.
  DateTime? connectedAt;

  /// Callbacks invoked when [ConnectionState] changes.
  final List<void Function(ConnectionState previous, ConnectionState next)>
  _onStateChanged = [];

  NetworkConnection({
    required this.host,
    required this.port,
    ConnectionState initialState = ConnectionState.disconnected,
    this.latencyMs = 0,
    this.packetLoss = 0.0,
    this.reconnectCount = 0,
  }) : _state = initialState;

  /// Current connection state.
  ConnectionState get state => _state;

  /// Whether the connection is fully established and usable.
  bool get isConnected => _state == ConnectionState.connected;

  /// Whether transport is in a transitional state.
  bool get isBusy =>
      _state == ConnectionState.connecting ||
      _state == ConnectionState.reconnecting;

  /// Transition to a new [ConnectionState] and notify listeners.
  void setState(ConnectionState next) {
    if (_state == next) return;
    final previous = _state;
    _state = next;
    if (next == ConnectionState.connected) {
      connectedAt ??= DateTime.now().toUtc();
    }
    for (final cb in List.of(_onStateChanged)) {
      cb(previous, next);
    }
  }

  /// Register a callback for state transitions.
  void onStateChanged(
    void Function(ConnectionState previous, ConnectionState next) callback,
  ) {
    _onStateChanged.add(callback);
  }

  /// Remove a previously registered state-change callback.
  void removeStateListener(
    void Function(ConnectionState previous, ConnectionState next) callback,
  ) {
    _onStateChanged.remove(callback);
  }

  @override
  String toString() =>
      'NetworkConnection($host:$port state=${_state.name} '
      'latency=${latencyMs}ms loss=${(packetLoss * 100).toStringAsFixed(1)}%)';
}

/// Network Packet
///
/// Defines the core data structures for network transmissions.
/// All data sent over the network is encapsulated in a [NetworkPacket].
library;

/// The type of a network packet, determining how it is routed and prioritized.
enum PacketType {
  /// Reliable ordered delivery — use for game state updates.
  reliable,

  /// Best-effort, no retransmission — use for position/animation ticks.
  unreliable,

  /// Sent to all connected peers in a room.
  broadcast,

  /// Authentication handshake packets.
  auth,

  /// Ping / latency measurement.
  ping,

  /// Session control (join, leave, kick).
  session,
}

/// The relative priority given to a packet during dispatch.
enum PacketPriority {
  /// Sent immediately, before lower-priority packets.
  high,

  /// Default priority for most gameplay packets.
  normal,

  /// Background traffic: analytics, telemetry, non-critical updates.
  low,
}

/// A single unit of data transmitted over the network.
class NetworkPacket {
  /// Unique monotonically increasing number assigned by the sender.
  final int sequenceNumber;

  /// How the packet should be treated by the transport layer.
  final PacketType type;

  /// Dispatch urgency of this packet.
  final PacketPriority priority;

  /// Optional logical channel identifier (e.g. "chat", "transforms", "input").
  final String? channelId;

  /// The packet payload. Must be JSON-serializable.
  final Map<String, dynamic> payload;

  /// UTC time when the packet was created.
  final DateTime timestamp;

  /// Optional ID of the sending player / peer.
  final String? senderId;

  NetworkPacket({
    required this.sequenceNumber,
    required this.type,
    required this.payload,
    this.priority = PacketPriority.normal,
    this.channelId,
    this.senderId,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now().toUtc();

  /// Serialise to a JSON-compatible map for wire transmission.
  Map<String, dynamic> toJson() => {
    'seq': sequenceNumber,
    'type': type.name,
    'priority': priority.name,
    if (channelId != null) 'channel': channelId,
    if (senderId != null) 'sender': senderId,
    'ts': timestamp.millisecondsSinceEpoch,
    'payload': payload,
  };

  /// Deserialise a [NetworkPacket] from a received JSON map.
  factory NetworkPacket.fromJson(Map<String, dynamic> json) {
    return NetworkPacket(
      sequenceNumber: (json['seq'] as num).toInt(),
      type: PacketType.values.byName(json['type'] as String),
      priority: PacketPriority.values.byName(
        (json['priority'] as String?) ?? PacketPriority.normal.name,
      ),
      channelId: json['channel'] as String?,
      senderId: json['sender'] as String?,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (json['ts'] as num).toInt(),
        isUtc: true,
      ),
      payload: Map<String, dynamic>.from(json['payload'] as Map),
    );
  }

  @override
  String toString() =>
      'NetworkPacket(seq=$sequenceNumber, type=${type.name}, '
      'channel=$channelId, sender=$senderId)';
}

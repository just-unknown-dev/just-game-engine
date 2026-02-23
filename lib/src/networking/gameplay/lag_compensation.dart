/// Lag Compensation
///
/// Snapshot buffer and state interpolation utilities for hiding network
/// latency on remote objects. Lets the server rewind game state to a past
/// moment for accurate hit detection, and lets the client interpolate
/// smoothly between received server states.
library;

import 'dart:ui';

import 'package:flutter/foundation.dart';

// ---------------------------------------------------------------------------
// Data models
// ---------------------------------------------------------------------------

/// The serialisable state of a single game object at one point in time.
class ObjectState {
  final String objectId;
  final Offset position;
  final double rotation;
  final Offset scale;
  final Offset velocity;
  final Map<String, dynamic> extras;

  const ObjectState({
    required this.objectId,
    required this.position,
    this.rotation = 0,
    this.scale = const Offset(1, 1),
    this.velocity = Offset.zero,
    this.extras = const {},
  });

  /// Linearly interpolate towards [other] by factor [t] ∈ [0, 1].
  ObjectState lerp(ObjectState other, double t) {
    return ObjectState(
      objectId: objectId,
      position: Offset.lerp(position, other.position, t)!,
      rotation: rotation + (other.rotation - rotation) * t,
      scale: Offset.lerp(scale, other.scale, t)!,
      velocity: Offset.lerp(velocity, other.velocity, t)!,
      extras: other.extras,
    );
  }
}

/// A snapshot of the entire (or partial) game state at one moment.
class StateSnapshot {
  /// Transport-level sequence number for ordering.
  final int sequenceNumber;

  /// UTC server timestamp when this snapshot was recorded.
  final DateTime timestamp;

  /// All object states included in this snapshot (keyed by object ID).
  final Map<String, ObjectState> objectStates;

  StateSnapshot({
    required this.sequenceNumber,
    required this.timestamp,
    required this.objectStates,
  });

  @override
  String toString() =>
      'StateSnapshot(seq=$sequenceNumber, objects=${objectStates.length})';
}

// ---------------------------------------------------------------------------
// Snapshot buffer
// ---------------------------------------------------------------------------

/// A fixed-capacity ring-buffer of [StateSnapshot]s ordered by timestamp.
///
/// Used both for client-side interpolation (keep the last N frames and
/// render between them) and for server-side rewind (look up what the world
/// looked like [latencyMs] ago for hit-registration).
class SnapshotBuffer {
  final int capacity;
  final List<StateSnapshot> _buffer = [];

  SnapshotBuffer({this.capacity = 64});

  /// All buffered snapshots, oldest first.
  List<StateSnapshot> get snapshots => List.unmodifiable(_buffer);

  /// Number of snapshots currently buffered.
  int get length => _buffer.length;

  /// Whether the buffer is empty.
  bool get isEmpty => _buffer.isEmpty;

  /// Add [snapshot] to the buffer. Evicts the oldest entry when at capacity.
  void record(StateSnapshot snapshot) {
    _buffer.add(snapshot);
    // Keep sorted by timestamp for binary search.
    _buffer.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    while (_buffer.length > capacity) {
      _buffer.removeAt(0);
    }
  }

  /// Return the two snapshots that bracket [targetTime] for interpolation.
  /// Returns `null` if the buffer doesn't span [targetTime].
  (StateSnapshot before, StateSnapshot after)? bracketing(DateTime targetTime) {
    if (_buffer.length < 2) return null;
    for (int i = 0; i < _buffer.length - 1; i++) {
      if (_buffer[i].timestamp.isBefore(targetTime) &&
          !_buffer[i + 1].timestamp.isBefore(targetTime)) {
        return (_buffer[i], _buffer[i + 1]);
      }
    }
    return null;
  }

  /// Find the snapshot closest to [targetTime].
  StateSnapshot? closest(DateTime targetTime) {
    if (_buffer.isEmpty) return null;
    return _buffer.reduce((a, b) {
      final aDiff = (a.timestamp.difference(targetTime)).abs();
      final bDiff = (b.timestamp.difference(targetTime)).abs();
      return aDiff <= bDiff ? a : b;
    });
  }

  /// Clear all buffered snapshots.
  void clear() => _buffer.clear();
}

// ---------------------------------------------------------------------------
// Lag compensator
// ---------------------------------------------------------------------------

/// Provides client-side lag compensation via snapshot interpolation.
///
/// The client buffers received server snapshots and renders objects at a
/// configurable [interpolationDelay] behind the leading edge, ensuring
/// smooth motion even with variable network jitter.
class LagCompensator {
  final SnapshotBuffer _buffer;

  /// How far behind the latest snapshot to render, in milliseconds.
  /// A value of 0 renders at the most recent snapshot (no interpolation).
  final int interpolationDelayMs;

  LagCompensator({int bufferCapacity = 32, this.interpolationDelayMs = 100})
    : _buffer = SnapshotBuffer(capacity: bufferCapacity);

  /// Number of snapshots in the internal buffer.
  int get bufferedCount => _buffer.length;

  /// Record a new [snapshot] received from the server.
  void recordSnapshot(StateSnapshot snapshot) {
    _buffer.record(snapshot);
  }

  /// Return interpolated [ObjectState]s for the render-time target.
  ///
  /// [renderTime] is typically `now - interpolationDelayMs`. The compensator
  /// finds the two snapshots that bracket [renderTime] and linearly
  /// interpolates between them.
  Map<String, ObjectState> interpolate([DateTime? renderTime]) {
    final target =
        renderTime ??
        DateTime.now().toUtc().subtract(
          Duration(milliseconds: interpolationDelayMs),
        );

    final bracket = _buffer.bracketing(target);
    if (bracket == null) {
      // Fall back to the closest snapshot.
      final closest = _buffer.closest(target);
      return closest?.objectStates ?? {};
    }

    final (before, after) = bracket;

    final span = after.timestamp.difference(before.timestamp).inMicroseconds;
    if (span == 0) return after.objectStates;

    final elapsed = target.difference(before.timestamp).inMicroseconds;
    final t = (elapsed / span).clamp(0.0, 1.0);

    // Interpolate all objects that appear in both snapshots.
    final result = <String, ObjectState>{};
    for (final id in before.objectStates.keys) {
      final beforeState = before.objectStates[id]!;
      final afterState = after.objectStates[id];
      result[id] = afterState != null
          ? beforeState.lerp(afterState, t)
          : beforeState;
    }
    // Pass through objects only in the 'after' snapshot.
    for (final id in after.objectStates.keys) {
      result.putIfAbsent(id, () => after.objectStates[id]!);
    }

    return result;
  }

  /// Rewind to the snapshot at [targetTime] (for server-side hit registration).
  ///
  /// Returns the authoritative [StateSnapshot] closest to [targetTime],
  /// or `null` if the buffer has no data.
  StateSnapshot? rewindToTime(DateTime targetTime) {
    return _buffer.closest(targetTime);
  }

  /// Clear all buffered snapshots.
  void reset() {
    _buffer.clear();
    debugPrint('LagCompensator: buffer cleared');
  }

  /// Release resources.
  void dispose() {
    reset();
    debugPrint('LagCompensator: disposed');
  }
}

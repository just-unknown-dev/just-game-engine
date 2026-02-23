/// Client-Side Prediction
///
/// Implements client-side input prediction to hide network latency.
/// The client applies input locally and reconciles with authoritative
/// server state when it arrives.
library;

import 'dart:ui';

import 'package:flutter/foundation.dart';

// ---------------------------------------------------------------------------
// Data models
// ---------------------------------------------------------------------------

/// A snapshot of a single input frame, used for prediction and reconciliation.
class InputSnapshot {
  /// Monotonically increasing sequence number matching the packet seq.
  final int sequenceNumber;

  /// UTC time this input was sampled.
  final DateTime timestamp;

  /// Movement direction as a unit (or zero) vector.
  final Offset inputVector;

  /// Length of the frame in seconds.
  final double deltaTime;

  /// Arbitrary extra input state (jump pressed, shoot button, etc.).
  final Map<String, dynamic> extras;

  const InputSnapshot({
    required this.sequenceNumber,
    required this.timestamp,
    required this.inputVector,
    required this.deltaTime,
    this.extras = const {},
  });

  @override
  String toString() => 'InputSnapshot(seq=$sequenceNumber, input=$inputVector)';
}

/// The predicted position after applying all pending inputs.
class PredictionState {
  /// Current predicted world-space position.
  Offset position;

  /// Current predicted velocity.
  Offset velocity;

  /// The sequence number of the last input included in this prediction.
  int lastAppliedSeq;

  PredictionState({
    required this.position,
    required this.velocity,
    this.lastAppliedSeq = 0,
  });
}

// ---------------------------------------------------------------------------
// Client-side prediction
// ---------------------------------------------------------------------------

/// Manages client-side prediction and server reconciliation.
///
/// **Usage pattern:**
/// 1. Each frame call [applyInput] with the current input and delta time.
///    The predicted position is updated immediately.
/// 2. When an authoritative server update arrives, call [reconcile] with
///    the server-acknowledged sequence number and server position.
///    Pending inputs that the server has not yet seen are replayed.
class ClientPrediction {
  final PredictionState _state;
  final List<InputSnapshot> _pendingInputs = [];

  /// User-supplied movement function: given a position, velocity, input
  /// vector, and delta time, returns the new (position, velocity) pair.
  final (Offset position, Offset velocity) Function(
    Offset position,
    Offset velocity,
    Offset inputVector,
    double deltaTime,
  )
  movementFunction;

  /// Maximum number of unacknowledged inputs to retain.
  final int maxPendingInputs;

  int _seq = 0;

  ClientPrediction({
    required Offset initialPosition,
    required this.movementFunction,
    this.maxPendingInputs = 64,
  }) : _state = PredictionState(
         position: initialPosition,
         velocity: Offset.zero,
       );

  /// Current predicted position.
  Offset get position => _state.position;

  /// Current predicted velocity.
  Offset get velocity => _state.velocity;

  /// Number of inputs awaiting server acknowledgement.
  int get pendingCount => _pendingInputs.length;

  /// Apply [inputVector] for this frame and advance the prediction.
  ///
  /// Returns an [InputSnapshot] that should be included in the packet sent
  /// to the server so the server can process the same input.
  InputSnapshot applyInput(Offset inputVector, double deltaTime) {
    final snapshot = InputSnapshot(
      sequenceNumber: _seq++,
      timestamp: DateTime.now().toUtc(),
      inputVector: inputVector,
      deltaTime: deltaTime,
    );

    final (newPos, newVel) = movementFunction(
      _state.position,
      _state.velocity,
      inputVector,
      deltaTime,
    );

    _state.position = newPos;
    _state.velocity = newVel;
    _state.lastAppliedSeq = snapshot.sequenceNumber;

    _pendingInputs.add(snapshot);

    // Discard oldest inputs if buffer overflows.
    while (_pendingInputs.length > maxPendingInputs) {
      _pendingInputs.removeAt(0);
    }

    return snapshot;
  }

  /// Reconcile the local prediction with an authoritative server update.
  ///
  /// Discards all inputs the server has acknowledged ([serverAckedSeq] ≤ seq),
  /// then re-applies any remaining pending inputs on top of the server position.
  void reconcile(
    int serverAckedSeq,
    Offset serverPosition, [
    Offset? serverVelocity,
  ]) {
    // Remove acknowledged inputs.
    _pendingInputs.removeWhere((s) => s.sequenceNumber <= serverAckedSeq);

    // Reset to authoritative state.
    _state.position = serverPosition;
    _state.velocity = serverVelocity ?? Offset.zero;

    // Replay unacknowledged inputs.
    for (final snapshot in _pendingInputs) {
      final (newPos, newVel) = movementFunction(
        _state.position,
        _state.velocity,
        snapshot.inputVector,
        snapshot.deltaTime,
      );
      _state.position = newPos;
      _state.velocity = newVel;
    }

    debugPrint(
      'ClientPrediction: reconciled at seq=$serverAckedSeq, '
      'replayed ${_pendingInputs.length} inputs, '
      'final pos=${_state.position}',
    );
  }

  /// Discard all pending inputs and reset position.
  void reset(Offset position) {
    _pendingInputs.clear();
    _state.position = position;
    _state.velocity = Offset.zero;
    debugPrint('ClientPrediction: reset to $position');
  }
}

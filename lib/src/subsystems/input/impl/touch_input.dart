part of '../input_management.dart';

/// Touch point information
class TouchPoint {
  final int id;
  final Offset position;
  final double pressure;
  final double size;

  TouchPoint({
    required this.id,
    required this.position,
    required this.pressure,
    required this.size,
  });
}

/// Handles touchscreen input
class TouchInput {
  /// Active touch points
  final Map<int, TouchPoint> _touches = {};

  /// Touches started this frame
  final Map<int, TouchPoint> _touchesStarted = {};

  /// Touches ended this frame
  final Map<int, TouchPoint> _touchesEnded = {};

  /// Initialize touch input
  void initialize() {
    _touches.clear();
    _touchesStarted.clear();
    _touchesEnded.clear();
  }

  /// Update touch state each frame
  void update() {
    _touchesStarted.clear();
    _touchesEnded.clear();
  }

  /// Handle pointer event from Flutter
  void handlePointerEvent(PointerEvent event) {
    // Only process touch events, ignore mouse/stylus
    if (event.kind != PointerDeviceKind.touch) return;

    if (event is PointerDownEvent) {
      final touch = TouchPoint(
        id: event.pointer,
        position: event.localPosition,
        pressure: event.pressure,
        size: event.size,
      );
      _touches[event.pointer] = touch;
      _touchesStarted[event.pointer] = touch;
    } else if (event is PointerMoveEvent) {
      _touches[event.pointer] = TouchPoint(
        id: event.pointer,
        position: event.localPosition,
        pressure: event.pressure,
        size: event.size,
      );
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      final touch = _touches[event.pointer];
      if (touch != null) {
        _touchesEnded[event.pointer] = touch;
      }
      _touches.remove(event.pointer);
    }
  }

  /// Get all active touch points
  List<TouchPoint> get touches => _touches.values.toList();

  /// Get number of active touches
  int get touchCount => _touches.length;

  /// Get touch by ID
  TouchPoint? getTouch(int id) => _touches[id];

  /// Check if touch with ID exists
  bool hasTouch(int id) => _touches.containsKey(id);

  /// Get touches started this frame
  List<TouchPoint> get touchesStarted => _touchesStarted.values.toList();

  /// Get touches ended this frame
  List<TouchPoint> get touchesEnded => _touchesEnded.values.toList();

  /// Get first touch position (convenience)
  Offset? get firstTouchPosition =>
      _touches.isEmpty ? null : _touches.values.first.position;

  /// Clear all touch state
  void clear() {
    _touches.clear();
    _touchesStarted.clear();
    _touchesEnded.clear();
  }

  /// Dispose touch resources
  void dispose() {
    clear();
  }
}

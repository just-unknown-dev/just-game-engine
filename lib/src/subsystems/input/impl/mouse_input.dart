part of '../input_management.dart';

/// Handles mouse input
class MouseInput {
  /// Current mouse position
  Offset _position = Offset.zero;

  /// Previous mouse position
  Offset _previousPosition = Offset.zero;

  /// Mouse delta this frame
  Offset _delta = Offset.zero;

  /// Mouse buttons currently pressed
  final Set<int> _buttonsDown = {};

  /// Mouse buttons pressed this frame
  final Set<int> _buttonsPressed = {};

  /// Mouse buttons released this frame
  final Set<int> _buttonsReleased = {};

  /// Previous frame buttons down
  final Set<int> _previousButtonsDown = {};

  /// Scroll delta
  Offset _scrollDelta = Offset.zero;

  /// Manually set scroll delta (for custom scroll handling)
  void setScrollDelta(Offset delta) {
    _scrollDelta = delta;
  }

  /// Initialize mouse input
  void initialize() {
    _position = Offset.zero;
    _previousPosition = Offset.zero;
    _delta = Offset.zero;
    _buttonsDown.clear();
    _buttonsPressed.clear();
    _buttonsReleased.clear();
    _previousButtonsDown.clear();
    _scrollDelta = Offset.zero;
  }

  /// Update mouse state each frame
  void update() {
    // Calculate delta
    _delta = _position - _previousPosition;
    _previousPosition = _position;

    // Calculate pressed and released
    _buttonsPressed.clear();
    _buttonsReleased.clear();

    for (final button in _buttonsDown) {
      if (!_previousButtonsDown.contains(button)) {
        _buttonsPressed.add(button);
      }
    }

    for (final button in _previousButtonsDown) {
      if (!_buttonsDown.contains(button)) {
        _buttonsReleased.add(button);
      }
    }

    // Update previous state
    _previousButtonsDown.clear();
    _previousButtonsDown.addAll(_buttonsDown);

    // Reset scroll delta
    _scrollDelta = Offset.zero;
  }

  /// Handle pointer event from Flutter
  void handlePointerEvent(PointerEvent event) {
    if (event is PointerHoverEvent || event is PointerMoveEvent) {
      _position = event.localPosition;
    } else if (event is PointerDownEvent) {
      _position = event.localPosition;
      _buttonsDown.add(event.buttons);
    } else if (event is PointerUpEvent) {
      _position = event.localPosition;
      _buttonsDown.remove(event.buttons);
    }
    // Note: Scroll events are handled separately via onPointerSignal in GameWidget
    // The scroll delta can be accessed via dynamic casting if needed
  }

  /// Get current mouse position
  Offset get position => _position;

  /// Get mouse movement delta this frame
  Offset get delta => _delta;

  /// Get scroll delta this frame
  Offset get scrollDelta => _scrollDelta;

  /// Check if mouse button is currently held down
  bool isButtonDown(int button) {
    return _buttonsDown.any((b) => b & (1 << button) != 0);
  }

  /// Check if mouse button was pressed this frame
  bool isButtonPressed(int button) {
    return _buttonsPressed.any((b) => b & (1 << button) != 0);
  }

  /// Check if mouse button was released this frame
  bool isButtonReleased(int button) {
    return _buttonsReleased.any((b) => b & (1 << button) != 0);
  }

  /// Check if left mouse button is down
  bool get isLeftButtonDown => isButtonDown(MouseButton.left);

  /// Check if right mouse button is down
  bool get isRightButtonDown => isButtonDown(MouseButton.right);

  /// Check if middle mouse button is down
  bool get isMiddleButtonDown => isButtonDown(MouseButton.middle);

  /// Clear all mouse state
  void clear() {
    _position = Offset.zero;
    _previousPosition = Offset.zero;
    _delta = Offset.zero;
    _buttonsDown.clear();
    _buttonsPressed.clear();
    _buttonsReleased.clear();
    _previousButtonsDown.clear();
    _scrollDelta = Offset.zero;
  }

  /// Dispose mouse resources
  void dispose() {
    clear();
  }
}

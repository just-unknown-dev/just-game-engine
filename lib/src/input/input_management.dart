/// Input Management
///
/// Processes user inputs from keyboards, mice, controllers, and touchscreens.
/// This module handles all types of user input for the game.
library;

import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Mouse button constants
class MouseButton {
  static const int left = 0;
  static const int right = 1;
  static const int middle = 2;
}

/// Main input manager class
class InputManager {
  /// Keyboard input handler
  final keyboard = KeyboardInput();

  /// Mouse input handler
  final mouse = MouseInput();

  /// Touch input handler
  final touch = TouchInput();

  /// Controller input handler
  final controller = ControllerInput();

  /// Callbacks for external handling
  final List<void Function(KeyEvent)> _keyCallbacks = [];
  final List<void Function(PointerEvent)> _pointerCallbacks = [];

  /// Initialize input system
  void initialize() {
    keyboard.initialize();
    mouse.initialize();
    touch.initialize();
    controller.initialize();
  }

  /// Update input state (call each frame)
  void update() {
    keyboard.update();
    mouse.update();
    touch.update();
    controller.update();
  }

  /// Handle key event (call from widget)
  void handleKeyEvent(KeyEvent event) {
    keyboard.handleKeyEvent(event);
    for (final callback in _keyCallbacks) {
      callback(event);
    }
  }

  /// Handle pointer event (call from widget)
  void handlePointerEvent(PointerEvent event) {
    mouse.handlePointerEvent(event);
    touch.handlePointerEvent(event);
    for (final callback in _pointerCallbacks) {
      callback(event);
    }
  }

  /// Register callback for key events
  void onKeyEvent(void Function(KeyEvent) callback) {
    _keyCallbacks.add(callback);
  }

  /// Register callback for pointer events
  void onPointerEvent(void Function(PointerEvent) callback) {
    _pointerCallbacks.add(callback);
  }

  /// Clear all input states
  void clear() {
    keyboard.clear();
    mouse.clear();
    touch.clear();
    controller.clear();
  }

  /// Clean up input resources
  void dispose() {
    keyboard.dispose();
    mouse.dispose();
    touch.dispose();
    controller.dispose();
    _keyCallbacks.clear();
    _pointerCallbacks.clear();
  }
}

/// Handles keyboard input
class KeyboardInput {
  /// Keys currently pressed
  final Set<LogicalKeyboardKey> _keysDown = {};

  /// Keys pressed this frame
  final Set<LogicalKeyboardKey> _keysPressed = {};

  /// Keys released this frame
  final Set<LogicalKeyboardKey> _keysReleased = {};

  /// Previous frame keys down
  final Set<LogicalKeyboardKey> _previousKeysDown = {};

  /// Initialize keyboard input
  void initialize() {
    _keysDown.clear();
    _keysPressed.clear();
    _keysReleased.clear();
    _previousKeysDown.clear();
  }

  /// Update keyboard state each frame
  void update() {
    // Calculate pressed and released
    _keysPressed.clear();
    _keysReleased.clear();

    for (final key in _keysDown) {
      if (!_previousKeysDown.contains(key)) {
        _keysPressed.add(key);
      }
    }

    for (final key in _previousKeysDown) {
      if (!_keysDown.contains(key)) {
        _keysReleased.add(key);
      }
    }

    // Update previous state
    _previousKeysDown.clear();
    _previousKeysDown.addAll(_keysDown);
  }

  /// Handle key event from Flutter
  void handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      _keysDown.add(event.logicalKey);
      debugPrint(
        'KeyDown: ${event.logicalKey.keyLabel} - _keysDown size: ${_keysDown.length}',
      );
    } else if (event is KeyRepeatEvent) {
      // Keep the key in the down state during repeats
      _keysDown.add(event.logicalKey);
      debugPrint(
        'KeyRepeat: ${event.logicalKey.keyLabel} - _keysDown size: ${_keysDown.length}',
      );
    } else if (event is KeyUpEvent) {
      _keysDown.remove(event.logicalKey);
      debugPrint(
        'KeyUp: ${event.logicalKey.keyLabel} - _keysDown size: ${_keysDown.length}',
      );
    }
  }

  /// Check if a key is currently held down
  bool isKeyDown(LogicalKeyboardKey key) {
    return _keysDown.contains(key);
  }

  /// Check if a key was pressed this frame
  bool isKeyPressed(LogicalKeyboardKey key) {
    return _keysPressed.contains(key);
  }

  /// Check if a key was released this frame
  bool isKeyReleased(LogicalKeyboardKey key) {
    return _keysReleased.contains(key);
  }

  /// Get all currently pressed keys
  Set<LogicalKeyboardKey> get keysDown => Set.unmodifiable(_keysDown);

  /// Check if any key is down
  bool get anyKeyDown => _keysDown.isNotEmpty;

  /// Check if any key was pressed this frame
  bool get anyKeyPressed => _keysPressed.isNotEmpty;

  /// Get horizontal input axis (-1 left, 0 neutral, 1 right)
  double get horizontal {
    double value = 0;
    if (isKeyDown(LogicalKeyboardKey.arrowLeft) ||
        isKeyDown(LogicalKeyboardKey.keyA)) {
      value -= 1;
    }
    if (isKeyDown(LogicalKeyboardKey.arrowRight) ||
        isKeyDown(LogicalKeyboardKey.keyD)) {
      value += 1;
    }
    if (value != 0) {
      debugPrint(
        'Horizontal: $value (A: ${_keysDown.contains(LogicalKeyboardKey.keyA)}, D: ${_keysDown.contains(LogicalKeyboardKey.keyD)}, Left: ${_keysDown.contains(LogicalKeyboardKey.arrowLeft)}, Right: ${_keysDown.contains(LogicalKeyboardKey.arrowRight)})',
      );
    }
    return value;
  }

  /// Get vertical input axis (-1 up, 0 neutral, 1 down)
  double get vertical {
    double value = 0;
    if (isKeyDown(LogicalKeyboardKey.arrowUp) ||
        isKeyDown(LogicalKeyboardKey.keyW)) {
      value -= 1;
    }
    if (isKeyDown(LogicalKeyboardKey.arrowDown) ||
        isKeyDown(LogicalKeyboardKey.keyS)) {
      value += 1;
    }
    if (value != 0) {
      debugPrint(
        'Vertical: $value (W: ${_keysDown.contains(LogicalKeyboardKey.keyW)}, S: ${_keysDown.contains(LogicalKeyboardKey.keyS)}, Up: ${_keysDown.contains(LogicalKeyboardKey.arrowUp)}, Down: ${_keysDown.contains(LogicalKeyboardKey.arrowDown)})',
      );
    }
    return value;
  }

  /// Clear all keyboard state
  void clear() {
    _keysDown.clear();
    _keysPressed.clear();
    _keysReleased.clear();
    _previousKeysDown.clear();
  }

  /// Dispose keyboard resources
  void dispose() {
    clear();
  }
}

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

/// Gamepad axis identifiers
class GamepadAxis {
  static const String leftStickX = 'leftStickX';
  static const String leftStickY = 'leftStickY';
  static const String rightStickX = 'rightStickX';
  static const String rightStickY = 'rightStickY';
  static const String leftTrigger = 'leftTrigger';
  static const String rightTrigger = 'rightTrigger';
}

/// Gamepad button identifiers
class GamepadButton {
  static const int a = 0;
  static const int b = 1;
  static const int x = 2;
  static const int y = 3;
  static const int leftBumper = 4;
  static const int rightBumper = 5;
  static const int leftTriggerButton = 6;
  static const int rightTriggerButton = 7;
  static const int back = 8;
  static const int start = 9;
  static const int leftStick = 10;
  static const int rightStick = 11;
  static const int dpadUp = 12;
  static const int dpadDown = 13;
  static const int dpadLeft = 14;
  static const int dpadRight = 15;
}

/// Handles game controller/gamepad input
class ControllerInput {
  /// Axis values (-1 to 1)
  final Map<String, double> _axes = {};

  /// Buttons currently pressed
  final Set<int> _buttonsDown = {};

  /// Buttons pressed this frame
  final Set<int> _buttonsPressed = {};

  /// Buttons released this frame
  final Set<int> _buttonsReleased = {};

  /// Previous frame buttons
  final Set<int> _previousButtonsDown = {};

  /// Dead zone for analog sticks
  double deadZone = 0.15;

  /// Initialize controller input
  void initialize() {
    _axes.clear();
    _buttonsDown.clear();
    _buttonsPressed.clear();
    _buttonsReleased.clear();
    _previousButtonsDown.clear();
  }

  /// Update controller state each frame
  void update() {
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
  }

  /// Set axis value (for testing or external input)
  void setAxis(String axis, double value) {
    // Apply dead zone
    if (value.abs() < deadZone) {
      value = 0;
    }
    _axes[axis] = value.clamp(-1.0, 1.0);
  }

  /// Set button state (for testing or external input)
  void setButton(int button, bool pressed) {
    if (pressed) {
      _buttonsDown.add(button);
    } else {
      _buttonsDown.remove(button);
    }
  }

  /// Get controller axis value (-1 to 1)
  double getAxis(String axis) {
    return _axes[axis] ?? 0.0;
  }

  /// Check if controller button is currently held down
  bool isButtonDown(int button) {
    return _buttonsDown.contains(button);
  }

  /// Check if controller button was pressed this frame
  bool isButtonPressed(int button) {
    return _buttonsPressed.contains(button);
  }

  /// Check if controller button was released this frame
  bool isButtonReleased(int button) {
    return _buttonsReleased.contains(button);
  }

  /// Get left stick as vector
  Offset get leftStick =>
      Offset(getAxis(GamepadAxis.leftStickX), getAxis(GamepadAxis.leftStickY));

  /// Get right stick as vector
  Offset get rightStick => Offset(
    getAxis(GamepadAxis.rightStickX),
    getAxis(GamepadAxis.rightStickY),
  );

  /// Clear all controller state
  void clear() {
    _axes.clear();
    _buttonsDown.clear();
    _buttonsPressed.clear();
    _buttonsReleased.clear();
    _previousButtonsDown.clear();
  }

  /// Dispose controller resources
  void dispose() {
    clear();
  }
}

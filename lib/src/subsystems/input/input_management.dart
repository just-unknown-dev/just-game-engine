import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

part 'impl/mouse_button.dart';
part 'impl/keyboard_input.dart';
part 'impl/mouse_input.dart';
part 'impl/touch_input.dart';
part 'impl/virtual_joystick.dart';
part 'controller_input.dart';

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

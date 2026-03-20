part of '../input_management.dart';

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
    } else if (event is KeyRepeatEvent) {
      // Keep the key in the down state during repeats
      _keysDown.add(event.logicalKey);
    } else if (event is KeyUpEvent) {
      _keysDown.remove(event.logicalKey);
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

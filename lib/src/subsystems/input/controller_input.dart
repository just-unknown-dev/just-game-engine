part of 'input_management.dart';

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

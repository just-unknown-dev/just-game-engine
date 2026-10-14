/// The engine's camera subsystem: the output camera and the brain that
/// decides what it shows.
library;

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/painting.dart' show Offset;

import '../../../subsystems/camera/camera_system.dart';
import '../../base/engine_context.dart';
import 'camera_brain.dart';

/// Owns the output [mainCamera] and the [brain] that drives it.
///
/// The brain is evaluated by `CameraBrainSystem`, inside the ECS frame, so
/// it sees this frame's positions; this system's own update only advances
/// the post effects.
class CameraSystem {
  /// The output camera everything renders through. Reading it before
  /// [initialize] throws.
  late Camera mainCamera;

  /// The brain driving [mainCamera]. Reading it before [initialize] throws.
  late CameraBrain brain;
  bool _initialized = false;

  /// Whether [initialize] has run since the system was made or disposed.
  bool get isInitialized => _initialized;

  /// Makes a fresh [mainCamera] at the origin, zoom 1, and a [brain]
  /// driving it — with [context]'s camera stages and managers when given
  /// (see [CameraRegistries.of]). Does nothing when already initialized.
  void initialize({EngineContext? context}) {
    if (_initialized) return;
    mainCamera = Camera(position: Offset.zero, zoom: 1.0);
    brain = CameraBrain(
      mainCamera,
      registries: context == null ? null : CameraRegistries.of(context),
    );
    _initialized = true;
    if (kDebugMode) debugPrint('Camera System initialized');
  }

  /// Advances [mainCamera]'s post effects by [deltaTime] seconds. Does
  /// nothing before [initialize] or for a [deltaTime] of zero or less.
  void update(double deltaTime) {
    if (!_initialized || deltaTime <= 0) return;
    mainCamera.effectManager.update(deltaTime);
  }

  /// Resets the brain and marks the system uninitialized; a later
  /// [initialize] makes a new camera and brain.
  void dispose() {
    if (_initialized) brain.reset();
    _initialized = false;
  }
}

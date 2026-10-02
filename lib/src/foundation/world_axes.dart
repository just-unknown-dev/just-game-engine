/// The engine's world axes, declared once.
library;

import 'package:just_dart/just_dart.dart';

/// Which way is which in the engine's world — for 2-D and 3-D alike.
///
/// ```text
///   +X  right
///   +Y  down        (screen space: a 2-D level's y grows downwards)
///   +Z  forward     (into the screen, away from a 2-D camera)
/// ```
///
/// The basis is **right-handed**. Consequences worth knowing:
///
/// * "Up" is **−Y**. Gravity is +Y; a jump is −Y.
/// * A positive rotation about Z carries +X towards +Y — **clockwise on
///   screen**, the same sense as `Canvas.rotate`.
/// * A 2-D camera looks along +Z. Larger z is further away.
/// * glTF / Blender content is Y-up with +Z towards the viewer; an importer
///   turns it 180° about X (`(x, y, z) → (x, −y, −z)`) to land in this world.
///
/// Nothing else in the engine should spell these directions out as literals:
/// cameras, audio, gizmos and importers read them from here.
abstract final class WorldAxes {
  /// +X.
  static const double rightX = 1.0, rightY = 0.0, rightZ = 0.0;

  /// +Y (gravity's direction).
  static const double downX = 0.0, downY = 1.0, downZ = 0.0;

  /// −Y.
  static const double upX = 0.0, upY = -1.0, upZ = 0.0;

  /// +Z, into the screen.
  static const double forwardX = 0.0, forwardY = 0.0, forwardZ = 1.0;

  /// Write the right direction into [out].
  static void rightInto(Vector3 out) => out.setValues(rightX, rightY, rightZ);

  /// Write the up direction into [out].
  static void upInto(Vector3 out) => out.setValues(upX, upY, upZ);

  /// Write the down direction into [out].
  static void downInto(Vector3 out) => out.setValues(downX, downY, downZ);

  /// Write the forward direction into [out].
  static void forwardInto(Vector3 out) =>
      out.setValues(forwardX, forwardY, forwardZ);

  /// A new vector pointing right. Allocates — not for per-frame code.
  static Vector3 get right => Vector3(rightX, rightY, rightZ);

  /// A new vector pointing up. Allocates — not for per-frame code.
  static Vector3 get up => Vector3(upX, upY, upZ);

  /// A new vector pointing down. Allocates — not for per-frame code.
  static Vector3 get down => Vector3(downX, downY, downZ);

  /// A new vector pointing forward. Allocates — not for per-frame code.
  static Vector3 get forward => Vector3(forwardX, forwardY, forwardZ);
}

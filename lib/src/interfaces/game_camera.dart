/// Abstract camera contract.
///
/// ECS systems depend on this rather than the concrete [Camera] class,
/// keeping the ECS layer decoupled from the camera subsystem implementation.
library;

import 'package:flutter/material.dart';
import 'package:just_dart/just_dart.dart';

import '../subsystems/camera/camera_lens.dart';
import 'view_volume.dart';

/// Minimal camera interface consumed by ECS render systems.
///
/// The 2-D members ([position], [applyTransform], [getVisibleBounds]) are
/// what the Canvas renderer uses. The matrices and [screenToWorldRay]
/// describe the same camera in 3-D — what a 3-D rendering backend, 3-D
/// picking or frustum culling reads.
abstract interface class GameCamera {
  /// Camera position in world space (x, y).
  Offset get position;

  /// Viewport size (set by the rendering system each frame).
  Size get viewportSize;
  set viewportSize(Size size);

  /// Apply the camera's view transform to [canvas].
  void applyTransform(Canvas canvas, Size size);

  /// Return the axis-aligned visible area in world space.
  Rect getVisibleBounds();

  /// Orthographic or perspective, and how much it sees.
  CameraLens get lens;

  /// Whether this is a plain 2-D camera: no pitch or yaw, orthographic.
  bool get isPlanar;

  /// World space → the camera's own (+X right, +Y down, +Z ahead).
  void viewMatrixInto(Matrix4 out);

  /// Camera space → clip space (x, y in −1..1 with y down, depth 0..1).
  void projectionMatrixInto(Matrix4 out);

  /// World space → clip space.
  void viewProjectionInto(Matrix4 out);

  /// World space → canvas pixels: what [applyTransform] applies.
  void canvasMatrixInto(Matrix4 out);

  /// The ray from the camera through the pixel [screen].
  Ray3 screenToWorldRay(Offset screen, [Ray3? out]);

  /// What the camera sees, for culling — kept up to date on each read.
  ViewVolume get viewVolume;
}

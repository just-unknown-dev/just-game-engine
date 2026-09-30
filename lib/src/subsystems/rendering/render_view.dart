/// What a frame is drawn from: the camera, as matrices.
library;

import 'dart:ui';

import 'package:just_dart/just_dart.dart';

import '../../interfaces/game_camera.dart';
import '../camera/camera_lens.dart';

/// The camera of one frame, in the forms a renderer needs — reused frame to
/// frame, so reading it allocates nothing.
///
/// A 2-D renderer draws through the canvas with the camera applied and never
/// needs this. It is for what draws the world another way: a 3-D backend
/// rendering into a texture, a frustum culler, a picking pass. The
/// [RenderingEngine] fills it at most once a frame, and only when something
/// reads it (`RenderingEngine.view`).
///
/// Matrices follow the engine's conventions (see `JustMatrix4`): world axes
/// +X right, +Y down, +Z forward; clip space x, y in −1..1 with y down,
/// depth 0..1.
class RenderView {
  /// Pixels drawn into.
  Size viewportSize = Size.zero;

  /// World → camera space.
  final Matrix4 view = Matrix4.identity();

  /// Camera space → clip space.
  final Matrix4 projection = Matrix4.identity();

  /// World → clip space.
  final Matrix4 viewProjection = Matrix4.identity();

  /// World → canvas pixels: what the camera applies to the canvas.
  final Matrix4 canvas = Matrix4.identity();

  /// The part of the world plane z = 0 in view.
  Rect visibleRect = Rect.zero;

  /// The camera's lens.
  CameraLens lens = const CameraLens();

  /// Whether the camera is a plain 2-D one.
  bool isPlanar = true;

  /// How far between two physics steps this frame is drawn (0..1).
  double interpolation = 1.0;

  /// Fill from [camera], drawing into [size].
  void update(GameCamera camera, Size size, {double interpolation = 1.0}) {
    viewportSize = size;
    camera.viewMatrixInto(view);
    camera.projectionMatrixInto(projection);
    camera.viewProjectionInto(viewProjection);
    camera.canvasMatrixInto(canvas);
    visibleRect = camera.getVisibleBounds();
    lens = camera.lens;
    isPlanar = camera.isPlanar;
    this.interpolation = interpolation;
  }
}

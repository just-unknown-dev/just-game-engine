/// Camera System
///
/// The output camera — what everything renders through — and the brain that
/// decides what it shows.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_dart/just_dart.dart';

import '../../interfaces/game_camera.dart';
import '../../interfaces/view_volume.dart';
import 'camera_brain.dart';
import 'camera_effects.dart';
import 'camera_lens.dart';
import 'camera_state.dart';

// ─── Camera ──────────────────────────────────────────────────────────────────

/// The output camera: a view of the world and the maths to draw through it.
///
/// It holds a position, a zoom and a roll, turns them into a canvas
/// transform, converts between screen and world, and carries the post
/// effects. It does **not** decide where to look. Shots are virtual cameras —
/// entities with a `VirtualCameraComponent` — and the [CameraBrain] picks one,
/// blends to it and writes the result here every frame.
///
/// A game with no virtual cameras can still move this by hand: with nothing
/// to choose from, the brain leaves it alone.
///
/// ## In 3-D
///
/// The camera also has a depth ([z]), a pitch and a yaw, and a [lens]. With
/// none of them set it is [isPlanar] — a 2-D camera — and draws, converts
/// and culls exactly as a 2-D camera always has. Otherwise its matrices
/// ([viewMatrixInto], [projectionMatrixInto], [canvasMatrixInto]) and
/// [screenToWorldRay] describe a camera in space; [screenToWorld] then finds
/// the point under the pointer on the world plane z = 0.
///
/// The camera's own axes are the world's (`WorldAxes`): it looks along +Z
/// with +Y down. Its orientation is `qY(yaw) · qX(pitch) · qZ(−roll)` — the
/// roll negated, because [rotation] turns the *view*, the opposite of
/// turning the camera.
class Camera implements GameCamera {
  Camera({
    this.position = Offset.zero,
    this.zoom = 1.0,
    this.rotation = 0.0,
    this.viewportSize = Size.zero,
    this.minZoom = 0.1,
    this.maxZoom = 10.0,
    this.z = 0.0,
    this.pitch = 0.0,
    this.yaw = 0.0,
    this.lens = const CameraLens(),
  });

  @override
  Offset position;

  /// Zoom level (`1.0` = normal, `>1` = zoom-in, `<1` = zoom-out).
  double zoom;

  /// Rotation in radians.
  double rotation;

  @override
  Size viewportSize;

  double minZoom;
  double maxZoom;

  /// Depth of the camera — its world z. 0 for a 2-D camera.
  double z;

  /// Turn about the world X axis, in radians. 0 for a 2-D camera.
  double pitch;

  /// Turn about the world Y axis, in radians. 0 for a 2-D camera.
  double yaw;

  /// Orthographic (2-D) or perspective, and how much it sees.
  @override
  CameraLens lens;

  /// Whether this is a plain 2-D camera: no pitch or yaw, orthographic.
  @override
  bool get isPlanar => pitch == 0 && yaw == 0 && lens.isOrthographic;

  /// Attach [CameraEffect] instances here (fade, letterbox, motion blur…).
  final CameraEffectManager effectManager = CameraEffectManager();

  // ── State ─────────────────────────────────────────────────────────────

  /// What this camera shows, as a value.
  CameraState get state => CameraState(
    position: position,
    zoom: zoom,
    rotation: rotation,
    z: z,
    pitch: pitch,
    yaw: yaw,
    lens: lens,
  );

  /// Shows [state]. Zoom is clamped to [[minZoom], [maxZoom]].
  void apply(CameraState state) {
    position = state.position;
    zoom = state.zoom.clamp(minZoom, maxZoom);
    rotation = state.rotation;
    z = state.z;
    pitch = state.pitch;
    yaw = state.yaw;
    lens = state.lens;
  }

  // ── Direct control ────────────────────────────────────────────────────

  void setPosition(Offset newPosition) => position = newPosition;

  /// Set the camera zoom, clamped to [[minZoom], [maxZoom]].
  void setZoom(double newZoom) => zoom = newZoom.clamp(minZoom, maxZoom);

  /// Translate the camera by [delta] in world units.
  void moveBy(Offset delta) => position += delta;

  /// Multiply the current zoom by [factor].
  void zoomBy(double factor) => setZoom(zoom * factor);

  /// Alias for [setPosition].
  void lookAt(Offset target) => setPosition(target);

  /// Zoom toward [worldPoint] so the point stays fixed on screen.
  ///
  /// ```
  /// newPos = worldPoint − (worldPoint − position) × (currentZoom / newZoom)
  /// ```
  void zoomToPoint(Offset worldPoint, double targetZoom) {
    final newZoom = targetZoom.clamp(minZoom, maxZoom);
    position = worldPoint - (worldPoint - position) * (zoom / newZoom);
    zoom = newZoom;
  }

  // ── Transform ─────────────────────────────────────────────────────────

  @override
  void applyTransform(Canvas canvas, Size size) {
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(zoom, zoom);
    canvas.rotate(rotation);
    canvas.translate(-position.dx, -position.dy);
  }

  // ── Matrices ──────────────────────────────────────────────────────────

  final Quaternion _q = Quaternion.identity();
  final Vector3 _v = Vector3.zero();
  final Vector3 _w = Vector3.zero();
  // One scratch matrix per use, so a caller may pass any of its own.
  final Matrix4 _view = Matrix4.zero();
  final Matrix4 _viewport = Matrix4.zero();
  final Matrix4 _canvas = Matrix4.zero();
  final Matrix4 _inverse = Matrix4.zero();
  static final Vector3 _zero = Vector3.zero();
  static final Vector3 _one = Vector3(1, 1, 1);

  /// The camera's orientation in the world:
  /// `qY(yaw) · qX(pitch) · qZ(−roll)`.
  void orientationInto(Quaternion out) => out.setEuler(pitch, yaw, -rotation);

  /// World space → the camera's own (+X right, +Y down, +Z ahead).
  @override
  void viewMatrixInto(Matrix4 out) {
    orientationInto(_q);
    _q.conjugate();
    out.setFromTrs(_zero, _q, _one);
    _v.setValues(-position.dx, -position.dy, -z);
    _q.rotateInto(_v, _v);
    final m = out.storage;
    m[12] = _v.x;
    m[13] = _v.y;
    m[14] = _v.z;
  }

  /// Camera space → the engine's clip space (x, y in −1..1 with y down,
  /// depth 0..1). An orthographic lens sees [viewportSize] / [zoom] world
  /// units; a perspective one its field of view.
  @override
  void projectionMatrixInto(Matrix4 out) {
    final w = viewportSize.width > 0 ? viewportSize.width : 1.0;
    final h = viewportSize.height > 0 ? viewportSize.height : 1.0;
    if (lens.isOrthographic) {
      final k = zoom > 0 ? zoom : 1.0;
      final hw = w / (2 * k), hh = h / (2 * k);
      out.setOrthographicYDown(-hw, hw, -hh, hh, lens.near, lens.far);
    } else {
      out.setPerspectiveYDown(lens.fieldOfView, w / h, lens.near, lens.far);
    }
  }

  /// World space → clip space: projection × view.
  @override
  void viewProjectionInto(Matrix4 out) {
    viewMatrixInto(_view);
    projectionMatrixInto(out);
    out.setProduct(out, _view);
  }

  /// World space → canvas pixels, the matrix [applyTransform] applies —
  /// for a 2-D camera exactly its translate, scale and rotate.
  @override
  void canvasMatrixInto(Matrix4 out) {
    if (isPlanar) {
      final c = math.cos(rotation), s = math.sin(rotation);
      final px = -position.dx, py = -position.dy;
      out.setFromPlanarTrs(
        viewportSize.width / 2 + zoom * (c * px - s * py),
        viewportSize.height / 2 + zoom * (s * px + c * py),
        0,
        rotation,
        zoom,
        zoom,
        1,
      );
      return;
    }
    viewProjectionInto(out);
    // Clip space → pixels.
    final hw = viewportSize.width / 2, hh = viewportSize.height / 2;
    _viewport.setZero();
    final v = _viewport.storage;
    v[0] = hw;
    v[5] = hh;
    v[10] = 1;
    v[12] = hw;
    v[13] = hh;
    v[15] = 1;
    out.setProduct(_viewport, out);
  }

  /// The ray from the camera through the pixel [screen]: for a 2-D camera,
  /// straight ahead (+Z) from behind the world plane; for a perspective one,
  /// from the camera out through the pixel. Written into [out] when given.
  @override
  Ray3 screenToWorldRay(Offset screen, [Ray3? out]) {
    final ray = out ?? Ray3();
    final w = viewportSize.width > 0 ? viewportSize.width : 1.0;
    final h = viewportSize.height > 0 ? viewportSize.height : 1.0;
    final nx = screen.dx / w * 2 - 1, ny = screen.dy / h * 2 - 1;
    viewProjectionInto(_inverse);
    _inverse.invert();
    _v.setValues(nx, ny, 0);
    _inverse.transformPointInto(_v, _v);
    _w.setValues(nx, ny, 1);
    _inverse.transformPointInto(_w, _w);
    _w.sub(_v);
    _w.normalize();
    ray.setValues(_v.x, _v.y, _v.z, _w.x, _w.y, _w.z);
    return ray;
  }

  /// Where the world point [world] is on screen, in pixels, into [out]; its
  /// z is the depth (0 near .. 1 far) for a camera in space.
  void worldToScreen3(Vector3 world, Vector3 out) {
    canvasMatrixInto(_canvas);
    _canvas.transformPointInto(world, out);
  }

  final Ray3 _ray = Ray3();

  final PlanarViewVolume _planarVolume = PlanarViewVolume();
  final FrustumViewVolume _frustumVolume = FrustumViewVolume();
  final Matrix4 _volumeMatrix = Matrix4.zero();

  /// What the camera sees: the visible rectangle for a 2-D camera, the
  /// frustum for one in space. The same object each time, refreshed.
  @override
  ViewVolume get viewVolume {
    if (isPlanar) {
      _planarVolume.planarBounds = getVisibleBounds();
      return _planarVolume;
    }
    viewProjectionInto(_volumeMatrix);
    _frustumVolume.update(_volumeMatrix, getVisibleBounds());
    return _frustumVolume;
  }

  /// The point on the world plane z = 0 under [screen], or null when the
  /// camera looks along the plane or away from it.
  Offset? _onWorldPlane(Offset screen) {
    screenToWorldRay(screen, _ray);
    final t = _ray.intersectZ();
    if (t == null) return null;
    _ray.atInto(t, _v);
    return Offset(_v.x, _v.y);
  }

  // ── Coordinate conversion ─────────────────────────────────────────────

  /// The world point under [screenPos]. For a camera in space, the one on
  /// the world plane z = 0 (the camera's own position when it cannot see
  /// the plane).
  Offset screenToWorld(Offset screenPos) {
    if (!isPlanar) return _onWorldPlane(screenPos) ?? position;
    final centered =
        screenPos - Offset(viewportSize.width / 2, viewportSize.height / 2);
    final scaled = centered / zoom;
    final c = math.cos(-rotation);
    final s = math.sin(-rotation);
    return Offset(
          scaled.dx * c - scaled.dy * s,
          scaled.dx * s + scaled.dy * c,
        ) +
        position;
  }

  /// Where the world point [worldPos] (at z = 0) is on screen.
  Offset worldToScreen(Offset worldPos) {
    if (!isPlanar) {
      _w.setValues(worldPos.dx, worldPos.dy, 0);
      worldToScreen3(_w, _w);
      return Offset(_w.x, _w.y);
    }
    final rel = worldPos - position;
    final c = math.cos(rotation);
    final s = math.sin(rotation);
    final rotated = Offset(rel.dx * c - rel.dy * s, rel.dx * s + rel.dy * c);
    return rotated * zoom +
        Offset(viewportSize.width / 2, viewportSize.height / 2);
  }

  /// The world area in view — for a camera in space, the part of the world
  /// plane z = 0 its corners see (everything, when a corner misses it).
  @override
  Rect getVisibleBounds() {
    if (!isPlanar) return _visibleOnPlane();
    return Rect.fromCenter(
      center: position,
      width: viewportSize.width / zoom,
      height: viewportSize.height / zoom,
    );
  }

  Rect _visibleOnPlane() {
    final w = viewportSize.width, h = viewportSize.height;
    double? l, t, r, b;
    for (final corner in [
      Offset.zero,
      Offset(w, 0),
      Offset(0, h),
      Offset(w, h),
    ]) {
      final p = _onWorldPlane(corner);
      if (p == null) {
        // A corner that misses the plane sees to the horizon.
        return Rect.fromCenter(center: position, width: 1e9, height: 1e9);
      }
      l = l == null ? p.dx : math.min(l, p.dx);
      t = t == null ? p.dy : math.min(t, p.dy);
      r = r == null ? p.dx : math.max(r, p.dx);
      b = b == null ? p.dy : math.max(b, p.dy);
    }
    return Rect.fromLTRB(l!, t!, r!, b!);
  }

  bool isVisible(Offset point) => getVisibleBounds().contains(point);

  bool isRectVisible(Rect? rect) {
    if (rect == null) return true;
    return getVisibleBounds().overlaps(rect);
  }

  void reset() {
    position = Offset.zero;
    zoom = 1.0;
    rotation = 0.0;
    z = 0.0;
    pitch = 0.0;
    yaw = 0.0;
    lens = const CameraLens();
    effectManager.clearEffects();
  }
}

// ─── CameraSystem ─────────────────────────────────────────────────────────────

/// Owns the output [mainCamera] and the [brain] that drives it.
///
/// The brain is evaluated by `CameraBrainSystem`, inside the ECS frame, so
/// it sees this frame's positions; this system's own update only advances
/// the post effects.
class CameraSystem {
  late Camera mainCamera;
  late CameraBrain brain;
  bool _initialized = false;

  bool get isInitialized => _initialized;

  void initialize() {
    if (_initialized) return;
    mainCamera = Camera(position: Offset.zero, zoom: 1.0);
    brain = CameraBrain(mainCamera);
    _initialized = true;
    debugPrint('Camera System initialized');
  }

  void update(double deltaTime) {
    if (!_initialized || deltaTime <= 0) return;
    mainCamera.effectManager.update(deltaTime);
  }

  void dispose() {
    if (_initialized) brain.reset();
    _initialized = false;
  }
}

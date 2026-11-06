/// Output camera
///
/// The output camera — what everything renders through. The brain that
/// decides what it shows (`camera_brain.dart`), and the `CameraEngine` that
/// owns both (`camera_engine.dart`), are beside it. This file imports only
/// `interfaces/` and the camera state and effects, so the rendering
/// contracts can use it.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_dart/just_dart.dart';

import '../interfaces/game_camera.dart';
import '../interfaces/view_volume.dart';
import 'camera_effects.dart';
import '../interfaces/camera_lens.dart';
import 'camera_state.dart';

// ─── OutputCamera ────────────────────────────────────────────────────────────

/// The output camera: a view of the world and the maths to draw through it.
///
/// It holds a position, a zoom and a roll, turns them into a canvas
/// transform, converts between screen and world, and carries the post
/// effects. It does **not** decide where to look. Shots are virtual cameras —
/// entities with a `VirtualCameraComponent` — and the `CameraBrain` picks one,
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
class OutputCamera implements GameCamera {
  /// A [zoom] of zero, a negative one or one that is not a number starts
  /// at [minZoom] instead — see [zoom].
  OutputCamera({
    this.position = Offset.zero,
    double zoom = 1.0,
    this.rotation = 0.0,
    this.viewportSize = Size.zero,
    this.minZoom = 0.1,
    this.maxZoom = 10.0,
    this.z = 0.0,
    this.pitch = 0.0,
    this.yaw = 0.0,
    this.lens = const CameraLens(),
  }) {
    this.zoom = zoom;
  }

  @override
  Offset position;

  /// The smallest zoom the camera ever holds, whatever it is told: a zoom
  /// of 0 would divide every world size on screen by zero.
  static const double minSafeZoom = 1e-4;

  double _zoom = 1.0;

  /// Zoom level (`1.0` = normal, `>1` = zoom-in, `<1` = zoom-out).
  ///
  /// Always positive and finite. Setting it directly is not limited to
  /// [minZoom]..[maxZoom] (use [setZoom] for that), but a value at or below
  /// zero, or not a number, becomes [minZoom] (at least [minSafeZoom]), and
  /// an infinite one becomes [maxZoom].
  double get zoom => _zoom;
  set zoom(double value) {
    if (value.isFinite && value > 0) {
      _zoom = value;
    } else if (value == double.infinity && maxZoom.isFinite && maxZoom > 0) {
      _zoom = maxZoom;
    } else {
      _zoom = minZoom.isFinite && minZoom > minSafeZoom ? minZoom : minSafeZoom;
    }
  }

  /// Rotation in radians.
  double rotation;

  @override
  Size viewportSize;

  /// The lowest zoom [setZoom], [zoomBy], [zoomToPoint] and [apply] allow,
  /// and what a zero, negative or NaN [zoom] becomes (see [zoom]). `0.1`
  /// by default.
  double minZoom;

  /// The highest zoom [setZoom], [zoomBy], [zoomToPoint] and [apply] allow,
  /// and what an infinite [zoom] becomes (see [zoom]). `10` by default.
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

  /// Whether this is a plain 2-D camera: no pitch or yaw, orthographic —
  /// and not [inSpace].
  @override
  bool get isPlanar =>
      !inSpace && pitch == 0 && yaw == 0 && lens.isOrthographic;

  /// Looking at a 3-D scene even when it looks like a 2-D camera: an
  /// orthographic view straight along an axis (an editor's front view)
  /// still sees space, not a flat level. Set by whoever points it so.
  bool inSpace = false;

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

  /// [value] clamped to [[minZoom], [maxZoom]] — taken the other way round
  /// when [minZoom] is the higher, rather than throwing.
  double _clampZoom(double value) => value
      .clamp(math.min(minZoom, maxZoom), math.max(minZoom, maxZoom))
      .toDouble();

  /// Shows [state]. Zoom is clamped to [[minZoom], [maxZoom]].
  void apply(CameraState state) {
    position = state.position;
    zoom = _clampZoom(state.zoom);
    rotation = state.rotation;
    z = state.z;
    pitch = state.pitch;
    yaw = state.yaw;
    lens = state.lens;
  }

  // ── Direct control ────────────────────────────────────────────────────

  /// Centres the view on [newPosition], in world units. A brain driving
  /// this camera overwrites it every frame while it has a virtual camera.
  void setPosition(Offset newPosition) => position = newPosition;

  /// Set the camera zoom, clamped to [[minZoom], [maxZoom]].
  void setZoom(double newZoom) => zoom = _clampZoom(newZoom);

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
    final previous = zoom;
    zoom = _clampZoom(targetZoom);
    position = worldPoint - (worldPoint - position) * (previous / zoom);
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
  ///
  /// Built from the lens's safe values ([CameraLens.safeNear] and the rest),
  /// so a lens that cannot project still gives a finite matrix.
  @override
  void projectionMatrixInto(Matrix4 out) {
    final w = viewportSize.width > 0 ? viewportSize.width : 1.0;
    final h = viewportSize.height > 0 ? viewportSize.height : 1.0;
    if (lens.isOrthographic) {
      final hw = w / (2 * zoom), hh = h / (2 * zoom);
      out.setOrthographicYDown(-hw, hw, -hh, hh, lens.safeNear, lens.safeFar);
    } else {
      out.setPerspectiveYDown(
        lens.safeFieldOfView,
        w / h,
        lens.safeNear,
        lens.safeFar,
      );
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
  Ray3D screenToWorldRay(Offset screen, [Ray3D? out]) {
    viewProjectionInto(_inverse);
    _inverse.invert();
    return _rayThrough(screen.dx, screen.dy, out ?? Ray3D());
  }

  /// The ray through the pixel ([sx], [sy]) into [ray], with [_inverse]
  /// already holding the inverse view-projection.
  Ray3D _rayThrough(double sx, double sy, Ray3D ray) {
    final w = viewportSize.width > 0 ? viewportSize.width : 1.0;
    final h = viewportSize.height > 0 ? viewportSize.height : 1.0;
    final nx = sx / w * 2 - 1, ny = sy / h * 2 - 1;
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

  final Ray3D _ray = Ray3D();

  final PlanarViewVolume _planarVolume = PlanarViewVolume();
  final FrustumViewVolume _frustumVolume = FrustumViewVolume();
  final Matrix4 _volumeMatrix = Matrix4.zero();

  /// What the camera sees: the visible rectangle for a 2-D camera, the
  /// frustum for one in space. The same object each time, refreshed.
  @override
  ViewVolume get viewVolume {
    if (isPlanar) {
      _planarVolume.planarBounds = visibleBounds;
      return _planarVolume;
    }
    viewProjectionInto(_volumeMatrix);
    _frustumVolume.update(_volumeMatrix, visibleBounds);
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

  /// The world area in view, as an axis-aligned box: with a roll
  /// ([rotation]) the screen shows a turned rectangle, and this is the box
  /// around it — what culling must keep. For a camera in space, the part of
  /// the world plane z = 0 its corners see (everything, when a corner misses
  /// it).
  @override
  Rect get visibleBounds {
    if (!isPlanar) return _visibleOnPlane();
    final w = viewportSize.width / zoom, h = viewportSize.height / zoom;
    if (rotation == 0.0) {
      return Rect.fromCenter(center: position, width: w, height: h);
    }
    final c = math.cos(rotation).abs(), s = math.sin(rotation).abs();
    return Rect.fromCenter(
      center: position,
      width: w * c + h * s,
      height: w * s + h * c,
    );
  }

  Rect _visibleOnPlane() {
    final w = viewportSize.width, h = viewportSize.height;
    // One inverse for all four corners.
    viewProjectionInto(_inverse);
    _inverse.invert();
    var l = double.infinity, t = double.infinity;
    var r = double.negativeInfinity, b = double.negativeInfinity;
    for (var corner = 0; corner < 4; corner++) {
      _rayThrough(corner.isOdd ? w : 0, corner < 2 ? 0 : h, _ray);
      final hit = _ray.intersectZ();
      if (hit == null) {
        // A corner that misses the plane sees to the horizon.
        return Rect.fromCenter(center: position, width: 1e9, height: 1e9);
      }
      _ray.atInto(hit, _v);
      l = math.min(l, _v.x);
      t = math.min(t, _v.y);
      r = math.max(r, _v.x);
      b = math.max(b, _v.y);
    }
    return Rect.fromLTRB(l, t, r, b);
  }

  /// Whether the world point [point] is on screen. For a rolled 2-D camera
  /// that is the turned rectangle the screen shows, not the box around it;
  /// otherwise whether [point] lies inside [visibleBounds].
  bool isVisible(Offset point) {
    if (!isPlanar || rotation == 0.0) {
      return visibleBounds.contains(point);
    }
    final s = worldToScreen(point);
    return s.dx >= 0 &&
        s.dx < viewportSize.width &&
        s.dy >= 0 &&
        s.dy < viewportSize.height;
  }

  /// Whether the world rectangle [rect] overlaps [visibleBounds] — for a
  /// rolled camera the box around the screen, so a rectangle near a corner
  /// may count as visible while just off screen. A null [rect] — nothing
  /// known about its size — counts as visible, and an inside-out one (the
  /// bounds of something flipped) counts as the box it spans.
  bool isRectVisible(Rect? rect) {
    if (rect == null) return true;
    final box = rect.left <= rect.right && rect.top <= rect.bottom
        ? rect
        : Rect.fromPoints(rect.topLeft, rect.bottomRight);
    return visibleBounds.overlaps(box);
  }

  /// Back to the origin at zoom 1 with no roll, depth, pitch or yaw, the
  /// default [lens], and every effect removed. [minZoom], [maxZoom] and
  /// [viewportSize] are kept.
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

/// Camera System
///
/// Manages cameras for the game engine: viewport control, coordinate
/// transforms, trauma-based shake, spring motion, world bounds clamping,
/// zoom-to-point, velocity tracking and a pluggable behavior stack.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../interfaces/game_camera.dart';
import 'camera_effects.dart';

// ─── CameraBehavior ──────────────────────────────────────────────────────────

/// Abstract base for pluggable camera behaviors.
///
/// Add to [CameraSystem] via [CameraSystem.addBehavior]. The system calls
/// [update] every frame and auto-removes behaviors when [isComplete] is `true`.
///
/// Concrete implementations live in `camera_behaviors.dart`.
abstract class CameraBehavior {
  /// Called once per frame before [Camera.update].
  void update(Camera camera, double dt);

  /// When `true` the system removes this behavior automatically.
  bool get isComplete;
}

// ─── Camera ──────────────────────────────────────────────────────────────────

/// Camera — viewport control, coordinate transforms, trauma shake, spring
/// motion and visual effects.
///
/// ### Smooth motion
/// By default ([useSpring] = `true`) position and zoom targets use a
/// critically-damped spring ([springStiffness], [springDamping]).  Set
/// [useSpring] = `false` to fall back to the legacy lerp path
/// ([smoothingFactor]).
///
/// ### Trauma shake
/// Call [addTrauma] with a value in [0, 1]; a deterministic noise-based
/// positional + rotational offset decays at [traumaDecayRate] per second.
///
/// ### World bounds
/// Set [worldBounds] to clamp the viewport inside a world rectangle.
///
/// ### Effects
/// Access [effectManager] to attach [CameraEffect] instances.
class Camera implements GameCamera {
  // ── Public fields ─────────────────────────────────────────────────────

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

  /// World-space rectangle the camera will not show outside of.
  /// Set to `null` to disable clamping.
  Rect? worldBounds;

  // ── Spring motion ─────────────────────────────────────────────────────

  /// When `true` (default), position and zoom use a critically-damped spring.
  bool useSpring;

  /// Spring stiffness — higher = snappier. Default = 80.
  double springStiffness;

  /// Spring damping. Default = 18 (≈ 2 × √80: critically damped).
  double springDamping;

  // ── Legacy lerp smoothing (prefer useSpring = true) ───────────────────

  bool smoothing;
  double smoothingFactor;

  // ── Trauma shake ──────────────────────────────────────────────────────

  /// Maximum positional offset (pixels per axis) at full trauma.
  double maxShakeOffset;

  /// Maximum rotational offset (radians) at full trauma.
  double maxShakeAngle;

  /// Rate at which trauma decays per second.
  double traumaDecayRate;

  // ── Effect manager ────────────────────────────────────────────────────

  /// Attach [CameraEffect] instances here (fade, letterbox, motion blur…).
  final CameraEffectManager effectManager = CameraEffectManager();

  // ── Private state ──────────────────────────────────────────────────────

  Offset? _targetPosition;
  double? _targetZoom;
  Offset _springVelocity = Offset.zero;
  double _zoomSpringVelocity = 0.0;

  double _trauma = 0.0;
  double _shakeTime = 0.0;

  Offset _prevPosition = Offset.zero;
  Offset _smoothedVelocity = Offset.zero;

  // ── Constructor ───────────────────────────────────────────────────────

  Camera({
    this.position = Offset.zero,
    this.zoom = 1.0,
    this.rotation = 0.0,
    this.viewportSize = Size.zero,
    this.minZoom = 0.1,
    this.maxZoom = 10.0,
    this.worldBounds,
    this.useSpring = true,
    this.springStiffness = 80.0,
    this.springDamping = 18.0,
    this.maxShakeOffset = 20.0,
    this.maxShakeAngle = 0.05,
    this.traumaDecayRate = 1.0,
    this.smoothing = false,
    this.smoothingFactor = 0.1,
  });

  // ── Position / Zoom control ───────────────────────────────────────────

  /// Set the camera position. When [smooth] = `true` and smoothing is
  /// enabled the camera eases toward the target; otherwise it snaps.
  void setPosition(Offset newPosition, {bool smooth = false}) {
    if (smooth && (useSpring || smoothing)) {
      _targetPosition = newPosition;
    } else {
      position = newPosition;
      _targetPosition = null;
      _springVelocity = Offset.zero;
    }
  }

  /// Set the camera zoom, clamped to [[minZoom], [maxZoom]].
  void setZoom(double newZoom, {bool smooth = false}) {
    final clamped = newZoom.clamp(minZoom, maxZoom);
    if (smooth && (useSpring || smoothing)) {
      _targetZoom = clamped;
    } else {
      zoom = clamped;
      _targetZoom = null;
      _zoomSpringVelocity = 0.0;
    }
  }

  /// Translate the camera by [delta] in world units.
  void moveBy(Offset delta) => position += delta;

  /// Multiply the current zoom by [factor].
  void zoomBy(double factor) => setZoom(zoom * factor);

  /// Alias for [setPosition].
  void lookAt(Offset target, {bool smooth = false}) =>
      setPosition(target, smooth: smooth);

  /// Follow [target] with an optional rectangular [deadZone].
  ///
  /// Movement only begins when the target is outside `deadZone.dx/dy`
  /// around the current camera position.
  void follow(Offset target, {Offset? deadZone, bool smooth = true}) {
    if (deadZone != null) {
      final diff = target - position;
      if (diff.dx.abs() <= deadZone.dx && diff.dy.abs() <= deadZone.dy) {
        return;
      }
    }
    setPosition(target, smooth: smooth);
  }

  /// Zoom toward [worldPoint] so the point stays fixed on screen.
  ///
  /// ```
  /// newPos = worldPoint − (worldPoint − position) × (currentZoom / newZoom)
  /// ```
  void zoomToPoint(
    Offset worldPoint,
    double targetZoom, {
    bool smooth = false,
  }) {
    final newZoom = targetZoom.clamp(minZoom, maxZoom);
    final newPos = worldPoint - (worldPoint - position) * (zoom / newZoom);
    setZoom(newZoom, smooth: smooth);
    setPosition(newPos, smooth: smooth);
  }

  // ── Trauma shake ──────────────────────────────────────────────────────

  /// Add [amount] (0..1) to traumaClamped to 1.  Decays at [traumaDecayRate].
  void addTrauma(double amount) {
    _trauma = (_trauma + amount).clamp(0.0, 1.0);
  }

  /// Current trauma value in [0, 1].
  double get trauma => _trauma;

  /// Convenience wrapper: maps [intensity] pixels to trauma and sets decay
  /// rate so trauma reaches zero in approximately [duration] seconds.
  void shake(double intensity, double duration) {
    addTrauma((intensity / maxShakeOffset).clamp(0.0, 1.0));
    if (duration > 0) traumaDecayRate = 1.0 / duration;
  }

  // ── Camera velocity ───────────────────────────────────────────────────

  /// Low-pass-filtered world-space velocity in pixels per second.
  Offset get velocity => _smoothedVelocity;

  // ── Update ────────────────────────────────────────────────────────────

  void update(double deltaTime) {
    if (deltaTime <= 0) return;
    _updateMotion(deltaTime);
    _applyWorldBounds();
    _updateVelocity(deltaTime);
    _updateTrauma(deltaTime);
    effectManager.update(deltaTime);
  }

  void _updateMotion(double dt) {
    if (_targetPosition != null) {
      if (useSpring) {
        final force = (_targetPosition! - position) * springStiffness;
        _springVelocity += (force - _springVelocity * springDamping) * dt;
        position += _springVelocity * dt;
        if ((_targetPosition! - position).distance < 0.5 &&
            _springVelocity.distance < 0.5) {
          position = _targetPosition!;
          _targetPosition = null;
          _springVelocity = Offset.zero;
        }
      } else {
        final diff = _targetPosition! - position;
        position += diff * smoothingFactor;
        if (diff.distance < 0.1) {
          position = _targetPosition!;
          _targetPosition = null;
        }
      }
    }

    if (_targetZoom != null) {
      if (useSpring) {
        final force = (_targetZoom! - zoom) * springStiffness;
        _zoomSpringVelocity +=
            (force - _zoomSpringVelocity * springDamping) * dt;
        zoom += _zoomSpringVelocity * dt;
        if ((_targetZoom! - zoom).abs() < 0.005 &&
            _zoomSpringVelocity.abs() < 0.005) {
          zoom = _targetZoom!;
          _targetZoom = null;
          _zoomSpringVelocity = 0.0;
        }
      } else {
        final diff = _targetZoom! - zoom;
        zoom += diff * smoothingFactor;
        if (diff.abs() < 0.01) {
          zoom = _targetZoom!;
          _targetZoom = null;
        }
      }
    }
  }

  void _applyWorldBounds() {
    if (worldBounds == null || viewportSize == Size.zero) return;
    final halfW = viewportSize.width / (2 * zoom);
    final halfH = viewportSize.height / (2 * zoom);
    double x = position.dx;
    double y = position.dy;
    if (worldBounds!.width > viewportSize.width / zoom) {
      x = x.clamp(worldBounds!.left + halfW, worldBounds!.right - halfW);
    } else {
      x = worldBounds!.center.dx;
    }
    if (worldBounds!.height > viewportSize.height / zoom) {
      y = y.clamp(worldBounds!.top + halfH, worldBounds!.bottom - halfH);
    } else {
      y = worldBounds!.center.dy;
    }
    position = Offset(x, y);
  }

  void _updateVelocity(double dt) {
    final raw = (position - _prevPosition) * (1.0 / dt);
    _smoothedVelocity = Offset(
      _smoothedVelocity.dx + 0.2 * (raw.dx - _smoothedVelocity.dx),
      _smoothedVelocity.dy + 0.2 * (raw.dy - _smoothedVelocity.dy),
    );
    _prevPosition = position;
  }

  void _updateTrauma(double dt) {
    if (_trauma > 0) {
      _trauma = (_trauma - traumaDecayRate * dt).clamp(0.0, 1.0);
      _shakeTime += dt;
    }
  }

  // Deterministic multi-octave noise in [-1, 1].
  double _noise(int seed, double t) =>
      math.sin(seed * 7919 + t * 3.7) * 0.5 +
      math.sin(seed * 1613 + t * 7.3) * 0.3 +
      math.sin(seed * 3167 + t * 11.1) * 0.2;

  Offset get _shakeOffset {
    if (_trauma <= 0) return Offset.zero;
    final i = _trauma * _trauma;
    return Offset(
      _noise(1, _shakeTime) * maxShakeOffset * i,
      _noise(2, _shakeTime) * maxShakeOffset * i,
    );
  }

  double get _shakeRotation {
    if (_trauma <= 0) return 0.0;
    return _noise(3, _shakeTime) * maxShakeAngle * _trauma * _trauma;
  }

  // ── Canvas transform ──────────────────────────────────────────────────

  @override
  void applyTransform(Canvas canvas, Size size) {
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(zoom, zoom);
    canvas.rotate(rotation + _shakeRotation);
    final off = _shakeOffset;
    canvas.translate(-(position.dx + off.dx), -(position.dy + off.dy));
  }

  // ── Coordinate conversion ─────────────────────────────────────────────

  Offset screenToWorld(Offset screenPos) {
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

  Offset worldToScreen(Offset worldPos) {
    final rel = worldPos - position;
    final c = math.cos(rotation);
    final s = math.sin(rotation);
    final rotated = Offset(rel.dx * c - rel.dy * s, rel.dx * s + rel.dy * c);
    return rotated * zoom +
        Offset(viewportSize.width / 2, viewportSize.height / 2);
  }

  @override
  Rect getVisibleBounds() => Rect.fromCenter(
    center: position,
    width: viewportSize.width / zoom,
    height: viewportSize.height / zoom,
  );

  bool isVisible(Offset point) => getVisibleBounds().contains(point);

  bool isRectVisible(Rect? rect) {
    if (rect == null) return true;
    return getVisibleBounds().overlaps(rect);
  }

  void reset() {
    position = Offset.zero;
    zoom = 1.0;
    rotation = 0.0;
    _targetPosition = null;
    _targetZoom = null;
    _springVelocity = Offset.zero;
    _zoomSpringVelocity = 0.0;
    _trauma = 0.0;
    _shakeTime = 0.0;
    _smoothedVelocity = Offset.zero;
    _prevPosition = Offset.zero;
    effectManager.clearEffects();
  }
}

// ─── CameraSystem ─────────────────────────────────────────────────────────────

/// Manages the [mainCamera] and drives the pluggable behavior stack each frame.
///
/// ```dart
/// cameraSystem.addBehavior(SpringFollowBehavior(target: player.position));
/// final follow = cameraSystem.getBehavior<SpringFollowBehavior>();
/// follow?.updateTarget(player.position);
/// ```
class CameraSystem {
  late Camera mainCamera;
  bool _initialized = false;
  final List<CameraBehavior> _behaviors = [];

  bool get isInitialized => _initialized;

  void initialize() {
    if (_initialized) return;
    mainCamera = Camera(position: Offset.zero, zoom: 1.0);
    _initialized = true;
    debugPrint('Camera System initialized');
  }

  void addBehavior(CameraBehavior behavior) => _behaviors.add(behavior);
  void removeBehavior(CameraBehavior behavior) => _behaviors.remove(behavior);
  void clearBehaviors() => _behaviors.clear();

  /// Return the first behavior of type [T], or `null` if none found.
  T? getBehavior<T extends CameraBehavior>() {
    for (final b in _behaviors) {
      if (b is T) return b;
    }
    return null;
  }

  void update(double deltaTime) {
    if (!_initialized) return;
    for (int i = _behaviors.length - 1; i >= 0; i--) {
      _behaviors[i].update(mainCamera, deltaTime);
      if (_behaviors[i].isComplete) _behaviors.removeAt(i);
    }
    mainCamera.update(deltaTime);
  }

  void dispose() {
    _behaviors.clear();
    _initialized = false;
  }
}

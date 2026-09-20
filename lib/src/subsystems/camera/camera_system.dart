/// Camera System
///
/// The output camera — what everything renders through — and the brain that
/// decides what it shows.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../interfaces/game_camera.dart';
import 'camera_brain.dart';
import 'camera_effects.dart';
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
class Camera implements GameCamera {
  Camera({
    this.position = Offset.zero,
    this.zoom = 1.0,
    this.rotation = 0.0,
    this.viewportSize = Size.zero,
    this.minZoom = 0.1,
    this.maxZoom = 10.0,
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

  /// Attach [CameraEffect] instances here (fade, letterbox, motion blur…).
  final CameraEffectManager effectManager = CameraEffectManager();

  // ── State ─────────────────────────────────────────────────────────────

  /// What this camera shows, as a value.
  CameraState get state =>
      CameraState(position: position, zoom: zoom, rotation: rotation);

  /// Shows [state]. Zoom is clamped to [[minZoom], [maxZoom]].
  void apply(CameraState state) {
    position = state.position;
    zoom = state.zoom.clamp(minZoom, maxZoom);
    rotation = state.rotation;
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

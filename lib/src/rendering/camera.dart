/// Camera System
///
/// Manages the viewport and camera transformations for rendering.
library;

import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Camera class for controlling the viewport
///
/// The camera determines what part of the world is visible and how it's displayed.
class Camera {
  /// Camera position in world space
  Offset position;

  /// Zoom level (1.0 = normal, >1.0 = zoom in, <1.0 = zoom out)
  double zoom;

  /// Rotation in radians
  double rotation;

  /// Viewport size (set by rendering engine)
  Size viewportSize;

  /// Minimum zoom level
  double minZoom;

  /// Maximum zoom level
  double maxZoom;

  /// Whether to smooth camera movement
  bool smoothing;

  /// Smoothing factor (0.0 - 1.0, higher = smoother but more lag)
  double smoothingFactor;

  /// Target position for smooth movement
  Offset? _targetPosition;

  /// Target zoom for smooth movement
  double? _targetZoom;

  /// Create a camera
  Camera({
    this.position = Offset.zero,
    this.zoom = 1.0,
    this.rotation = 0.0,
    this.viewportSize = Size.zero,
    this.minZoom = 0.1,
    this.maxZoom = 10.0,
    this.smoothing = false,
    this.smoothingFactor = 0.1,
  });

  /// Set the camera position
  void setPosition(Offset newPosition, {bool smooth = false}) {
    if (smooth && smoothing) {
      _targetPosition = newPosition;
    } else {
      position = newPosition;
      _targetPosition = null;
    }
  }

  /// Set the camera zoom
  void setZoom(double newZoom, {bool smooth = false}) {
    final clampedZoom = newZoom.clamp(minZoom, maxZoom);
    if (smooth && smoothing) {
      _targetZoom = clampedZoom;
    } else {
      zoom = clampedZoom;
      _targetZoom = null;
    }
  }

  /// Move the camera by an offset
  void moveBy(Offset delta) {
    position += delta;
  }

  /// Zoom by a factor
  void zoomBy(double factor) {
    setZoom(zoom * factor);
  }

  /// Update camera (for smooth movement)
  void update(double deltaTime) {
    if (_targetPosition != null) {
      final diff = _targetPosition! - position;
      position += diff * smoothingFactor;

      // Stop when close enough
      if (diff.distance < 0.1) {
        position = _targetPosition!;
        _targetPosition = null;
      }
    }

    if (_targetZoom != null) {
      final diff = _targetZoom! - zoom;
      zoom += diff * smoothingFactor;

      // Stop when close enough
      if ((diff).abs() < 0.01) {
        zoom = _targetZoom!;
        _targetZoom = null;
      }
    }
  }

  /// Look at a specific point
  void lookAt(Offset target, {bool smooth = false}) {
    setPosition(target, smooth: smooth);
  }

  /// Apply camera transform to canvas
  void applyTransform(Canvas canvas, Size size) {
    // Translate to center of viewport
    canvas.translate(size.width / 2, size.height / 2);

    // Apply zoom
    canvas.scale(zoom, zoom);

    // Apply rotation
    canvas.rotate(rotation);

    // Translate by camera position (inverted)
    canvas.translate(-position.dx, -position.dy);
  }

  /// Convert screen coordinates to world coordinates
  Offset screenToWorld(Offset screenPos) {
    // Step 1: Adjust for viewport center (origin is at center of screen)
    final centered =
        screenPos - Offset(viewportSize.width / 2, viewportSize.height / 2);

    // Step 2: Apply inverse zoom
    final scaled = centered / zoom;

    // Step 3: Apply inverse rotation (rotate by -rotation)
    final cos = math.cos(-rotation);
    final sin = math.sin(-rotation);
    final rotated = Offset(
      scaled.dx * cos - scaled.dy * sin,
      scaled.dx * sin + scaled.dy * cos,
    );

    // Step 4: Add camera position (translate to world space)
    return rotated + position;
  }

  /// Convert world coordinates to screen coordinates
  Offset worldToScreen(Offset worldPos) {
    // Step 1: Subtract camera position (translate to camera space)
    final relative = worldPos - position;

    // Step 2: Apply rotation
    final cos = math.cos(rotation);
    final sin = math.sin(rotation);
    final rotated = Offset(
      relative.dx * cos - relative.dy * sin,
      relative.dx * sin + relative.dy * cos,
    );

    // Step 3: Apply zoom
    final scaled = rotated * zoom;

    // Step 4: Adjust for viewport center (origin is at center of screen)
    return scaled + Offset(viewportSize.width / 2, viewportSize.height / 2);
  }

  /// Get the visible world bounds
  Rect getVisibleBounds() {
    final halfWidth = viewportSize.width / (2 * zoom);
    final halfHeight = viewportSize.height / (2 * zoom);

    return Rect.fromCenter(
      center: position,
      width: halfWidth * 2,
      height: halfHeight * 2,
    );
  }

  /// Check if a point is visible
  bool isVisible(Offset point) {
    return getVisibleBounds().contains(point);
  }

  /// Follow a target with optional dead zone
  void follow(Offset target, {Offset? deadZone, bool smooth = true}) {
    if (deadZone != null) {
      final diff = target - position;
      if (diff.dx.abs() > deadZone.dx || diff.dy.abs() > deadZone.dy) {
        setPosition(target, smooth: smooth);
      }
    } else {
      setPosition(target, smooth: smooth);
    }
  }

  /// Shake the camera
  void shake(double intensity, double duration) {
    // TODO: Implement camera shake
    // This would need integration with the time system
  }

  /// Reset camera to default values
  void reset() {
    position = Offset.zero;
    zoom = 1.0;
    rotation = 0.0;
    _targetPosition = null;
    _targetZoom = null;
  }
}

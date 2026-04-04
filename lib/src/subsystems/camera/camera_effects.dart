/// Camera Effects
///
/// Visual effect overlays applied in world-space and screen-space by the
/// camera's [CameraEffectManager].
///
/// Effects participate in three rendering phases:
///  - [CameraEffect.preRender]  — before the world `canvas.save()` (push saveLayer)
///  - [CameraEffect.postRender] — after `canvas.restore()` in reverse order (pop saveLayer)
///  - [CameraEffect.render]     — after post-process passes (screen-space overlay)
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

// ─── CameraEffect base ───────────────────────────────────────────────────────

/// Abstract base class for camera visual effects.
///
/// Subclass and override any combination of [preRender], [postRender], and
/// [render] to participate in the rendering pipeline.
abstract class CameraEffect {
  /// Update internal state once per frame.
  void update(double dt) {}

  /// Called before the world `canvas.save()` + camera transform.
  ///
  /// Push a `saveLayer` here to wrap the entire world render (e.g. motion blur).
  void preRender(Canvas canvas, Size size) {}

  /// Called after `canvas.restore()`, in **reverse** order of [preRender] calls.
  ///
  /// Pop any `saveLayer` pushed in [preRender] here.
  void postRender(Canvas canvas, Size size) {}

  /// Called after all post-process passes for pure screen-space overlays
  /// (e.g. fade-to-black, letterbox bars).
  void render(Canvas canvas, Size size) {}

  /// When `true` the [CameraEffectManager] removes this effect automatically.
  bool get isComplete;
}

// ─── CameraEffectManager ─────────────────────────────────────────────────────

/// Owns a list of [CameraEffect] instances and routes rendering calls each frame.
class CameraEffectManager {
  final List<CameraEffect> _effects = [];

  /// Add [effect] to the manager.
  void addEffect(CameraEffect effect) => _effects.add(effect);

  /// Remove [effect] from the manager.
  void removeEffect(CameraEffect effect) => _effects.remove(effect);

  /// Remove all effects.
  void clearEffects() => _effects.clear();

  /// Whether there are any active effects.
  bool get hasEffects => _effects.isNotEmpty;

  /// Update all effects; auto-removes completed ones.
  void update(double dt) {
    for (int i = _effects.length - 1; i >= 0; i--) {
      _effects[i].update(dt);
      if (_effects[i].isComplete) _effects.removeAt(i);
    }
  }

  /// Forward: call [CameraEffect.preRender] on each effect in list order.
  void preRender(Canvas canvas, Size size) {
    for (final e in _effects) {
      e.preRender(canvas, size);
    }
  }

  /// Reverse: call [CameraEffect.postRender] in LIFO order.
  void postRender(Canvas canvas, Size size) {
    for (int i = _effects.length - 1; i >= 0; i--) {
      _effects[i].postRender(canvas, size);
    }
  }

  /// Forward: call [CameraEffect.render] on each effect in list order.
  void render(Canvas canvas, Size size) {
    for (final e in _effects) {
      e.render(canvas, size);
    }
  }
}

// ─── ScreenFadeEffect ────────────────────────────────────────────────────────

/// Full-screen colour overlay with animated alpha.
///
/// Three entry points:
/// - [fadeIn]  — animate alpha 0 → 1 (fade to [color])
/// - [fadeOut] — animate alpha from current → 0 (clear screen)
/// - [flash]   — instantly pop to full [color], hold, then fade out
///
/// ```dart
/// final fade = ScreenFadeEffect();
/// camera.effectManager.addEffect(fade);
/// fade.flash(Colors.white, holdDuration: 0.1, fadeDuration: 0.4);
/// ```
class ScreenFadeEffect extends CameraEffect {
  /// The overlay colour (alpha channel is driven by the animation).
  Color color;

  double _alpha = 0.0;
  double _fromAlpha = 0.0;
  double _toAlpha = 0.0;
  double _duration = 0.0;
  double _elapsed = 0.0;
  bool _animating = false;

  // Flash hold state
  bool _inHold = false;
  double _holdRemaining = 0.0;
  double _postHoldFadeDuration = 0.0;

  final Paint _paint = Paint();

  /// Create a [ScreenFadeEffect] with an optional [color] (defaults to black).
  ScreenFadeEffect({this.color = Colors.black});

  /// Fade to [color] over [duration] seconds.
  void fadeIn(double duration, {Color? color}) {
    if (color != null) this.color = color;
    _startAnim(_alpha, 1.0, duration);
  }

  /// Fade the overlay out over [duration] seconds.
  void fadeOut(double duration) => _startAnim(_alpha, 0.0, duration);

  /// Instantly show [flashColor], hold, then fade out.
  void flash(
    Color flashColor, {
    double holdDuration = 0.1,
    double fadeDuration = 0.3,
  }) {
    color = flashColor;
    _alpha = 1.0;
    _animating = false;
    _inHold = true;
    _holdRemaining = holdDuration;
    _postHoldFadeDuration = fadeDuration;
  }

  void _startAnim(double from, double to, double duration) {
    _fromAlpha = from;
    _toAlpha = to;
    _duration = duration;
    _elapsed = 0.0;
    _animating = true;
    _inHold = false;
  }

  @override
  void update(double dt) {
    if (_inHold) {
      _holdRemaining -= dt;
      if (_holdRemaining <= 0) {
        _inHold = false;
        _startAnim(1.0, 0.0, _postHoldFadeDuration);
      }
      return;
    }
    if (!_animating) return;
    _elapsed += dt;
    final t = _duration > 0 ? (_elapsed / _duration).clamp(0.0, 1.0) : 1.0;
    _alpha = _fromAlpha + (_toAlpha - _fromAlpha) * t;
    if (t >= 1.0) {
      _alpha = _toAlpha;
      _animating = false;
    }
  }

  @override
  void render(Canvas canvas, Size size) {
    if (_alpha < 0.001) return;
    _paint.color = color.withValues(alpha: _alpha.clamp(0.0, 1.0));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), _paint);
  }

  @override
  bool get isComplete => !_animating && !_inHold && _alpha <= 0.0;
}

// ─── LetterboxEffect ─────────────────────────────────────────────────────────

/// Animated cinematic letterbox — solid bars at the top and bottom of the screen.
///
/// ```dart
/// final lb = LetterboxEffect();
/// camera.effectManager.addEffect(lb);
/// lb.show(0.5);   // slide bars in over 0.5 s
/// lb.hide(0.5);   // slide bars out over 0.5 s
/// ```
class LetterboxEffect extends CameraEffect {
  /// Target bar height as a fraction of screen height (e.g. `0.1` = 10%).
  double barHeightFraction;

  /// Bar fill colour.
  Color color;

  double _current = 0.0;
  double _from = 0.0;
  double _target = 0.0;
  double _duration = 0.0;
  double _elapsed = 0.0;
  bool _animating = false;
  bool _active = false;

  final Paint _paint = Paint();

  /// Create a [LetterboxEffect].
  ///
  /// [barHeightFraction] — fraction of screen height each bar occupies (default 0.1).
  LetterboxEffect({this.barHeightFraction = 0.1, this.color = Colors.black});

  /// Animate bars in over [duration] seconds.
  ///
  /// Optionally override [fraction] to use a different bar size.
  void show(double duration, {double? fraction}) {
    if (fraction != null) barHeightFraction = fraction;
    _active = true;
    _startAnim(_current, barHeightFraction, duration);
  }

  /// Animate bars out over [duration] seconds.
  void hide(double duration) => _startAnim(_current, 0.0, duration);

  void _startAnim(double from, double to, double duration) {
    _from = from;
    _target = to;
    _duration = duration;
    _elapsed = 0.0;
    _animating = true;
  }

  @override
  void update(double dt) {
    if (!_animating) return;
    _elapsed += dt;
    final t = _duration > 0 ? (_elapsed / _duration).clamp(0.0, 1.0) : 1.0;
    _current = _from + (_target - _from) * t;
    if (t >= 1.0) {
      _current = _target;
      _animating = false;
      if (_current <= 0.0) _active = false;
    }
  }

  @override
  void render(Canvas canvas, Size size) {
    if (_current < 0.001) return;
    final h = _current * size.height;
    _paint.color = color;
    // Top bar
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, h), _paint);
    // Bottom bar
    canvas.drawRect(Rect.fromLTWH(0, size.height - h, size.width, h), _paint);
  }

  @override
  bool get isComplete => !_active && !_animating;
}

// ─── MotionBlurEffect ─────────────────────────────────────────────────────────

/// Directional motion blur driven by camera velocity.
///
/// Wraps the world render in a `saveLayer` with a directional
/// [ui.ImageFilter.blur] oriented along the camera's movement direction.
///
/// ```dart
/// final blur = MotionBlurEffect(velocityFn: () => camera.velocity);
/// camera.effectManager.addEffect(blur);
/// ```
///
/// The effect is permanent (never auto-removed). Call
/// [CameraEffectManager.removeEffect] to stop it.
class MotionBlurEffect extends CameraEffect {
  /// Returns the camera's current world-space velocity (pixels/s).
  ///
  /// Typically `() => camera.velocity` where `camera` is the scene's [Camera].
  final Offset Function() velocityFn;

  /// Minimum speed (world px/s) before any blur is applied.
  final double minSpeed;

  /// Maximum blur sigma (pixels) achieved at [maxSpeed].
  final double maxBlurSigma;

  /// Speed that maps to [maxBlurSigma].
  final double maxSpeed;

  bool _didPushLayer = false;

  /// Create a [MotionBlurEffect].
  MotionBlurEffect({
    required this.velocityFn,
    this.minSpeed = 150.0,
    this.maxBlurSigma = 6.0,
    this.maxSpeed = 800.0,
  });

  @override
  void preRender(Canvas canvas, Size size) {
    _didPushLayer = false;
    final vel = velocityFn();
    final speed = vel.distance;
    if (speed < minSpeed) return;

    final t = ((speed - minSpeed) / (maxSpeed - minSpeed)).clamp(0.0, 1.0);
    final sigma = maxBlurSigma * t;
    final nx = vel.dx / speed;
    final ny = vel.dy / speed;
    final sigmaX = (sigma * nx.abs()).clamp(0.0, maxBlurSigma);
    final sigmaY = (sigma * ny.abs()).clamp(0.0, maxBlurSigma);
    if (sigmaX < 0.5 && sigmaY < 0.5) return;

    canvas.saveLayer(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..imageFilter = ui.ImageFilter.blur(sigmaX: sigmaX, sigmaY: sigmaY),
    );
    _didPushLayer = true;
  }

  @override
  void postRender(Canvas canvas, Size size) {
    if (_didPushLayer) {
      canvas.restore();
      _didPushLayer = false;
    }
  }

  @override
  bool get isComplete => false; // Permanent until explicitly removed.
}

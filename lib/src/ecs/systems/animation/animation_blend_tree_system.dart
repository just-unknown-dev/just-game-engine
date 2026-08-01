/// Animation Blend Tree System
///
/// Advances every entity's `AnimationBlendTreeComponent` — resolving
/// `play()` requests into crossfades, evaluating blend-tree weights,
/// advancing phase-synchronized playback, and writing the resulting
/// weighted frames into the entity's `BlendSprite`. See
/// `ANIMATION_BLEND_TREE.md` at the package root for the algorithm this
/// implements.
library;

import 'package:flutter/painting.dart' show Offset;

import '../../ecs.dart';
import '../../components/components.dart';
import '../../../subsystems/animation/blend/blend.dart';
import '../../../subsystems/rendering/impl/blend_sprite.dart';
import '../system_priorities.dart';

class AnimationBlendTreeSystem extends System {
  @override
  int get priority => SystemPriorities.animation;

  @override
  List<Type> get requiredComponents => [
    RenderableComponent,
    AnimationBlendTreeComponent,
  ];

  /// Layers below this weight are skipped from the actual draw call — a
  /// bounded, imperceptible optimization: alphas for layers drawn *after* a
  /// skipped one are still computed from the full, un-pruned weight list
  /// (see [BlendCompositor]), so skipping only ever discards that layer's
  /// own negligible contribution, never distorts the rest.
  static const double _minDrawWeight = 0.004;

  @override
  void update(double deltaTime) {
    forEach((entity) {
      final renderable =
          entity.getComponent<RenderableComponent>()!.renderable;
      if (renderable is! BlendSprite) return;
      final c = entity.getComponent<AnimationBlendTreeComponent>()!;

      _resolvePlayRequest(c);

      final currentState = c.machine.states[c.currentStateName]!;
      final currentWeighted = _evaluateMotion(currentState.motion, c);
      c.currentPhase = _advancePhase(
        c.currentPhase,
        _cycleRate(currentWeighted, c.clips),
        deltaTime,
        loop: currentState.loop,
      );

      var merged = [
        for (final (clip, w) in currentWeighted) (clip, w, c.currentPhase),
      ];

      if (c.isTransitioning) {
        final targetState = c.machine.states[c.targetStateName!]!;
        final targetWeighted = _evaluateMotion(targetState.motion, c);
        c.targetPhase = _advancePhase(
          c.targetPhase,
          _cycleRate(targetWeighted, c.clips),
          deltaTime,
          loop: targetState.loop,
        );

        c.transitionElapsed += deltaTime;
        final t = c.transitionDuration > 0
            ? (c.transitionElapsed / c.transitionDuration).clamp(0.0, 1.0)
            : 1.0;

        merged = [
          for (final (clip, w, p) in merged) (clip, w * (1.0 - t), p),
          for (final (clip, w) in targetWeighted) (clip, w * t, c.targetPhase),
        ];

        if (t >= 1.0) {
          c.currentStateName = c.targetStateName!;
          c.currentPhase = c.targetPhase;
          c.targetStateName = null;
          c.transitionElapsed = 0.0;
        }
      }

      _composite(c, merged, renderable);
    });
  }

  // ── Play-request resolution ──────────────────────────────────────────────

  void _resolvePlayRequest(AnimationBlendTreeComponent c) {
    final requested = c.requestedState;
    if (requested == null) return;
    c.requestedState = null;
    final restart = c.requestedRestart;
    c.requestedRestart = false;

    if (!restart) {
      if (!c.isTransitioning && requested == c.currentStateName) {
        return; // already playing this
      }
      if (c.isTransitioning && requested == c.targetStateName) {
        return; // already crossfading toward this
      }
    }

    if (restart && requested == c.currentStateName && !c.isTransitioning) {
      // Restart-in-place: no crossfade target needed, just reset phase.
      c.currentPhase = 0.0;
      return;
    }

    if (c.isTransitioning) {
      // Mid-transition re-request: collapse to whichever side was visually
      // dominant rather than blending three states at once — see
      // ANIMATION_BLEND_TREE.md, "transition-interrupt rule".
      final t = c.transitionDuration > 0
          ? (c.transitionElapsed / c.transitionDuration).clamp(0.0, 1.0)
          : 1.0;
      if (t >= 0.5) {
        c.currentStateName = c.targetStateName!;
        c.currentPhase = c.targetPhase;
      }
      c.targetStateName = null;
      c.transitionElapsed = 0.0;

      if (requested == c.currentStateName && !restart) return;
    }

    c.targetStateName = requested;
    c.targetPhase = 0.0;
    c.transitionElapsed = 0.0;
    c.transitionDuration = c.machine.durationFor(c.currentStateName, requested);
  }

  // ── Blend-tree evaluation ────────────────────────────────────────────────

  /// Resolves [motion] against [c]'s current parameter values into weighted
  /// clip contributions (summing to 1.0). `switch`es exhaustively over the
  /// sealed [BlendMotion] hierarchy.
  List<(String clip, double weight)> _evaluateMotion(
    BlendMotion motion,
    AnimationBlendTreeComponent c,
  ) {
    switch (motion) {
      case ClipMotion m:
        return [(m.clip, 1.0)];

      case BlendTree1DMotion m:
        final weights = m.space.evaluate(c.getFloat(m.parameter));
        return [
          for (var i = 0; i < m.children.length; i++)
            (m.children[i].clip, weights[i]),
        ];

      case BlendTree2DMotion m:
        final query = Offset(
          c.getFloat(m.parameterX),
          c.getFloat(m.parameterY),
        );
        final weights = m.space.evaluate(query);
        return [
          for (var i = 0; i < m.children.length; i++)
            (m.children[i].clip, weights[i]),
        ];
    }
  }

  /// Weighted-average loop frequency (cycles/second) of the currently
  /// contributing clips — see "Phase synchronization" in
  /// `ANIMATION_BLEND_TREE.md`.
  double _cycleRate(
    List<(String clip, double weight)> weighted,
    Map<String, BlendClip> clips,
  ) {
    var rate = 0.0;
    for (final (clipName, weight) in weighted) {
      if (weight <= 0) continue;
      final clip = clips[clipName];
      if (clip == null || clip.frameCount <= 0) continue;
      rate += weight * (clip.fps / clip.frameCount);
    }
    return rate;
  }

  /// Advances a normalized `[0,1)` phase by `deltaTime * rate` cycles,
  /// wrapping while [loop] and clamping (not wrapping) otherwise — the same
  /// rate-based formula covers both looping states and one-shot states
  /// (for a one-shot `ClipMotion`, `rate == 1/clipDuration`, so this is
  /// exactly `elapsed/duration` clamped at 1).
  double _advancePhase(
    double phase,
    double rate,
    double deltaTime, {
    required bool loop,
  }) {
    final next = phase + deltaTime * rate;
    if (!loop) return next.clamp(0.0, 1.0);
    if (!next.isFinite) return 0.0;
    return next % 1.0;
  }

  int _frameIndexFor(BlendClip clip, double phase) {
    if (clip.frameCount <= 0) return 0;
    final idx = (phase * clip.frameCount).floor();
    return idx.clamp(0, clip.frameCount - 1);
  }

  // ── Compositing ───────────────────────────────────────────────────────────

  void _composite(
    AnimationBlendTreeComponent c,
    List<(String clip, double weight, double phase)> merged,
    BlendSprite sprite,
  ) {
    final alphas = BlendCompositor.cumulativeAlphas([
      for (final (_, w, _) in merged) w,
    ]);

    sprite.layers.clear();
    for (var i = 0; i < merged.length; i++) {
      final (clipName, weight, phase) = merged[i];
      if (weight < _minDrawWeight) continue;

      final clip = c.clips[clipName];
      final source = clip?.frameSource;
      final image = source?.image;
      if (clip == null || source == null || image == null) continue;

      sprite.layers.add(
        BlendLayer(
          image: image,
          sourceRect: source.frameRect(
            _frameIndexFor(clip, phase),
            c.directionRow,
          ),
          alpha: alphas[i],
        ),
      );
    }
  }
}

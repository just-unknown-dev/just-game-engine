part of '../effect_system.dart';

/// Animates the [Renderable.opacity] of an entity's [RenderableComponent]
/// from a starting alpha to [to] over [durationTicks] ticks.
///
/// Opacity is clamped to `[0.0, 1.0]` after each delta application.
///
/// The entity must have a [RenderableComponent]; if absent, the effect is
/// a no-op. Applies an **additive delta** per tick so multiple [FadeEffect]s
/// stack — two simultaneous fades contribute the sum of their opacity deltas.
///
/// ```dart
/// // Fade out:
/// FadeEffect(to: 0.0, durationTicks: 60, easing: EasingType.easeInQuad)
///
/// // Fade in from black:
/// FadeEffect(from: 0.0, to: 1.0, durationTicks: 30)
/// ```
class FadeEffect extends DeterministicEffect {
  /// Explicit start opacity `[0, 1]`. When `null` the entity's current
  /// [Renderable.opacity] is captured on the first tick.
  final double? from;

  /// Target opacity `[0, 1]`.
  final double to;

  /// Easing curve.
  final EasingType easing;

  double? _capturedFrom;

  FadeEffect({
    required this.to,
    this.from,
    this.easing = EasingType.linear,
    super.durationTicks = 30,
    super.loop,
    super.onComplete,
  }) : assert(to >= 0.0 && to <= 1.0, 'FadeEffect.to must be in [0, 1]');

  @override
  void applyTick(EffectContext ctx, int prevElapsed, int currElapsed) {
    final renderable = ctx.getComponent<RenderableComponent>();
    if (renderable == null) return;

    if (prevElapsed == 0) {
      _capturedFrom = from ?? renderable.renderable.opacity;
    }
    final effectiveFrom = _capturedFrom;
    if (effectiveFrom == null) return;

    final totalDelta = to - effectiveFrom;
    final prevEased = EffectEasings.resolve(easing, tAt(prevElapsed));
    final currEased = EffectEasings.resolve(easing, tAt(currElapsed));
    renderable.renderable.opacity =
        (renderable.renderable.opacity + totalDelta * (currEased - prevEased))
            .clamp(0.0, 1.0);
  }

  @override
  void reset() {
    super.reset();
    _capturedFrom = null;
  }

  @override
  String get effectType => 'fade';

  @override
  Map<String, dynamic> toJson() => {
    'to': to,
    if (from != null) 'from': from,
    if (_capturedFrom != null) 'capturedFrom': _capturedFrom,
    'easing': easing.name,
    'durationTicks': durationTicks,
    'loop': loop,
  };

  factory FadeEffect._fromJson(Map<String, dynamic> json) {
    final effect = FadeEffect(
      to: (json['to'] as num).toDouble(),
      from: json['from'] != null ? (json['from'] as num).toDouble() : null,
      easing: EasingType.values.byName(json['easing'] as String),
      durationTicks: json['durationTicks'] as int,
      loop: (json['loop'] as bool?) ?? false,
    );
    if (json['capturedFrom'] != null) {
      effect._capturedFrom = (json['capturedFrom'] as num).toDouble();
    }
    return effect;
  }
}

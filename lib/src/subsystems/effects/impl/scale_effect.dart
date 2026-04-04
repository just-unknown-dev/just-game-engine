part of '../effect_system.dart';

/// Animates an entity's [TransformComponent.scale] from its captured start
/// to [to] over [durationTicks] ticks.
///
/// Applies an **additive delta** each tick. Two simultaneous [ScaleEffect]s
/// will sum their scale contributions additively.
///
/// ```dart
/// // Grow from current scale to 2×:
/// ScaleEffect(to: 2.0, durationTicks: 45, easing: EasingType.easeOutBack)
/// ```
class ScaleEffect extends DeterministicEffect {
  /// Explicit start scale. When `null` the entity's current scale is
  /// captured on the first tick.
  final double? from;

  /// Target scale value.
  final double to;

  /// Easing curve.
  final EasingType easing;

  double? _capturedFrom;

  ScaleEffect({
    required this.to,
    this.from,
    this.easing = EasingType.linear,
    super.durationTicks = 30,
    super.loop,
    super.onComplete,
  });

  @override
  void applyTick(EffectContext ctx, int prevElapsed, int currElapsed) {
    final transform = ctx.getComponent<TransformComponent>();
    if (transform == null) return;

    if (prevElapsed == 0) {
      _capturedFrom = from ?? transform.scale;
    }
    final effectiveFrom = _capturedFrom;
    if (effectiveFrom == null) return;

    final totalDelta = to - effectiveFrom;
    final prevEased = EffectEasings.resolve(easing, tAt(prevElapsed));
    final currEased = EffectEasings.resolve(easing, tAt(currElapsed));
    transform.scale += totalDelta * (currEased - prevEased);
  }

  @override
  void reset() {
    super.reset();
    _capturedFrom = null;
  }

  @override
  String get effectType => 'scale';

  @override
  Map<String, dynamic> toJson() => {
    'to': to,
    if (from != null) 'from': from,
    if (_capturedFrom != null) 'capturedFrom': _capturedFrom,
    'easing': easing.name,
    'durationTicks': durationTicks,
    'loop': loop,
  };

  factory ScaleEffect._fromJson(Map<String, dynamic> json) {
    final effect = ScaleEffect(
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

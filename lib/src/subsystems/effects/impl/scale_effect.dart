part of '../effect_system.dart';

/// Animates an entity's [TransformComponent.scale] from its captured start
/// to [to] over [durationTicks] ticks.
///
/// Applies an **additive delta** each tick. Two simultaneous [ScaleEffect]s
/// will sum their scale contributions additively.
///
/// ```dart
/// // Grow from current scale to 2×:
/// ScaleEffect(to: 2.0, durationTicks: 45, easing: EasingType.easeOutCubic)
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

  /// Scales uniformly to [to] over [durationTicks] ticks (30 by default),
  /// along [easing] (linear by default), starting from [from] or, when that
  /// is null, from the mean of the entity's X and Y scale on the first
  /// tick. The same change goes onto X, Y and Z.
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

    final scale = transform.scale;
    if (prevElapsed == 0) {
      // The size, whatever the mirroring: a flipped sprite (x < 0) scales
      // as big as an unflipped one and stays flipped.
      _capturedFrom = from ?? (scale.x.abs() + scale.y.abs()) / 2;
    }
    final effectiveFrom = _capturedFrom;
    if (effectiveFrom == null) return;

    final totalDelta = to - effectiveFrom;
    final prevEased = easing.transform(tAt(prevElapsed));
    final currEased = easing.transform(tAt(currElapsed));
    final delta = totalDelta * (currEased - prevEased);
    scale.x += _sign(scale.x) * delta;
    scale.y += _sign(scale.y) * delta;
    scale.z += _sign(scale.z) * delta;
  }

  static double _sign(double v) => v < 0 ? -1.0 : 1.0;

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

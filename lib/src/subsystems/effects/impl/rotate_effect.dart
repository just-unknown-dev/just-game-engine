part of '../effect_system.dart';

/// Animates an entity's [TransformComponent.rotation] from its captured
/// start to [to] (radians) over [durationTicks] ticks.
///
/// Applies an **additive delta** each tick. Positive values rotate clockwise
/// in Flutter's coordinate system.
///
/// ```dart
/// // Spin 360° over 120 ticks:
/// RotateEffect(to: 2 * math.pi, durationTicks: 120, loop: true)
/// ```
class RotateEffect extends DeterministicEffect {
  /// Explicit start angle in radians. When `null` the entity's current
  /// [TransformComponent.rotation] is captured on the first tick.
  final double? from;

  /// Target rotation in radians.
  final double to;

  /// Easing curve.
  final EasingType easing;

  double? _capturedFrom;

  RotateEffect({
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
      _capturedFrom = from ?? transform.rotation;
    }
    final effectiveFrom = _capturedFrom;
    if (effectiveFrom == null) return;

    final totalDelta = to - effectiveFrom;
    final prevEased = EffectEasings.resolve(easing, tAt(prevElapsed));
    final currEased = EffectEasings.resolve(easing, tAt(currElapsed));
    transform.rotation += totalDelta * (currEased - prevEased);
  }

  @override
  void reset() {
    super.reset();
    _capturedFrom = null;
  }

  @override
  String get effectType => 'rotate';

  @override
  Map<String, dynamic> toJson() => {
    'to': to,
    if (from != null) 'from': from,
    if (_capturedFrom != null) 'capturedFrom': _capturedFrom,
    'easing': easing.name,
    'durationTicks': durationTicks,
    'loop': loop,
  };

  factory RotateEffect._fromJson(Map<String, dynamic> json) {
    final effect = RotateEffect(
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

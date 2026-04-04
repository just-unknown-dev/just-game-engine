part of '../effect_system.dart';

/// Translates an entity's position from its captured start to [to] over
/// [durationTicks] ticks.
///
/// Applies an **additive delta** each tick. Two simultaneous [MoveEffect]s
/// accumulate correctly on the same entity.
///
/// ```dart
/// // Move to an absolute world position:
/// MoveEffect(to: Offset(400, 200), durationTicks: 60)
///
/// // Move from a known start (ignoring current position):
/// MoveEffect(from: Offset(0, 0), to: Offset(400, 200), durationTicks: 60)
/// ```
class MoveEffect extends DeterministicEffect {
  /// Explicit start position. When `null` the entity's current
  /// [TransformComponent.position] is captured on the first tick.
  final Offset? from;

  /// Target world position.
  final Offset to;

  /// Easing curve applied to normalised progress.
  final EasingType easing;

  // Runtime-captured baseline — set on first applyTick call.
  Offset? _capturedFrom;

  MoveEffect({
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

    // Capture baseline on the first tick of this run (prevElapsed == 0).
    if (prevElapsed == 0) {
      _capturedFrom = from ?? transform.position;
    }
    final effectiveFrom = _capturedFrom;
    if (effectiveFrom == null) return;

    final totalDelta = to - effectiveFrom;
    final prevEased = EffectEasings.resolve(easing, tAt(prevElapsed));
    final currEased = EffectEasings.resolve(easing, tAt(currElapsed));
    transform.position += totalDelta * (currEased - prevEased);
  }

  @override
  void reset() {
    super.reset();
    _capturedFrom = null;
  }

  @override
  String get effectType => 'move';

  @override
  Map<String, dynamic> toJson() => {
    'to': [to.dx, to.dy],
    if (from != null) 'from': [from!.dx, from!.dy],
    if (_capturedFrom != null)
      'capturedFrom': [_capturedFrom!.dx, _capturedFrom!.dy],
    'easing': easing.name,
    'durationTicks': durationTicks,
    'loop': loop,
  };

  factory MoveEffect._fromJson(Map<String, dynamic> json) {
    final toList = json['to'] as List;
    final fromList = json['from'] as List?;
    final effect = MoveEffect(
      to: Offset((toList[0] as num).toDouble(), (toList[1] as num).toDouble()),
      from: fromList != null
          ? Offset(
              (fromList[0] as num).toDouble(),
              (fromList[1] as num).toDouble(),
            )
          : null,
      easing: EasingType.values.byName(json['easing'] as String),
      durationTicks: json['durationTicks'] as int,
      loop: (json['loop'] as bool?) ?? false,
    );
    final capturedList = json['capturedFrom'] as List?;
    if (capturedList != null) {
      effect._capturedFrom = Offset(
        (capturedList[0] as num).toDouble(),
        (capturedList[1] as num).toDouble(),
      );
    }
    return effect;
  }
}

part of '../effect_system.dart';

/// Translates an entity's position from its captured start to [to] over
/// [durationTicks] ticks.
///
/// Applies an **additive delta** each tick. Two simultaneous [MoveEffect]s
/// accumulate correctly on the same entity.
///
/// ```dart
/// // Move to an absolute world position:
/// MoveEffect(to: Vector3(400, 200, 0), durationTicks: 60)
///
/// // Move by an offset, from wherever the entity is — with `from` given,
/// // the entity moves by `to − from`:
/// MoveEffect(
///   from: Vector3.zero(),
///   to: Vector3(400, 200, 0),
///   durationTicks: 60,
/// )
/// ```
class MoveEffect extends DeterministicEffect {
  /// The start the move is measured from. The entity is not put there:
  /// being additive, it moves by `to − from` from wherever it is. When
  /// `null`, the entity's position on the first tick is the start, so it
  /// ends at [to].
  final Vector3? from;

  /// Target world position.
  final Vector3 to;

  /// Easing curve applied to normalised progress.
  final EasingType easing;

  // Runtime-captured baseline — set on first applyTick call.
  Vector3? _capturedFrom;

  /// Moves to world position [to] over [durationTicks] ticks (30 by
  /// default), along [easing] (linear by default), from the entity's
  /// position on the first tick — or, given [from], by `to − from` from
  /// wherever the entity is.
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
    final prevEased = easing.transform(tAt(prevElapsed));
    final currEased = easing.transform(tAt(currElapsed));
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
    'to': [to.x, to.y, to.z],
    if (from != null) 'from': [from!.x, from!.y, from!.z],
    if (_capturedFrom != null)
      'capturedFrom': [_capturedFrom!.x, _capturedFrom!.y, _capturedFrom!.z],
    'easing': easing.name,
    'durationTicks': durationTicks,
    'loop': loop,
  };

  factory MoveEffect._fromJson(Map<String, dynamic> json) {
    final toList = json['to'] as List;
    final fromList = json['from'] as List?;
    final effect = MoveEffect(
      to: Vector3(
        (toList[0] as num).toDouble(),
        (toList[1] as num).toDouble(),
        toList.length > 2 ? (toList[2] as num).toDouble() : 0.0,
      ),
      from: fromList != null
          ? Vector3(
              (fromList[0] as num).toDouble(),
              (fromList[1] as num).toDouble(),
              fromList.length > 2 ? (fromList[2] as num).toDouble() : 0.0,
            )
          : null,
      easing: EasingType.values.byName(json['easing'] as String),
      durationTicks: json['durationTicks'] as int,
      loop: (json['loop'] as bool?) ?? false,
    );
    final capturedList = json['capturedFrom'] as List?;
    if (capturedList != null) {
      effect._capturedFrom = Vector3(
        (capturedList[0] as num).toDouble(),
        (capturedList[1] as num).toDouble(),
        capturedList.length > 2 ? (capturedList[2] as num).toDouble() : 0.0,
      );
    }
    return effect;
  }
}

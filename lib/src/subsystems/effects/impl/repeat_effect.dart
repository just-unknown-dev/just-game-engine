part of '../effect_system.dart';

/// Repeats a single child effect a fixed number of times.
///
/// * `times > 0` — finite repetitions. Total [durationTicks] = child duration
///   × [times].
/// * `times == 0` — infinite. [EffectPlayer] handles restart because [loop]
///   is set to `true` and [durationTicks] equals one child duration.
///
/// Child baselines are re-captured at the start of each iteration because
/// each iteration resets the child and subsequent `applyTick` calls begin
/// with `prevElapsed == 0`.
///
/// ```dart
/// // Bounce 3 times:
/// RepeatEffect(
///   child: MoveEffect(to: Offset(0, -30), durationTicks: 15),
///   times: 3,
/// )
///
/// // Infinite idle float:
/// RepeatEffect(
///   child: MoveEffect(to: Offset(0, -10), durationTicks: 30),
///   times: 0, // infinite
/// )
/// ```
class RepeatEffect extends DeterministicEffect {
  final DeterministicEffect child;

  /// Number of repetitions. `0` = infinite (effect loops via [EffectPlayer]).
  final int times;

  RepeatEffect({
    required this.child,
    this.times = 1,
    super.onComplete,
    super.onLoopComplete,
  }) : assert(times >= 0, 'times must be ≥ 0'),
       super(
         durationTicks: times > 0
             ? child.durationTicks * times
             : child.durationTicks,
         loop: times == 0, // infinite → delegate looping to EffectPlayer
       );

  @override
  void applyTick(EffectContext ctx, int prevElapsed, int currElapsed) {
    if (times == 0) {
      // Infinite: child covers the single durationTicks window; EffectPlayer
      // resets this effect (including child.reset()) between iterations.
      child.applyTick(ctx, prevElapsed, currElapsed);
      return;
    }

    // Finite multi-iteration: walk through each iteration covered by
    // [prevElapsed, currElapsed].
    final childD = child.durationTicks;
    int pos = prevElapsed;

    while (pos < currElapsed) {
      final iterIndex = pos ~/ childD;
      if (iterIndex >= times) break;

      final iterStart = iterIndex * childD;
      final intraStart = pos - iterStart;
      final intraEnd = math.min(currElapsed - iterStart, childD);

      if (intraStart < intraEnd) {
        child.applyTick(ctx, intraStart, intraEnd);
      }

      if (intraEnd >= childD) {
        // Completed this iteration — reset child and move to next.
        child.reset();
        pos = iterStart + childD;
      } else {
        break; // Did not reach end of this iteration yet.
      }
    }
  }

  @override
  void reset() {
    super.reset();
    child.reset();
  }

  @override
  String get effectType => 'repeat';

  @override
  Map<String, dynamic> toJson() {
    final s = EffectSerializer();
    return {
      'child': s.encodeEffect(child),
      'times': times,
      'durationTicks': durationTicks,
    };
  }

  factory RepeatEffect._fromJson(Map<String, dynamic> json) {
    final s = EffectSerializer();
    return RepeatEffect(
      child: s.decodeEffect(json['child'] as Map<String, dynamic>),
      times: json['times'] as int,
    );
  }
}

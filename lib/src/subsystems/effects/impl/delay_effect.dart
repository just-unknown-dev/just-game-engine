part of '../effect_system.dart';

/// A no-op effect that occupies `durationTicks` ticks without mutating any
/// component. Use it as a spacer inside [SequenceEffect].
///
/// ```dart
/// SequenceEffect(children: [
///   MoveEffect(to: Vector3(200, 0, 0), durationTicks: 30),
///   DelayEffect(durationTicks: 15),   // pause for 15 ticks
///   FadeEffect(to: 0.0, durationTicks: 30),
/// ])
/// ```
class DelayEffect extends DeterministicEffect {
  /// A pause of [durationTicks] ticks (30 by default); [onComplete] runs
  /// when it is over. It cannot loop.
  DelayEffect({super.durationTicks = 30, super.onComplete});

  @override
  void applyTick(EffectContext ctx, int prevElapsed, int currElapsed) {
    // Deliberately empty — time passes, nothing changes.
  }

  @override
  String get effectType => 'delay';

  @override
  Map<String, dynamic> toJson() => {'durationTicks': durationTicks};

  factory DelayEffect._fromJson(Map<String, dynamic> json) =>
      DelayEffect(durationTicks: json['durationTicks'] as int);
}

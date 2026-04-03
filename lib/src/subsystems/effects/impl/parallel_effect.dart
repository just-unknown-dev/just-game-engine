part of '../effect_system.dart';

/// Runs all child effects **simultaneously**.
///
/// Total [durationTicks] equals the maximum child duration. Shorter children
/// complete early and stop contributing; the parallel wrapper continues until
/// the longest child finishes.
///
/// ```dart
/// ParallelEffect([
///   MoveEffect(to: Offset(300, 0), durationTicks: 60),
///   ScaleEffect(to: 1.5, durationTicks: 40),
///   FadeEffect(to: 0.0, durationTicks: 60),
/// ])
/// ```
class ParallelEffect extends DeterministicEffect {
  /// Child effects to run simultaneously.
  final List<DeterministicEffect> children;

  ParallelEffect({
    required this.children,
    super.loop,
    super.onComplete,
    super.onLoopComplete,
  }) : assert(
         children.isNotEmpty,
         'ParallelEffect requires at least one child',
       ),
       super(
         durationTicks: children.fold(
           0,
           (m, c) => math.max(m, c.durationTicks),
         ),
       );

  @override
  void applyTick(EffectContext ctx, int prevElapsed, int currElapsed) {
    for (final child in children) {
      final childPrev = prevElapsed.clamp(0, child.durationTicks);
      final childCurr = currElapsed.clamp(0, child.durationTicks);
      if (childCurr > childPrev) {
        child.applyTick(ctx, childPrev, childCurr);
      }
    }
  }

  @override
  void reset() {
    super.reset();
    for (final child in children) {
      child.reset();
    }
  }

  @override
  String get effectType => 'parallel';

  @override
  Map<String, dynamic> toJson() {
    final s = EffectSerializer();
    return {
      'children': children.map(s.encodeEffect).toList(),
      'durationTicks': durationTicks,
      'loop': loop,
    };
  }

  factory ParallelEffect._fromJson(Map<String, dynamic> json) {
    final s = EffectSerializer();
    final childrenJson = json['children'] as List;
    return ParallelEffect(
      children: childrenJson
          .cast<Map<String, dynamic>>()
          .map(s.decodeEffect)
          .toList(),
      loop: (json['loop'] as bool?) ?? false,
    );
  }
}

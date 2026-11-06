part of '../deterministic_effects.dart';

/// Runs all child effects **simultaneously**.
///
/// Total [durationTicks] equals the maximum child duration. Shorter children
/// complete early and stop contributing; the parallel wrapper continues until
/// the longest child finishes.
///
/// A child's [DeterministicEffect.onComplete] runs when its part ends —
/// children ending on the same tick in list order; the parallel's own when
/// the longest ends. A child's `loop` is not used: each plays once.
///
/// ```dart
/// ParallelEffect(children: [
///   MoveEffect(to: Vector3(300, 0, 0), durationTicks: 60),
///   ScaleEffect(to: 1.5, durationTicks: 40),
///   FadeEffect(to: 0.0, durationTicks: 60),
/// ])
/// ```
class ParallelEffect extends DeterministicEffect {
  /// Child effects to run simultaneously.
  final List<DeterministicEffect> children;

  /// Plays all of [children] (at least one, asserted) from the same tick;
  /// lasts as long as the longest of them.
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
    var ended = 0;
    for (final child in children) {
      final childPrev = prevElapsed.clamp(0, child.durationTicks);
      final childCurr = currElapsed.clamp(0, child.durationTicks);
      if (childCurr > childPrev) {
        child.applyTick(ctx, childPrev, childCurr);
        if (childCurr == child.durationTicks) ended++;
      }
    }
    if (ended == 0) return;
    // The children whose part ended in this range call back by the tick
    // each ended on, in list order within a tick — the order tick-by-tick
    // steps call them in, so a wide (fast-forward) range calls them alike.
    final order = [
      for (var i = 0; i < children.length; i++)
        if (prevElapsed < children[i].durationTicks &&
            currElapsed >= children[i].durationTicks)
          i,
    ];
    if (order.length > 1) {
      order.sort((a, b) {
        final byEnd = children[a].durationTicks - children[b].durationTicks;
        return byEnd != 0 ? byEnd : a - b;
      });
    }
    for (final i in order) {
      children[i].onComplete?.call();
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

  factory ParallelEffect._fromJson(
    Map<String, dynamic> json,
    EffectSerializer s,
  ) {
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

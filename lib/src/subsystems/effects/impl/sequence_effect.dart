part of '../effect_system.dart';

/// Runs a list of child effects **one after another** in order.
///
/// The total [durationTicks] equals the sum of all children's durations.
/// Each child is active only during its own time slice; once it completes,
/// the next one begins. Child baselines are captured correctly because each
/// child's `prevElapsed` resets to `0` at the start of its slice.
///
/// ```dart
/// SequenceEffect([
///   MoveEffect(to: Offset(200, 0), durationTicks: 30),
///   ShakeEffect(amplitude: 8, durationTicks: 20),
///   FadeEffect(to: 0.0, durationTicks: 30),
/// ])
/// ```
class SequenceEffect extends DeterministicEffect {
  /// Ordered child effects.
  final List<DeterministicEffect> children;

  /// Cumulative tick offsets: `_offsets[i]` is the tick at which
  /// `children[i]` starts, relative to the beginning of the sequence.
  late final List<int> _offsets;

  SequenceEffect({
    required this.children,
    super.loop,
    super.onComplete,
    super.onLoopComplete,
  }) : assert(
         children.isNotEmpty,
         'SequenceEffect requires at least one child',
       ),
       super(durationTicks: children.fold(0, (s, c) => s + c.durationTicks)) {
    _offsets = List.generate(children.length, (i) {
      return children.sublist(0, i).fold(0, (s, c) => s + c.durationTicks);
    });
  }

  @override
  void applyTick(EffectContext ctx, int prevElapsed, int currElapsed) {
    for (int i = 0; i < children.length; i++) {
      final child = children[i];
      final childStart = _offsets[i];
      final childEnd = childStart + child.durationTicks;

      // Skip children entirely outside this range.
      if (prevElapsed >= childEnd || currElapsed <= childStart) continue;

      final childPrev = (prevElapsed - childStart).clamp(
        0,
        child.durationTicks,
      );
      final childCurr = (currElapsed - childStart).clamp(
        0,
        child.durationTicks,
      );
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
  String get effectType => 'sequence';

  @override
  Map<String, dynamic> toJson() {
    final s = EffectSerializer();
    return {
      'children': children.map(s.encodeEffect).toList(),
      'durationTicks': durationTicks,
      'loop': loop,
    };
  }

  factory SequenceEffect._fromJson(Map<String, dynamic> json) {
    final s = EffectSerializer();
    final childrenJson = json['children'] as List;
    return SequenceEffect(
      children: childrenJson
          .cast<Map<String, dynamic>>()
          .map(s.decodeEffect)
          .toList(),
      loop: (json['loop'] as bool?) ?? false,
    );
  }
}

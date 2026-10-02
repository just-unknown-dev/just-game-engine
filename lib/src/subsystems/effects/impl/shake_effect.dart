part of '../effect_system.dart';

/// Applies a damped oscillating positional shake to [TransformComponent].
///
/// ### Determinism
/// The shake uses `sin` and `cos` driven by the integer tick count so
/// every peer with the same `(amplitude, frequency, durationTicks)` tuple
/// produces bit-identical results.
///
/// The X axis oscillates with `sin`, the Y axis with `cos − 1`, creating a
/// circular shake pattern that starts and ends exactly where the entity
/// was: nothing is left over when it ends, and a looping shake does not
/// drift. Linear damping shrinks the amplitude to zero at `durationTicks`.
///
/// ```dart
/// // Short screen-shake after a hit:
/// ShakeEffect(amplitude: 8.0, frequency: 3.0, durationTicks: 20)
/// ```
class ShakeEffect extends DeterministicEffect {
  /// Peak shake distance in world units.
  final double amplitude;

  /// Number of full oscillation cycles over the total duration.
  final double frequency;

  /// When `true` only the X axis is shaken (horizontal shake).
  final bool xOnly;

  /// A shake of up to [amplitude] world units (not negative, asserted),
  /// [frequency] cycles (4 by default) over [durationTicks] ticks (30 by
  /// default), on both axes unless [xOnly].
  ShakeEffect({
    required this.amplitude,
    this.frequency = 4.0,
    this.xOnly = false,
    super.durationTicks = 30,
    super.loop,
    super.onComplete,
  }) : assert(amplitude >= 0, 'amplitude must be ≥ 0');

  /// Compute the shake offset **at** a specific elapsed tick count: zero
  /// at the start and at the end.
  Vector3 _offsetAt(int elapsed) {
    if (durationTicks == 0) return Vector3.zero();
    final t = elapsed / durationTicks; // normalised 0..1
    final damping = 1.0 - t; // linear fade-out
    final angle = elapsed * frequency * 2 * math.pi / durationTicks;
    final dx = amplitude * damping * math.sin(angle);
    // cos − 1, not cos: the circle's top is where the entity started, so
    // the offset is 0 at the first tick as well as the last.
    final dy = xOnly ? 0.0 : amplitude * damping * (math.cos(angle) - 1);
    return Vector3(dx, dy, 0);
  }

  @override
  void applyTick(EffectContext ctx, int prevElapsed, int currElapsed) {
    final transform = ctx.getComponent<TransformComponent>();
    if (transform == null) return;

    // Additive delta: position at currElapsed − position at prevElapsed.
    final delta = _offsetAt(currElapsed) - _offsetAt(prevElapsed);
    transform.position += delta;
  }

  @override
  String get effectType => 'shake';

  @override
  Map<String, dynamic> toJson() => {
    'amplitude': amplitude,
    'frequency': frequency,
    'xOnly': xOnly,
    'durationTicks': durationTicks,
    'loop': loop,
  };

  factory ShakeEffect._fromJson(Map<String, dynamic> json) => ShakeEffect(
    amplitude: (json['amplitude'] as num).toDouble(),
    frequency: (json['frequency'] as num? ?? 4.0).toDouble(),
    xOnly: (json['xOnly'] as bool?) ?? false,
    durationTicks: json['durationTicks'] as int,
    loop: (json['loop'] as bool?) ?? false,
  );
}

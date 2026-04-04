part of '../effect_system.dart';

/// Applies a damped oscillating positional shake to [TransformComponent].
///
/// ### Determinism
/// The shake uses `sin` and `cos` driven by the integer tick count so
/// every peer with the same `(amplitude, frequency, durationTicks)` tuple
/// produces bit-identical results.
///
/// The X axis oscillates with `sin`, the Y axis with `cos`, creating a
/// circular shake pattern. Linear damping shrinks the amplitude to zero
/// at `durationTicks`.
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

  ShakeEffect({
    required this.amplitude,
    this.frequency = 4.0,
    this.xOnly = false,
    super.durationTicks = 30,
    super.loop,
    super.onComplete,
  }) : assert(amplitude >= 0, 'amplitude must be ≥ 0');

  /// Compute the shake offset **at** a specific elapsed tick count.
  Offset _offsetAt(int elapsed) {
    if (durationTicks == 0) return Offset.zero;
    final t = elapsed / durationTicks; // normalised 0..1
    final damping = 1.0 - t; // linear fade-out
    final angle = elapsed * frequency * 2 * math.pi / durationTicks;
    final dx = amplitude * damping * math.sin(angle);
    final dy = xOnly ? 0.0 : amplitude * damping * math.cos(angle);
    return Offset(dx, dy);
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

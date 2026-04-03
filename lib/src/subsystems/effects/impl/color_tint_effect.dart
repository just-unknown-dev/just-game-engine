part of '../effect_system.dart';

/// Animates the [Renderable.tint] colour of an entity's [RenderableComponent]
/// from a starting colour to [to] over [durationTicks] ticks.
///
/// Unlike transform effects, colour blending uses **absolute interpolation**
/// each tick (the current tint is set to the lerped value rather than having
/// a delta added). Running two [ColorTintEffect]s simultaneously causes the
/// last-applied one to win for the tint value; prefer [ParallelEffect] with
/// complementary colours for intentional blending.
///
/// The entity must have a [RenderableComponent]; if absent the effect no-ops.
///
/// ```dart
/// // Flash red then back to white:
/// ColorTintEffect(to: Colors.red, durationTicks: 15)
/// ```
class ColorTintEffect extends DeterministicEffect {
  /// Explicit start colour. When `null` the entity's current
  /// [Renderable.tint] is captured on the first tick
  /// (`Colors.white` if no tint is set).
  final Color? from;

  /// Target tint colour.
  final Color to;

  /// Easing curve.
  final EasingType easing;

  Color? _capturedFrom;

  ColorTintEffect({
    required this.to,
    this.from,
    this.easing = EasingType.linear,
    super.durationTicks = 30,
    super.loop,
    super.onComplete,
  });

  @override
  void applyTick(EffectContext ctx, int prevElapsed, int currElapsed) {
    final renderable = ctx.getComponent<RenderableComponent>();
    if (renderable == null) return;

    if (prevElapsed == 0) {
      _capturedFrom = from ?? renderable.renderable.tint ?? Colors.white;
    }
    final effectiveFrom = _capturedFrom;
    if (effectiveFrom == null) return;

    // Absolute lerp — set tint directly (not additive delta).
    final currT = tAt(currElapsed);
    final currEased = EffectEasings.resolve(easing, currT);
    renderable.renderable.tint = Color.lerp(effectiveFrom, to, currEased);
  }

  @override
  void reset() {
    super.reset();
    _capturedFrom = null;
  }

  @override
  String get effectType => 'colorTint';

  @override
  Map<String, dynamic> toJson() => {
    'to': to.toARGB32(),
    if (from != null) 'from': from!.toARGB32(),
    if (_capturedFrom != null) 'capturedFrom': _capturedFrom!.toARGB32(),
    'easing': easing.name,
    'durationTicks': durationTicks,
    'loop': loop,
  };

  factory ColorTintEffect._fromJson(Map<String, dynamic> json) {
    final effect = ColorTintEffect(
      to: Color(json['to'] as int),
      from: json['from'] != null ? Color(json['from'] as int) : null,
      easing: EasingType.values.byName(json['easing'] as String),
      durationTicks: json['durationTicks'] as int,
      loop: (json['loop'] as bool?) ?? false,
    );
    if (json['capturedFrom'] != null) {
      effect._capturedFrom = Color(json['capturedFrom'] as int);
    }
    return effect;
  }
}

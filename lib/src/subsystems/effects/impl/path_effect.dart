part of '../effect_system.dart';

/// Moves an entity along a path defined by [waypoints] over [durationTicks].
///
/// ### Path types
/// * **Linear** (default, or < 4 waypoints): the entity moves through each
///   waypoint at equal spacing along `t`. Waypoints must have at least 2
///   entries.
/// * **Cubic Bézier** (`cubicBezier: true`, exactly 4 waypoints `P0 P1 P2 P3`):
///   a classic cubic Bézier spline. Use control points `P1` and `P2` to shape
///   the curve.
///
/// Applies an **additive delta** each tick. The effect is stateless beyond
/// the captured baseline, so fast-forward works correctly.
///
/// ```dart
/// // Parabolic arc via Bézier:
/// PathEffect(
///   waypoints: [
///     Offset(0, 0),    // P0 – start (relative; captured from entity at t=0)
///     Offset(50, -80), // P1 – control
///     Offset(150, -80),// P2 – control
///     Offset(200, 0),  // P3 – end
///   ],
///   cubicBezier: true,
///   durationTicks: 60,
/// )
/// ```
class PathEffect extends DeterministicEffect {
  /// Path control points.
  ///
  /// * Linear: 2+ absolute world-space positions. The entity moves through
  ///   them at equal time intervals.
  /// * Cubic Bézier: exactly 4 positions `[P0, P1, P2, P3]`.
  ///   When [cubicBezier] is `true` and [relativeToStart] is `true`
  ///   (default), `P0` is treated as `Offset.zero` and the others are
  ///   the offset relative to the entity's start position.
  final List<Offset> waypoints;

  /// When `true`, interpret [waypoints] as a cubic Bézier spline
  /// (requires exactly 4 points).
  final bool cubicBezier;

  /// When `true`, waypoints are offsets relative to the entity's position
  /// at the start of the effect.  When `false`, waypoints are absolute
  /// world-space positions.
  final bool relativeToStart;

  /// Easing applied to the normalised path progress.
  final EasingType easing;

  // Runtime.
  Offset? _capturedStart;

  PathEffect({
    required this.waypoints,
    this.cubicBezier = false,
    this.relativeToStart = true,
    this.easing = EasingType.linear,
    super.durationTicks = 60,
    super.loop,
    super.onComplete,
  }) : assert(waypoints.length >= 2, 'PathEffect needs at least 2 waypoints'),
       assert(
         !cubicBezier || waypoints.length == 4,
         'Cubic Bézier PathEffect requires exactly 4 waypoints',
       );

  /// Evaluate path position at normalised [t] ∈ [0, 1].
  Offset _evaluate(double t, Offset origin) {
    if (cubicBezier) {
      // Standard cubic Bézier: B(t) = (1-t)³P0 + 3(1-t)²tP1 + 3(1-t)t²P2 + t³P3
      final mt = 1.0 - t;
      final p0 = relativeToStart ? origin + waypoints[0] : waypoints[0];
      final p1 = relativeToStart ? origin + waypoints[1] : waypoints[1];
      final p2 = relativeToStart ? origin + waypoints[2] : waypoints[2];
      final p3 = relativeToStart ? origin + waypoints[3] : waypoints[3];
      return p0 * (mt * mt * mt) +
          p1 * (3 * mt * mt * t) +
          p2 * (3 * mt * t * t) +
          p3 * (t * t * t);
    } else {
      // Linear interpolation through waypoints.
      final n = waypoints.length - 1;
      final segment = (t * n).clamp(0.0, n.toDouble() - 1e-10);
      final segIdx = segment.floor();
      final segT = segment - segIdx;
      final a = relativeToStart
          ? origin + waypoints[segIdx]
          : waypoints[segIdx];
      final b = relativeToStart
          ? origin + waypoints[segIdx + 1]
          : waypoints[segIdx + 1];
      return Offset.lerp(a, b, segT)!;
    }
  }

  @override
  void applyTick(EffectContext ctx, int prevElapsed, int currElapsed) {
    final transform = ctx.getComponent<TransformComponent>();
    if (transform == null) return;

    if (prevElapsed == 0) {
      _capturedStart = transform.position;
    }
    final origin = _capturedStart!;

    final prevT = EffectEasings.resolve(easing, tAt(prevElapsed));
    final currT = EffectEasings.resolve(easing, tAt(currElapsed));
    final prevPos = _evaluate(prevT, origin);
    final currPos = _evaluate(currT, origin);
    transform.position += currPos - prevPos;
  }

  @override
  void reset() {
    super.reset();
    _capturedStart = null;
  }

  @override
  String get effectType => 'path';

  @override
  Map<String, dynamic> toJson() {
    final waypointsList = waypoints.map((p) => [p.dx, p.dy]).toList();
    return {
      'waypoints': waypointsList,
      'cubicBezier': cubicBezier,
      'relativeToStart': relativeToStart,
      'easing': easing.name,
      'durationTicks': durationTicks,
      'loop': loop,
      if (_capturedStart != null)
        'capturedStart': [_capturedStart!.dx, _capturedStart!.dy],
    };
  }

  factory PathEffect._fromJson(Map<String, dynamic> json) {
    final rawWaypoints = json['waypoints'] as List;
    final waypoints = rawWaypoints.map((p) {
      final list = p as List;
      return Offset((list[0] as num).toDouble(), (list[1] as num).toDouble());
    }).toList();
    final effect = PathEffect(
      waypoints: waypoints,
      cubicBezier: (json['cubicBezier'] as bool?) ?? false,
      relativeToStart: (json['relativeToStart'] as bool?) ?? true,
      easing: EasingType.values.byName(json['easing'] as String),
      durationTicks: json['durationTicks'] as int,
      loop: (json['loop'] as bool?) ?? false,
    );
    final capturedList = json['capturedStart'] as List?;
    if (capturedList != null) {
      effect._capturedStart = Offset(
        (capturedList[0] as num).toDouble(),
        (capturedList[1] as num).toDouble(),
      );
    }
    return effect;
  }
}

/// Keys and the curve between them: the part of a timeline that turns a
/// time into a value.
library;

import '../animation/animation_system.dart' show Easing, Easings;

/// How a key reaches the next one.
enum KeyInterpolation {
  /// Holds its value until the next key.
  step,
  linear,

  /// A cubic bezier through the two keys' tangent handles.
  bezier,

  /// A named easing function (see [KeyEasings]) — for shapes a single bezier
  /// cannot make, like a bounce.
  eased,
}

/// How an editor keeps a key's two handles in step. The runtime ignores it.
enum TangentMode {
  /// Recomputed from the neighbouring keys whenever they move.
  auto,

  /// Both handles horizontal: the value eases to rest at the key.
  flat,

  /// In and out point the same way; moving one moves the other.
  aligned,

  /// In and out are independent: a corner.
  broken,
}

/// A bezier handle, as an offset from its key: [dt] seconds, [dv] value.
class Tangent {
  const Tangent(this.dt, this.dv);

  static const Tangent zero = Tangent(0, 0);

  final double dt;
  final double dv;

  List<double> toJson() => [dt, dv];

  static Tangent fromJson(Object? json) => json is List && json.length == 2
      ? Tangent((json[0] as num).toDouble(), (json[1] as num).toDouble())
      : zero;

  @override
  bool operator ==(Object other) =>
      other is Tangent && other.dt == dt && other.dv == dv;

  @override
  int get hashCode => Object.hash(dt, dv);
}

/// A value at a time.
///
/// [value] is a `num` for anything that blends, an ARGB `int` tagged by the
/// track as a colour, or a `bool` / `String` for what can only step (a flag,
/// an enum's name, a path).
class TimelineKey {
  const TimelineKey({
    required this.time,
    required this.value,
    this.interpolation = KeyInterpolation.bezier,
    this.inTangent = Tangent.zero,
    this.outTangent = Tangent.zero,
    this.tangentMode = TangentMode.auto,
    this.easing = '',
  });

  /// Seconds from the start of the timeline.
  final double time;
  final Object value;

  /// How this key reaches the next.
  final KeyInterpolation interpolation;

  /// The handle arriving at this key; [Tangent.dt] is zero or negative.
  final Tangent inTangent;

  /// The handle leaving this key; [Tangent.dt] is zero or positive.
  final Tangent outTangent;
  final TangentMode tangentMode;

  /// The [KeyEasings] name, for [KeyInterpolation.eased].
  final String easing;

  double get number => value is num ? (value as num).toDouble() : 0.0;

  TimelineKey copyWith({
    double? time,
    Object? value,
    KeyInterpolation? interpolation,
    Tangent? inTangent,
    Tangent? outTangent,
    TangentMode? tangentMode,
    String? easing,
  }) => TimelineKey(
    time: time ?? this.time,
    value: value ?? this.value,
    interpolation: interpolation ?? this.interpolation,
    inTangent: inTangent ?? this.inTangent,
    outTangent: outTangent ?? this.outTangent,
    tangentMode: tangentMode ?? this.tangentMode,
    easing: easing ?? this.easing,
  );

  Map<String, dynamic> toJson() => {
    't': time,
    'v': value,
    if (interpolation != KeyInterpolation.bezier) 'i': interpolation.name,
    if (inTangent != Tangent.zero) 'in': inTangent.toJson(),
    if (outTangent != Tangent.zero) 'out': outTangent.toJson(),
    if (tangentMode != TangentMode.auto) 'm': tangentMode.name,
    if (easing.isNotEmpty) 'e': easing,
  };

  factory TimelineKey.fromJson(Map<String, dynamic> json) => TimelineKey(
    time: (json['t'] as num?)?.toDouble() ?? 0,
    value: json['v'] as Object? ?? 0,
    interpolation:
        KeyInterpolation.values.asNameMap()[json['i']] ??
        KeyInterpolation.bezier,
    inTangent: Tangent.fromJson(json['in']),
    outTangent: Tangent.fromJson(json['out']),
    tangentMode: TangentMode.values.asNameMap()[json['m']] ?? TangentMode.auto,
    easing: json['e'] as String? ?? '',
  );
}

/// The engine's easing functions by name, so a key in a file can ask for
/// one: shapes a single bezier cannot make, like a bounce.
abstract final class KeyEasings {
  static final Map<String, Easing> _all = {
    'linear': Easings.linear,
    'easeInQuad': Easings.easeInQuad,
    'easeOutQuad': Easings.easeOutQuad,
    'easeInOutQuad': Easings.easeInOutQuad,
    'easeInCubic': Easings.easeInCubic,
    'easeOutCubic': Easings.easeOutCubic,
    'easeInOutCubic': Easings.easeInOutCubic,
    'easeInOutSine': Easings.easeInOutSine,
    'easeInExpo': Easings.easeInExpo,
    'easeOutExpo': Easings.easeOutExpo,
    'easeInElastic': Easings.easeInElastic,
    'easeOutElastic': Easings.easeOutElastic,
    'easeInBounce': Easings.easeInBounce,
    'easeOutBounce': Easings.easeOutBounce,
  };

  static List<String> get names => _all.keys.toList();

  /// Adds (or replaces) an easing a game wants to name in its timelines.
  static void register(String name, Easing easing) => _all[name] = easing;

  static double apply(String name, double t) =>
      (_all[name] ?? Easings.linear)(t);
}

/// Keys in time order, and the value between them.
class KeyCurve {
  KeyCurve(List<TimelineKey> keys)
    : keys = List.unmodifiable(
        List.of(keys)..sort((a, b) => a.time.compareTo(b.time)),
      );

  static final KeyCurve empty = KeyCurve(const []);

  final List<TimelineKey> keys;

  bool get isEmpty => keys.isEmpty;

  /// When the last key is; 0 for an empty curve.
  double get end => keys.isEmpty ? 0 : keys.last.time;

  /// The value at [t]: before the first key its value, after the last its
  /// value, between two keys whatever the earlier one's interpolation says.
  /// Null for an empty curve.
  Object? valueAt(double t, {bool isColor = false}) {
    if (keys.isEmpty) return null;
    if (t <= keys.first.time) return keys.first.value;
    if (t >= keys.last.time) return keys.last.value;
    // The last key at or before t.
    var lo = 0, hi = keys.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      keys[mid].time <= t ? lo = mid : hi = mid;
    }
    final a = keys[lo], b = keys[hi];
    // On a key is the key: no solve, no rounding.
    if (t == a.time) return a.value;
    if (a.interpolation == KeyInterpolation.step ||
        a.value is! num ||
        b.value is! num) {
      return a.value;
    }
    final span = b.time - a.time;
    if (span <= 0) return b.value;
    final u = (t - a.time) / span;
    final s = switch (a.interpolation) {
      KeyInterpolation.linear => u,
      KeyInterpolation.eased => KeyEasings.apply(a.easing, u),
      // Colours take the bezier's *timing* (0–1) but never its overshoot:
      // a channel past 255 is not a colour.
      KeyInterpolation.bezier => isColor ? _bezierProgress(a, b, t) : null,
      KeyInterpolation.step => 0.0,
    };
    if (s == null) return _bezierValue(a, b, t);
    return isColor
        ? lerpColor(a.value as int, b.value as int, s.clamp(0.0, 1.0))
        : a.number + (b.number - a.number) * s;
  }

  double numberAt(double t) => (valueAt(t) as num?)?.toDouble() ?? 0.0;

  /// The control points' times, kept between the two keys so the curve is a
  /// function of time — it never runs backwards.
  static (double, double) _controlTimes(TimelineKey a, TimelineKey b) {
    final span = b.time - a.time;
    return (
      a.time + a.outTangent.dt.clamp(0.0, span),
      b.time + b.inTangent.dt.clamp(-span, 0.0),
    );
  }

  /// The bezier parameter at which the curve's time is [t].
  static double _solve(TimelineKey a, TimelineKey b, double t) {
    final (t1, t2) = _controlTimes(a, b);
    double x(double s) {
      final i = 1 - s;
      return i * i * i * a.time +
          3 * i * i * s * t1 +
          3 * i * s * s * t2 +
          s * s * s * b.time;
    }

    // Monotonic in s, so bisection always lands; 24 steps is sub-microsecond.
    var lo = 0.0, hi = 1.0;
    for (var n = 0; n < 24; n++) {
      final mid = (lo + hi) / 2;
      x(mid) < t ? lo = mid : hi = mid;
    }
    return (lo + hi) / 2;
  }

  static double _bezierValue(TimelineKey a, TimelineKey b, double t) {
    // Handles of no length are a straight line: skip the solve.
    if (a.outTangent == Tangent.zero && b.inTangent == Tangent.zero) {
      return a.number +
          (b.number - a.number) * (t - a.time) / (b.time - a.time);
    }
    final s = _solve(a, b, t), i = 1 - s;
    final v1 = a.number + a.outTangent.dv, v2 = b.number + b.inTangent.dv;
    return i * i * i * a.number +
        3 * i * i * s * v1 +
        3 * i * s * s * v2 +
        s * s * s * b.number;
  }

  /// How far from [a] to [b] the bezier is at [t], as 0–1, reading the
  /// handles' values as fractions of the way — what a colour blends by.
  static double _bezierProgress(TimelineKey a, TimelineKey b, double t) {
    if (a.outTangent == Tangent.zero && b.inTangent == Tangent.zero) {
      return (t - a.time) / (b.time - a.time);
    }
    final s = _solve(a, b, t), i = 1 - s;
    return 3 * i * i * s * a.outTangent.dv.clamp(0.0, 1.0) +
        3 * i * s * s * (1 + b.inTangent.dv.clamp(-1.0, 0.0)) +
        s * s * s;
  }

  /// ARGB [a] to [b] by [s], channel by channel.
  static int lerpColor(int a, int b, double s) {
    int channel(int shift) {
      final from = (a >> shift) & 0xFF, to = (b >> shift) & 0xFF;
      return (from + (to - from) * s).round().clamp(0, 255);
    }

    return (channel(24) << 24) |
        (channel(16) << 16) |
        (channel(8) << 8) |
        channel(0);
  }

  // ── Editing helpers (pure; an editor builds a new curve from them) ───────

  /// This curve with [key] added, replacing any key at the same time.
  KeyCurve withKey(TimelineKey key, {double epsilon = 1e-4}) => KeyCurve([
    for (final k in keys)
      if ((k.time - key.time).abs() > epsilon) k,
    key,
  ]).withAutoTangents();

  KeyCurve withoutKeyAt(int index) => KeyCurve([
    for (var i = 0; i < keys.length; i++)
      if (i != index) keys[i],
  ]).withAutoTangents();

  /// Recomputes the handles of every [TangentMode.auto] and
  /// [TangentMode.flat] key from its neighbours: a smooth curve through the
  /// keys that does not overshoot at a peak.
  KeyCurve withAutoTangents() {
    if (keys.length < 2) return this;
    final out = <TimelineKey>[];
    for (var i = 0; i < keys.length; i++) {
      final k = keys[i];
      if (k.value is! num ||
          (k.tangentMode != TangentMode.auto &&
              k.tangentMode != TangentMode.flat)) {
        out.add(k);
        continue;
      }
      final prev = i > 0 ? keys[i - 1] : null;
      final next = i < keys.length - 1 ? keys[i + 1] : null;
      final before = prev == null ? 0.0 : (k.time - prev.time) / 3;
      final after = next == null ? 0.0 : (next.time - k.time) / 3;
      var slope = 0.0;
      if (k.tangentMode == TangentMode.auto) {
        final from = prev != null && prev.value is num ? prev : null;
        final to = next != null && next.value is num ? next : null;
        if (from != null && to != null) {
          // A peak or a trough rests flat; otherwise the slope through the
          // neighbours.
          if ((to.number - k.number) * (k.number - from.number) > 0) {
            slope = (to.number - from.number) / (to.time - from.time);
          }
        } else if ((from ?? to) case final only?) {
          // An end key aims at its one neighbour, so two keys make a line.
          final span = only.time - k.time;
          if (span != 0) slope = (only.number - k.number) / span;
        }
      }
      out.add(
        k.copyWith(
          inTangent: Tangent(-before, -before * slope),
          outTangent: Tangent(after, after * slope),
        ),
      );
    }
    return KeyCurve(out);
  }

  List<Map<String, dynamic>> toJson() => [for (final k in keys) k.toJson()];

  factory KeyCurve.fromJson(Object? json) => KeyCurve([
    if (json is List)
      for (final k in json)
        if (k is Map) TimelineKey.fromJson(k.cast<String, dynamic>()),
  ]);
}

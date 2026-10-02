/// Keys and the curve between them: the part of a timeline that turns a
/// time into a value.
library;

import '../../foundation/easing.dart';

/// How a key reaches the next one.
enum KeyInterpolation {
  /// Holds its value until the next key.
  step,

  /// A straight line to the next key's value, at an even pace.
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
class KeyTangent {
  /// A handle [dt] seconds and [dv] in value from its key.
  const KeyTangent(this.dt, this.dv);

  /// A handle of no length, on its key. Between two keys whose facing
  /// handles are both zero, a bezier is a straight line.
  static const KeyTangent zero = KeyTangent(0, 0);

  /// Seconds from the key: negative for an in handle, positive for an out.
  /// Clamped to the span between the two keys when the curve is read.
  final double dt;

  /// Value from the key's value, in the track's units. On a colour track
  /// it is read as a fraction of the way between the two keys, clamped to
  /// 0–1 for an out handle and −1–0 for an in handle.
  final double dv;

  /// The handle as a two-number list, `[dt, dv]`.
  List<double> toJson() => [dt, dv];

  /// Reads [toJson]'s `[dt, dv]`; anything but a two-item list is [zero].
  /// Throws a [TypeError] when an item is not a number.
  static KeyTangent fromJson(Object? json) => json is List && json.length == 2
      ? KeyTangent((json[0] as num).toDouble(), (json[1] as num).toDouble())
      : zero;

  @override
  bool operator ==(Object other) =>
      other is KeyTangent && other.dt == dt && other.dv == dv;

  @override
  int get hashCode => Object.hash(dt, dv);
}

/// A value at a time.
///
/// [value] is a `num` for anything that blends, an ARGB `int` tagged by the
/// track as a colour, or a `bool` / `String` for what can only step (a flag,
/// an enum's name, a path).
class TimelineKey {
  /// A key holding [value] at [time] seconds. By default it reaches the
  /// next key by a bezier with zero-length handles — a straight line — and
  /// its handles are [TangentMode.auto], for [KeyCurve.withAutoTangents] to
  /// set.
  const TimelineKey({
    required this.time,
    required this.value,
    this.interpolation = KeyInterpolation.bezier,
    this.inTangent = KeyTangent.zero,
    this.outTangent = KeyTangent.zero,
    this.tangentMode = TangentMode.auto,
    this.easing = '',
  });

  /// Seconds from the start of the timeline.
  final double time;

  /// The value at [time]: a `num`, an ARGB `int` on a colour track, or a
  /// `bool` / `String`, which only steps.
  final Object value;

  /// How this key reaches the next.
  final KeyInterpolation interpolation;

  /// The handle arriving at this key; [KeyTangent.dt] is zero or negative.
  final KeyTangent inTangent;

  /// The handle leaving this key; [KeyTangent.dt] is zero or positive.
  final KeyTangent outTangent;

  /// How an editor keeps the two handles in step, and whether
  /// [KeyCurve.withAutoTangents] recomputes them. Playback ignores it.
  final TangentMode tangentMode;

  /// The [KeyEasings] name, for [KeyInterpolation.eased].
  final String easing;

  /// [value] as a double; 0 when it is not a number.
  double get number => value is num ? (value as num).toDouble() : 0.0;

  /// A copy with the given fields replaced.
  TimelineKey copyWith({
    double? time,
    Object? value,
    KeyInterpolation? interpolation,
    KeyTangent? inTangent,
    KeyTangent? outTangent,
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

  /// This key as a compact JSON map: `t` (time) and `v` (value) always;
  /// `i` (interpolation), `in` and `out` (handles), `m` (tangent mode) and
  /// `e` (easing) only when not the default.
  Map<String, dynamic> toJson() => {
    't': time,
    'v': value,
    if (interpolation != KeyInterpolation.bezier) 'i': interpolation.name,
    if (inTangent != KeyTangent.zero) 'in': inTangent.toJson(),
    if (outTangent != KeyTangent.zero) 'out': outTangent.toJson(),
    if (tangentMode != TangentMode.auto) 'm': tangentMode.name,
    if (easing.isNotEmpty) 'e': easing,
  };

  /// Reads [toJson]'s shape. What is missing takes its default — a missing
  /// time or value is 0 — as does an unknown interpolation or tangent mode.
  factory TimelineKey.fromJson(Map<String, dynamic> json) => TimelineKey(
    time: (json['t'] as num?)?.toDouble() ?? 0,
    value: json['v'] as Object? ?? 0,
    interpolation:
        KeyInterpolation.values.asNameMap()[json['i']] ??
        KeyInterpolation.bezier,
    inTangent: KeyTangent.fromJson(json['in']),
    outTangent: KeyTangent.fromJson(json['out']),
    tangentMode: TangentMode.values.asNameMap()[json['m']] ?? TangentMode.auto,
    easing: json['e'] as String? ?? '',
  );
}

/// Easing functions by name, so a key in a file can ask for one: shapes a
/// single bezier cannot make, like a bounce. A key saves the name, so the
/// names never change.
///
/// Each engine has its own (`engine.context.easings`), holding the engine's
/// ([Easings]) and whatever a game registers. [builtIn] holds only the
/// engine's, and cannot be changed.
final class KeyEasings {
  /// The engine's easings (unless [withBuiltIns] is false), to add to.
  KeyEasings({bool withBuiltIns = true}) : _frozen = false {
    if (withBuiltIns) _all.addAll(_engine);
  }

  KeyEasings._frozen() : _frozen = true {
    _all.addAll(_engine);
  }

  /// The engine's easings and nothing else — what a curve uses when given
  /// none. Read-only: [register] throws.
  static final KeyEasings builtIn = KeyEasings._frozen();

  final bool _frozen;
  final Map<String, EasingFunction> _all = {};

  static const Map<String, EasingFunction> _engine = {
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

  /// Every name, the engine's first.
  List<String> get names => _all.keys.toList();

  /// Adds (or replaces) an easing a game wants to name in its timelines.
  void register(String name, EasingFunction easing) {
    if (_frozen) {
      throw UnsupportedError(
        'KeyEasings.builtIn cannot be changed: register into an engine\'s '
        '(engine.context.easings).',
      );
    }
    _all[name] = easing;
  }

  /// [name]'s easing at [t]; linear for a name not registered.
  double apply(String name, double t) => (_all[name] ?? Easings.linear)(t);
}

/// Keys in time order, and the value between them.
class KeyCurve {
  /// A curve through [keys], copied, sorted by time and made unmodifiable.
  /// Handles are kept as given; see [withAutoTangents].
  KeyCurve(List<TimelineKey> keys)
    : keys = List.unmodifiable(
        List.of(keys)..sort((a, b) => a.time.compareTo(b.time)),
      );

  /// A curve with no keys.
  static final KeyCurve empty = KeyCurve(const []);

  /// The keys, in time order. Unmodifiable.
  final List<TimelineKey> keys;

  /// Whether the curve has no keys, so [valueAt] is null everywhere.
  bool get isEmpty => keys.isEmpty;

  /// When the last key is; 0 for an empty curve.
  double get end => keys.isEmpty ? 0 : keys.last.time;

  /// The value at [t]: before the first key its value, after the last its
  /// value, between two keys whatever the earlier one's interpolation says.
  /// Null for an empty curve. A named easing is looked up in [easings] — the
  /// engine's own ([KeyEasings.builtIn]) when null.
  Object? valueAt(double t, {bool isColor = false, KeyEasings? easings}) {
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
      KeyInterpolation.eased => (easings ?? KeyEasings.builtIn).apply(
        a.easing,
        u,
      ),
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

  /// [valueAt] [t] as a double; 0 for an empty curve. A named easing is
  /// looked up in [easings] — the built-in ones when null. A `bool` value
  /// reads as 1 or 0 and any other value that is not a number (a `String`)
  /// as 0. Not for colours: it blends the ARGB int as one number.
  double numberAt(double t, {KeyEasings? easings}) =>
      switch (valueAt(t, easings: easings)) {
        final num n => n.toDouble(),
        true => 1.0,
        _ => 0.0,
      };

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
    if (a.outTangent == KeyTangent.zero && b.inTangent == KeyTangent.zero) {
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
    if (a.outTangent == KeyTangent.zero && b.inTangent == KeyTangent.zero) {
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

  /// This curve without the key at [index] (none removed when it is out of
  /// range), with the auto handles recomputed.
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
          inTangent: KeyTangent(-before, -before * slope),
          outTangent: KeyTangent(after, after * slope),
        ),
      );
    }
    return KeyCurve(out);
  }

  /// The keys as a list of [TimelineKey.toJson] maps, in time order.
  List<Map<String, dynamic>> toJson() => [for (final k in keys) k.toJson()];

  /// Reads [toJson]'s list. Anything but a list is an empty curve, and
  /// entries that are not maps are skipped. Handles are kept as saved.
  factory KeyCurve.fromJson(Object? json) => KeyCurve([
    if (json is List)
      for (final k in json)
        if (k is Map) TimelineKey.fromJson(k.cast<String, dynamic>()),
  ]);
}

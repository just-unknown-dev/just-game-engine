/// Where the words in a scene's UI come from.
///
/// A saved scene cannot hold a closure, so a text says `"Coins: {coins}"`
/// and the game says what `coins` means:
///
/// ```dart
/// UiBindings.register('coins', () => signals.coins.value);
/// ```
///
/// The same names feed a bar's fill or a slider's value. This is the shape
/// `AnimatorBindings` already uses for animator parameters.
library;

import 'dart:math' as math;

import '../../ecs/ecs.dart';

/// Reads a value for a name. Anything may be returned; how it is written is
/// [UiBindings.format]'s business.
typedef UiBindingReader = Object? Function();

/// Reads a value for a name, for a particular entity — what `{self.health}`
/// asks for.
typedef UiEntityBindingReader = Object? Function(Entity entity);

abstract final class UiBindings {
  static final Map<String, UiBindingReader> _global = {};
  static final Map<String, UiEntityBindingReader> _perEntity = {};

  /// Makes [name] readable as `{name}`.
  static void register(String name, UiBindingReader read) =>
      _global[name] = read;

  /// Makes [name] readable as `{self.name}`, against the entity the text
  /// belongs to.
  static void registerForEntity(String name, UiEntityBindingReader read) =>
      _perEntity[name] = read;

  static void unregister(String name) {
    _global.remove(name);
    _perEntity.remove(name);
  }

  /// Everything a game has offered, for an editor to suggest.
  static List<String> get names =>
      [..._global.keys, for (final n in _perEntity.keys) 'self.$n']..sort();

  static bool has(String name) =>
      _global.containsKey(name) ||
      (name.startsWith('self.') && _perEntity.containsKey(name.substring(5)));

  /// Forgets every binding. For a test, or a game tearing down.
  static void clear() {
    _global.clear();
    _perEntity.clear();
  }

  /// What [name] reads right now, or null when nobody offers it.
  static Object? read(String name, {Entity? self}) {
    if (name.startsWith('self.')) {
      final reader = _perEntity[name.substring(5)];
      if (reader == null || self == null) return null;
      return reader(self);
    }
    return _global[name]?.call();
  }

  /// [name] as a number, for a bar or a slider; null when it is not one.
  static double? readNumber(String name, {Entity? self}) {
    final value = read(name, self: self);
    if (value is num) return value.toDouble();
    if (value is bool) return value ? 1 : 0;
    if (value is String) return double.tryParse(value);
    return null;
  }

  /// [source] with every `{name}` replaced by what it reads.
  ///
  /// A name may carry a format after a colon — `{time:mm:ss}`,
  /// `{score:n0}`, `{health:0.0}` — and `{{` writes a plain brace. A name
  /// nobody offers is left as it was written, so the mistake is on screen
  /// rather than silently blank.
  static String interpolate(String source, {Entity? self}) {
    if (!source.contains('{')) return source;
    final out = StringBuffer();
    var i = 0;
    while (i < source.length) {
      final char = source[i];
      if (char != '{') {
        out.write(char);
        i++;
        continue;
      }
      if (i + 1 < source.length && source[i + 1] == '{') {
        out.write('{');
        i += 2;
        continue;
      }
      final close = source.indexOf('}', i);
      if (close < 0) {
        out.write(source.substring(i));
        break;
      }
      final body = source.substring(i + 1, close);
      final colon = body.indexOf(':');
      final name = (colon < 0 ? body : body.substring(0, colon)).trim();
      final pattern = colon < 0 ? null : body.substring(colon + 1).trim();
      if (!has(name)) {
        out.write(source.substring(i, close + 1));
      } else {
        out.write(format(read(name, self: self), pattern));
      }
      i = close + 1;
    }
    return out.toString();
  }

  /// Every binding [source] asks for, in the order it asks.
  static List<String> namesIn(String source) {
    final found = <String>[];
    var i = 0;
    while (i < source.length) {
      if (source[i] != '{') {
        i++;
        continue;
      }
      if (i + 1 < source.length && source[i + 1] == '{') {
        i += 2;
        continue;
      }
      final close = source.indexOf('}', i);
      if (close < 0) break;
      final body = source.substring(i + 1, close);
      final colon = body.indexOf(':');
      found.add((colon < 0 ? body : body.substring(0, colon)).trim());
      i = close + 1;
    }
    return found;
  }

  /// How a value is written.
  ///
  /// - `mm:ss`, `hh:mm:ss`, `m:ss.S` — seconds as a clock
  /// - `n0`, `n1`… — a number with that many decimals and thousands marks
  /// - `0`, `0.00` — a number with that many decimals
  /// - `%`, `%0` — a fraction as a percentage
  /// - nothing — `toString`, with whole doubles losing their `.0`
  static String format(Object? value, [String? pattern]) {
    if (value == null) return '';
    if (pattern == null || pattern.isEmpty) {
      if (value is double && value == value.roundToDouble()) {
        return value.toInt().toString();
      }
      return '$value';
    }
    final number = value is num ? value.toDouble() : double.tryParse('$value');
    if (number == null) return '$value';

    if (pattern.contains(':') || pattern == 'S') return _clock(number, pattern);
    if (pattern.startsWith('%')) {
      final digits = int.tryParse(pattern.substring(1)) ?? 0;
      return '${(number * 100).toStringAsFixed(digits)}%';
    }
    if (pattern.startsWith('n')) {
      final digits = int.tryParse(pattern.substring(1)) ?? 0;
      return _grouped(number.toStringAsFixed(digits));
    }
    if (pattern.startsWith('0')) {
      final dot = pattern.indexOf('.');
      final digits = dot < 0 ? 0 : pattern.length - dot - 1;
      return number.toStringAsFixed(digits);
    }
    return '$value';
  }

  /// [seconds] laid out as [pattern] says: `mm:ss`, `h:mm:ss`, `m:ss.S`.
  static String _clock(double seconds, String pattern) {
    final negative = seconds < 0;
    final total = seconds.abs();
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    final secs = total % 60;
    final tenths = ((total - total.floorToDouble()) * 10).floor();

    String pad(int value, int width) => value.toString().padLeft(width, '0');

    final out = StringBuffer(negative ? '-' : '');
    if (pattern.contains('h')) {
      out
        ..write(pad(hours, pattern.contains('hh') ? 2 : 1))
        ..write(':')
        ..write(pad(minutes, 2));
    } else {
      // No hours asked for: minutes carry the whole span.
      final allMinutes = total ~/ 60;
      out.write(pad(allMinutes, pattern.contains('mm') ? 2 : 1));
    }
    out
      ..write(':')
      ..write(pad(secs.floor(), 2));
    if (pattern.contains('.S')) {
      out
        ..write('.')
        ..write(tenths);
    }
    return out.toString();
  }

  /// `1234567.8` → `1,234,567.8`.
  static String _grouped(String number) {
    final dot = number.indexOf('.');
    final whole = dot < 0 ? number : number.substring(0, dot);
    final rest = dot < 0 ? '' : number.substring(dot);
    final negative = whole.startsWith('-');
    final digits = negative ? whole.substring(1) : whole;
    final out = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return '${negative ? '-' : ''}$out$rest';
  }

  /// What the engine offers about itself, for anything that has not been
  /// given a game of its own. Called once by `registerUiSystems`.
  static void registerBuiltIns() {
    registerForEntity('name', (e) => e.name ?? '');
    registerForEntity('id', (e) => e.id);
  }

  /// A fraction of the way from [from] to [to], for a bar reading two
  /// bindings — `health` over `maxHealth`.
  static double fraction(String value, String max, {Entity? self}) {
    final now = readNumber(value, self: self) ?? 0;
    final most = readNumber(max, self: self) ?? 0;
    if (most <= 0) return 0;
    return (now / most).clamp(0.0, 1.0);
  }

  /// A hue for `[rainbow]` and the like, so effects elsewhere agree.
  static double hueAt(double seconds, double offset) =>
      (seconds * 120 + offset * 40) % 360;

  /// Seconds into a repeating span, for wave and pulse.
  static double phase(double seconds, double period) =>
      period <= 0 ? 0 : (seconds % period) / period * 2 * math.pi;
}

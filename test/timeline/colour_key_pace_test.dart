// Colour keys are ARGB ints: auto handles worked out as if they were
// numbers would be millions of units long, so a colour track's auto keys
// blend at an even pace and its flat keys ease, whatever such handles hold.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// The red channel of [argb], 0–255.
int _red(Object? argb) => ((argb! as int) >> 16) & 0xFF;

KeyCurve _keyed(int from, int to) => KeyCurve([
  TimelineKey(time: 0, value: from),
  TimelineKey(time: 1, value: to),
]).withAutoTangents();

void main() {
  test('black to white keyed as numbers fades at an even pace', () {
    final fade = _keyed(0xFF000000, 0xFFFFFFFF);
    expect(_red(fade.valueAt(0.25, isColor: true)), closeTo(64, 1));
    expect(_red(fade.valueAt(0.5, isColor: true)), closeTo(128, 1));
    expect(_red(fade.valueAt(0.75, isColor: true)), closeTo(191, 1));
  });

  test('white to black fades at the same pace, the other way', () {
    final fade = _keyed(0xFFFFFFFF, 0xFF000000);
    expect(_red(fade.valueAt(0.25, isColor: true)), closeTo(191, 1));
    expect(_red(fade.valueAt(0.75, isColor: true)), closeTo(64, 1));
  });

  test('red to green and green to red mirror each other', () {
    final there = _keyed(0xFFFF0000, 0xFF00FF00);
    final back = _keyed(0xFF00FF00, 0xFFFF0000);
    for (final t in [0.1, 0.3, 0.6, 0.9]) {
      expect(
        _red(there.valueAt(t, isColor: true)),
        closeTo(255 - _red(back.valueAt(t, isColor: true)), 1),
      );
    }
  });

  test('told it is a colour, auto handles are a third of the way', () {
    final fade = KeyCurve([
      const TimelineKey(time: 0, value: 0xFF000000),
      const TimelineKey(time: 2, value: 0xFFFFFFFF),
    ]).withAutoTangents(isColor: true);
    expect(fade.keys.first.outTangent, KeyTangent(2 / 3, 1 / 3));
    expect(fade.keys.last.inTangent, KeyTangent(-2 / 3, -1 / 3));
    expect(_red(fade.valueAt(0.5, isColor: true)), closeTo(64, 1));
    final keyed = KeyCurve(
      const [],
    ).withKey(const TimelineKey(time: 0, value: 0xFF000000), isColor: true);
    expect(keyed.keys, hasLength(1));
  });

  test('flat colour keys ease in and out', () {
    final fade = KeyCurve([
      const TimelineKey(
        time: 0,
        value: 0xFF000000,
        tangentMode: TangentMode.flat,
      ),
      const TimelineKey(
        time: 1,
        value: 0xFFFFFFFF,
        tangentMode: TangentMode.flat,
      ),
    ]).withAutoTangents();
    expect(_red(fade.valueAt(0.5, isColor: true)), closeTo(128, 1));
    expect(_red(fade.valueAt(0.25, isColor: true)), lessThan(64));
    expect(_red(fade.valueAt(0.75, isColor: true)), greaterThan(191));
  });
}

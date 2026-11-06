// One table of easing functions (Easings) behind both saved vocabularies:
// the effects' EasingType (saved by name) and the timelines' KeyEasings
// (saved by name in a key's `e`). The expected values were taken from the
// implementations before they were merged — EffectEasings.resolve and the
// animation subsystem's Easings — so a saved effect or timeline eases
// as it did. They were recorded on Windows; sin and pow come from each
// platform's maths library and may differ in the last bit, hence [_same].

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

const _ts = [0.0, 0.25, 0.5, 0.75, 1.0];

/// The recorded value, to within the last bits of a double.
Matcher _same(double expected) => closeTo(expected, 1e-12);

/// Every EasingType name, in declaration order (an effect saves the name),
/// with its value at 0, 0.25, 0.5, 0.75 and 1.
const _effectCurves = <String, List<double>>{
  'linear': [0.0, 0.25, 0.5, 0.75, 1.0],
  'easeInQuad': [0.0, 0.0625, 0.25, 0.5625, 1.0],
  'easeOutQuad': [0.0, 0.4375, 0.75, 0.9375, 1.0],
  'easeInOutQuad': [0.0, 0.125, 0.5, 0.875, 1.0],
  'easeInCubic': [0.0, 0.015625, 0.125, 0.421875, 1.0],
  'easeOutCubic': [0.0, 0.578125, 0.875, 0.984375, 1.0],
  'easeInOutCubic': [0.0, 0.0625, 0.5, 0.9375, 1.0],
  'easeInSine': [
    0.0,
    0.07612046748871326,
    0.2928932188134524,
    0.6173165676349102,
    0.9999999999999999,
  ],
  'easeOutSine': [
    0.0,
    0.3826834323650898,
    0.7071067811865476,
    0.9238795325112867,
    1.0,
  ],
  'easeInOutSine': [
    -0.0,
    0.1464466094067262,
    0.49999999999999994,
    0.8535533905932737,
    1.0,
  ],
  'easeInExpo': [0.0, 0.005524271728019903, 0.03125, 0.1767766952966369, 1.0],
  'easeOutExpo': [0.0, 0.8232233047033631, 0.96875, 0.99447572827198, 1.0],
  'easeInElastic': [
    0.0,
    -0.005524271728019903,
    -0.015625000000000045,
    0.08838834764831832,
    1.0,
  ],
  'easeOutElastic': [0.0, 0.9116116523516816, 1.015625, 1.00552427172802, 1.0],
  'easeInBounce': [0.0, 0.02734375, 0.234375, 0.52734375, 1.0],
  'easeOutBounce': [0.0, 0.47265625, 0.765625, 0.97265625, 1.0],
};

/// Every KeyEasings name, in registry order (a timeline key saves the name).
const _timelineNames = [
  'linear',
  'easeInQuad',
  'easeOutQuad',
  'easeInOutQuad',
  'easeInCubic',
  'easeOutCubic',
  'easeInOutCubic',
  'easeInOutSine',
  'easeInExpo',
  'easeOutExpo',
  'easeInElastic',
  'easeOutElastic',
  'easeInBounce',
  'easeOutBounce',
];

void main() {
  test('every EasingType keeps its saved name, in order', () {
    expect(EasingType.values.map((e) => e.name), _effectCurves.keys);
    for (final name in _effectCurves.keys) {
      expect(EasingType.values.byName(name).name, name);
    }
  });

  test('every EasingType eases as before', () {
    for (final MapEntry(key: name, value: expected) in _effectCurves.entries) {
      final type = EasingType.values.byName(name);
      for (var i = 0; i < _ts.length; i++) {
        final at = '$name(${_ts[i]})';
        expect(type.transform(_ts[i]), _same(expected[i]), reason: at);
        expect(type.curve(_ts[i]), _same(expected[i]), reason: at);
      }
    }
  });

  test('every KeyEasings name still resolves, in order', () {
    expect(
      KeyEasings.builtIn.names.take(_timelineNames.length),
      _timelineNames,
    );
  });

  test('every KeyEasings name eases as before', () {
    for (final name in _timelineNames) {
      final expected = _effectCurves[name]!;
      for (var i = 0; i < _ts.length; i++) {
        expect(
          KeyEasings.builtIn.apply(name, _ts[i]),
          _same(expected[i]),
          reason: '$name(${_ts[i]})',
        );
      }
    }
  });

  test('effects and timelines read the same functions from Easings', () {
    for (final type in EasingType.values) {
      for (final t in _ts) {
        final viaTable = switch (type) {
          EasingType.linear => Easings.linear(t),
          EasingType.easeInQuad => Easings.easeInQuad(t),
          EasingType.easeOutQuad => Easings.easeOutQuad(t),
          EasingType.easeInOutQuad => Easings.easeInOutQuad(t),
          EasingType.easeInCubic => Easings.easeInCubic(t),
          EasingType.easeOutCubic => Easings.easeOutCubic(t),
          EasingType.easeInOutCubic => Easings.easeInOutCubic(t),
          EasingType.easeInSine => Easings.easeInSine(t),
          EasingType.easeOutSine => Easings.easeOutSine(t),
          EasingType.easeInOutSine => Easings.easeInOutSine(t),
          EasingType.easeInExpo => Easings.easeInExpo(t),
          EasingType.easeOutExpo => Easings.easeOutExpo(t),
          EasingType.easeInElastic => Easings.easeInElastic(t),
          EasingType.easeOutElastic => Easings.easeOutElastic(t),
          EasingType.easeInBounce => Easings.easeInBounce(t),
          EasingType.easeOutBounce => Easings.easeOutBounce(t),
        };
        expect(type.transform(t), viaTable, reason: '${type.name}($t)');
        if (_timelineNames.contains(type.name)) {
          expect(KeyEasings.builtIn.apply(type.name, t), viaTable);
        }
      }
    }
  });

  test('an unknown timeline easing falls back to linear', () {
    expect(KeyEasings.builtIn.apply('noSuchEasing', 0.3), 0.3);
  });
}

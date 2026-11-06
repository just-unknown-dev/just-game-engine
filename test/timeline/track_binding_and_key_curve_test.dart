// TrackBinding.fromJson and KeyCurve.numberAt.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  group('TrackBinding.fromJson', () {
    test('a bare string reads as an entity target reads one', () {
      expect(TrackBinding.fromJson('#door'), const TrackBinding.tag('door'));
      expect(TrackBinding.fromJson('Door'), const TrackBinding.name('Door'));
      expect(TrackBinding.fromJson('self'), TrackBinding.owner);
      expect(TrackBinding.fromJson('  '), TrackBinding.owner);
      expect(TrackBinding.fromJson(null), TrackBinding.owner);
    });

    test('what the engine writes reads back unchanged', () {
      for (final binding in const [
        TrackBinding.owner,
        TrackBinding.name('Door'),
        TrackBinding.tag('lift'),
        TrackBinding.name(''),
      ]) {
        expect(TrackBinding.fromJson(binding.toJson()), binding);
      }
    });
  });

  group('KeyCurve.numberAt', () {
    test('reads a registered easing when given the easings', () {
      final easings = KeyEasings()..register('half', (t) => 0.5);
      final curve = KeyCurve([
        TimelineKey(
          time: 0,
          value: 0.0,
          interpolation: KeyInterpolation.eased,
          easing: 'half',
        ),
        TimelineKey(time: 1, value: 10.0),
      ]);
      expect(curve.numberAt(0.25), closeTo(2.5, 1e-9), reason: 'linear');
      expect(curve.numberAt(0.25, easings: easings), closeTo(5, 1e-9));
    });

    test('a bool reads as 1 or 0, a string as 0', () {
      final bools = KeyCurve([
        TimelineKey(time: 0, value: true),
        TimelineKey(time: 1, value: false),
      ]);
      expect(bools.numberAt(0.5), 1.0);
      expect(bools.numberAt(1), 0.0);
      final strings = KeyCurve([TimelineKey(time: 0, value: 'idle')]);
      expect(strings.numberAt(0), 0.0);
      expect(KeyCurve.empty.numberAt(3), 0.0);
    });
  });
}

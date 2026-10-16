// Animator and timeline fixes from the 2.0.0 final pass: parameters read
// the way conditions read them (F14, F15); newer graph files are refused
// (F16); a default can be cleared (F17); a bare-string track binding means
// what it says (F18); a curve reads engine easings and non-numbers (F20).

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  group('F14/F15 AnimatorComponent reads parameters as conditions do', () {
    test('numbers from bools and bools from numbers', () {
      final animator = AnimatorComponent()
        ..setBool('grounded', true)
        ..setTrigger('jumped')
        ..setFloat('speed', 2.5)
        ..setInt('lives', 0);
      expect(animator.getFloat('grounded'), 1.0, reason: 'used to throw');
      expect(animator.getInt('jumped'), 1);
      expect(animator.getBool('speed'), isTrue, reason: 'non-zero is on');
      expect(animator.getBool('lives'), isFalse);
      expect(animator.getFloat('missing'), 0.0);
      expect(animator.getBool('missing'), isFalse);
      animator.resetTrigger('jumped');
      expect(animator.getFloat('jumped'), 0.0);
    });
  });

  group('F16 AnimatorGraph versions', () {
    test('writes its version and reads a file without one as current', () {
      final graph = AnimatorGraph(states: const [AnimatorState(name: 'idle')]);
      final json = graph.toJson();
      // Format 2 adds crossfades and blend trees; a graph using neither is
      // still written as format 1, so older engines read it.
      expect(json['version'], 1);
      expect(
        graph
            .copyWith(transitions: const [AnimatorTransition(from: 'idle', to: 'idle', duration: 0.1)])
            .toJson()['version'],
        AnimatorGraph.formatVersion,
      );
      final versionless = Map<String, dynamic>.of(json)..remove('version');
      expect(AnimatorGraph.fromJson(versionless).states.single.name, 'idle');
    });

    test('refuses a graph from a newer engine', () {
      final json = AnimatorGraph().toJson()
        ..['version'] = AnimatorGraph.formatVersion + 1;
      expect(
        () => AnimatorGraph.fromJson(json),
        throwsA(
          isA<UnsupportedFormatVersionException>()
              .having((e) => e.found, 'found', AnimatorGraph.formatVersion + 1)
              .having((e) => e.kind, 'kind', 'animator graph'),
        ),
      );
    });
  });

  test('F17 AnimatorParameter.copyWith can clear the default', () {
    const p = AnimatorParameter(name: 'speed', defaultValue: 3.0);
    expect(p.copyWith().defaultValue, 3.0);
    expect(p.copyWith(clearDefaultValue: true).defaultValue, isNull);
    expect(p.copyWith(defaultValue: 5.0).defaultValue, 5.0);
  });

  group('F18 TrackBinding.fromJson', () {
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

  group('F20 KeyCurve.numberAt', () {
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

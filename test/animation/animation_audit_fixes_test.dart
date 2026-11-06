// Animator fixes from the 2.0.0 final pass: parameters read the way
// conditions read them (F14, F15); newer graph files are refused (F16); a
// default can be cleared (F17). (The timeline ones are in
// timeline/track_binding_and_key_curve_test.dart.)

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  group('AnimatorComponent reads parameters as conditions do', () {
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

  group('AnimatorGraph versions', () {
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

  test('AnimatorParameter.copyWith can clear the default', () {
    const p = AnimatorParameter(name: 'speed', defaultValue: 3.0);
    expect(p.copyWith().defaultValue, 3.0);
    expect(p.copyWith(clearDefaultValue: true).defaultValue, isNull);
    expect(p.copyWith(defaultValue: 5.0).defaultValue, 5.0);
  });
}

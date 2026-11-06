// A context's animation state: the default graph loader reads the
// context's bundle, and a context without built-ins has no parameter
// bindings.

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// Files from a map, for a context's bundle.
class _MapBundle extends CachingAssetBundle {
  _MapBundle(this.files);
  final Map<String, String> files;
  final List<String> reads = [];

  @override
  Future<ByteData> load(String key) async {
    reads.add(key);
    final text = files[key];
    if (text == null) throw StateError('no $key');
    return ByteData.sublistView(utf8.encode(text));
  }
}

const _graph = AnimatorGraph(
  entry: 'idle',
  parameters: [AnimatorParameter(name: 'speed', binding: 'speedX')],
  states: [
    AnimatorState(name: 'idle'),
    AnimatorState(name: 'run'),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test("the graph loader reads the context's bundle", () async {
    final bundle = _MapBundle({'g.animator.json': _graph.encode()});
    final context = EngineContext(bundle: bundle);
    addTearDown(context.dispose);
    final graph = await context.animatorGraphs('g.animator.json');
    expect(bundle.reads, ['g.animator.json']);
    expect(graph.toJson(), _graph.toJson());
  });

  test('a context without built-ins has no bindings', () {
    final context = EngineContext(withBuiltIns: false);
    addTearDown(context.dispose);
    expect(context.animatorBindings.ids, isEmpty);
    expect(context.animatorBindings.of('speedX'), isNull);
    final withThem = EngineContext();
    addTearDown(withThem.dispose);
    expect(withThem.animatorBindings.of('speedX'), isNotNull);
  });
}

// A context's timeline state: the default loader reads the context's bundle
// with the context's track kinds and migration rules, brings an older file
// up to date (a v2 track naming a renamed component plays the new one), and
// a context without built-ins starts with no track kinds or easings.

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test("the bundle loader reads with the context's kinds and rules", () async {
    final bundle = _MapBundle({
      't.timeline.json': jsonEncode({
        'duration': 2,
        'tracks': [
          {'kind': 'event', 'events': <dynamic>[]},
          {'kind': 'weather', 'name': 'rain'},
        ],
      }),
    });
    final context = EngineContext(bundle: bundle);
    addTearDown(context.dispose);
    context.trackKinds.register(
      'weather',
      (json) => EventTrack(name: json['name'] as String),
    );
    context.migrations.perTrack.add(
      (track) => track['kind'] == 'event' ? {...track, 'name': 'moved'} : track,
    );

    final asset = await context.timelines('t.timeline.json');
    expect(bundle.reads, ['t.timeline.json']);
    expect(asset.duration, 2);
    expect(asset.tracks[0].name, 'moved', reason: "the context's rule ran");
    expect(asset.tracks[1], isA<EventTrack>(), reason: "the context's kind");
    expect(asset.tracks[1].name, 'rain');
  });

  test('a format 2 timeline keying a renamed component drives the new '
      'one', () async {
    final bundle = _MapBundle({
      'grow.timeline.json': jsonEncode({
        'formatVersion': 2,
        'duration': 1,
        'tracks': [
          {
            'kind': 'property',
            'component': 'CircleComponent',
            'field': 'radius',
            'keys': [
              {'t': 0, 'v': 10, 'i': 'linear'},
              {'t': 1, 'v': 30},
            ],
          },
        ],
      }),
    });
    final context = EngineContext(
      bundle: bundle,
      extensions: [BuiltInComponents.extension],
    );
    addTearDown(context.dispose);
    final world = World(context: context);
    addTearDown(world.dispose);
    registerSpriteSystems(world);

    final asset = await context.timelines('grow.timeline.json');
    expect(
      (asset.tracks.single as PropertyTrack).component,
      'Circle2DComponent',
    );

    final circle = Circle2DComponent(radius: 1);
    final player = TimelinePlayerComponent(
      timelinePath: 'grow.timeline.json',
      playOnStart: true,
    );
    world.createEntityWithComponents([TransformComponent(), circle, player]);
    world.update(0);
    await pumpEventQueue();
    world.update(0.5);
    expect(circle.radius, closeTo(20, 1e-9));
  });

  test('a context without built-ins has no track kinds or easings', () {
    final context = EngineContext(withBuiltIns: false);
    addTearDown(context.dispose);
    expect(context.trackKinds.kinds, isEmpty);
    expect(context.trackKinds.offered, isEmpty);
    expect(context.easings.names, isEmpty);
    expect(
      context.easings.apply('easeInQuad', 0.5),
      0.5,
      reason: 'an unknown easing is linear',
    );
    final withThem = EngineContext();
    addTearDown(withThem.dispose);
    expect(withThem.trackKinds.kinds, contains(PropertyTrack.kindId));
    expect(withThem.easings.apply('easeInQuad', 0.5), 0.25);
  });
}

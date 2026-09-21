// Timelines: keys and curves, property tracks, playback, the player
// component, and the v3 → v4 migration.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

const _dt = 1 / 60;

TimelineKey _k(
  double t,
  Object v, {
  KeyInterpolation i = KeyInterpolation.linear,
}) => TimelineKey(time: t, value: v, interpolation: i);

PropertyTrack _posX(
  List<TimelineKey> keys, {
  PropertyTrackMode mode = PropertyTrackMode.absolute,
  TrackBinding binding = TrackBinding.owner,
}) => PropertyTrack(
  component: 'TransformComponent',
  field: 'position',
  channel: 'x',
  mode: mode,
  binding: binding,
  curve: KeyCurve(keys),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(registerCoreCodecs);

  group('curves', () {
    test('linear, step and the ends', () {
      final curve = KeyCurve([
        _k(1, 10.0),
        _k(2, 20.0, i: KeyInterpolation.step),
        _k(3, 40.0),
      ]);
      expect(curve.valueAt(0), 10.0, reason: 'before the first key');
      expect(curve.valueAt(1.5), closeTo(15, 1e-9));
      expect(curve.valueAt(2.9), 20.0, reason: 'a step holds');
      expect(curve.valueAt(3), 40.0);
      expect(curve.valueAt(9), 40.0, reason: 'after the last key');
      expect(KeyCurve.empty.valueAt(1), isNull);
    });

    test('a bezier hits its keys and never runs backwards in time', () {
      final curve = KeyCurve([
        const TimelineKey(
          time: 0,
          value: 0.0,
          outTangent: Tangent(5, 0), // far longer than the segment
          tangentMode: TangentMode.broken,
        ),
        const TimelineKey(
          time: 1,
          value: 100.0,
          inTangent: Tangent(-5, 0),
          tangentMode: TangentMode.broken,
        ),
      ]);
      expect(curve.numberAt(0), 0);
      expect(curve.numberAt(1), 100);
      var last = -1.0;
      for (var i = 0; i <= 100; i++) {
        final v = curve.numberAt(i / 100);
        expect(v, greaterThanOrEqualTo(last - 1e-6), reason: 'at ${i / 100}');
        last = v;
      }
      expect(curve.numberAt(0.5), closeTo(50, 0.5), reason: 'an S, symmetric');
      expect(curve.numberAt(0.1), lessThan(5), reason: 'it eases in');
    });

    test('an eased key uses the named easing, overshoot and all', () {
      final curve = KeyCurve([
        const TimelineKey(
          time: 0,
          value: 0.0,
          interpolation: KeyInterpolation.eased,
          easing: 'easeOutBounce',
        ),
        _k(1, 10.0),
      ]);
      expect(curve.numberAt(1), 10);
      expect(
        curve.numberAt(0.5),
        closeTo(10 * Easings.easeOutBounce(0.5), 1e-9),
      );
    });

    test('colours blend by channel and never leave the range', () {
      final curve = KeyCurve([_k(0, 0xFF000000), _k(1, 0xFFFF8000)]);
      expect(curve.valueAt(0.5, isColor: true), 0xFF804000);
      final wild = KeyCurve([
        const TimelineKey(
          time: 0,
          value: 0xFF000000,
          outTangent: Tangent(0.3, 9),
          tangentMode: TangentMode.broken,
        ),
        _k(1, 0xFFFFFFFF),
      ]);
      for (var i = 0; i <= 10; i++) {
        final c = wild.valueAt(i / 10, isColor: true)! as int;
        expect(c >> 24 & 0xFF, 0xFF);
      }
    });

    test('auto tangents rest flat on a peak and slope through a run', () {
      final curve = KeyCurve([
        const TimelineKey(time: 0, value: 0.0),
        const TimelineKey(time: 1, value: 10.0),
        const TimelineKey(time: 2, value: 0.0),
      ]).withAutoTangents();
      expect(curve.keys[1].outTangent.dv, 0, reason: 'a peak');
      var top = 0.0;
      for (var i = 0; i <= 200; i++) {
        final v = curve.numberAt(i / 100);
        if (v > top) top = v;
      }
      expect(top, closeTo(10, 1e-6), reason: 'no overshoot past the peak');

      final run = KeyCurve([
        const TimelineKey(time: 0, value: 0.0),
        const TimelineKey(time: 1, value: 10.0),
        const TimelineKey(time: 2, value: 20.0),
      ]).withAutoTangents();
      expect(run.keys[1].outTangent.dv, closeTo(10 / 3, 1e-9));
      expect(run.numberAt(1.5), closeTo(15, 0.2));
    });

    test('withKey replaces a key at the same time', () {
      final curve = KeyCurve([_k(0, 1.0), _k(1, 2.0)]).withKey(_k(1, 5.0));
      expect(curve.keys, hasLength(2));
      expect(curve.keys.last.value, 5.0);
    });
  });

  group('asset', () {
    test('round-trips through JSON, unknown tracks included', () {
      final asset = TimelineAsset(
        name: 'door',
        duration: 2,
        fps: 24,
        wrap: TimelineWrap.pingPong,
        markers: const [TimelineMarker(time: 1, name: 'open')],
        tracks: [
          _posX(
            [_k(0, 0.0), _k(2, 64.0)],
            mode: PropertyTrackMode.relative,
            binding: const TrackBinding.tag('door'),
          ),
          EventTrack(
            events: const [
              TimelineEvent(time: 1, name: 'clunk', payload: 'loud'),
            ],
          ),
        ],
      );
      final json = asset.toJson();
      (json['tracks'] as List).add({'kind': 'weather', 'rain': 3});
      final back = TimelineAsset.parse(TimelineAsset.fromJson(json).encode());
      expect(back.toJson(), json);
      expect(back.tracks[2], isA<UnknownTrack>());
      expect(back.markerNamed('open')!.time, 1);
      final track = back.tracks.first as PropertyTrack;
      expect(track.binding, const TrackBinding.tag('door'));
      expect(track.isRelative, isTrue);
      expect(track.path, 'TransformComponent.position.x');
    });

    test('validate says what is wrong', () {
      final asset = TimelineAsset(
        duration: 1,
        tracks: [
          _posX([_k(0, 0.0), _k(3, 1.0)]),
          _posX([_k(0, 0.0)]),
          _posX([_k(0, 0.0)], binding: const TrackBinding.name(' ')),
        ],
      );
      final problems = asset.validate().join('\n');
      expect(problems, contains('runs past the end'));
      expect(problems, contains('two tracks'));
      expect(problems, contains('bound to nobody'));
      expect(
        TimelineAsset(
          tracks: [
            _posX([_k(0, 0.0)]),
          ],
        ).validate(),
        isEmpty,
      );
    });

    test('a package registers its own kind of track', () {
      TimelineTrackKinds.register('test.counter', _CounterTrack.fromJson);
      addTearDown(() => TimelineTrackKinds.unregister('test.counter'));
      final asset = TimelineAsset.fromJson({
        'duration': 1.0,
        'tracks': [
          {'kind': 'test.counter'},
        ],
      });
      expect(asset.tracks.single, isA<_CounterTrack>());
      final world = World();
      final playback = TimelinePlayback(
        asset,
        world: world,
        owner: world.createEntity(),
      )..play();
      playback.update(0.5);
      expect(_CounterTrack.applied, greaterThan(0));
    });
  });

  group('property access', () {
    late World world;
    setUp(() => world = World());

    test('reads and writes a channel, a number, a bool and a colour', () {
      final entity = world.createEntityWithComponents([
        TransformComponent(position: Vector3(3, 4, 0)),
        SpriteAnimationComponent(atlasPath: 'a.json'),
      ]);
      final y = PropertyAccess.of(
        entity,
        'TransformComponent',
        'position',
        'y',
      )!;
      expect(y.read(), 4.0);
      y.write(9.5);
      final at = entity.getComponent<TransformComponent>()!.position;
      expect([at.x, at.y], [3.0, 9.5], reason: 'x is left alone');

      final flip = PropertyAccess.of(
        entity,
        'SpriteAnimationComponent',
        'flipX',
      )!;
      flip.write(true);
      final tint = PropertyAccess.of(
        entity,
        'SpriteAnimationComponent',
        'tint',
      )!;
      expect(tint.read(), isNull);
      tint.write(0xFF112233);
      final sprite = entity.getComponent<SpriteAnimationComponent>()!;
      expect(sprite.flipX, isTrue);
      expect(sprite.tint!.toARGB32(), 0xFF112233);

      expect(PropertyAccess.of(entity, 'TransformComponent', 'nope'), isNull);
      expect(PropertyAccess.of(entity, 'NopeComponent', 'x'), isNull);
      expect(
        PropertyAccess.of(entity, 'VelocityComponent', 'velocity', 'x'),
        isNull,
        reason: 'the entity has no such component',
      );
    });
  });

  group('playback', () {
    late World world;
    setUp(() => world = World());

    Entity at(double x, {String? name, String? tag}) =>
        world.createEntityWithComponents([
          TransformComponent(position: Vector3(x, 0, 0)),
          if (tag != null) TagComponent(tag),
        ], name: name);

    double xOf(Entity e) => e.getComponent<TransformComponent>()!.position.x;

    test('a relative timeline moves two entities from where each stands', () {
      final asset = TimelineAsset(
        duration: 1,
        tracks: [
          _posX([_k(0, 0.0), _k(1, 64.0)], mode: PropertyTrackMode.relative),
        ],
      );
      final a = at(100), b = at(500);
      final pa = TimelinePlayback(asset, world: world, owner: a)..play();
      final pb = TimelinePlayback(asset, world: world, owner: b)..play();
      pa.update(0.5);
      pb.update(1.0);
      expect(xOf(a), closeTo(132, 1e-9));
      expect(xOf(b), closeTo(564, 1e-9));
      expect(pb.isFinished, isTrue);
      expect(pa.isFinished, isFalse);

      // Playing again starts from where it now stands.
      pb.play();
      pb.update(1.0);
      expect(xOf(b), closeTo(628, 1e-9));
    });

    test('bindings resolve late; one bound to nobody is skipped', () {
      final asset = TimelineAsset(
        duration: 1,
        tracks: [
          _posX([
            _k(0, 0.0),
            _k(1, 10.0),
          ], binding: const TrackBinding.name('Door')),
          _posX([
            _k(0, 0.0),
            _k(1, 20.0),
          ], binding: const TrackBinding.tag('lift')),
        ],
      );
      final owner = at(0);
      final lift = at(0, tag: 'lift');
      final playback = TimelinePlayback(asset, world: world, owner: owner)
        ..play();
      playback.update(0.5);
      expect(xOf(lift), closeTo(10, 1e-9));
      expect(xOf(owner), 0, reason: 'nothing is bound to self');

      final door = at(0, name: 'Door'); // arrives mid-play
      playback.update(0.25);
      expect(xOf(door), closeTo(7.5, 1e-9));
    });

    test('wrap: once stops, loop carries over, ping-pong comes back', () {
      final asset = TimelineAsset(
        duration: 1,
        tracks: [
          _posX([_k(0, 0.0), _k(1, 100.0)]),
        ],
      );
      final e = at(0);
      final once = TimelinePlayback(asset, world: world, owner: e)..play();
      once.update(1.5);
      expect(xOf(e), 100);
      expect(once.isPlaying, isFalse);

      final loop = TimelinePlayback(asset, world: world, owner: e)
        ..wrap = TimelineWrap.loop
        ..play();
      loop.update(1.25);
      expect(xOf(e), closeTo(25, 1e-6));
      expect(loop.isPlaying, isTrue);

      final bounce = TimelinePlayback(asset, world: world, owner: e)
        ..wrap = TimelineWrap.pingPong
        ..play();
      bounce.update(1.25);
      expect(xOf(e), closeTo(75, 1e-6));
      bounce.update(1.0);
      expect(xOf(e), closeTo(25, 1e-6), reason: 'off the start, forwards');

      final back = TimelinePlayback(asset, world: world, owner: e)
        ..speed = -2
        ..play();
      expect(back.time, 1, reason: 'backwards starts at the end');
      back.update(0.25);
      expect(xOf(e), closeTo(50, 1e-6));
      back.update(1);
      expect(back.isFinished, isTrue);
      expect(xOf(e), 0);
    });

    test('events fire once per crossing, both ways, and not on a seek', () {
      final fired = <String>[];
      final asset = TimelineAsset(
        duration: 1,
        tracks: [
          EventTrack(
            events: const [
              TimelineEvent(time: 0, name: 'start'),
              TimelineEvent(time: 0.5, name: 'mid', payload: 'p'),
              TimelineEvent(time: 1, name: 'end'),
            ],
          ),
        ],
      );
      final playback = TimelinePlayback(
        asset,
        world: world,
        owner: at(0),
        onEvent: (e) => fired.add(e.name + e.payload),
      )..wrap = TimelineWrap.pingPong;

      playback.seek(0.75);
      expect(fired, isEmpty);

      playback.play(from: 0);
      playback.update(0.25);
      expect(fired, ['start']);
      playback.update(0.25);
      playback.update(0.25);
      expect(fired, ['start', 'midp']);
      playback.update(0.5); // to the end and a quarter of the way back
      expect(fired, ['start', 'midp', 'end']);
      playback.update(0.5);
      expect(fired, ['start', 'midp', 'end', 'midp']);

      fired.clear();
      final loop = TimelinePlayback(
        asset,
        world: world,
        owner: at(0),
        onEvent: (e) => fired.add(e.name),
      )..wrap = TimelineWrap.loop;
      loop.play();
      loop.update(1.25);
      expect(fired, ['start', 'mid', 'end', 'start']);
      loop.update(40); // dozens of laps in one step do not fire dozens
      expect(fired.length, lessThan(16));
    });

    test('a muted track is not played; markers start a play', () {
      final asset = TimelineAsset(
        duration: 2,
        markers: const [TimelineMarker(time: 1, name: 'half')],
        tracks: [
          _posX([_k(0, 0.0), _k(2, 200.0)]),
          PropertyTrack(
            component: 'TransformComponent',
            field: 'rotation',
            muted: true,
            curve: KeyCurve([_k(0, 0.0), _k(2, 2.0)]),
          ),
        ],
      );
      final e = at(0);
      final playback = TimelinePlayback(asset, world: world, owner: e);
      expect(playback.playFrom('nope'), isFalse);
      expect(playback.playFrom('half'), isTrue);
      playback.update(0.5);
      expect(xOf(e), closeTo(150, 1e-9));
      expect(e.getComponent<TransformComponent>()!.rotation, 0);
    });
  });

  group('a play range', () {
    late World world;
    setUp(() => world = World());

    /// 0 → 100 over two seconds, with an event before a range of 0.5–1.5,
    /// one on its start, one inside it and one past its end.
    TimelineAsset asset() => TimelineAsset(
      duration: 2,
      tracks: [
        _posX([_k(0, 0.0), _k(2, 100.0)]),
        EventTrack(
          events: const [
            TimelineEvent(time: 0, name: 'before'),
            TimelineEvent(time: 0.5, name: 'start'),
            TimelineEvent(time: 1, name: 'inside'),
            TimelineEvent(time: 2, name: 'after'),
          ],
        ),
      ],
    );

    Entity at(double x) => world.createEntityWithComponents([
      TransformComponent(position: Vector3(x, 0, 0)),
    ]);

    double xOf(Entity e) => e.getComponent<TransformComponent>()!.position.x;

    test('play, stop and progress run between its edges', () {
      final e = at(0);
      final fired = <String>[];
      final playback = TimelinePlayback(
        asset(),
        world: world,
        owner: e,
        onEvent: (f) => fired.add(f.name),
      )..range = (0.5, 1.5);
      expect(playback.bounds, (0.5, 1.5));
      expect(playback.playLength, 1);

      playback.play();
      expect(playback.time, 0.5, reason: 'not zero');
      expect(fired, isEmpty, reason: 'nothing has ticked yet');
      playback.update(0.5);
      expect(xOf(e), closeTo(50, 1e-9));
      expect(playback.progress, closeTo(0.5, 1e-9));
      expect(
        fired,
        ['start', 'inside'],
        reason:
            'what sits where play begins happens on the first tick; what '
            'lies before the range never does',
      );
      playback.update(0.5);
      expect(playback.isFinished, isTrue, reason: 'the end of the range');
      expect(xOf(e), closeTo(75, 1e-9));
      expect(fired, ['start', 'inside'], reason: 'nothing past 1.5 s');

      playback.stop();
      expect(playback.time, 0.5, reason: 'rewinds to the range, not to 0');
    });

    test('loop and ping-pong turn at its edges', () {
      final e = at(0);
      final loop = TimelinePlayback(asset(), world: world, owner: e)
        ..range = (1, 2)
        ..wrap = TimelineWrap.loop;
      loop.play();
      loop.update(1.25);
      expect(loop.time, closeTo(1.25, 1e-9), reason: 'wrapped to 1, not to 0');
      expect(xOf(e), closeTo(62.5, 1e-6));

      final bounce = TimelinePlayback(asset(), world: world, owner: e)
        ..range = (1, 2)
        ..wrap = TimelineWrap.pingPong;
      bounce.play();
      bounce.update(1.25);
      expect(bounce.time, closeTo(1.75, 1e-9));

      final back = TimelinePlayback(asset(), world: world, owner: e)
        ..range = (0.5, 1.5)
        ..speed = -1;
      back.play();
      expect(back.time, 1.5, reason: 'backwards starts at the range end');
      back.update(1.0);
      expect(back.time, 0.5);
      expect(back.isFinished, isTrue);
    });

    test('a range that is not a stretch of time plays the whole thing', () {
      final e = at(0);
      for (final asked in <(double, double)>[
        (2, 1), // backwards
        (1, 1), // empty
        (9, 9), // past the end
        (-5, 0), // before the start
      ]) {
        final playback = TimelinePlayback(asset(), world: world, owner: e)
          ..range = asked;
        expect(playback.bounds, (0.0, 2.0), reason: '$asked');
      }
      // Past the end, or at zero, means "to the end".
      final open = TimelinePlayback(asset(), world: world, owner: e)
        ..range = (1, 0);
      expect(open.bounds, (1.0, 2.0));
      final clipped = TimelinePlayback(asset(), world: world, owner: e)
        ..range = (1, 99);
      expect(clipped.bounds, (1.0, 2.0));
    });

    test('two entities play different parts of one timeline', () async {
      registerSpriteSystems(world, timelineLoader: (_) async => asset());
      final whole = world.createEntityWithComponents([
        TransformComponent(),
        TimelinePlayerComponent(
          timelinePath: 'a.timeline.json',
          playOnStart: true,
        ),
      ]);
      final half = world.createEntityWithComponents([
        TransformComponent(),
        TimelinePlayerComponent(
          timelinePath: 'a.timeline.json',
          playOnStart: true,
          from: 1,
          to: 2,
        ),
      ]);
      world.update(_dt);
      await Future<void>.delayed(Duration.zero);
      world.update(0.5);
      expect(xOf(whole), closeTo(25, 1), reason: 'half a second in');
      expect(xOf(half), closeTo(75, 1), reason: 'from 1 s, half a second in');
      expect(
        half.getComponent<TimelinePlayerComponent>()!.progress,
        closeTo(0.5, 0.05),
      );
      expect(
        whole.getComponent<TimelinePlayerComponent>()!.progress,
        closeTo(0.25, 0.05),
      );
    });

    test('changing the range mid-play brings the playhead into it', () async {
      registerSpriteSystems(world, timelineLoader: (_) async => asset());
      final entity = world.createEntityWithComponents([
        TransformComponent(),
        TimelinePlayerComponent(
          timelinePath: 'a.timeline.json',
          playOnStart: true,
        ),
      ]);
      final player = entity.getComponent<TimelinePlayerComponent>()!;
      world.update(_dt);
      await Future<void>.delayed(Duration.zero);
      world.update(0.25);
      expect(player.time, closeTo(0.25, 0.02));

      player
        ..from = 1
        ..to = 2;
      world.update(_dt);
      expect(player.hasRange, isTrue);
      player.play();
      world.update(_dt);
      expect(player.time, greaterThanOrEqualTo(1));
    });

    test('the range survives a save and a load', () {
      final definition = ComponentDefinitionRegistry.instance.definitionByType(
        'TimelinePlayerComponent',
      )!;
      final player = TimelinePlayerComponent(from: 0.25, to: 1.75);
      final saved = {
        for (final f in definition.fields) f.name: f.encodeFrom(player),
      };
      final loaded = TimelinePlayerComponent();
      for (final f in definition.fields) {
        f.decodeInto(loaded, saved[f.name]);
      }
      expect((loaded.from, loaded.to), (0.25, 1.75));
      expect(loaded.playRange, (0.25, 1.75));

      // A scene saved before the fields existed has no key for them, and
      // the loader passes over what it does not find.
      final older = definition.decode({
        'type': 'TimelinePlayerComponent',
        'fields': {'timelinePath': 'a.timeline.json', 'playOnStart': true},
      });
      expect((older as TimelinePlayerComponent).hasRange, isFalse);
      expect(older.timelinePath, 'a.timeline.json');
    });
  });

  group('the player component', () {
    late World world;
    late TimelineSystem system;
    final files = <String, TimelineAsset>{};
    var loads = 0;

    setUp(() {
      loads = 0;
      files
        ..clear()
        ..['slide.timeline.json'] = TimelineAsset(
          duration: 1,
          tracks: [
            _posX([_k(0, 0.0), _k(1, 60.0)], mode: PropertyTrackMode.relative),
            EventTrack(events: const [TimelineEvent(time: 0.5, name: 'half')]),
          ],
        );
      world = World();
      // A game with no editor: only the engine's own registration.
      registerSpriteSystems(
        world,
        timelineLoader: (path) async {
          loads++;
          final asset = files[path];
          if (asset == null) throw StateError('no $path');
          return TimelineAsset.parse(asset.encode());
        },
      );
      system = world.systems.whereType<TimelineSystem>().single;
    });

    Future<void> settle() => Future<void>.delayed(Duration.zero);

    test('loads a shared asset once and plays it on start', () async {
      final fired = <String>[];
      system.events.listen((e) => fired.add(e.name));
      final a = world.createEntityWithComponents([
        TransformComponent(position: Vector3(10, 0, 0)),
        TimelinePlayerComponent(
          timelinePath: 'slide.timeline.json',
          playOnStart: true,
        ),
      ]);
      final b = world.createEntityWithComponents([
        TransformComponent(position: Vector3(200, 0, 0)),
        TimelinePlayerComponent(timelinePath: 'slide.timeline.json'),
      ]);
      world.update(_dt);
      await settle();
      expect(loads, 1);
      for (var i = 0; i < 30; i++) {
        world.update(_dt);
      }
      expect(
        a.getComponent<TransformComponent>()!.position.x,
        closeTo(40, 1e-6),
      );
      expect(b.getComponent<TransformComponent>()!.position.x, 200);
      world.update(_dt);
      expect(fired, ['half']);
      expect(system.assetOf(a), isNotNull);
    });

    test('play asked before the load is done once it lands', () async {
      final entity = world.createEntityWithComponents([
        TransformComponent(),
        TimelinePlayerComponent(timelinePath: 'slide.timeline.json'),
      ]);
      final player = entity.getComponent<TimelinePlayerComponent>()!..play();
      world.update(_dt);
      expect(player.isPlaying, isFalse);
      await settle();
      expect(player.isPlaying, isTrue);
      world.update(0.5);
      expect(player.progress, closeTo(0.5, 1e-9));

      player.speed = 2;
      world.update(0.125);
      expect(player.time, closeTo(0.75, 1e-9));
    });

    test('an inline timeline plays with no file; a missing file is asked for '
        'once', () async {
      final inline = world.createEntityWithComponents([
        TransformComponent(),
        TimelinePlayerComponent(
          inline: TimelineAsset(
            duration: 1,
            tracks: [
              _posX([_k(0, 5.0), _k(1, 15.0)]),
            ],
          ),
          playOnStart: true,
          wrap: TimelineWrapChoice.loop,
        ),
      ]);
      world.createEntityWithComponents([
        TransformComponent(),
        TimelinePlayerComponent(timelinePath: 'gone.timeline.json'),
      ]);
      for (var i = 0; i < 5; i++) {
        world.update(0.25);
        await settle();
      }
      expect(loads, 1);
      expect(
        inline.getComponent<TransformComponent>()!.position.x,
        closeTo(7.5, 1e-6),
        reason: '1.25 s into a 1 s loop',
      );
    });

    test('reload starts players of that file over with the new one', () async {
      final entity = world.createEntityWithComponents([
        TransformComponent(),
        TimelinePlayerComponent(
          timelinePath: 'slide.timeline.json',
          playOnStart: true,
        ),
      ]);
      world.update(_dt);
      await settle();
      files['slide.timeline.json'] = TimelineAsset(duration: 9);
      system.reload('slide.timeline.json');
      world.update(_dt);
      await settle();
      expect(loads, 2);
      expect(system.assetOf(entity)!.duration, 9);
    });

    test('the component survives a save and a load', () {
      final registry = ComponentDefinitionRegistry.instance;
      final definition = registry.definitionByType('TimelinePlayerComponent')!;
      final player = TimelinePlayerComponent(
        timelinePath: 'a.timeline.json',
        inline: TimelineAsset(
          tracks: [
            _posX([_k(0, 1.0)]),
          ],
        ),
        speed: -1.5,
        wrap: TimelineWrapChoice.pingPong,
        listenSignal: 'go',
      );
      final saved = {
        for (final f in definition.fields) f.name: f.encodeFrom(player),
      };
      final loaded = TimelinePlayerComponent();
      for (final f in definition.fields) {
        f.decodeInto(loaded, saved[f.name]);
      }
      expect(loaded.timelinePath, 'a.timeline.json');
      expect(loaded.inline!.toJson(), player.inline!.toJson());
      expect(loaded.speed, -1.5);
      expect(loaded.wrap, TimelineWrapChoice.pingPong);
      expect(loaded.listenSignal, 'go');
    });
  });

  group('v3 → v4', () {
    Map<String, dynamic> v3() => {
      'version': 3,
      'entities': [
        {
          'name': 'Lift',
          'components': [
            {
              'type': 'TransformComponent',
              'fields': {
                'position': {'x': 0.0, 'y': 0.0},
              },
            },
            {
              'type': 'AnimationControllerComponent',
              'fields': {
                'duration': 2.0,
                'loop': true,
                'playOnStart': true,
                'keyframes': [
                  {'time': 0.0, 'posX': 0.0, 'posY': 10.0, 'easing': 'easeIn'},
                  {'time': 1.0, 'posX': 100.0, 'rotation': 1.0},
                  {'time': 2.0, 'posX': 0.0, 'posY': 30.0},
                ],
                'events': [
                  {'time': 1.0, 'name': 'top'},
                ],
              },
            },
          ],
        },
      ],
    };

    test('the old controller becomes a player with an inline timeline', () {
      final migrated = SceneFormat.migrate(v3());
      expect(migrated['version'], SceneFormat.current);
      final components =
          (migrated['entities'] as List).single['components'] as List;
      final player = components[1] as Map;
      expect(player['type'], 'TimelinePlayerComponent');
      final fields = player['fields'] as Map;
      expect(fields['playOnStart'], isTrue);
      final asset = TimelineAsset.fromJson(
        (fields['inline'] as Map).cast<String, dynamic>(),
      );
      expect(asset.duration, 2);
      expect(asset.wrap, TimelineWrap.loop);
      expect(asset.validate(), isEmpty);
      expect(
        [for (final t in asset.propertyTracks) t.path],
        [
          'TransformComponent.position.x',
          'TransformComponent.position.y',
          'TransformComponent.rotation',
        ],
      );
      expect(asset.tracks.last, isA<EventTrack>());

      // It plays as it used to: eased in (t²) to the first key, then linear.
      final x = asset.propertyTracks.first.curve;
      expect(x.numberAt(0.5), closeTo(25, 0.01));
      expect(x.numberAt(1.5), closeTo(50, 1e-9));
      // posY skipped the middle keyframe: one segment, 0 → 2 s.
      final y = asset.propertyTracks.elementAt(1).curve;
      expect(y.keys, hasLength(2));
      expect(y.numberAt(1), closeTo(10 + 20 * 0.25, 0.01));
    });

    test('the migrated scene loads and moves the entity', () {
      final world = World();
      registerSpriteSystems(world);
      final migrated = SceneFormat.migrate(v3());
      final entityJson = (migrated['entities'] as List).single as Map;
      final playerJson =
          ((entityJson['components'] as List)[1] as Map)['fields'] as Map;
      final definition = ComponentDefinitionRegistry.instance.definitionByType(
        'TimelinePlayerComponent',
      )!;
      final player = TimelinePlayerComponent();
      for (final f in definition.fields) {
        f.decodeInto(player, playerJson[f.name]);
      }
      final entity = world.createEntityWithComponents([
        TransformComponent(),
        player,
      ]);
      world.update(0);
      world.update(1.0);
      final at = entity.getComponent<TransformComponent>()!;
      expect(at.position.x, closeTo(100, 1e-6));
      expect(at.rotation, closeTo(1, 1e-6));
    });
  });
}

class _CounterTrack extends TimelineTrack {
  _CounterTrack();

  static int applied = 0;

  static _CounterTrack fromJson(Map<String, dynamic> json) => _CounterTrack();

  @override
  String get kind => 'test.counter';

  @override
  double get end => 0;

  @override
  String get summary => 'Counter';

  @override
  TrackRunner createRunner() => _CounterRunner();

  @override
  TimelineTrack withBase({
    String? name,
    TrackBinding? binding,
    bool? muted,
    bool? locked,
  }) => this;

  @override
  Map<String, dynamic> bodyToJson() => const {};
}

class _CounterRunner extends TrackRunner {
  @override
  void apply(TimelineContext context, double time) => _CounterTrack.applied++;
}

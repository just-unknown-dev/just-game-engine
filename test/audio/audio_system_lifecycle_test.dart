// AudioSystem: a stop after a play asked while the entity was off wins; a
// sound stops as soon as its component or entity goes, also while no update
// runs (a paused game clearing its level); a stream whose backend throws is
// let go without an uncaught error; and the fields a scene saves round-trip.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// Records the voices streams make; [failLoads] makes every load throw.
class _Backend implements AudioBackend {
  @override
  Future<bool> initialize() async => true;

  @override
  Stream<String> get voiceEndedStream => const Stream.empty();

  final List<String> log = [];
  bool failLoads = false;
  int _voices = 0;

  @override
  Future<String?> loadSource(String path, {bool stream = false}) async {
    if (failLoads) throw StateError('no such file: $path');
    return 'src:$path';
  }

  @override
  Future<String?> playVoice(
    String sourceId, {
    double volume = 1.0,
    bool loop = false,
    double pan = 0.0,
    double pitch = 1.0,
    double speed = 1.0,
    bool spatial = false,
    double lowPass = 0,
  }) async {
    final id = 'voice-${++_voices}';
    log.add('play $id');
    return id;
  }

  @override
  Future<void> stopVoice(String voiceId) async => log.add('stop $voiceId');

  @override
  Future<void> disposeSource(String sourceId) async =>
      log.add('free $sourceId');

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

/// Records what the system asks, and plays nothing.
class _Audio extends AudioEngine {
  _Audio(this.backend) : super.withBackend(backend);

  @override
  final _Backend backend;

  final List<String> log = [];
  final Set<String> live = {};
  int _played = 0;

  @override
  bool get isInitialized => true;

  @override
  bool isSfxPlaying(String id) => live.contains(id);

  @override
  Future<String?> playSfx(
    String path, {
    double volume = 1.0,
    bool loop = false,
    double pan = 0.0,
    double pitch = 1.0,
    double speed = 1.0,
    List<AudioEffect> effects = const [],
    Audio3DPosition? position3D,
    Audio3DSettings settings3D = const Audio3DSettings(),
    AudioChannel channel = AudioChannel.sfx,
  }) async {
    final id = 'sfx-${++_played}';
    log.add('play $path');
    live.add(id);
    return id;
  }

  @override
  Future<void> stopSfx(String id) async {
    log.add('stop $id');
    live.remove(id);
  }

  @override
  Future<void> pauseSfx(String id) async => log.add('pause $id');

  @override
  Future<void> resumeSfx(String id) async => log.add('resume $id');
}

void main() {
  late World world;
  late _Audio audio;
  late AudioSystem system;

  setUp(() {
    audio = _Audio(_Backend());
    world = World()..initialize();
    system = AudioSystem(engine: audio);
    world.addSystem(system);
  });
  tearDown(() => world.dispose());

  void frames(int count) {
    for (var i = 0; i < count; i++) {
      world
        ..update(1 / 60)
        ..frame(1 / 60, 1);
    }
  }

  group('play asked while switched off, then stop', () {
    test('a source stays stopped when it is back on', () async {
      final source = AudioSourceComponent(clipPath: 'door.wav', loop: true);
      final entity = world.createEntityWithComponents([source]);
      frames(1);
      await pumpEventQueue();
      entity.isActive = false;
      frames(1);
      source.play(); // from the start, once it is back on…
      frames(1);
      entity.isActive = true;
      source.stop(); // …but stopped before that happens
      frames(2);
      await pumpEventQueue();
      expect(audio.log.where((l) => l.startsWith('play')), [
        'play door.wav',
      ], reason: 'the stop came last');
      expect(source.handle, isNull);
    });

    test('a stream stays stopped when it is back on', () async {
      final music = AudioStreamComponent(path: 'music.ogg');
      final entity = world.createEntityWithComponents([music]);
      frames(1);
      await pumpEventQueue();
      entity.isActive = false;
      frames(1);
      music.play();
      frames(1);
      entity.isActive = true;
      music.stop();
      frames(2);
      await pumpEventQueue();
      expect(audio.backend.log.where((l) => l.startsWith('play')), [
        'play voice-1',
      ]);
      expect(music.stream, isNull);
    });
  });

  group('a sound whose component or entity goes', () {
    test('stops at once, with no update after', () async {
      final source = AudioSourceComponent(clipPath: 'loop.wav', loop: true);
      final music = AudioStreamComponent(path: 'music.ogg');
      final a = world.createEntityWithComponents([source]);
      world.createEntityWithComponents([music]);
      frames(1);
      await pumpEventQueue();
      audio.log.clear();
      audio.backend.log.clear();

      // A pause menu's "quit to title": the level goes, nothing updates.
      world.destroyEntity(a);
      expect(audio.log, ['stop sfx-1']);
      world.destroyAllEntities();
      await pumpEventQueue();
      expect(audio.backend.log, containsAll(['stop voice-1']));
      expect(music.stream, isNull);
      expect(audio.live, isEmpty);
    });

    test('a removed or replaced source stops at once', () async {
      final first = AudioSourceComponent(clipPath: 'a.wav', loop: true);
      final entity = world.createEntityWithComponents([first]);
      frames(1);
      await pumpEventQueue();
      entity.addComponent(AudioSourceComponent(clipPath: 'b.wav'));
      expect(audio.log.last, 'stop sfx-1');
      expect(first.handle, isNull);
    });

    test('a stopped sound is not stopped again when its entity goes', () {
      final source = AudioSourceComponent(clipPath: 'a.wav', loop: true);
      final entity = world.createEntityWithComponents([source]);
      frames(1);
      source.stop();
      frames(1);
      final stops = audio.log.where((l) => l.startsWith('stop')).length;
      world.destroyEntity(entity);
      expect(audio.log.where((l) => l.startsWith('stop')), hasLength(stops));
    });
  });

  test(
    'a stream whose backend throws is let go, with no uncaught error',
    () async {
      audio.backend.failLoads = true;
      final music = AudioStreamComponent(path: 'missing.ogg');
      final errors = <Object>[];
      await runZonedGuarded(() async {
        world.createEntityWithComponents([music]);
        frames(1);
        await pumpEventQueue();
      }, (error, _) => errors.add(error));
      expect(errors, isEmpty);
      expect(music.stream, isNull);
      frames(1);
      await pumpEventQueue();
      expect(music.stream, isNull, reason: 'playOnAdd tried it once');
    },
  );

  group('saved fields', () {
    final defs = World(
      extensions: [BuiltInComponents.extension],
    ).context.definitions;

    T roundTrip<T extends Component>(T component) =>
        defs.decode(defs.encode(component)!) as T;

    test("a source's speed", () {
      final back = roundTrip(AudioSourceComponent(clipPath: 'a', speed: 1.5));
      expect(back.speed, 1.5);
    });

    test("a stream's channel and fade-in", () {
      final back = roundTrip(
        AudioStreamComponent(
          path: 'm.ogg',
          channel: AudioChannel.sfx,
          fadeInDuration: const Duration(milliseconds: 1500),
        ),
      );
      expect(back.channel, AudioChannel.sfx);
      expect(back.fadeInDuration, const Duration(milliseconds: 1500));
      final none = roundTrip(AudioStreamComponent(path: 'm.ogg'));
      expect(none.channel, AudioChannel.music);
      expect(none.fadeInDuration, isNull);
    });

    test('an older file without them keeps the defaults', () {
      final stream =
          defs.decode({'type': 'AudioStreamComponent', 'streamPath': 'm.ogg'})
              as AudioStreamComponent;
      expect(stream.channel, AudioChannel.music);
      expect(stream.fadeInDuration, isNull);
      final source =
          defs.decode({'type': 'AudioSourceComponent', 'path': 'a.wav'})
              as AudioSourceComponent;
      expect(source.speed, 1.0);
    });
  });
}

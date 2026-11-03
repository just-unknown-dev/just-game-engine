// AudioSystem: pause, resume and stop are requests on the components and
// one-shots a call, not trigger components that change the world's shape
// (P2); sounds still loading are stopped by whatever stops the system
// (A13); a switched-off entity's sound pauses, and its volume is followed
// (A14); suspending for the background leaves what the game paused alone
// (C2).

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// Records the voices streams make, and plays nothing.
class _Backend implements AudioBackend {
  final List<String> log = [];
  int _voices = 0;

  @override
  Future<String?> loadSource(String path, {bool stream = false}) async =>
      'src:$path';

  @override
  Future<String?> playVoice(
    String sourceId, {
    double volume = 1.0,
    bool loop = false,
    double pan = 0.0,
    double pitch = 1.0,
    double speed = 1.0,
    String busName = 'sfx',
    bool spatial = false,
    double lowPass = 0,
  }) async {
    final id = 'voice-${++_voices}';
    log.add('play $id');
    return id;
  }

  @override
  Future<void> pauseVoice(String voiceId) async => log.add('pause $voiceId');

  @override
  Future<void> resumeVoice(String voiceId) async => log.add('resume $voiceId');

  @override
  Future<void> stopVoice(String voiceId) async => log.add('stop $voiceId');

  @override
  Future<void> setVoiceVolume(String voiceId, double volume) async =>
      log.add('volume $voiceId $volume');

  @override
  Future<void> disposeSource(String sourceId) async =>
      log.add('free $sourceId');

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

/// Records what the system asks, and plays nothing. While [hold] is set a
/// sound asked for loads until it is completed.
class _Audio extends AudioEngine {
  _Audio(this.backend) : super.withBackend(backend);

  @override
  final _Backend backend;

  final List<String> log = [];
  final List<({String path, double pan, Audio3DPosition? at})> played = [];
  final Set<String> live = {};
  Completer<void>? hold;

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
    Audio3DPosition? position3d,
    AudioSpatial spatial = const AudioSpatial(),
    AudioChannel channel = AudioChannel.sfx,
  }) async {
    played.add((path: path, pan: pan, at: position3d));
    final id = 'sfx-${played.length}';
    log.add('play $path ${channel.name}');
    await hold?.future;
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

  @override
  Future<void> setSfxVolume(String id, double volume) async =>
      log.add('volume $id $volume');
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

  /// A fixed step and a rendered frame, [count] times.
  void frames(int count) {
    for (var i = 0; i < count; i++) {
      world
        ..update(1 / 60)
        ..frame(1 / 60, 1);
    }
  }

  /// A looping source on a new entity, playing.
  Future<(Entity, AudioSourceComponent)> playing([
    String clip = 'a.wav',
  ]) async {
    final source = AudioSourceComponent(clipPath: clip, loop: true);
    final entity = world.createEntityWithComponents([source]);
    frames(1);
    await pumpEventQueue();
    audio.log.clear();
    return (entity, source);
  }

  group('P2 requests on a source', () {
    test('pause, resume and stop, at the next update', () async {
      final (entity, source) = await playing();
      final shape = entity.components.length;

      source.pause();
      expect(source.pendingRequest, AudioRequest.pause);
      expect(audio.log, isEmpty, reason: 'carried out by the system');
      frames(1);
      expect(audio.log, ['pause sfx-1']);
      expect(source.pendingRequest, isNull);

      source.resume();
      frames(1);
      source.stop();
      expect(source.playOnAdd, isTrue, reason: 'the saved field is left alone');
      frames(1);
      expect(audio.log, ['pause sfx-1', 'resume sfx-1', 'stop sfx-1']);
      expect(source.handle, isNull);
      expect(entity.components, hasLength(shape), reason: 'nothing added');

      frames(3);
      expect(audio.played, hasLength(1), reason: 'stopped stays stopped');
      source.play(); // plays again from the start
      frames(1);
      expect(audio.played, hasLength(2));
      expect(source.playOnAdd, isTrue);
    });

    test('starting a sound never changes what the scene saves', () async {
      final (_, source) = await playing();
      expect(source.playOnAdd, isTrue);
      frames(3);
      expect(audio.played, hasLength(1), reason: 'playOnAdd plays it once');
      expect(source.playOnAdd, isTrue);
    });

    test('stopAll forgets: playOnAdd sounds start again', () async {
      final (_, source) = await playing();
      system.stopAll();
      frames(1);
      expect(audio.played, hasLength(2));
      expect(source.playOnAdd, isTrue);
    });

    test(
      'stop wins in one update; else the last of pause and resume',
      () async {
        final (_, source) = await playing();
        source
          ..stop()
          ..pause()
          ..resume();
        frames(1);
        expect(audio.log, ['stop sfx-1']);

        final (_, other) = await playing('b.wav');
        other
          ..pause()
          ..resume();
        frames(1);
        expect(audio.log, isEmpty, reason: 'still playing: nothing to resume');
      },
    );

    test('a source that is not playing is not affected', () {
      final source = AudioSourceComponent(clipPath: 'a.wav', playOnAdd: false);
      world.createEntityWithComponents([source]);
      source
        ..pause()
        ..resume();
      frames(1);
      expect(audio.log, isEmpty);
      expect(source.pendingRequest, isNull);
    });

    test('a sound stopped or paused while it loads', () async {
      final hold = audio.hold = Completer<void>();
      final stopped = AudioSourceComponent(clipPath: 'a.wav', loop: true);
      final paused = AudioSourceComponent(clipPath: 'b.wav', loop: true);
      world
        ..createEntityWithComponents([stopped])
        ..createEntityWithComponents([paused]);
      frames(1); // asked to play…
      stopped.stop();
      paused.pause();
      frames(1); // …and stopped or paused before they start
      hold.complete();
      await pumpEventQueue();
      expect(audio.log, containsAll(['stop sfx-1', 'pause sfx-2']));
      expect(stopped.handle, isNull);
      expect(paused.handle, 'sfx-2');
    });
  });

  group('P2 one-shots', () {
    test('play at the next update, flat or placed, with nothing added', () {
      final hit = world.createEntityWithComponents([
        TransformComponent(position: Vector3(3, 4, 5)),
      ]);
      system
        ..playOneShot('flat.wav', pan: -0.5, channel: AudioChannel.voice)
        ..playOneShot(
          'placed.wav',
          pan: 1,
          position: hit.getComponent<TransformComponent>()!.position,
        );
      hit.getComponent<TransformComponent>()!.position.setValues(9, 9, 9);
      expect(audio.played, isEmpty);
      frames(1);
      expect(audio.log, ['play flat.wav voice', 'play placed.wav sfx']);
      expect(audio.played[0].pan, -0.5);
      expect(audio.played[0].at, isNull);
      expect(audio.played[1].pan, 0, reason: 'placed in 3-D: not panned');
      final at = audio.played[1].at!;
      expect((at.x, at.y, at.z), (3, 4, 5), reason: 'where it was asked for');
      frames(2);
      expect(audio.played, hasLength(2), reason: 'played once');
    });

    test('stopAll lets go of those not played yet', () {
      system
        ..playOneShot('a.wav')
        ..stopAll();
      frames(1);
      expect(audio.played, isEmpty);
    });
  });

  group('A13 a sound still loading', () {
    for (final (name, stop) in <(String, void Function(World, AudioSystem))>[
      ('stopAll()', (_, system) => system.stopAll()),
      ('the system removed', (world, system) => world.removeSystem(system)),
      ('the system disposed', (_, system) => system.dispose()),
    ]) {
      test('is stopped when it starts after $name', () async {
        final hold = audio.hold = Completer<void>();
        final source = AudioSourceComponent(clipPath: 'a.wav', loop: true);
        world.createEntityWithComponents([source]);
        frames(1);
        stop(world, system);
        hold.complete();
        await pumpEventQueue();
        expect(audio.log, ['play a.wav sfx', 'stop sfx-1']);
        expect(source.handle, isNull);
        expect(audio.live, isEmpty, reason: 'it played on forever');
      });
    }
  });

  group('A14 a switched-off entity', () {
    test('pauses its sound, which plays on when it is back on', () async {
      final (entity, source) = await playing();
      entity.isActive = false;
      frames(2);
      expect(audio.log, ['pause sfx-1']);
      entity.isActive = true;
      frames(1);
      expect(audio.log, ['pause sfx-1', 'resume sfx-1']);
      expect(source.handle, 'sfx-1', reason: 'the same sound, played on');
    });

    test('keeps what the game paused paused', () async {
      final (entity, source) = await playing();
      source.pause();
      frames(1);
      entity.isActive = false;
      frames(1);
      entity.isActive = true;
      frames(1);
      expect(audio.log, ['pause sfx-1']);
    });

    test('still hears stop, pause and resume', () async {
      final (entity, source) = await playing();
      entity.isActive = false;
      frames(1);
      source.pause();
      frames(1);
      entity.isActive = true;
      frames(1);
      expect(audio.log, ['pause sfx-1'], reason: 'paused by the game now');
      entity.isActive = false;
      frames(1);
      source.stop();
      frames(1);
      expect(audio.log, ['pause sfx-1', 'stop sfx-1']);
      expect(source.handle, isNull);
      entity.isActive = true;
      frames(1);
      expect(audio.played, hasLength(1), reason: 'not started again');
    });

    test('a volume changed while it plays is followed', () async {
      final (_, source) = await playing();
      frames(1);
      expect(audio.log, isEmpty, reason: 'nothing changed');
      source.volume = 0.25;
      frames(2);
      expect(audio.log, ['volume sfx-1 0.25']);
    });
  });

  group('streams', () {
    Future<AudioStreamComponent> streaming() async {
      final music = AudioStreamComponent(path: 'music.ogg');
      world.createEntityWithComponents([music]);
      frames(1);
      await pumpEventQueue();
      audio.backend.log.clear();
      return music;
    }

    test('pause, resume, stop and volume', () async {
      final music = await streaming();
      music.pause();
      frames(1);
      music.resume();
      frames(1);
      music.volume = 0.5;
      frames(1);
      music.stop();
      frames(1);
      await pumpEventQueue();
      expect(audio.backend.log, [
        'pause voice-1',
        'resume voice-1',
        'volume voice-1 0.5',
        'stop voice-1',
        'free src:music.ogg',
      ]);
      expect(music.stream, isNull);
    });

    test('one stopped while it opens is let go', () async {
      final music = AudioStreamComponent(path: 'music.ogg');
      world.createEntityWithComponents([music]);
      frames(1); // opening…
      system.stopAll(); // …and stopped before it plays
      await pumpEventQueue();
      expect(audio.backend.log, isNot(contains('play voice-1')));
      expect(audio.backend.log, contains('free src:music.ogg'));
    });

    test('pauses while its entity is switched off', () async {
      final music = AudioStreamComponent(path: 'music.ogg');
      final entity = world.createEntityWithComponents([music]);
      frames(1);
      await pumpEventQueue();
      audio.backend.log.clear();
      entity.isActive = false;
      frames(1);
      entity.isActive = true;
      frames(1);
      await pumpEventQueue();
      expect(audio.backend.log, ['pause voice-1', 'resume voice-1']);
    });
  });

  group('C2 suspend', () {
    test('pauses what plays and plays on only that', () async {
      final (_, playingSource) = await playing('a.wav');
      final (_, pausedSource) = await playing('b.wav');
      pausedSource.pause(); // by the game
      frames(1);
      final music = AudioStreamComponent(path: 'music.ogg');
      world.createEntityWithComponents([music]);
      frames(1);
      await pumpEventQueue();
      audio.log.clear();
      audio.backend.log.clear();

      system.suspend();
      expect(audio.log, ['pause sfx-1']);
      expect(audio.backend.log, ['pause voice-1']);
      system.suspend(); // twice does nothing more
      expect(audio.log, hasLength(1));

      system.resumeSuspended();
      expect(audio.log, ['pause sfx-1', 'resume sfx-1']);
      expect(audio.backend.log, ['pause voice-1', 'resume voice-1']);
      expect(playingSource.handle, 'sfx-1');
    });

    test('a sound starting while suspended starts paused', () async {
      system.suspend();
      world.createEntityWithComponents([
        AudioSourceComponent(clipPath: 'a.wav', loop: true),
      ]);
      frames(1);
      await pumpEventQueue();
      expect(audio.log, ['play a.wav sfx', 'pause sfx-1']);
      system.resumeSuspended();
      expect(audio.log.last, 'resume sfx-1');
    });
  });

  test('P11 the queries are the same lists every time', () {
    expect(
      identical(system.requiredComponents, system.requiredComponents),
      isTrue,
    );
  });
}

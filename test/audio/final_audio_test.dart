// Audio fixes from the 2.0.0 final pass: a sound placed in 3-D is not also
// panned, and a stream fades in from silence (F25); .flac is detected
// (F34).

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// Records what the system plays, and plays nothing.
class _RecordingAudio extends AudioEngine {
  _RecordingAudio(super.backend) : super.withBackend();

  final List<double> pans = [];

  @override
  bool get isInitialized => true;

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
    pans.add(pan);
    return 'sfx-${pans.length}';
  }
}

/// Records voices played and fades, and does nothing else.
class _Backend implements AudioBackend {
  final List<double> playVolumes = [];
  final List<(double, Duration)> fades = [];

  @override
  Future<String?> loadSource(String path, {bool stream = false}) async => 'src';

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
    playVolumes.add(volume);
    return 'voice';
  }

  @override
  Future<void> fadeVoiceVolume(
    String voiceId,
    double target,
    Duration duration,
  ) async => fades.add((target, duration));

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

class _Bundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => ByteData(4);
}

void main() {
  late World world;
  late _Backend backend;
  late _RecordingAudio audio;

  setUp(() {
    backend = _Backend();
    audio = _RecordingAudio(backend);
    world = World()..initialize();
    world.addSystem(AudioSystem(engine: audio));
  });
  tearDown(() => world.dispose());

  group('F25', () {
    test('a sound placed in 3-D is not panned as well', () {
      world.createEntityWithComponents([
        TransformComponent(position: Vector3(5, 0, 0)),
        AudioSourceComponent(clipPath: 'a.wav', pan: -1, is3d: true),
      ]);
      world.getSystem<AudioSystem>()!.playOneShot(
        'b.wav',
        pan: 1,
        position: Vector3(5, 0, 0),
      );
      // 3-D without a transform plays flat, so its pan counts.
      world.createEntityWithComponents([
        AudioSourceComponent(clipPath: 'c.wav', pan: 0.5, is3d: true),
      ]);
      world.update(1 / 60);
      expect(audio.pans, unorderedEquals([0.0, 0.0, 0.5]));
    });

    test('a stream with a fade-in starts silent and fades up', () async {
      world.createEntityWithComponents([
        AudioStreamComponent(
          path: 'music.ogg',
          volume: 0.8,
          fadeInDuration: const Duration(seconds: 2),
        ),
      ]);
      world.update(1 / 60);
      await pumpEventQueue();
      expect(backend.playVolumes, [0.0]);
      expect(backend.fades, [(0.8, const Duration(seconds: 2))]);
    });

    test('a stream without one starts at its volume', () async {
      world.createEntityWithComponents([
        AudioStreamComponent(path: 'music.ogg', volume: 0.8),
      ]);
      world.update(1 / 60);
      await pumpEventQueue();
      expect(backend.playVolumes, [0.8]);
      expect(backend.fades, isEmpty);
    });
  });

  test('F34 an audio asset tells .flac, in any case', () async {
    final manager = AssetManager(bundle: _Bundle());
    for (final (path, format) in [
      ('a.flac', AudioFormat.flac),
      ('b.MP3', AudioFormat.mp3),
      ('c.Ogg', AudioFormat.ogg),
      ('d.wav', AudioFormat.wav),
      ('e.aac', null),
    ]) {
      final asset = await manager.loadAudio(path);
      expect(asset.format, format, reason: path);
    }
  });
}

// An audio track's sounds belong to its bound entity: with the default
// player they are heard from there when that entity is a 3-D sound source,
// with its distances, and flat otherwise.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// Records what is played, and plays nothing.
class _RecordingAudio extends AudioEngine {
  _RecordingAudio() : super.withBackend(_Backend());

  final List<(String, Audio3DPosition?, Audio3DSettings)> played = [];

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
    Audio3DPosition? position3D,
    Audio3DSettings settings3D = const Audio3DSettings(),
    AudioChannel channel = AudioChannel.sfx,
  }) async {
    played.add((path, position3D, settings3D));
    return 'sfx-${played.length}';
  }
}

class _Backend implements AudioBackend {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late World world;
  late _RecordingAudio audio;

  setUp(() {
    audio = _RecordingAudio();
    world = World(extensions: [BuiltInComponents.extension])..initialize();
    world.addSystem(AudioSystem(engine: audio));
  });
  tearDown(() => world.dispose());

  /// Plays a timeline with a creak at 0.5 s, bound to [door], to its end.
  void creak(Entity door) {
    TimelinePlayback(
        TimelineAsset(
          duration: 1,
          tracks: [
            AudioTrack(
              binding: TrackBinding.name(door.name!),
              blocks: const [TimelineBlock(start: 0.5, value: 'creak.wav')],
            ),
          ],
        ),
        world: world,
        owner: world.createEntity(),
      )
      ..play()
      ..update(1);
    world.update(1 / 60);
  }

  test('a 3-D sound source is heard from where it is, at its distances', () {
    final door = world.createEntityWithComponents([
      TransformComponent(position: Vector3(300, 20, 5)),
      AudioSourceComponent(
        clipPath: 'hum.wav',
        playOnAdd: false,
        is3D: true,
        minDistance: 2,
        maxDistance: 80,
      ),
    ], name: 'Door');
    creak(door);
    final (path, at, spatial) = audio.played.single;
    expect(path, 'creak.wav');
    expect((at?.x, at?.y, at?.z), (300.0, 20.0, 5.0));
    expect((spatial.minDistance, spatial.maxDistance), (2.0, 80.0));
  });

  test('anything else plays flat, as a 2-D game\'s sounds do', () {
    final door = world.createEntityWithComponents([
      TransformComponent(position: Vector3(300, 20, 5)),
      AudioSourceComponent(clipPath: 'hum.wav', playOnAdd: false),
    ], name: 'Door');
    creak(door);
    expect(audio.played.single.$2, isNull);

    audio.played.clear();
    final gate = world.createEntityWithComponents([
      TransformComponent(position: Vector3(10, 0, 0)),
    ], name: 'Gate');
    creak(gate);
    expect(audio.played.single.$2, isNull);
  });
}

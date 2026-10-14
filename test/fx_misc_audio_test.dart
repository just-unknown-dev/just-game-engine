// AudioSystem tells the audio engine where the listener and 3-D sources are
// only when that changes — not every frame for things standing still.

import 'dart:ui' show Offset, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// Counts what the system sends, and plays nothing.
class _CountingAudio extends AudioEngine {
  final List<Audio3DListener> listeners = [];
  final List<(String, Audio3DPosition)> positions = [];

  @override
  void setListener3D(Audio3DListener listener) => listeners.add(listener);

  @override
  void updateSfxPosition(String id, Audio3DPosition position) =>
      positions.add((id, position));
}

void main() {
  late World world;
  late _CountingAudio audio;

  setUp(() {
    audio = _CountingAudio();
    world = World()..initialize();
    world.addSystem(AudioSystem(engine: audio));
  });

  tearDown(() => world.dispose());

  void frames(int count) {
    for (var i = 0; i < count; i++) {
      world.update(1 / 60);
    }
  }

  test('the listener is sent once while it stands still', () {
    final listener = world.createEntityWithComponents([
      TransformComponent(position: Vector3(1, 2, 3)),
      AudioListenerComponent(),
    ]);
    frames(5);
    expect(audio.listeners, hasLength(1));
    expect(audio.listeners.single.position.x, 1);

    listener.getComponent<TransformComponent>()!.position.x = 7;
    frames(3);
    expect(audio.listeners, hasLength(2));
    expect(audio.listeners.last.position.x, 7);

    listener.getComponent<AudioListenerComponent>()!.forwardX = 1;
    frames(1);
    expect(audio.listeners, hasLength(3), reason: 'turning counts too');
  });

  test('a listener from the camera hears where the camera is and faces', () {
    final camera = Camera(position: const Offset(2, -3), viewportSize: const Size(800, 600))
      ..z = -8
      ..yaw = 1.5707963267948966; // turned a quarter: facing +X
    world
      ..removeSystem(world.systems.whereType<AudioSystem>().single)
      ..addSystem(AudioSystem(engine: audio, camera: camera));
    world.createEntityWithComponents([AudioListenerComponent(fromCamera: true)]);
    frames(2);
    expect(audio.listeners, hasLength(1));
    final heard = audio.listeners.single;
    expect([heard.position.x, heard.position.y, heard.position.z], [closeTo(2, 1e-9), closeTo(-3, 1e-9), closeTo(-8, 1e-9)]);
    expect([heard.forward.x, heard.forward.y, heard.forward.z], [closeTo(1, 1e-9), closeTo(0, 1e-9), closeTo(0, 1e-9)]);
    expect(heard.up.y, closeTo(-1, 1e-9), reason: 'up is -Y');
    camera.z = -5;
    frames(1);
    expect(audio.listeners, hasLength(2));
  });

  test('a 3-D source is sent when it moves, and when it plays anew', () {
    final source = AudioSourceComponent(
      clipPath: 'assets/fx/hum.wav',
      is3d: true,
      playOnAdd: false,
    )..handle = 'sfx-1';
    final entity = world.createEntityWithComponents([
      TransformComponent(position: Vector3(4, 0, 0)),
      source,
    ]);
    frames(5);
    expect(audio.positions, hasLength(1));
    expect(audio.positions.single.$1, 'sfx-1');

    entity.getComponent<TransformComponent>()!.position.y = 9;
    frames(2);
    expect(audio.positions, hasLength(2));
    expect(audio.positions.last.$2.y, 9);

    source.handle = 'sfx-2'; // restarted: a new playback, same place
    frames(2);
    expect(audio.positions, hasLength(3));
    expect(audio.positions.last.$1, 'sfx-2');
  });

  test('a 2-D source is never positioned', () {
    world.createEntityWithComponents([
      TransformComponent(position: Vector3(4, 0, 0)),
      AudioSourceComponent(clipPath: 'assets/fx/hum.wav', playOnAdd: false)
        ..handle = 'sfx-1',
    ]);
    frames(3);
    expect(audio.positions, isEmpty);
  });
}

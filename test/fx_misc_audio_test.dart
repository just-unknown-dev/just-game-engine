// AudioSystem tells the audio engine where the listener and 3-D sources are
// only when that changes — not every frame for things standing still — and
// stops what an entity played when the entity goes.

import 'dart:ui' show Offset, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// Counts what the system sends, and plays nothing.
class _CountingAudio extends AudioEngine {
  final List<Audio3DListener> listeners = [];
  final List<(String, Audio3DPosition)> positions = [];
  final List<(String, AudioSpatial)> spatials = [];
  final List<String> stopped = [];
  final List<({String path, Audio3DPosition? at, AudioSpatial spatial, AudioChannel channel})>
  played = [];

  /// The sounds still playing.
  final Set<String> live = {};

  /// Whether it has started; nothing plays before.
  bool started = true;

  @override
  bool get isInitialized => started;

  @override
  void setListener3D(Audio3DListener listener) => listeners.add(listener);

  @override
  void updateSfxPosition(String id, Audio3DPosition position) =>
      positions.add((id, position));

  @override
  void setSfxSpatial(String id, AudioSpatial spatial) =>
      spatials.add((id, spatial));

  @override
  bool isSfxPlaying(String id) => live.contains(id);

  @override
  Future<void> stopSfx(String id) async {
    stopped.add(id);
    live.remove(id);
  }

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
    played.add((path: path, at: position3d, spatial: spatial, channel: channel));
    final id = 'sfx-${played.length}';
    live.add(id);
    return id;
  }
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

  /// Fixed steps and rendered frames, one each, [count] times.
  void frames(int count) {
    for (var i = 0; i < count; i++) {
      world
        ..update(1 / 60)
        ..frame(1 / 60, 1);
    }
  }

  void useCamera(Camera camera) {
    world
      ..removeSystem(world.systems.whereType<AudioSystem>().single)
      ..addSystem(AudioSystem(engine: audio, camera: camera));
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

    // A quarter turn about Y: forward (+Z) becomes +X.
    listener.getComponent<TransformComponent>()!.setEuler(
      0,
      1.5707963267948966,
      0,
    );
    frames(1);
    expect(audio.listeners, hasLength(3), reason: 'turning counts too');
    final turned = audio.listeners.last;
    expect(turned.forward.x, closeTo(1, 1e-9));
    expect(turned.forward.z, closeTo(0, 1e-9));
    expect(turned.up.y, closeTo(-1, 1e-9), reason: 'up stays -Y');
  });

  Camera quarterTurnedCamera() =>
      Camera(position: const Offset(2, -3), viewportSize: const Size(800, 600))
        ..z = -8
        ..yaw = 1.5707963267948966; // turned a quarter: facing +X

  test('a listener at the camera hears where the camera is and faces', () {
    final camera = quarterTurnedCamera();
    useCamera(camera);
    world.createEntityWithComponents([
      AudioListenerComponent(atCamera: true, faceCamera: true),
    ]);
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

  test('a listener on the player faces like the camera, from the player', () {
    useCamera(quarterTurnedCamera());
    world.createEntityWithComponents([
      TransformComponent(position: Vector3(10, 0, 4)),
      AudioListenerComponent(faceCamera: true),
    ]);
    frames(1);
    final heard = audio.listeners.single;
    expect([heard.position.x, heard.position.y, heard.position.z], [10, 0, 4]);
    expect(heard.forward.x, closeTo(1, 1e-9));
  });

  test('with no listener, the camera hears', () {
    useCamera(quarterTurnedCamera());
    frames(1);
    final heard = audio.listeners.single;
    expect(heard.position.z, closeTo(-8, 1e-9));
    expect(heard.forward.x, closeTo(1, 1e-9));
  });

  test('with no listener and no camera, nothing is sent', () {
    frames(2);
    expect(audio.listeners, isEmpty);
  });

  test('a 3-D source is played where it is, as it is heard', () async {
    world.createEntityWithComponents([
      TransformComponent(position: Vector3(4, 0, 1)),
      AudioSourceComponent(
        clipPath: 'assets/fx/hum.wav',
        is3d: true,
        loop: true,
        minDistance: 2,
        maxDistance: 30,
        dopplerLevel: 1,
        farCutoff: 1500,
        channel: AudioChannel.ambient,
      ),
    ]);
    frames(1);
    final play = audio.played.single;
    expect([play.at!.x, play.at!.y, play.at!.z], [4, 0, 1]);
    expect(
      play.spatial,
      const AudioSpatial(
        minDistance: 2,
        maxDistance: 30,
        dopplerLevel: 1,
        farCutoff: 1500,
      ),
    );
    expect(play.channel, AudioChannel.ambient);
  });

  test('a 3-D source is sent when it moves, and when it plays anew', () {
    final source = AudioSourceComponent(
      clipPath: 'assets/fx/hum.wav',
      is3d: true,
      playOnAdd: false,
    )..handle = 'sfx-1';
    audio.live.add('sfx-1');
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
    audio.live.add('sfx-2');
    frames(2);
    expect(audio.positions, hasLength(3));
    expect(audio.positions.last.$1, 'sfx-2');
  });

  test('changing how a playing source is heard is sent once', () {
    final source = AudioSourceComponent(
      clipPath: 'assets/fx/hum.wav',
      is3d: true,
      playOnAdd: false,
    )..handle = 'sfx-1';
    audio.live.add('sfx-1');
    world.createEntityWithComponents([TransformComponent(), source]);
    frames(2);
    expect(audio.spatials, isEmpty);
    source
      ..maxDistance = 12
      ..rolloff = AudioRolloff.linear;
    frames(3);
    expect(audio.spatials, hasLength(1));
    expect(audio.spatials.single.$2.maxDistance, 12);
    expect(audio.spatials.single.$2.rolloff, AudioRolloff.linear);
  });

  test('a 2-D source is never positioned', () {
    audio.live.add('sfx-1');
    world.createEntityWithComponents([
      TransformComponent(position: Vector3(4, 0, 0)),
      AudioSourceComponent(clipPath: 'assets/fx/hum.wav', playOnAdd: false)
        ..handle = 'sfx-1',
    ]);
    frames(3);
    expect(audio.positions, isEmpty);
  });

  test('a source stops when its entity or its component goes', () async {
    final a = world.createEntityWithComponents([
      TransformComponent(),
      AudioSourceComponent(clipPath: 'a.wav', loop: true),
    ]);
    final b = world.createEntityWithComponents([
      TransformComponent(),
      AudioSourceComponent(clipPath: 'b.wav', loop: true),
    ]);
    frames(1);
    await pumpEventQueue();
    frames(1);
    expect(audio.live, {'sfx-1', 'sfx-2'});

    world.destroyEntity(a);
    b.removeComponent<AudioSourceComponent>();
    frames(1);
    expect(audio.stopped, unorderedEquals(['sfx-1', 'sfx-2']));
  });

  test('an entity gone while its sound loads is not heard', () async {
    final a = world.createEntityWithComponents([
      AudioSourceComponent(clipPath: 'a.wav', loop: true),
    ]);
    frames(1); // asked to play…
    world.destroyEntity(a); // …and gone before the answer
    await pumpEventQueue();
    expect(audio.stopped, ['sfx-1']);
  });

  test('a sound that played to its end lets its handle go', () async {
    final source = AudioSourceComponent(clipPath: 'a.wav');
    world.createEntityWithComponents([source]);
    frames(1);
    await pumpEventQueue();
    expect(source.handle, 'sfx-1');
    audio.live.remove('sfx-1'); // the end, as the engine reports it
    frames(1);
    expect(source.handle, isNull);
    expect(audio.played, hasLength(1), reason: 'not played again');
  });

  test('nothing plays before the audio engine has started', () async {
    audio.started = false;
    final source = AudioSourceComponent(clipPath: 'a.wav', loop: true);
    world.createEntityWithComponents([source]);
    world.createEntityWithComponents([AudioPlayComponent(clipPath: 'b.wav')]);
    final music = world.createEntityWithComponents([AudioStreamComponent(path: 'c.wav')]);
    frames(3);
    expect(audio.played, isEmpty);
    expect(source.playOnAdd, isTrue, reason: 'it waits');
    expect(world.query([AudioPlayComponent]), isEmpty, reason: 'a one-shot is let go');
    expect(music.getComponent<AudioStreamComponent>()!.stream, isNull, reason: 'not opened');

    world.destroyEntity(music); // (this engine has no backend to stream from)
    audio.started = true; // the first tap, on the web
    frames(1);
    expect(audio.played.map((p) => p.path), ['a.wav']);
  });

  test('removing the system stops what it played', () async {
    world.createEntityWithComponents([
      AudioSourceComponent(clipPath: 'a.wav', loop: true),
    ]);
    frames(1);
    await pumpEventQueue();
    frames(1);
    world.removeSystem(world.systems.whereType<AudioSystem>().single);
    expect(audio.stopped, ['sfx-1']);
  });
}

// The skeletal clip track: a timeline playing clips on a model.
@Tags(['graphics3d'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/just_game_engine_3d.dart';
import 'package:just_graphics_engine/testing.dart';
import 'package:just_graphics_engine/just_graphics_engine.dart' show NullGpuDevice, rendererNullShaders;

import 'fixtures.dart';

const _barPath = 'assets/models/bar.glb';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late World world;
  setUp(() {
    world = World()..initialize();
    world.context.install(Graphics3D());
  });
  tearDown(() => world.dispose());

  TimelineAsset asset() => TimelineAsset(
    duration: 3,
    tracks: [
      SkeletalClipTrack(
        blocks: const [TimelineBlock(start: 1, length: 1, value: 'wave', speed: 2, loop: false)],
      ),
    ],
  );

  test('it is registered, and round-trips', () {
    expect(world.context.trackKinds.has(SkeletalClipTrack.kindId), isTrue);
    final back = world.context.trackKinds.resolve(TimelineAsset.parse(asset().encode()));
    expect(back.tracks.single, isA<SkeletalClipTrack>());
    expect((back.tracks.single as SkeletalClipTrack).blocks.single.value, 'wave');
  });

  test('a block plays its clip (crossfading), then the model goes back', () {
    final player = AnimationPlayerComponent(clip: 'idle', crossfade: 0.25)..speed = 1.5;
    final entity = world.createEntityWithComponents([player]);
    final playback = TimelinePlayback(asset(), world: world, owner: entity)..play();
    playback.update(0.5);
    expect(player.playingClip, 'idle');
    playback.update(1.0);
    expect((player.playingClip, player.playingSpeed, player.playingLoop), ('wave', 2.0, false));
    expect(player.fadingFrom, 'idle', reason: 'playing through crossfades');
    expect((player.clip, player.speed, player.loop), ('idle', 1.5, true), reason: 'what was authored stays');
    playback.update(1.0);
    expect((player.playingClip, player.playingSpeed, player.playingLoop), ('idle', 1.5, true));
    expect(player.isDriven, isFalse, reason: 'handed back to what was authored');
  });

  test('scrubbing in an editor puts the clip where the timeline is', () {
    final player = AnimationPlayerComponent(clip: 'idle');
    final entity = world.createEntityWithComponents([player]);
    final playback = TimelinePlayback(asset(), world: world, owner: entity, isPreview: true)..play();
    playback.seek(1.25);
    expect(player.playingClip, 'wave');
    expect(player.clip, 'idle', reason: 'a preview leaves what is saved alone');
    expect(player.time, closeTo(0.5, 1e-9), reason: 'a quarter second in at speed 2');
    expect(player.isFading, isFalse, reason: 'a scrub cuts');
  });
  test('a block over a blend tree hands the blend back when it ends', () {
    final player = AnimationPlayerComponent();
    final entity = world.createEntityWithComponents([player]);
    // A blend tree's state, as an animator plays it.
    player
      ..playBlend(['idle', 'walk'], [0.75, 0.25], speeds: [1, 1.5])
      ..playingSpeed = 1.2;
    final playback = TimelinePlayback(asset(), world: world, owner: entity)..play();
    playback.update(1.5);
    expect((player.playingClip, player.isBlending), ('wave', false));
    playback.update(1.0);
    expect(player.blendClips, ['idle', 'walk']);
    expect(player.blendWeights, [0.75, 0.25]);
    expect(player.blendSpeeds, [1, 1.5]);
    expect((player.playingSpeed, player.playingLoop), (1.2, true));
    player.setBlendWeights([0.1, 0.9]);
    expect(player.blendWeights, [0.1, 0.9], reason: 'its animator goes on weighing it');
  });

  group('scrubbing a loaded model', () {
    late Engine engine;

    setUp(() async {
      final service = Graphics3D(device: NullGpuDevice(shaders: rendererNullShaders));
      engine = Engine(
        config: EngineConfig(services: [service]),
        context: EngineContext(bundle: TestBundle({_barPath: skinnedBarGlb()})),
      );
      await engine.initialize();
      await service.models.load(_barPath);
    });
    tearDown(() => engine.dispose());

    /// Where scrubbing to [at] puts a 1 s clip played by [block].
    double scrubbedTo(TimelineBlock block, double at) {
      final player = AnimationPlayerComponent(clip: 'hop');
      final entity = engine.world.createEntityWithComponents([
        TransformComponent(),
        ModelComponent(model: _barPath),
        player,
      ]);
      final timeline = TimelineAsset(duration: 8, tracks: [SkeletalClipTrack(blocks: [block])]);
      TimelinePlayback(timeline, world: engine.world, owner: entity, isPreview: true)
        ..play()
        ..seek(at);
      expect(player.playingClip, 'bend');
      return player.time;
    }

    test('a looping block wraps its clip', () {
      const block = TimelineBlock(start: 0, length: 6, value: 'bend', loop: true);
      expect(scrubbedTo(block, 3.25), closeTo(0.25, 1e-9));
    });

    test('a block that does not loop holds the clip at its end', () {
      const block = TimelineBlock(start: 0, length: 6, value: 'bend', loop: false);
      expect(scrubbedTo(block, 3.25), 1);
    });

    test('a block played backwards counts from the end of the clip', () {
      const once = TimelineBlock(start: 0, length: 6, value: 'bend', speed: -1, loop: false);
      expect(scrubbedTo(once, 0.25), closeTo(0.75, 1e-9));
      expect(scrubbedTo(once, 3), 0, reason: 'held at its start');
      const looping = TimelineBlock(start: 0, length: 6, value: 'bend', speed: -1, loop: true);
      expect(scrubbedTo(looping, 1.25), closeTo(0.75, 1e-9));
    });
  });
}

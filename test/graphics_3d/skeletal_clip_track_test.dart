// The skeletal clip track: a timeline playing clips on a model.
@Tags(['graphics3d'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/graphics_3d.dart';

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
    expect(player.clip, 'idle');
    playback.update(1.0);
    expect((player.clip, player.speed, player.loop), ('wave', 2.0, false));
    expect(player.fadingFrom, 'idle', reason: 'playing through crossfades');
    playback.update(1.0);
    expect((player.clip, player.speed, player.loop), ('idle', 1.5, true));
  });

  test('scrubbing in an editor puts the clip where the timeline is', () {
    final player = AnimationPlayerComponent(clip: 'idle');
    final entity = world.createEntityWithComponents([player]);
    final playback = TimelinePlayback(asset(), world: world, owner: entity, isPreview: true)..play();
    playback.seek(1.25);
    expect(player.clip, 'wave');
    expect(player.time, closeTo(0.5, 1e-9), reason: 'a quarter second in at speed 2');
    expect(player.isFading, isFalse, reason: 'a scrub cuts');
  });
}

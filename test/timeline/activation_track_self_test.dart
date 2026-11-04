// An activation track bound to the entity playing its timeline (the
// default binding), or to a parent of it: the entity drops out of the
// world's queries while it is off, yet its timeline must go on playing to
// switch it back on.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late World world;
  setUp(() {
    world = World(extensions: [BuiltInComponents.extension]);
    registerSpriteSystems(world);
  });
  tearDown(() => world.dispose());

  /// A platform on [length] seconds of [blocks], looping.
  TimelinePlayerComponent blinking(List<TimelineBlock> blocks) =>
      TimelinePlayerComponent(
        playOnStart: true,
        inline: TimelineAsset(
          duration: 3,
          wrap: TimelineWrap.loop,
          tracks: [ActivationTrack(blocks: blocks)],
        ),
      );

  test('a platform that blinks itself out comes back', () {
    final player = blinking(const [TimelineBlock(start: 0, length: 1)]);
    final platform = world.createEntityWithComponents([player]);
    world.update(0.5);
    expect(platform.isActive, isTrue);
    world.update(1.0); // t = 1.5: outside the block
    expect(platform.isActive, isFalse);
    expect(player.time, closeTo(1.5, 1e-9));
    world.update(1.0); // t = 2.5: still off, but still playing
    expect(player.time, closeTo(2.5, 1e-9));
    world.update(1.0); // t = 0.5 of the next lap: on again
    expect(platform.isActive, isTrue);
    expect(player.time, closeTo(0.5, 1e-9));
  });

  test('switched off by its own track at the start, it still plays on', () {
    final player = blinking(const [TimelineBlock(start: 1, length: 1)]);
    final platform = world.createEntityWithComponents([player]);
    world.update(0.1);
    expect(platform.isActive, isFalse, reason: 'no block at the start');
    world.update(1.0);
    expect(platform.isActive, isTrue, reason: 'the block switched it on');
  });

  test('a track holding a parent of the player off keeps playing', () {
    final parent = world.createEntity(name: 'Room');
    final player = TimelinePlayerComponent(
      playOnStart: true,
      inline: TimelineAsset(
        duration: 2,
        wrap: TimelineWrap.loop,
        tracks: [
          ActivationTrack(
            binding: const TrackBinding.name('Room'),
            blocks: const [TimelineBlock(start: 0, length: 1)],
          ),
        ],
      ),
    );
    final child = world.createEntityWithComponents([
      player,
      ParentComponent(parentId: parent.id),
    ]);
    world.update(0.5);
    expect(parent.isActive, isTrue);
    world.update(1.0);
    expect(parent.isActive, isFalse);
    expect(child.isActiveInHierarchy, isFalse);
    world.update(1.0); // t = 0.5 again
    expect(parent.isActive, isTrue);
    expect(child.isActiveInHierarchy, isTrue);
  });

  test('a player switched off by the game, not its timeline, waits', () {
    final player = blinking(const [TimelineBlock(start: 0, length: 3)]);
    final platform = world.createEntityWithComponents([player]);
    world.update(0.5);
    platform.isActive = false;
    world.update(1.0);
    expect(player.time, closeTo(0.5, 1e-9), reason: 'not stepped while off');
    expect(platform.isActive, isFalse);
  });

  test('a new activation track starts with a block, so nothing vanishes '
      'the moment it is added', () {
    final offer = world.context.trackKinds.offerFor(ActivationTrack.kindId)!;
    final track = offer.create() as ActivationTrack;
    expect(track.blocks, isNotEmpty);
    expect(track.blocks.first.start, 0);
  });

  test('validate says an empty activation track keeps its entity off', () {
    final asset = TimelineAsset(duration: 1, tracks: [ActivationTrack()]);
    expect(
      asset.validate().join('\n'),
      contains('keeps the entity playing it switched off'),
    );
  });
}

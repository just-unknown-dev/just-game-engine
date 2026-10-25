// What fades out keeps playing as it played (held at its end, at its own
// speed), a blend's cycle keeps one clip's stride between two speeds of it
// and weighs different clips' lengths, a socket is drawn between its poses
// like the parent it rides, a parent is posed once an update however many
// sockets it carries, and a parent's pose is let go with the parent.
@Tags(['graphics3d'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/graphics_3d.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_graphics_engine/testing.dart';

import 'fixtures.dart';

const _barPath = 'assets/models/bar.glb';

/// Moves [transform] 1 m along +X each update, its previous pose captured
/// first — as physics does, before animation runs.
final class _Mover extends System {
  _Mover(this.transform) {
    priority = SystemPriorities.physics;
  }

  final TransformComponent transform;

  @override
  List<Type> get requiredComponents => const [];

  @override
  void update(double deltaTime) {
    transform
      ..capturePrevious()
      ..position.x += 1;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Engine engine;
  late Graphics3D service;

  setUp(() async {
    service = Graphics3D(device: NullGpuDevice(shaders: rendererNullShaders));
    engine = Engine(
      config: EngineConfig(graphics3D: service),
      context: EngineContext(bundle: TestBundle({_barPath: skinnedBarGlb()})),
    );
    await engine.initialize();
    await service.models.load(_barPath);
  });
  tearDown(() => engine.dispose());

  AnimationSystem3D system() =>
      engine.world.systems.whereType<AnimationSystem3D>().single;

  Entity character(AnimationPlayerComponent player) =>
      engine.world.createEntityWithComponents([
        TransformComponent(),
        ModelComponent(model: _barPath),
        player,
      ], name: 'Bar');

  Entity socket(Entity parent, {String node = 'tip'}) =>
      engine.world.createEntityWithComponents([
        TransformComponent(),
        ParentComponent(parentId: parent.id),
        SocketComponent(node: node),
        Cube3D(width: 0.1, height: 0.1, depth: 0.1),
      ], name: 'Hat');

  group('what fades out', () {
    test('a clip held at its end stays there, not back at its start', () {
      final player = AnimationPlayerComponent(clip: 'bend', loop: false);
      character(player);
      for (var i = 0; i < 5; i++) {
        system().update(0.25);
      }
      expect(player.time, 1);
      player.play('', fade: 0.5);
      system().update(0.1);
      expect(player.fadingFrom, 'bend');
      expect(player.fadingFromTime, 1, reason: 'held, not wrapped to 0.1');
    });

    test('plays at its own speed, whatever the new clip is set to', () {
      final player = AnimationPlayerComponent(clip: 'bend', speed: 0.5);
      character(player);
      system().update(0.4);
      expect(player.time, closeTo(0.2, 1e-9));
      player
        ..play('hop', fade: 1)
        ..playingSpeed = 2;
      system().update(0.1);
      expect(player.fadingFromTime, closeTo(0.25, 1e-9));
      expect(player.time, closeTo(0.2, 1e-9));
    });

    test('a paused clip fades out where it stopped', () {
      final player = AnimationPlayerComponent(clip: 'bend');
      character(player);
      system().update(0.3);
      player
        ..isPlaying = false
        ..play('hop', fade: 1);
      system().update(0.2);
      expect(player.fadingFromTime, closeTo(0.3, 1e-9));
    });

    test('a blend moves on at its clips\' own speeds', () {
      final player = AnimationPlayerComponent();
      character(player);
      // Both clips last 1 s; at speed 2 one cycle takes half a second.
      player.playBlend(['bend', 'grow'], [1, 0], speeds: [2, 2], fade: 0);
      system().update(0.1);
      expect(player.phase, closeTo(0.2, 1e-9));
      player.play('hop', fade: 1);
      system().update(0.1);
      expect(player.fadingFromPhase, closeTo(0.4, 1e-9));
    });

    test('an animator\'s transition keeps the old state\'s speed', () {
      final player = AnimationPlayerComponent(clip: 'bend', speed: 0.5);
      final bar = character(player);
      system().update(0.4);
      const SkeletalAnimationTarget().enter(
        bar,
        const AnimatorState(name: 'fast hop', clip: 'hop', speed: 3),
        fade: 1,
      );
      expect((player.playingClip, player.playingSpeed), ('hop', 3.0));
      expect((player.clip, player.speed), ('bend', 0.5), reason: 'as authored');
      system().update(0.1);
      expect(player.fadingFromTime, closeTo(0.25, 1e-9));
    });
  });

  // The bar's clips each last 1 s.
  group('a blend\'s cycle', () {
    test('one clip at two speeds keeps its stride between them', () {
      // A walk whose feet cover 2 m a cycle: slowed to 0.6 at 1.2 m/s, as
      // authored at 2 m/s.
      const tree = AnimatorBlendTree(
        parameter: 'speed',
        motions: [
          AnimatorBlendMotion(clip: 'bend', threshold: 1.2, speed: 0.6),
          AnimatorBlendMotion(clip: 'bend', threshold: 2),
        ],
      );
      final player = AnimationPlayerComponent();
      character(player);
      player.playBlend(['bend', 'bend'], [1, 0], speeds: [0.6, 1], fade: 0);
      for (final speed in [1.2, 1.4, 1.6, 1.8, 2.0]) {
        player.setBlendWeights(tree.weights(speed));
        system().update(0.1);
        expect(speed * player.duration, closeTo(2, 1e-9), reason: '$speed m/s');
      }
    });

    test('different clips weigh their lengths, as an idle and a walk', () {
      final player = AnimationPlayerComponent();
      character(player);
      player.playBlend(['bend', 'grow'], [0.5, 0.5], speeds: [1, 3], fade: 0);
      system().update(0.1);
      // Half of 1 s and half of a third of one.
      expect(player.duration, closeTo(2 / 3, 1e-9));
      expect(player.phase, closeTo(0.15, 1e-9));
    });

    test('a clip twice beside another: its speeds, then the clips', () {
      final player = AnimationPlayerComponent();
      character(player);
      player.playBlend(
        ['grow', 'bend', 'grow'],
        [0.25, 0.5, 0.25],
        speeds: [1, 1, 3],
        fade: 0,
      );
      system().update(0.1);
      // grow at its mean speed, 2, lasts half a second; bend 1 s.
      expect(player.duration, closeTo(0.75, 1e-9));
    });

    test('what fades out keeps its cycle', () {
      final player = AnimationPlayerComponent();
      character(player);
      player.playBlend(['bend', 'bend'], [0.5, 0.5], speeds: [1, 3], fade: 0);
      system().update(0.1);
      expect(player.phase, closeTo(0.2, 1e-9), reason: 'at speed 2');
      player.play('hop', fade: 1);
      system().update(0.1);
      expect(player.fadingFromPhase, closeTo(0.4, 1e-9));
    });
  });

  group('sockets', () {
    test('a socket is drawn between its poses, with its parent', () {
      final bar = character(AnimationPlayerComponent(clip: 'bend', playing: false));
      final hat = socket(bar);
      engine.world.addSystem(_Mover(bar.getComponent<TransformComponent>()!));
      final view = frameView(eye: Vector3(0, -3, -8));
      final renderer = service.sceneRenderer..update(view);

      // The first update meets the parent: it has no history yet.
      engine.world.update(1 / 60);
      renderer.update(view);
      engine.world.update(1 / 60);
      expect(hat.getComponent<TransformComponent>()!.position.x, closeTo(2, 1e-9));
      renderer.update(view..interpolation = 0.25);
      final drawn = renderer.debugShapeInstances.single!.world.storage;
      expect(drawn[12], closeTo(1.25, 1e-9), reason: 'with the hand, not a step ahead');
      expect(drawn[13], closeTo(-1, 1e-6), reason: 'the tip, 1 m up');

      engine.world.update(1 / 60);
      renderer.update(view..interpolation = 0.5);
      expect(renderer.debugShapeInstances.single!.world.storage[12], closeTo(2.5, 1e-9));
    });

    test('a socket on a moving joint starts from the joint\'s last pose', () {
      final player = AnimationPlayerComponent(clip: 'hop');
      final bar = character(player);
      final hat = socket(bar);
      // hop lifts the root 0.5 m from half a second in.
      system().update(0.4);
      system().update(0.2);
      final t = hat.getComponent<TransformComponent>()!;
      expect(t.position.y, closeTo(-1.5, 1e-6));
      expect(t.prevPosition.y, closeTo(-1, 1e-6), reason: 'where the update began');
    });

    test('a parent is posed once an update, for all its sockets', () {
      final bar = character(AnimationPlayerComponent(clip: 'bend'));
      final hats = [for (var i = 0; i < 3; i++) socket(bar)];
      final animations = system();
      final before = animations.debugPoses;
      animations
        ..update(0.1)
        ..update(0.1);
      expect(animations.debugPoses - before, 2);
      final at = [for (final h in hats) h.getComponent<TransformComponent>()!.position.y];
      expect(at.toSet(), hasLength(1), reason: 'every one on the tip');
    });

    test('a destroyed parent\'s pose is let go', () {
      final bar = character(AnimationPlayerComponent(clip: 'bend'));
      socket(bar);
      final animations = system()..update(0.1);
      expect(animations.debugSocketParents, 1);
      engine.world.destroyEntity(bar);
      animations.update(0.1);
      expect(animations.debugSocketParents, 0);
    });
  });
}

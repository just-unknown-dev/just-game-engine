// Clips and blends played backwards on a skeleton: a clip that does not
// loop plays from its end to its start and then completes; a loop counts
// its laps upwards, so an exit time is reached; a blend goes from phase 1
// to 0; a blend motion with a negative speed is sampled from its end.
@Tags(['graphics3d'])
library;

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/just_game_engine_3d.dart';
// The renderer's own sampler, not exported.
import 'package:just_game_engine/src/graphics/graphics_3d/animation_3d_system.dart'
    show PlayerScratch, samplePlayer;
import 'package:just_graphics_engine/testing.dart';
import 'package:just_graphics_engine/just_graphics_engine.dart'
    show NullGpuDevice, Pose, rendererNullShaders;

import 'fixtures.dart';

const _barPath = 'assets/models/bar.glb';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Engine engine;
  late Graphics3D service;
  const target = SkeletalAnimationTarget();
  const state = AnimatorState(name: 'any');
  final animator = AnimatorComponent();

  setUp(() async {
    service = Graphics3D(device: NullGpuDevice(shaders: rendererNullShaders));
    engine = Engine(
      config: EngineConfig(services: [service]),
      context: EngineContext(bundle: TestBundle({_barPath: skinnedBarGlb()})),
    );
    await engine.initialize();
    await service.models.load(_barPath);
  });
  tearDown(() => engine.dispose());

  (Entity, AnimationPlayerComponent) bar(AnimationPlayerComponent player) {
    final entity = engine.world.createEntityWithComponents([
      TransformComponent(),
      ModelComponent(model: _barPath),
      player,
    ], name: 'Bar');
    return (entity, player);
  }

  void step(double seconds, [int times = 1]) {
    for (var i = 0; i < times; i++) {
      engine.world.update(seconds);
    }
  }

  /// The tip's turn about +Z in [player]'s pose now, radians.
  double tipAngle(AnimationPlayerComponent player) {
    final model = service.models.get(_barPath)!;
    final pose = Pose.rest(model.data);
    samplePlayer(player, model, pose, PlayerScratch(model.data.nodes.length));
    final tip = model.data.nodes.indexWhere((n) => n.name == 'tip');
    return 2 *
        math.atan2(pose.rotations[tip * 4 + 2], pose.rotations[tip * 4 + 3]);
  }

  test(
    'a clip that does not loop plays from its end to its start, then completes',
    () {
      final (entity, player) = bar(
        AnimationPlayerComponent(clip: 'bend', loop: false, speed: -1),
      );
      expect(
        target.isComplete(entity, state),
        isFalse,
        reason: 'not started yet',
      );
      step(0.25);
      expect(player.time, closeTo(0.75, 1e-9), reason: 'from its end');
      expect(tipAngle(player), closeTo(0.75 * math.pi / 2, 1e-3));
      expect(target.progress(entity, animator, state), closeTo(0.25, 1e-9));
      expect(target.isComplete(entity, state), isFalse);
      step(0.25, 3);
      expect(player.time, 0);
      expect(target.isComplete(entity, state), isTrue);
      expect(target.progress(entity, animator, state), closeTo(1, 1e-9));
    },
  );

  test('played again backwards, it starts from its end again', () {
    final (entity, player) = bar(
      AnimationPlayerComponent(clip: 'bend', loop: false),
    );
    step(0.5, 3);
    expect(player.time, 1);
    player
      ..play('bend', restart: true, fade: 0)
      ..playingSpeed = -2;
    step(0.25);
    expect(player.time, closeTo(0.5, 1e-9));
    expect(target.isComplete(entity, state), isFalse);
  });

  test('a loop played backwards counts its laps upwards', () {
    final (entity, player) = bar(
      AnimationPlayerComponent(clip: 'bend', speed: -1),
    );
    step(0.25);
    expect(player.time, closeTo(0.75, 1e-9));
    expect(player.cycles, 0);
    expect(target.progress(entity, animator, state), closeTo(0.25, 1e-9));
    step(0.25, 4);
    expect(player.cycles, 1);
    expect(target.progress(entity, animator, state), closeTo(1.25, 1e-9));
    step(0.25, 2);
    expect(target.progress(entity, animator, state), closeTo(1.75, 1e-9));
    expect(
      target.isComplete(entity, state),
      isFalse,
      reason: 'a loop never completes',
    );
  });

  test('an exit time is reached by a state played backwards', () async {
    const graph = AnimatorGraph(
      states: [
        AnimatorState(name: 'rewind', clip: 'bend', speed: -1),
        AnimatorState(name: 'after', clip: 'hop'),
      ],
      transitions: [
        AnimatorTransition(
          from: 'rewind',
          to: 'after',
          hasExitTime: true,
          exitTime: 1.5,
        ),
      ],
      entry: 'rewind',
    );
    engine.world.addSystem(AnimatorSystem(loader: (_) async => graph));
    final (entity, player) = bar(AnimationPlayerComponent());
    final animator = AnimatorComponent(graphPath: 'bar.animator.json');
    entity.addComponent(animator);
    step(0.1);
    await Future<void>.delayed(Duration.zero); // the graph loads
    step(0.1);
    expect(animator.currentState, 'rewind');
    step(0.1, 12);
    expect(animator.currentState, 'rewind');
    step(0.1, 4);
    expect(
      animator.currentState,
      'after',
      reason: 'a lap and a half, backwards',
    );
    expect(player.playingClip, 'hop');
  });

  test('a blend played backwards goes from phase 1 to 0, then completes', () {
    final (entity, player) = bar(AnimationPlayerComponent());
    player
      ..playBlend(['bend', 'grow'], [0.5, 0.5], fade: 0)
      ..playingSpeed = -1
      ..playingLoop = false;
    step(0.25);
    expect(player.phase, closeTo(0.75, 1e-9));
    expect(target.progress(entity, animator, state), closeTo(0.25, 1e-9));
    expect(target.isComplete(entity, state), isFalse);
    step(0.25, 3);
    expect(player.phase, 0);
    expect(target.isComplete(entity, state), isTrue);
  });

  test('a blend motion with a negative speed plays its clip from its end', () {
    final (_, player) = bar(AnimationPlayerComponent());
    player.playBlend(['bend'], [1], speeds: [-1], fade: 0);
    step(0.25);
    expect(
      player.phase,
      closeTo(0.25, 1e-9),
      reason: 'the blend runs forwards',
    );
    expect(
      tipAngle(player),
      closeTo(0.75 * math.pi / 2, 1e-3),
      reason: 'its clip from its end',
    );
    expect(player.duration, closeTo(1, 1e-9), reason: 'as long as at speed 1');
  });

  test(
    'setting the time places it there, even just after playing backwards',
    () {
      final (_, player) = bar(
        AnimationPlayerComponent(clip: 'bend', loop: false, speed: -1),
      );
      player.time = 0.4;
      step(0.1);
      expect(player.time, closeTo(0.3, 1e-9));
    },
  );
}

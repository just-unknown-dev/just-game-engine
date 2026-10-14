// An animator graph driving a skinned model: states play clips with the
// transitions' crossfades, a blend tree weighs its motions by a parameter,
// and exit times read the clip's progress.
@Tags(['graphics3d'])
library;

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/graphics_3d.dart';
import 'package:just_graphics_engine/testing.dart';

import 'fixtures.dart';

const _barPath = 'assets/models/bar.glb';

const _graph = AnimatorGraph(
  parameters: [AnimatorParameter(name: 'grow'), AnimatorParameter(name: 'go', type: AnimatorParameterType.trigger)],
  states: [
    AnimatorState(name: 'bending', clip: 'bend', loop: false),
    AnimatorState(
      name: 'mix',
      blend: AnimatorBlendTree(
        parameter: 'grow',
        motions: [AnimatorBlendMotion(clip: 'bend', threshold: 0), AnimatorBlendMotion(clip: 'grow', threshold: 1)],
      ),
    ),
    AnimatorState(name: 'hopping', clip: 'hop'),
  ],
  transitions: [
    AnimatorTransition(
      from: 'bending',
      to: 'mix',
      duration: 0.5,
      conditions: [AnimatorCondition(parameter: 'go')],
    ),
    AnimatorTransition(from: 'mix', to: 'hopping', hasExitTime: true, exitTime: 1.5),
  ],
  entry: 'bending',
);

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
    engine.world.addSystem(AnimatorSystem(loader: (_) async => _graph));
  });
  tearDown(() => engine.dispose());

  test('the extension registers the skeletal target', () {
    expect(engine.context.animationTargets.all.whereType<SkeletalAnimationTarget>(), hasLength(1));
  });

  test('states, crossfades, blend weights and exit times on a skeleton', () async {
    final bar = engine.world.createEntityWithComponents([
      TransformComponent(),
      ModelComponent(model: _barPath),
      AnimationPlayerComponent(),
      AnimatorComponent(graphPath: 'bar.animator.json'),
    ], name: 'Bar');
    final player = bar.getComponent<AnimationPlayerComponent>()!;
    final animator = bar.getComponent<AnimatorComponent>()!;
    void step([int n = 1]) {
      for (var i = 0; i < n; i++) {
        engine.world.update(0.1);
      }
    }

    step();
    await Future<void>.delayed(Duration.zero); // the graph loads
    step();
    expect(animator.currentState, 'bending');
    expect((player.clip, player.loop), ('bend', false));

    animator.parameters['grow'] = 0.25;
    animator.parameters['go'] = true;
    step();
    expect(animator.currentState, 'mix');
    expect(player.blendClips, ['bend', 'grow']);
    expect(player.blendWeights, [0.75, 0.25], reason: 'weighed in the update it entered');
    expect(player.fadingFrom, 'bend', reason: 'the transition crossfades');
    step(2);
    expect(player.fade, closeTo(0.4, 1e-9));
    step(3);
    expect(player.isFading, isFalse);

    // The blend's pose sits between its clips: the tip turned about three
    // quarters of the way it does in "bend" alone at the same point
    // (rotations blend normalised-linearly, not exactly by angle).
    final model = service.models.get(_barPath)!;
    final pose = Pose.rest(model.data), scratch = PlayerScratch(model.data.nodes.length);
    samplePlayer(player, model, pose, scratch);
    final tip = model.data.nodes.indexWhere((n) => n.name == 'tip');
    final angle = 2 * math.atan2(pose.rotations[tip * 4 + 2], pose.rotations[tip * 4 + 3]);
    expect(angle, closeTo(0.75 * player.phase * math.pi / 2, 0.01));

    // Exit time 1.5: a cycle and a half of the blend, then "hopping".
    expect(animator.currentState, 'mix');
    step(15);
    expect(animator.currentState, 'hopping');
    expect((player.clip, player.isBlending), ('hop', false));
  });
}

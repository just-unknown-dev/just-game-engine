// Animator graphs playing on something other than a sprite (an
// AnimationTarget a package registers), crossfading transitions, and blend
// trees — on a target, and on a sprite (which plays the heaviest motion).
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

class _Target extends AnimationTarget {
  final List<String> log = [];
  double progressNow = 0;
  bool complete = false;
  List<double>? lastWeights;

  @override
  bool drives(Entity entity) => entity.name == 'Hero';

  @override
  void enter(Entity entity, AnimatorState state, {double fade = 0}) =>
      log.add('enter ${state.name} fade $fade');

  @override
  void update(Entity entity, AnimatorComponent animator, AnimatorState state, double deltaTime) {
    final tree = state.blend;
    if (tree == null) return;
    lastWeights = tree.weights(AnimatorParameter.asNumber(animator.parameters[tree.parameter]));
  }

  @override
  double progress(Entity entity, AnimatorComponent animator, AnimatorState state) => progressNow;

  @override
  bool isComplete(Entity entity, AnimatorState state) => complete;
}

const _graph = AnimatorGraph(
  parameters: [AnimatorParameter(name: 'speed')],
  states: [
    AnimatorState(name: 'idle'),
    AnimatorState(
      name: 'move',
      blend: AnimatorBlendTree(
        parameter: 'speed',
        motions: [
          AnimatorBlendMotion(clip: 'walk', threshold: 1),
          AnimatorBlendMotion(clip: 'run', threshold: 5),
        ],
      ),
    ),
    AnimatorState(name: 'wave'),
  ],
  transitions: [
    AnimatorTransition(
      from: 'idle',
      to: 'move',
      duration: 0.3,
      conditions: [AnimatorCondition(parameter: 'speed', op: AnimatorOp.greater, value: 0.5)],
    ),
    AnimatorTransition(from: 'move', to: 'wave', hasExitTime: true, exitTime: 0.8),
  ],
  entry: 'idle',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late World world;
  late _Target target;
  late AnimatorSystem system;

  setUp(() async {
    world = World()..initialize();
    target = _Target();
    world.context.animationTargets.register(target);
    system = AnimatorSystem(loader: (_) async => _graph);
    world.addSystem(system);
  });
  tearDown(() => world.dispose());

  Future<void> settle() async {
    world.update(1 / 60); // starts loading the graph
    await Future<void>.delayed(Duration.zero);
  }

  test('an entity without a sprite plays on the target that drives it', () async {
    final hero = world.createEntityWithComponents([AnimatorComponent(graphPath: 'hero.animator.json')], name: 'Hero');
    final animator = hero.getComponent<AnimatorComponent>()!;
    await settle();
    world.update(1 / 60);
    expect(target.log, ['enter idle fade 0.0']);
    animator.parameters['speed'] = 3.0;
    world.update(1 / 60);
    expect(target.log.last, 'enter move fade 0.3', reason: "the transition's crossfade reaches the target");
    // The blend tree is weighed every update.
    world.update(1 / 60);
    expect(target.lastWeights, [0.5, 0.5]);
    // The exit time reads the target's progress.
    target.progressNow = 0.5;
    world.update(1 / 60);
    expect(animator.currentState, 'move');
    target.progressNow = 0.85;
    world.update(1 / 60);
    expect(animator.currentState, 'wave');
  });

  test('an entity no target drives is left alone', () async {
    final other = world.createEntityWithComponents([AnimatorComponent(graphPath: 'hero.animator.json')], name: 'Rock');
    await settle();
    world.update(1 / 60);
    expect(other.getComponent<AnimatorComponent>()!.currentState, isEmpty);
    expect(target.log, isEmpty);
  });

  test('a sprite plays the heaviest motion of a blend tree, switching as it changes', () async {
    final hero = world.createEntityWithComponents([
      AnimatorComponent(graphPath: 'hero.animator.json'),
      SpriteAnimationComponent(clip: 'idle'),
    ], name: 'Hero');
    final animator = hero.getComponent<AnimatorComponent>()!;
    final sprite = hero.getComponent<SpriteAnimationComponent>()!;
    await settle();
    world.update(1 / 60);
    animator.parameters['speed'] = 2.0;
    world.update(1 / 60);
    expect(animator.currentState, 'move');
    expect(sprite.clip, 'walk');
    expect(target.log, isEmpty, reason: 'a sprite is never handed to a target');
    animator.parameters['speed'] = 4.5;
    world.update(1 / 60);
    expect(sprite.clip, 'run');
  });
}

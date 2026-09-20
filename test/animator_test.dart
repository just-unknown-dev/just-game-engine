// The animation state machine: parameters in, a clip out.

import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

const _dt = 1 / 60;

/// idle (0.2 s, loops) · run (0.2 s, loops) · jump (0.2 s, once) · hurt.
Map<String, dynamic> _atlasJson() => {
  'frames': {
    for (var i = 0; i < 8; i++)
      'f$i': {
        'frame': {'x': i * 4, 'y': 0, 'w': 4, 'h': 4},
        'sourceSize': {'w': 4, 'h': 4},
        'spriteSourceSize': {'x': 0, 'y': 0, 'w': 4, 'h': 4},
        'duration': 100,
      },
  },
  'meta': {
    'app': 'aseprite',
    'image': 'hero.png',
    'size': {'w': 32, 'h': 4},
    'frameTags': [
      {'name': 'idle', 'from': 0, 'to': 1, 'direction': 'forward'},
      {'name': 'run', 'from': 2, 'to': 3, 'direction': 'forward'},
      {'name': 'jump', 'from': 4, 'to': 5, 'direction': 'forward'},
      {'name': 'hurt', 'from': 6, 'to': 7, 'direction': 'forward'},
    ],
    'just': {
      'clips': {
        'jump': {'loop': false},
        'hurt': {'loop': false},
      },
    },
  },
};

class _Loader extends SpriteAssetLoader {
  @override
  Future<ui.Image> loadImage(String path) async => _image();

  @override
  Future<SpriteAtlas> loadAtlas(String path) =>
      SpriteAtlas.fromJson(_atlasJson(), loadImage: (_) async => _image());

  static ui.Image _image() {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawPaint(Paint());
    return recorder.endRecording().toImageSync(32, 4);
  }
}

const _graph = AnimatorGraph(
  entry: 'idle',
  parameters: [
    AnimatorParameter(name: 'speed', binding: 'speedX'),
    AnimatorParameter(name: 'grounded', type: AnimatorParameterType.bool),
    AnimatorParameter(name: 'jumped', type: AnimatorParameterType.trigger),
    AnimatorParameter(name: 'hit', type: AnimatorParameterType.trigger),
  ],
  states: [
    AnimatorState(name: 'idle'),
    AnimatorState(name: 'run', speed: 2),
    AnimatorState(name: 'jump'),
    AnimatorState(name: 'ouch', clip: 'hurt'),
  ],
  transitions: [
    AnimatorTransition(
      from: 'idle',
      to: 'run',
      conditions: [
        AnimatorCondition(
          parameter: 'speed',
          op: AnimatorOp.greater,
          value: 10,
        ),
      ],
    ),
    AnimatorTransition(
      from: 'run',
      to: 'idle',
      conditions: [
        AnimatorCondition(
          parameter: 'speed',
          op: AnimatorOp.lessOrEqual,
          value: 10,
        ),
      ],
    ),
    AnimatorTransition(
      from: 'idle',
      to: 'jump',
      priority: 5,
      conditions: [AnimatorCondition(parameter: 'jumped')],
    ),
    // When the jump clip has played through.
    AnimatorTransition(from: 'jump', to: 'idle', hasExitTime: true),
    AnimatorTransition(
      from: AnimatorTransition.anyState,
      to: 'ouch',
      conditions: [AnimatorCondition(parameter: 'hit')],
    ),
    AnimatorTransition(from: 'ouch', to: 'idle', hasExitTime: true),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late World world;
  late AnimatorSystem animators;

  setUp(() {
    world = World();
    registerSpriteSystems(
      world,
      loader: _Loader(),
      graphLoader: (_) async => _graph,
    );
    animators = world.systems.whereType<AnimatorSystem>().single;
  });
  tearDown(() => world.dispose());

  Future<void> settle() async {
    world.update(0);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    world.update(0);
  }

  ({Entity entity, AnimatorComponent animator, SpriteAnimationComponent sprite})
  hero({bool faceVelocity = false}) {
    final animator = AnimatorComponent(
      graphPath: 'hero.animator.json',
      faceVelocity: faceVelocity,
    );
    final sprite = SpriteAnimationComponent(atlasPath: 'hero.json');
    final entity = world.createEntityWithComponents([
      TransformComponent(),
      VelocityComponent(),
      sprite,
      animator,
    ]);
    return (entity: entity, animator: animator, sprite: sprite);
  }

  void setSpeed(Entity e, double vx) =>
      e.getComponent<VelocityComponent>()!.velocity.x = vx;

  test('registerSpriteSystems orders animator before playback', () {
    final order = [
      for (final s in world.systems)
        if (s is AnimatorSystem || s is SpriteAnimationSystem) s.runtimeType,
    ];
    expect(order, [AnimatorSystem, SpriteAnimationSystem]);
    registerSpriteSystems(world);
    expect(world.systems.whereType<AnimatorSystem>(), hasLength(1));
  });

  test('it starts in the entry state, playing that clip', () async {
    final h = hero();
    await settle();
    expect(h.animator.currentState, 'idle');
    expect(h.sprite.clip, 'idle');
    expect(h.animator.getBool('grounded'), isFalse, reason: 'defaults filled');
  });

  test('a bound parameter drives a transition, and back', () async {
    final h = hero();
    await settle();
    setSpeed(h.entity, -120);
    world.update(_dt);
    expect(h.animator.getFloat('speed'), 120, reason: 'speedX is absolute');
    expect(h.animator.currentState, 'run');
    expect(h.sprite.clip, 'run');
    expect(h.sprite.speed, 2, reason: "the state's speed");

    setSpeed(h.entity, 0);
    world.update(_dt);
    expect(h.animator.currentState, 'idle');
    expect(h.animator.previousState, 'run');
    expect(h.sprite.speed, 1);
  });

  test(
    'a trigger fires once and is consumed; priority picks the winner',
    () async {
      final h = hero();
      await settle();
      setSpeed(h.entity, 50); // idle → run is also possible
      h.animator.setTrigger('jumped');
      world.update(_dt);
      expect(h.animator.currentState, 'jump', reason: 'priority 5 beats 0');
      expect(h.animator.getBool('jumped'), isFalse);
    },
  );

  test('an exit time waits for the clip, then leaves', () async {
    final h = hero();
    await settle();
    h.animator.setTrigger('jumped');
    world.update(_dt);
    expect(h.animator.currentState, 'jump');

    world.update(0.1);
    expect(h.animator.currentState, 'jump', reason: 'half way');
    world.update(0.15);
    world.update(_dt);
    expect(h.animator.currentState, 'idle');
  });

  test(
    'Any State goes first, from wherever it is, but not to itself',
    () async {
      final h = hero();
      final changes = <String>[];
      animators.stateChanges.listen((c) => changes.add('${c.from}>${c.to}'));
      await settle();
      setSpeed(h.entity, 50);
      world.update(_dt);
      h.animator.setTrigger('hit');
      world.update(_dt);
      expect(h.animator.currentState, 'ouch');
      expect(h.sprite.clip, 'hurt', reason: "the state's clip, not its name");

      h.animator.setTrigger('hit');
      world.update(_dt);
      expect(h.animator.currentState, 'ouch');
      expect(h.animator.stateTime, greaterThan(0), reason: 'not re-entered');
      expect(changes, ['>idle', 'idle>run', 'run>ouch']);
    },
  );

  test('disabled holds; faceVelocity flips and remembers', () async {
    final h = hero(faceVelocity: true);
    await settle();
    setSpeed(h.entity, -40);
    world.update(_dt);
    expect(h.sprite.flipX, isTrue);
    setSpeed(h.entity, 0);
    world.update(_dt);
    expect(h.sprite.flipX, isTrue, reason: 'still facing left');
    setSpeed(h.entity, 40);
    world.update(_dt);
    expect(h.sprite.flipX, isFalse);

    h.animator.enabled = false;
    final state = h.animator.currentState;
    setSpeed(h.entity, 0);
    world.update(_dt);
    expect(h.animator.currentState, state);
  });

  test('a kit can add a binding', () async {
    AnimatorBindings.register('always7', (_) => 7);
    addTearDown(() => AnimatorBindings.unregister('always7'));
    expect(AnimatorBindings.ids, contains('always7'));
    expect(
      AnimatorBindings.ids,
      containsAll(['speedX', 'velocityY', 'health']),
    );
  });

  test('reload starts animators of that graph over', () async {
    final h = hero();
    await settle();
    setSpeed(h.entity, 50);
    world.update(_dt);
    expect(h.animator.currentState, 'run');
    animators.reload('hero.animator.json');
    expect(h.animator.currentState, '');
    await settle();
    expect(animators.graphOf(h.entity), isNotNull);
  });

  group('the graph', () {
    test('round-trips through JSON', () {
      final back = AnimatorGraph.parse(_graph.encode());
      expect(back.toJson(), _graph.toJson());
      expect(back.states[3].clipName, 'hurt');
      expect(back.transitions[3].hasExitTime, isTrue);
      expect(back.parameters.first.binding, 'speedX');
    });

    test('validate says what is wrong in words', () {
      expect(_graph.validate(), isEmpty);
      const broken = AnimatorGraph(
        entry: 'nowhere',
        states: [
          AnimatorState(name: 'a'),
          AnimatorState(name: 'a'),
        ],
        transitions: [
          AnimatorTransition(from: 'a', to: 'b'),
          AnimatorTransition(
            from: 'a',
            to: 'a',
            conditions: [AnimatorCondition(parameter: 'ghost')],
          ),
        ],
      );
      final problems = broken.validate().join('\n');
      expect(problems, contains('Two states are named "a"'));
      expect(problems, contains('entry state "nowhere"'));
      expect(problems, contains('goes to "b"'));
      expect(problems, contains('fires at once'));
      expect(problems, contains('"ghost", which is not a parameter'));
    });

    test('conditions compare numbers, bools and triggers', () {
      const c = AnimatorCondition(
        parameter: 'x',
        op: AnimatorOp.greaterOrEqual,
        value: 2,
      );
      expect(c.holds(2, AnimatorParameterType.int), isTrue);
      expect(c.holds(1.9, AnimatorParameterType.float), isFalse);
      const not = AnimatorCondition(
        parameter: 'b',
        op: AnimatorOp.notEquals,
        value: true,
      );
      expect(not.holds(false, AnimatorParameterType.bool), isTrue);
      expect(not.holds(null, AnimatorParameterType.trigger), isFalse);
    });
  });

  test('the component round-trips through the scene codec', () {
    registerCoreCodecs();
    final out =
        ComponentCodecRegistry.instance.decode(
              ComponentCodecRegistry.instance.encode(
                AnimatorComponent(
                  graphPath: 'a.animator.json',
                  faceVelocity: true,
                ),
              )!,
            )
            as AnimatorComponent;
    expect(out.graphPath, 'a.animator.json');
    expect(out.faceVelocity, isTrue);
  });
}

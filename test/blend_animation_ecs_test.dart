import 'package:flutter/painting.dart' show Rect;
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  BlendClip clip({
    required String name,
    required double fps,
    required int frameCount,
  }) => BlendClip(name: name, fps: fps, frameCount: frameCount);

  // Wires up a minimal World + AnimationBlendTreeSystem + one entity with a
  // BlendSprite renderable and the given machine/clips — the fixture every
  // test in this file builds on. No real ui.Image is needed: phase/weight
  // math and transition bookkeeping never touch BlendFrameSource.image.
  (World, AnimationBlendTreeComponent) makeEntity(
    BlendStateMachine machine,
    Map<String, BlendClip> clips,
  ) {
    final world = World();
    world.initialize();
    world.addSystem(AnimationBlendTreeSystem());
    final entity = world.createEntity();
    entity.addComponent(RenderableComponent(renderable: BlendSprite()));
    final comp = AnimationBlendTreeComponent(machine: machine, clips: clips);
    entity.addComponent(comp);
    return (world, comp);
  }

  group('play() semantics', () {
    test('is a no-op when already playing the requested state', () {
      final machine = BlendStateMachine(
        states: {
          'idle': BlendState(motion: const ClipMotion('idle')),
          'run': BlendState(motion: const ClipMotion('run')),
        },
        defaultState: 'idle',
      );
      final (world, comp) = makeEntity(machine, {
        'idle': clip(name: 'idle', fps: 8, frameCount: 4),
        'run': clip(name: 'run', fps: 8, frameCount: 4),
      });

      comp.play('idle');
      world.update(0.016);
      expect(comp.isTransitioning, isFalse);
      expect(comp.currentStateName, 'idle');
    });

    test('starts a transition to a different state', () {
      final machine = BlendStateMachine(
        states: {
          'idle': BlendState(motion: const ClipMotion('idle')),
          'run': BlendState(motion: const ClipMotion('run')),
        },
        defaultState: 'idle',
        defaultTransitionDuration: 0.2,
      );
      final (world, comp) = makeEntity(machine, {
        'idle': clip(name: 'idle', fps: 8, frameCount: 4),
        'run': clip(name: 'run', fps: 8, frameCount: 4),
      });

      comp.play('run');
      world.update(0.01);
      expect(comp.isTransitioning, isTrue);
      expect(comp.currentStateName, 'idle');
      expect(comp.targetStateName, 'run');
      expect(comp.transitionDuration, closeTo(0.2, 1e-9));
    });

    test('unknown state names are silently ignored', () {
      final machine = BlendStateMachine(
        states: {'idle': BlendState(motion: const ClipMotion('idle'))},
        defaultState: 'idle',
      );
      final (world, comp) = makeEntity(machine, {
        'idle': clip(name: 'idle', fps: 8, frameCount: 4),
      });

      comp.play('does_not_exist');
      world.update(0.016);
      expect(comp.isTransitioning, isFalse);
      expect(comp.currentStateName, 'idle');
    });

    test('restart resets phase in place without starting a transition', () {
      final machine = BlendStateMachine(
        states: {'idle': BlendState(motion: const ClipMotion('idle'))},
        defaultState: 'idle',
      );
      final (world, comp) = makeEntity(machine, {
        'idle': clip(name: 'idle', fps: 8, frameCount: 4),
      });

      world.update(0.1); // 0.1 * (8fps/4frames = 2.0 cycles/sec) = phase 0.2
      expect(comp.currentPhase, greaterThan(0.0));

      comp.play('idle', restart: true);
      world.update(0.0);
      expect(comp.currentPhase, 0.0);
      expect(comp.isTransitioning, isFalse);
    });
  });

  group('Phase synchronization', () {
    test(
      'clips of different frame counts/fps blended 50/50 share one phase '
      'driven by the weighted-average cycle rate',
      () {
        final machine = BlendStateMachine(
          states: {
            'blend': BlendState(
              motion: BlendTree1DMotion(
                parameter: 'p',
                children: [
                  const BlendTree1DChild(threshold: 0, clip: 'a'),
                  const BlendTree1DChild(threshold: 10, clip: 'b'),
                ],
              ),
            ),
          },
          defaultState: 'blend',
        );
        final (world, comp) = makeEntity(machine, {
          'a': clip(name: 'a', fps: 8, frameCount: 4), // 2.0 cycles/sec
          'b': clip(name: 'b', fps: 6, frameCount: 12), // 0.5 cycles/sec
        });
        comp.setFloat('p', 5); // exact midpoint of [0,10] -> weights 0.5/0.5

        // rate = 0.5*2.0 + 0.5*0.5 = 1.25 cycles/sec
        world.update(0.1);
        expect(comp.currentPhase, closeTo(0.125, 1e-9));

        world.update(0.1);
        expect(comp.currentPhase, closeTo(0.25, 1e-9));
      },
    );
  });

  group('Transitions', () {
    late BlendStateMachine machine;
    setUp(() {
      machine = BlendStateMachine(
        states: {
          'idle': BlendState(motion: const ClipMotion('idle')),
          'run': BlendState(motion: const ClipMotion('run')),
        },
        defaultState: 'idle',
        defaultTransitionDuration: 0.2,
      );
    });

    test('crossfades over the configured duration then flips state', () {
      final (world, comp) = makeEntity(machine, {
        'idle': clip(name: 'idle', fps: 8, frameCount: 4),
        'run': clip(name: 'run', fps: 8, frameCount: 4),
      });

      comp.play('run');
      world.update(0.1); // 0.1s into a 0.2s crossfade
      expect(comp.isTransitioning, isTrue);
      expect(comp.currentStateName, 'idle');
      expect(comp.transitionElapsed, closeTo(0.1, 1e-9));

      world.update(0.11); // total elapsed 0.21s > 0.2s duration
      expect(comp.isTransitioning, isFalse);
      expect(comp.currentStateName, 'run');
      expect(comp.targetStateName, isNull);
    });

    test('both phases advance independently while transitioning', () {
      final (world, comp) = makeEntity(machine, {
        'idle': clip(name: 'idle', fps: 8, frameCount: 4), // 2.0 cycles/sec
        'run': clip(name: 'run', fps: 5, frameCount: 10), // 0.5 cycles/sec
      });

      comp.play('run');
      world.update(0.1);
      expect(comp.currentPhase, closeTo(0.2, 1e-9)); // idle: 0.1 * 2.0
      expect(comp.targetPhase, closeTo(0.05, 1e-9)); // run: 0.1 * 0.5
    });
  });

  group('One-shot states', () {
    test('isLocked while playing, completes and unlocks at the clip end', () {
      final machine = BlendStateMachine(
        states: {
          'idle': BlendState(motion: const ClipMotion('idle')),
          'attack': BlendState(motion: const ClipMotion('attack'), loop: false),
        },
        defaultState: 'idle',
        defaultTransitionDuration: 0.0, // instant, isolates one-shot timing
      );
      final (world, comp) = makeEntity(machine, {
        'idle': clip(name: 'idle', fps: 8, frameCount: 4),
        'attack': clip(name: 'attack', fps: 10, frameCount: 5), // 0.5s clip
      });

      comp.play('attack');
      world.update(0.0); // 0-duration transition resolves same tick
      expect(comp.currentStateName, 'attack');
      expect(comp.isLocked, isTrue);
      expect(comp.isCurrentStateComplete, isFalse);

      world.update(0.3); // 0.3s of 0.5s
      expect(comp.isLocked, isTrue);
      expect(comp.isCurrentStateComplete, isFalse);

      world.update(0.3); // 0.6s total > 0.5s duration
      expect(comp.isCurrentStateComplete, isTrue);
      expect(comp.isLocked, isFalse);
      expect(comp.currentPhase, 1.0); // clamped, not wrapped
    });
  });

  group('Mid-transition interrupts', () {
    late BlendStateMachine machine;
    late Map<String, BlendClip> clips;
    setUp(() {
      machine = BlendStateMachine(
        states: {
          'idle': BlendState(motion: const ClipMotion('idle')),
          'run': BlendState(motion: const ClipMotion('run')),
          'attack': BlendState(motion: const ClipMotion('attack'), loop: false),
        },
        defaultState: 'idle',
        defaultTransitionDuration: 0.2,
      );
      clips = {
        'idle': clip(name: 'idle', fps: 8, frameCount: 4),
        'run': clip(name: 'run', fps: 8, frameCount: 4),
        'attack': clip(name: 'attack', fps: 8, frameCount: 4),
      };
    });

    test('collapses onto the target when it was dominant (t >= 0.5)', () {
      final (world, comp) = makeEntity(machine, clips);

      comp.play('run');
      world.update(0.15); // t = 0.15/0.2 = 0.75 -> target is dominant
      expect(comp.isTransitioning, isTrue);

      comp.play('attack'); // interrupt with a third state
      world.update(0.0);
      expect(comp.currentStateName, 'run');
      expect(comp.targetStateName, 'attack');
    });

    test('collapses onto the original current when it was dominant (t < 0.5)', () {
      final (world, comp) = makeEntity(machine, clips);

      comp.play('run');
      world.update(0.05); // t = 0.05/0.2 = 0.25 -> current is still dominant
      expect(comp.isTransitioning, isTrue);

      comp.play('attack');
      world.update(0.0);
      expect(comp.currentStateName, 'idle');
      expect(comp.targetStateName, 'attack');
    });

    test('re-requesting the in-flight target is a no-op, not a collapse', () {
      final (world, comp) = makeEntity(machine, clips);

      comp.play('run');
      world.update(0.05);
      final elapsedBefore = comp.transitionElapsed;

      comp.play('run'); // already heading there
      world.update(0.05);
      expect(comp.transitionElapsed, closeTo(elapsedBefore + 0.05, 1e-9));
      expect(comp.targetStateName, 'run');
    });
  });

  group('BlendStateMachine.durationFor', () {
    test('an exact from-match beats a wildcard override, both beat the default', () {
      final machine = BlendStateMachine(
        states: {
          'a': BlendState(motion: const ClipMotion('a')),
          'b': BlendState(motion: const ClipMotion('b')),
        },
        transitions: const [
          BlendTransition(to: 'b', duration: 0.5), // wildcard: any -> b
          BlendTransition(from: 'a', to: 'b', duration: 0.1), // exact: a -> b
        ],
        defaultState: 'a',
        defaultTransitionDuration: 0.2,
      );
      expect(machine.durationFor('a', 'b'), 0.1);
      expect(machine.durationFor('z', 'b'), 0.5);
      expect(machine.durationFor('a', 'a'), 0.2);
    });
  });

  group('JSON round-trip', () {
    test('BlendStateMachine survives toJson/fromJson', () {
      final machine = BlendStateMachine(
        states: {
          'idle': BlendState(motion: const ClipMotion('idle')),
          'locomotion': BlendState(
            motion: BlendTree2DMotion(
              parameterX: 'moveX',
              parameterY: 'moveY',
              children: [
                const BlendTree2DChild(position: Offset(0, 0), clip: 'idle'),
                const BlendTree2DChild(position: Offset(0, 1), clip: 'run'),
              ],
            ),
          ),
          'attack': BlendState(motion: const ClipMotion('attack'), loop: false),
        },
        transitions: const [
          BlendTransition(from: 'idle', to: 'attack', duration: 0.05),
        ],
        defaultState: 'idle',
        defaultTransitionDuration: 0.15,
      );

      final restored = BlendStateMachine.fromJson(machine.toJson());

      expect(restored.defaultState, 'idle');
      expect(restored.defaultTransitionDuration, 0.15);
      expect(restored.durationFor('idle', 'attack'), 0.05);
      expect(restored.durationFor('idle', 'run'), 0.15); // falls back
      expect(restored.states['attack']!.loop, isFalse);

      final locomotion = restored.states['locomotion']!.motion;
      expect(locomotion, isA<BlendTree2DMotion>());
      locomotion as BlendTree2DMotion;
      expect(locomotion.parameterX, 'moveX');
      expect(locomotion.children.map((c) => c.clip), ['idle', 'run']);
    });

    test(
      'BlendClip.fromJson eagerly builds a GridBlendFrameSource when grid '
      'fields are present',
      () {
        final parsed = BlendClip.fromJson({
          'name': 'run',
          'fps': 12,
          'frameCount': 14,
          'frameWidth': 128,
          'frameHeight': 128,
          'columns': 14,
          'rows': 8,
        });
        expect(parsed.frameSource, isNotNull);
        expect(parsed.frameSource!.image, isNull);
        expect(
          parsed.frameSource!.frameRect(2, 3),
          const Rect.fromLTWH(256, 384, 128, 128),
        );
      },
    );

    test('BlendClip.fromJson leaves frameSource null without grid fields', () {
      final parsed = BlendClip.fromJson({
        'name': 'run',
        'fps': 12,
        'frameCount': 14,
        'assetPath': 'assets/run.json',
      });
      expect(parsed.frameSource, isNull);
      expect(parsed.assetPath, 'assets/run.json');
    });
  });
}

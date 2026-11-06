// The built-in deterministic effects: where each ends, that a jump over
// many ticks lands where stepping one tick at a time does, and that the
// composites (sequence, parallel, repeat) call their children's callbacks.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// An entity's state an effect can change.
typedef _State = ({
  List<double> position,
  double angle,
  List<double> scale,
  double opacity,
  Color? tint,
});

class _Probe {
  _Probe() {
    world = World()..initialize();
    entity = world.createEntityWithComponents([
      TransformComponent(position: Vector3(10, 20, 0)),
      RenderableComponent(renderable: CustomRenderable(onRender: (_, _) {})),
    ]);
  }

  late final World world;
  late final Entity entity;

  TransformComponent get transform =>
      entity.getComponent<TransformComponent>()!;
  Renderable get renderable =>
      entity.getComponent<RenderableComponent>()!.renderable;

  EffectContext at(int tick) =>
      EffectContext(entity: entity, currentTick: tick);

  _State get state => (
    position: [transform.position.x, transform.position.y],
    angle: transform.angle,
    scale: [transform.scale.x, transform.scale.y],
    opacity: renderable.opacity,
    tint: renderable.tint,
  );
}

/// Plays a fresh [make]() from tick 0 to [ticks], one tick at a time or in
/// one jump, and gives what it left.
_State _play(
  DeterministicEffect Function() make,
  int ticks, {
  required bool jump,
}) {
  final probe = _Probe();
  addTearDown(probe.world.dispose);
  final player = EffectPlayer()..add(make(), 0);
  if (jump) {
    player.advanceTo(ticks, probe.at(ticks));
  } else {
    for (var t = 1; t <= ticks; t++) {
      player.advanceTo(t, probe.at(t));
    }
  }
  return probe.state;
}

/// Expects [actual] to be [expected], each to within rounding.
void _near(List<double> actual, List<num> expected) {
  expect(actual, hasLength(expected.length));
  for (var i = 0; i < expected.length; i++) {
    expect(actual[i], closeTo(expected[i], 1e-9), reason: 'at $i');
  }
}

/// Whether two states match, numbers to within rounding.
void _expectSame(_State a, _State b) {
  for (var i = 0; i < 2; i++) {
    expect(a.position[i], closeTo(b.position[i], 1e-9));
    expect(a.scale[i], closeTo(b.scale[i], 1e-9));
  }
  expect(a.angle, closeTo(b.angle, 1e-9));
  expect(a.opacity, closeTo(b.opacity, 1e-9));
  expect(a.tint, b.tint);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final effects = <String, (DeterministicEffect Function(), int)>{
    'move': (() => MoveEffect(to: Vector3(400, 0, 0), durationTicks: 4), 4),
    'rotate': (() => RotateEffect(to: math.pi, durationTicks: 10), 10),
    'scale': (() => ScaleEffect(to: 2, durationTicks: 10), 10),
    'fade': (
      () => FadeEffect(to: 0, durationTicks: 10, easing: EasingType.easeInQuad),
      10,
    ),
    'colorTint': (
      () => ColorTintEffect(to: const Color(0xFFFF0000), durationTicks: 10),
      10,
    ),
    'shake': (() => ShakeEffect(amplitude: 8, durationTicks: 12), 12),
    'path': (
      () => PathEffect(
        waypoints: const [Offset(0, 0), Offset(50, -80), Offset(100, 0)],
        durationTicks: 10,
      ),
      10,
    ),
    'delay': (() => DelayEffect(durationTicks: 5), 5),
    'sequence': (
      () => SequenceEffect(
        children: [
          MoveEffect(
            from: Vector3.zero(),
            to: Vector3(30, 0, 0),
            durationTicks: 3,
          ),
          DelayEffect(durationTicks: 2),
          RotateEffect(to: 1, durationTicks: 4),
        ],
      ),
      9,
    ),
    'parallel': (
      () => ParallelEffect(
        children: [
          MoveEffect(
            from: Vector3.zero(),
            to: Vector3(0, 40, 0),
            durationTicks: 4,
          ),
          ScaleEffect(to: 3, durationTicks: 8),
        ],
      ),
      8,
    ),
    'repeat': (
      () => RepeatEffect(
        child: MoveEffect(
          from: Vector3.zero(),
          to: Vector3(5, 0, 0),
          durationTicks: 3,
        ),
        times: 3,
      ),
      9,
    ),
  };

  group('a jump lands where stepping does', () {
    for (final MapEntry(key: name, value: (make, ticks)) in effects.entries) {
      test(name, () {
        // Part-way, at the end, and well past it (advanceTo(t + 10)).
        for (final t in [ticks ~/ 2, ticks, ticks + 10]) {
          _expectSame(_play(make, t, jump: true), _play(make, t, jump: false));
        }
      });
    }
  });

  group('where each one ends', () {
    _State end(String name) {
      final (make, ticks) = effects[name]!;
      return _play(make, ticks + 10, jump: false);
    }

    test('move reaches its target', () {
      _near(end('move').position, [400, 0]);
    });

    test('rotate turns to its target', () {
      expect(end('rotate').angle, closeTo(math.pi, 1e-12));
    });

    test('scale grows to its target on both axes', () {
      _near(end('scale').scale, [2, 2]);
    });

    test('fade reaches its opacity', () {
      expect(end('fade').opacity, closeTo(0, 1e-9));
    });

    test('colorTint ends on its colour', () {
      expect(end('colorTint').tint, const Color(0xFFFF0000));
    });

    test('shake leaves the entity where it was', () {
      _near(end('shake').position, [10, 20]);
    });

    test('a relative path ends offset by its last waypoint', () {
      _near(end('path').position, [110, 20]);
    });

    test('delay changes nothing', () {
      final s = end('delay');
      expect(s.position, [10, 20]);
      expect(s.opacity, 1);
      expect(s.tint, isNull);
    });

    test('sequence plays its children in order', () {
      final s = end('sequence');
      _near(s.position, [40, 20]);
      expect(s.angle, closeTo(1, 1e-12));
    });

    test('parallel plays its children together, as long as the longest', () {
      final s = end('parallel');
      _near(s.position, [10, 60]);
      _near(s.scale, [3, 3]);
      expect(effects['parallel']!.$1().durationTicks, 8);
    });

    test('repeat plays its child the given number of times', () {
      _near(end('repeat').position, [25, 20]);
    });
  });

  group('composite callbacks', () {
    /// Steps [effect] tick by tick to [ticks], or jumps there, on a fresh
    /// probe.
    void run(DeterministicEffect effect, int ticks, {required bool jump}) {
      final probe = _Probe();
      addTearDown(probe.world.dispose);
      final player = EffectPlayer()..add(effect, 0);
      if (jump) {
        player.advanceTo(ticks, probe.at(ticks));
      } else {
        for (var t = 1; t <= ticks; t++) {
          player.advanceTo(t, probe.at(t));
        }
      }
    }

    for (final jump in [false, true]) {
      final how = jump ? 'in one jump' : 'tick by tick';

      test('a sequence calls each child onComplete in order, $how', () {
        final calls = <String>[];
        final sequence = SequenceEffect(
          children: [
            MoveEffect(
              to: Vector3(50, 0, 0),
              durationTicks: 3,
              onComplete: () => calls.add('move'),
            ),
            DelayEffect(durationTicks: 2, onComplete: () => calls.add('delay')),
            FadeEffect(
              to: 0,
              durationTicks: 3,
              onComplete: () => calls.add('fade'),
            ),
          ],
          onComplete: () => calls.add('sequence'),
        );
        run(sequence, 20, jump: jump);
        expect(calls, ['move', 'delay', 'fade', 'sequence']);
      });

      test('a parallel calls its children onComplete by end tick, $how', () {
        final calls = <String>[];
        final parallel = ParallelEffect(
          children: [
            DelayEffect(durationTicks: 6, onComplete: () => calls.add('6')),
            DelayEffect(durationTicks: 2, onComplete: () => calls.add('2a')),
            DelayEffect(durationTicks: 4, onComplete: () => calls.add('4')),
            DelayEffect(durationTicks: 2, onComplete: () => calls.add('2b')),
          ],
          onComplete: () => calls.add('parallel'),
        );
        run(parallel, 10, jump: jump);
        expect(calls, ['2a', '2b', '4', '6', 'parallel']);
      });

      test('a finite repeat calls onLoopComplete between laps, $how', () {
        final calls = <String>[];
        final repeat = RepeatEffect(
          child: DelayEffect(
            durationTicks: 2,
            onComplete: () => calls.add('c'),
          ),
          times: 3,
          onLoopComplete: () => calls.add('lap'),
          onComplete: () => calls.add('done'),
        );
        run(repeat, 10, jump: jump);
        expect(calls, ['c', 'lap', 'c', 'lap', 'c', 'done']);
      });

      test('an endless repeat calls its child each lap, $how', () {
        final calls = <String>[];
        final repeat = RepeatEffect(
          child: DelayEffect(
            durationTicks: 2,
            onComplete: () => calls.add('c'),
          ),
          times: 0,
          onLoopComplete: () => calls.add('lap'),
        );
        run(repeat, 6, jump: jump);
        expect(calls, ['c', 'lap', 'c', 'lap', 'c', 'lap']);
      });
    }

    test('a nested sequence calls the inner children too', () {
      final calls = <String>[];
      final outer = SequenceEffect(
        children: [
          SequenceEffect(
            children: [
              DelayEffect(durationTicks: 1, onComplete: () => calls.add('a')),
              DelayEffect(durationTicks: 1, onComplete: () => calls.add('b')),
            ],
            onComplete: () => calls.add('inner'),
          ),
          DelayEffect(durationTicks: 1, onComplete: () => calls.add('c')),
        ],
      );
      run(outer, 5, jump: true);
      expect(calls, ['a', 'b', 'inner', 'c']);
    });
  });

  group('colour tint', () {
    test('flashing red and back to white leaves no tint behind', () {
      final probe = _Probe();
      addTearDown(probe.world.dispose);
      expect(probe.renderable.tint, isNull);
      final player = EffectPlayer()
        ..add(
          SequenceEffect(
            children: [
              ColorTintEffect(to: const Color(0xFFFF0000), durationTicks: 4),
              ColorTintEffect(to: const Color(0xFFFFFFFF), durationTicks: 4),
            ],
          ),
          0,
        );
      for (var t = 1; t <= 8; t++) {
        player.advanceTo(t, probe.at(t));
        if (t == 4) expect(probe.renderable.tint, const Color(0xFFFF0000));
      }
      expect(probe.renderable.tint, isNull);
    });

    test('a tint ending on a see-through white keeps it', () {
      final probe = _Probe();
      addTearDown(probe.world.dispose);
      ColorTintEffect(
        to: const Color(0x80FFFFFF),
        durationTicks: 2,
      ).applyTick(probe.at(2), 0, 2);
      expect(probe.renderable.tint, const Color(0x80FFFFFF));
    });
  });

  group('path', () {
    test('a transform added after the first tick does not throw', () {
      final world = World()..initialize();
      addTearDown(world.dispose);
      final entity = world.createEntity();
      final player = EffectPlayer()
        ..add(
          PathEffect(
            waypoints: const [Offset(0, 0), Offset(100, 0)],
            durationTicks: 4,
          ),
          0,
        );
      EffectContext at(int t) => EffectContext(entity: entity, currentTick: t);
      player.advanceTo(1, at(1));
      entity.addComponent(TransformComponent(position: Vector3(5, 5, 0)));
      for (var t = 2; t <= 5; t++) {
        player.advanceTo(t, at(t));
      }
      // Like the other effects, one that found nothing to move on its
      // first tick leaves the entity alone.
      final p = entity.getComponent<TransformComponent>()!.position;
      expect([p.x, p.y], [5, 5]);
      expect(player.isEmpty, isTrue);
    });
  });
}

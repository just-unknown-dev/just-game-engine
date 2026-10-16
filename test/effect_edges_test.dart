// Deterministic effects at their edges: callbacks that cancel, looping
// effects fast-forwarded, fades along easings that overshoot, absolute
// paths, mirrored scales, and rollback done twice.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// Counts the ticks it is applied for.
class _Recorder extends DeterministicEffect {
  _Recorder({required super.durationTicks, super.loop});

  int applied = 0;

  @override
  void applyTick(EffectContext ctx, int prevElapsed, int currElapsed) {
    applied += currElapsed - prevElapsed;
  }

  @override
  String get effectType => 'rec';

  @override
  Map<String, dynamic> toJson() => {};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late World world;
  late Entity entity;
  setUp(() {
    world = World()..initialize();
    addTearDown(world.dispose);
    entity = world.createEntityWithComponents([
      TransformComponent(position: Vector3.fromXY(100, 100)),
      RenderableComponent(
        renderable: CircleRenderable(radius: 1, fillColor: Colors.red),
      ),
    ]);
  });
  EffectContext at(int t) => EffectContext(entity: entity, currentTick: t);

  test('an onComplete that cancels another effect loses none', () {
    final player = EffectPlayer();
    var bFired = 0, cFired = 0;
    final a = player.add(DelayEffect(durationTicks: 100), 0);
    player
      ..add(
        DelayEffect(
          durationTicks: 2,
          onComplete: () {
            bFired++;
            player.cancel(a);
          },
        ),
        0,
      )
      ..add(DelayEffect(durationTicks: 5, onComplete: () => cFired++), 0);
    for (var t = 1; t <= 10; t++) {
      player.advanceTo(t, at(t));
    }
    expect(bFired, 1);
    expect(cFired, 1);
    expect(a.isCancelled, isTrue);
    expect(player.isEmpty, isTrue);
  });

  test('cancelAll from a callback is safe', () {
    final player = EffectPlayer()
      ..add(DelayEffect(durationTicks: 100), 0)
      ..add(DelayEffect(durationTicks: 1), 0);
    player.add(
      DelayEffect(durationTicks: 1, onComplete: () => player.cancelAll()),
      0,
    );
    player.advanceTo(1, at(1));
    expect(player.activeCount, 0);
    player.advanceTo(2, at(2));
    expect(player.isEmpty, isTrue);
  });

  test('a looping effect fast-forwarded lands where stepping does', () {
    final stepped = _Recorder(durationTicks: 10, loop: true);
    final steppedPlayer = EffectPlayer()..add(stepped, 0);
    for (var t = 1; t <= 26; t++) {
      steppedPlayer.advanceTo(t, at(t));
    }
    final jumped = _Recorder(durationTicks: 10, loop: true);
    EffectPlayer()
      ..add(jumped, 0)
      ..advanceTo(25, at(25))
      ..advanceTo(26, at(26));
    expect(jumped.applied, stepped.applied);
  });

  test('a fade along an overshooting easing ends on its target', () {
    final renderable = entity.getComponent<RenderableComponent>()!.renderable
      ..opacity = 0;
    final fade = FadeEffect(
      to: 1,
      durationTicks: 60,
      easing: EasingType.easeOutElastic,
    );
    for (var t = 0; t < 60; t++) {
      fade.applyTick(at(t + 1), t, t + 1);
    }
    expect(renderable.opacity, closeTo(1, 1e-9));
  });

  test('an absolute path reaches its waypoints', () {
    PathEffect(
      waypoints: const [Offset(0, 0), Offset(50, 0)],
      relativeToStart: false,
      durationTicks: 10,
    ).applyTick(at(10), 0, 10);
    final p = entity.getComponent<TransformComponent>()!.position;
    expect([p.x, p.y], [50, 0]);
  });

  test('a mirrored entity stays mirrored when scaled', () {
    final t = entity.getComponent<TransformComponent>()!
      ..scale = Vector3(-1, 1, 1);
    ScaleEffect(to: 2, durationTicks: 4).applyTick(at(4), 0, 4);
    expect([t.scale.x, t.scale.y, t.scale.z], [-2, 2, 2]);
  });

  test('two rollbacks leave one copy of an effect', () {
    final runtime = PredictionEffectRuntime();
    final effect = _Recorder(durationTicks: 5);
    runtime
      ..scheduleEffect(entity: entity, effect: effect, startTick: 10)
      ..rollbackTo(5, world)
      ..rollbackTo(5, world);
    final player = entity.getComponent<EffectComponent>()!.player;
    expect(player.activeCount, 1);
    for (var t = 6; t <= 20; t++) {
      player.advanceTo(t, at(t));
    }
    expect(effect.applied, 5);
  });
}

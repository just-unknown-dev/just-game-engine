// A model's animator plays on its player through runtime state: a scene
// saved while it runs — at an editor's tick of 0 or a game's — holds the
// player's clip, speed, looping and playing as they were authored.
@Tags(['graphics3d'])
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/graphics_3d.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_graphics_engine/testing.dart';

import 'fixtures.dart';

const _barPath = 'assets/models/bar.glb';

/// Starts mid-hop, once, at its own speed — the way a character whose
/// "grounded" reads false before anything has moved it starts mid-jump.
const _graph = AnimatorGraph(
  entry: 'hopping',
  parameters: [
    AnimatorParameter(name: 'landed', type: AnimatorParameterType.trigger),
  ],
  states: [
    AnimatorState(name: 'hopping', clip: 'hop', speed: 1, loop: false),
    AnimatorState(name: 'growing', clip: 'grow', speed: 2),
  ],
  transitions: [
    AnimatorTransition(
      from: 'hopping',
      to: 'growing',
      duration: 0.2,
      conditions: [AnimatorCondition(parameter: 'landed')],
    ),
  ],
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

  test('a model saved while its animator runs is as authored', () async {
    final player = AnimationPlayerComponent(
      clip: 'bend',
      speed: 0.75,
      crossfade: 0.3,
    );
    final animator = AnimatorComponent(graphPath: 'bar.animator.json');
    final bar = engine.world.createEntityWithComponents([
      TransformComponent(),
      ModelComponent(model: _barPath),
      player,
      animator,
    ]);
    String saved() => jsonEncode(engine.context.definitions.encode(player)!);
    final authored = saved();

    // As an editor ticks while the scene is edited.
    engine.world.update(0);
    await Future<void>.delayed(Duration.zero);
    engine.world.update(0);
    engine.world.update(0);
    expect(animator.currentState, 'hopping', reason: 'the graph runs');
    expect(
      (player.playingClip, player.playingSpeed, player.playingLoop),
      ('hop', 1.0, false),
      reason: 'and the model plays what it chose',
    );
    expect(saved(), authored, reason: 'at dt 0');

    // As a game runs, through a crossfading transition.
    for (var i = 0; i < 5; i++) {
      engine.world.update(0.1);
    }
    animator.setTrigger('landed');
    for (var i = 0; i < 5; i++) {
      engine.world.update(0.1);
    }
    expect(animator.currentState, 'growing');
    expect((player.playingClip, player.playingSpeed), ('grow', 2.0));
    expect(saved(), authored, reason: 'at dt > 0');
    expect(
      (player.clip, player.speed, player.loop, player.playing),
      ('bend', 0.75, true, true),
    );

    // The animator gone, the model plays what was authored again.
    bar.removeComponent<AnimatorComponent>();
    engine.world.update(0.1);
    expect(player.isDriven, isFalse);
    expect(
      (player.playingClip, player.playingSpeed, player.playingLoop),
      ('bend', 0.75, true),
    );
    expect(player.time, 0, reason: 'from its start');
    engine.world.update(0.1);
    expect(player.time, closeTo(0.075, 1e-9), reason: 'at its authored speed');
  });
}

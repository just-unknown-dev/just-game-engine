// A system that throws does not freeze the frame's other work, and a
// plugin that throws on detach does not keep the engine alive; every
// feature's definitions are installed.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// Throws from every update while [throws].
class _Throwing extends System {
  bool throws = true;
  int updates = 0;
  @override
  List<Type> get requiredComponents => const [];
  @override
  void update(double deltaTime) {
    updates++;
    if (throws) throw StateError('broken system');
  }
}

class _BadPlugin extends EnginePlugin {
  @override
  String get id => 'bad';
  @override
  void detach() => throw StateError('bad plugin');
}

class _GoodPlugin extends EnginePlugin {
  int detached = 0;
  @override
  String get id => 'good';
  @override
  void detach() => detached++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GameLoop with a step that throws', () {
    late TimeManager time;
    late List<String> calls;
    late bool throws;
    late GameLoop loop;
    setUp(() {
      time = TimeManager();
      calls = [];
      throws = true;
      loop = GameLoop(
        timeManager: time,
        onUpdate: (_) {
          calls.add('update');
          if (throws) throw StateError('step');
        },
        onFrame: (_, _) => calls.add('frame'),
        onRender: () => calls.add('render'),
      )..start();
    });

    test('still runs the frame phase and the real-time callback', () {
      loop.tick(Duration.zero);
      calls.clear();
      expect(
        () => loop.tick(const Duration(milliseconds: 50)),
        throwsStateError,
      );
      expect(calls, ['update', 'frame', 'render']);
    });

    test('drops the frame\'s other steps instead of bursting later', () {
      loop.tick(Duration.zero);
      var at = 0;
      for (var i = 0; i < 5; i++) {
        at += 50; // three steps' worth each frame
        expect(() => loop.tick(Duration(milliseconds: at)), throwsStateError);
      }
      throws = false;
      calls.clear();
      loop.tick(Duration(milliseconds: at + 17));
      expect(
        calls.where((c) => c == 'update'),
        hasLength(1),
        reason: 'one frame, one step: no catch-up burst',
      );
    });
  });

  testWidgets('a throwing system does not stop the view repainting', (
    tester,
  ) async {
    final engine = Engine();
    await tester.runAsync(engine.initialize);
    final broken = _Throwing();
    engine.world.addSystem(broken);
    var frames = 0;
    engine.layers.register(_CountingLayer(() => frames++));
    engine.start();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: GameWidget(engine: engine),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      // The error reaches the framework; take it and go on.
      tester.takeException();
    }
    expect(broken.updates, greaterThan(1));
    expect(frames, greaterThan(1), reason: 'the layers kept ticking');
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(engine.dispose);
  });

  test(
    'a plugin that throws on detach does not keep the engine alive',
    () async {
      final engine = Engine();
      await engine.initialize();
      final good = _GoodPlugin();
      await engine.plugins.register(_BadPlugin());
      await engine.plugins.register(good);
      final world = engine.world;
      final entity = world.createEntity();
      await engine.dispose();
      expect(engine.state, EngineState.disposed);
      expect(good.detached, 1, reason: 'the other plugins still detach');
      expect(entity.isAlive, isFalse, reason: 'the world was disposed');
    },
  );

  test("BuiltInComponents.all holds every feature's definitions", () {
    final types = {for (final c in BuiltInComponents.all) c.type};
    for (final feature in <List<ComponentCodec>>[
      Shape2DDefinitions.all,
      PhysicsDefinitions.all,
      GameplayDefinitions.all,
      SpriteDefinitions.all,
      Physics2DDefinitions.all,
      CameraDefinitions.all,
      TimelineDefinitions.all,
      LevelMapDefinitions.all,
      InputDefinitions.all,
      EffectDefinitions.all,
      RenderingDefinitions.all,
      Material2DDefinitions.all,
      Lighting2DDefinitions.all,
      AnimationDefinitions.all,
      AudioDefinitions.all,
    ]) {
      for (final codec in feature) {
        expect(types, contains(codec.type));
      }
    }
    expect(types, hasLength(BuiltInComponents.all.length), reason: 'each once');
  });
}

/// A layer whose controller counts its frames.
class _CountingLayer extends GameLayer {
  _CountingLayer(this.onFrame);
  final VoidCallback onFrame;
  @override
  String get id => 'counting';
  @override
  GameLayerController createController(Engine engine) =>
      _CountingController(onFrame);
}

class _CountingController extends GameLayerController {
  _CountingController(this.tick);
  final VoidCallback tick;
  @override
  void onFrame() => tick();
  @override
  Widget build(BuildContext context) => const SizedBox();
}

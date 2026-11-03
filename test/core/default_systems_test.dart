// The engine's standard systems: none unless asked for, each at most once.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Engine> engineWith(Set<DefaultSystem> systems) async {
    final engine = Engine(config: EngineConfig(defaultSystems: systems));
    addTearDown(engine.dispose);
    await engine.initialize();
    return engine;
  }

  test('by default the world starts with no systems', () async {
    final engine = await engineWith(const {});
    expect(engine.world.systems, isEmpty);
  });

  test(
    'DefaultSystems.all: what a game runs, drawing through the camera',
    () async {
      final engine = await engineWith(DefaultSystems.all);
      final world = engine.world;
      for (final has in [
        world.hasSystem<InputSystem>,
        world.hasSystem<PhysicsSystem>,
        world.hasSystem<MovementSystem>,
        world.hasSystem<AudioSystem>,
        world.hasSystem<RenderSystem>,
        world.hasSystem<SpriteLoadSystem>,
        world.hasSystem<AnimatorSystem>,
        world.hasSystem<TimelineSystem>,
        world.hasSystem<LevelMapSystem>,
        world.hasSystem<MapCollisionSystem>,
        world.hasSystem<CameraBrainSystem>,
        world.hasSystem<CameraTriggerSystem>,
      ]) {
        expect(has(), isTrue);
      }
      final camera = engine.cameraSystem.mainCamera;
      expect(world.getSystem<RenderSystem>()!.camera, same(camera));
      expect(world.getSystem<PhysicsSystem>()!.camera, same(camera));
      expect(world.getSystem<PhysicsSystem>()!.physics, same(engine.physics));
      expect(world.getSystem<InputSystem>()!.input, same(engine.input));
    },
  );

  test('headless leaves out what draws and plays', () async {
    final engine = await engineWith(DefaultSystems.headless);
    expect(engine.world.hasSystem<RenderSystem>(), isFalse);
    expect(engine.world.hasSystem<AudioSystem>(), isFalse);
    expect(engine.world.hasSystem<PhysicsSystem>(), isTrue);
  });

  test("each at most once; a game's own instance is kept", () async {
    final engine = await engineWith(const {});
    final mine = RenderSystem(batchShapes: true);
    engine.world.addSystem(mine);
    registerDefaultSystems(engine.world, engine);
    final count = engine.world.systems.length;
    registerDefaultSystems(engine.world, engine);
    expect(engine.world.systems, hasLength(count), reason: 'nothing twice');
    expect(engine.world.getSystem<RenderSystem>(), same(mine));
    expect(engine.world.systems.whereType<RenderSystem>(), hasLength(1));
  });

  test('only what was asked for', () async {
    final engine = await engineWith(const {
      DefaultSystem.levelMaps,
      DefaultSystem.sprites,
    });
    expect(engine.world.hasSystem<LevelMapSystem>(), isTrue);
    expect(engine.world.hasSystem<MapCollisionSystem>(), isFalse);
    expect(engine.world.hasSystem<SpriteLoadSystem>(), isTrue);
    expect(engine.world.hasSystem<InputSystem>(), isFalse);
  });
}

// Tile collision on the real (pure-Dart) physics: a character lands on
// tiles and is grounded, passes up through one-way tiles, stands on a
// slope, and falls when the tile under it goes.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

const _slope = 2;

late PhysicsEngine _physics;

TilesetData _tileset() =>
    TilesetData(
        name: 't',
        image: '',
        tileWidth: 16,
        tileHeight: 16,
        columns: 4,
        tileCount: 4,
      )
      ..tileOrNew(0).collision = TileCollision.full(16, 16)
      ..tileOrNew(1).collision = TileCollision.full(16, 16, kind: 'oneWay')
      ..tileOrNew(_slope).collision = TileCollision(
        shapes: [
          const TilePolygonShape([
            Offset(0, 16),
            Offset(16, 0),
            Offset(16, 16),
          ]),
        ],
      );

/// A world with physics and the tile systems, and a map whose `Ground`
/// layer collides.
(World, Entity, MapLayerData) _world() {
  TileAssets.putTileset('test/t.tileset.json', _tileset());
  _physics = PhysicsEngine.pureDart()..initialize();
  final world = World()..initialize();
  addTearDown(() {
    world.dispose();
    _physics.dispose();
  });
  world.addSystem(PhysicsSystem(_physics));
  registerLevelMapSystems(world);
  final map = LevelMapData(tileWidth: 16, tileHeight: 16);
  map.addTileset('test/t.tileset.json');
  final ground = map.addLayer(name: 'Ground')..collides = true;
  final entity = world.createEntityWithComponents([
    TransformComponent(),
    LevelMapComponent(inline: map),
  ], name: 'Map');
  return (world, entity, ground);
}

Entity _body(World world, Offset at, {Vector3? velocity}) {
  final e = world.createEntityWithComponents([
    TransformComponent(position: Vector3(at.dx, at.dy, 0)),
    PhysicsBodyComponent(
      shape: RectangleShape(12, 12),
      restitution: 0,
      fixedRotation: true,
    ),
    VelocityComponent(velocity: velocity ?? Vector3.zero()),
  ]);
  return e;
}

void _run(World world, {int frames = 90}) {
  for (var i = 0; i < frames; i++) {
    world.update(1 / 60);
  }
}

void main() {
  setUp(TileAssets.clear);

  test('a body lands on solid tiles and is grounded on flat ground', () {
    final (world, _, ground) = _world();
    for (var x = 0; x < 8; x++) {
      ground.cells.setCell(x, 4, TileCell.make(0, 0));
    }
    final body = _body(world, const Offset(40, 20));

    _run(world);

    final comp = body.getComponent<PhysicsBodyComponent>()!;
    expect(comp.isGrounded, isTrue);
    expect(comp.groundNormal.dy, closeTo(-1, 0.01));
    final y = body.getComponent<TransformComponent>()!.position.y;
    expect(y, closeTo(64 - 6, 1.5), reason: 'resting on the top of row 4');
  });

  test('the bodies are generated: one merged box, marked, and not bouncy', () {
    final (world, map, ground) = _world();
    for (var x = 0; x < 8; x++) {
      ground.cells.setCell(x, 4, TileCell.make(0, 0));
      ground.cells.setCell(x, 5, TileCell.make(0, 0));
    }
    _run(world, frames: 1);

    final bodies = world.query([MapBodyComponent]).toList();
    expect(bodies, hasLength(1));
    final b = bodies.single;
    expect(b.hasComponent<GeneratedEntityComponent>(), isTrue);
    expect(b.getComponent<MapBodyComponent>()!.mapEntityId, map.id);
    expect(b.getComponent<MapBodyComponent>()!.cells, hasLength(16));
    final body = b.getComponent<PhysicsBodyComponent>()!;
    expect(body.restitution, 0);
    expect(body.showDebugOutline, isFalse);
    expect(body.isStatic, isTrue);
  });

  test('a layer that does not collide builds nothing', () {
    final (world, _, ground) = _world();
    ground.collides = false;
    ground.cells.setCell(0, 0, TileCell.make(0, 0));
    _run(world, frames: 2);
    expect(world.query([MapBodyComponent]), isEmpty);
  });

  test('one-way tiles are passed up through and landed on', () {
    final (world, _, ground) = _world();
    for (var x = 0; x < 8; x++) {
      ground.cells.setCell(x, 4, TileCell.make(0, 1));
    }
    // Below the platform, moving up fast.
    final body = _body(
      world,
      const Offset(40, 100),
      velocity: Vector3(0, -700, 0),
    );
    _run(world, frames: 120);

    final comp = body.getComponent<PhysicsBodyComponent>()!;
    expect(comp.isGrounded, isTrue);
    expect(body.getComponent<TransformComponent>()!.position.y, lessThan(64));
  });

  test('a body resting on a slope is grounded with a tilted normal', () {
    final (world, _, ground) = _world();
    for (var x = 0; x < 6; x++) {
      ground.cells.setCell(x, 4, TileCell.make(0, _slope));
      ground.cells.setCell(x, 5, TileCell.make(0, 0));
    }
    final body = _body(world, const Offset(40, 30));
    _run(world, frames: 30);

    final comp = body.getComponent<PhysicsBodyComponent>()!;
    expect(comp.isGrounded, isTrue);
    expect(comp.groundNormal.dx.abs(), greaterThan(0.3), reason: 'a 45° slope');
    expect(comp.groundNormal.dy, lessThan(-0.3));
  });

  test('taking a tile away at runtime rebuilds the collision', () {
    final (world, map, ground) = _world();
    for (var x = 0; x < 8; x++) {
      ground.cells.setCell(x, 4, TileCell.make(0, 0));
    }
    final body = _body(world, const Offset(40, 20));
    _run(world);
    expect(body.getComponent<PhysicsBodyComponent>()!.isGrounded, isTrue);

    final handle = LevelMaps.of(world, map)!;
    final changed = <TileChangedEvent>[];
    world.events.on<TileChangedEvent>(changed.add);
    handle.setTiles(ground, {
      for (var x = 0; x < 8; x++) TileCoord(x, 4): TileCell.empty,
    });
    _run(world, frames: 30);

    expect(changed.single.cells, hasLength(8));
    expect(
      body.getComponent<TransformComponent>()!.position.y,
      greaterThan(80),
    );
    expect(world.query([MapBodyComponent]), isEmpty);
    // The scene's map is untouched: the change is the game's own.
    expect(ground.cells.cellAt(0, 4), TileCell.make(0, 0));
  });

  test('clearing removes every generated body; the next frame rebuilds', () {
    final (world, _, ground) = _world();
    ground.cells.setCell(0, 0, TileCell.make(0, 0));
    _run(world, frames: 1);
    final system = world.systems.whereType<MapCollisionSystem>().single;
    expect(system.bodyCount, 1);

    system.clearGenerated();
    expect(world.query([MapBodyComponent]), isEmpty);
    system.isActive = false;
    _run(world, frames: 2);
    expect(world.query([MapBodyComponent]), isEmpty, reason: 'inactive');

    system.isActive = true;
    _run(world, frames: 1);
    expect(system.bodyCount, 1);
  });

  test('a registered kind decorates its bodies', () {
    MapCollisionKinds.register(
      MapCollisionKind(
        id: 'test.lava',
        label: 'Lava',
        sensor: true,
        decorate: (body, spec, properties) => body.addComponent(
          TagComponent('lava:${properties.getInt('heat')}'),
        ),
      ),
    );
    addTearDown(MapCollisionKinds.reset);
    final ts = _tileset()
      ..tileOrNew(3).collision = TileCollision.full(16, 16, kind: 'test.lava');
    ts.tile(3)!.properties.set('heat', 9, TilePropertyType.int);
    final (world, _, ground) = _world();
    TileAssets.putTileset('test/t.tileset.json', ts);
    ground.cells.setCell(0, 0, TileCell.make(0, 3));
    _run(world, frames: 2);

    final lava = world.query([MapBodyComponent]).single;
    expect(
      lava.getComponent<TagComponent>()?.tag,
      'lava:9',
      reason: 'the property of the tile it was built from',
    );
    expect(lava.getComponent<PhysicsBodyComponent>()!.isSensor, isTrue);
  });
}

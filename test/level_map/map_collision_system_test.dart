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
  final world = World()..initialize();
  world.context.tiles.putTileset('test/t.tileset.json', _tileset());
  _physics = PhysicsEngine.pureDart()..initialize();
  addTearDown(() {
    world.dispose();
    _physics.dispose();
  });
  world.addSystem(Physics2DSystem(_physics));
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
    RigidBody2DComponent(restitution: 0, lockRotation: true),
    Collider2DComponent(size: Vector2(12, 12)),
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
  test('a body lands on solid tiles and is grounded on flat ground', () {
    final (world, _, ground) = _world();
    for (var x = 0; x < 8; x++) {
      ground.cells.setCell(x, 4, TileCell.make(0, 0));
    }
    final body = _body(world, const Offset(40, 20));

    _run(world);

    final comp = body.getComponent<RigidBody2DComponent>()!;
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
    final body = b.getComponent<RigidBody2DComponent>()!;
    expect(body.restitution, 0);
    expect(b.getComponent<Collider2DComponent>()!.showDebugOutline, isFalse);
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

    final comp = body.getComponent<RigidBody2DComponent>()!;
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

    final comp = body.getComponent<RigidBody2DComponent>()!;
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
    expect(body.getComponent<RigidBody2DComponent>()!.isGrounded, isTrue);

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
    final (world, _, ground) = _world();
    world.context.collisionKinds.register(
      MapCollisionKind(
        id: 'test.lava',
        label: 'Lava',
        sensor: true,
        decorate: (body, spec, properties) => body.addComponent(
          TagComponent('lava:${properties.getInt('heat')}'),
        ),
      ),
    );
    final ts = _tileset()
      ..tileOrNew(3).collision = TileCollision.full(16, 16, kind: 'test.lava');
    ts.tile(3)!.properties.set('heat', 9, TilePropertyType.int);
    world.context.tiles.putTileset('test/t.tileset.json', ts);
    ground.cells.setCell(0, 0, TileCell.make(0, 3));
    _run(world, frames: 2);

    final lava = world.query([MapBodyComponent]).single;
    expect(
      lava.getComponent<TagComponent>()?.tags.single,
      'lava:9',
      reason: 'the property of the tile it was built from',
    );
    expect(lava.getComponent<RigidBody2DComponent>()!.isSensor, isTrue);
  });

  group('a change of cells', () {
    /// Ids of the bodies by the cells they cover, as `x,y` lists.
    Map<String, int> byCells(World world) => {
      for (final e in world.query([MapBodyComponent]))
        e
                .getComponent<MapBodyComponent>()!
                .cells
                .map((c) => '${c.x},${c.y}')
                .join(' '):
            e.id,
    };

    test('keeps every body it does not touch, and makes only what differs', () {
      final (world, map, ground) = _world();
      for (var x = 0; x < 4; x++) {
        ground.cells.setCell(x, 4, TileCell.make(0, 0));
        ground.cells.setCell(x + 6, 4, TileCell.make(0, 0));
        ground.cells.setCell(x, 8, TileCell.make(0, 0));
      }
      _run(world, frames: 1);
      final before = byCells(world);
      expect(before, hasLength(3));

      LevelMaps.of(
        world,
        map,
      )!.setTile(ground, const TileCoord(7, 4), TileCell.empty);
      _run(world, frames: 1);
      final after = byCells(world);
      expect(after, hasLength(4));
      // The two platforms not touched are the same bodies.
      expect(after['0,4 1,4 2,4 3,4'], before['0,4 1,4 2,4 3,4']);
      expect(after['0,8 1,8 2,8 3,8'], before['0,8 1,8 2,8 3,8']);
      // The broken one is two new ones.
      expect(after.containsKey('6,4 7,4 8,4 9,4'), isFalse);
      expect(after['6,4'], isNot(before['6,4 7,4 8,4 9,4']));
      expect(after.containsKey('8,4 9,4'), isTrue);
      // Putting it back makes one again.
      LevelMaps.of(
        world,
        map,
      )!.setTile(ground, const TileCoord(7, 4), TileCell.make(0, 0));
      _run(world, frames: 1);
      expect(byCells(world), hasLength(3));
      expect(byCells(world)['0,4 1,4 2,4 3,4'], before['0,4 1,4 2,4 3,4']);
    });

    test('leaves a body standing on another platform in contact', () {
      final (world, map, ground) = _world();
      for (var x = 0; x < 8; x++) {
        ground.cells.setCell(x, 4, TileCell.make(0, 0));
      }
      ground.cells.setCell(20, 4, TileCell.make(0, 0));
      final body = _body(world, const Offset(40, 20));
      _run(world);
      expect(body.getComponent<RigidBody2DComponent>()!.isGrounded, isTrue);

      final exits = <CollisionExit2DEvent>[];
      world.events.on<CollisionExit2DEvent>(exits.add);
      final handle = LevelMaps.of(world, map)!;
      handle.setTile(ground, const TileCoord(20, 4), TileCell.empty);
      _run(world, frames: 2);
      expect(exits, isEmpty);
      expect(body.getComponent<RigidBody2DComponent>()!.isGrounded, isTrue);
    });

    test('rebuilds a body whose tile changed for one of the same shape '
        'but other properties', () {
      final (world, _, ground) = _world();
      world.context.collisionKinds.register(
        MapCollisionKind(
          id: 'test.heat',
          label: 'Heat',
          decorate: (body, spec, properties) => body.addComponent(
            TagComponent('heat:${properties.getInt('heat')}'),
          ),
        ),
      );
      final ts = _tileset()
        ..tileOrNew(3).collision = TileCollision.full(16, 16, kind: 'test.heat')
        ..tileOrNew(4).collision = TileCollision.full(
          16,
          16,
          kind: 'test.heat',
        );
      ts.tile(3)!.properties.set('heat', 1, TilePropertyType.int);
      ts.tile(4)!.properties.set('heat', 2, TilePropertyType.int);
      world.context.tiles.putTileset('test/t.tileset.json', ts);
      ground.cells.setCell(0, 0, TileCell.make(0, 3));
      _run(world, frames: 2);
      expect(
        world
            .query([MapBodyComponent])
            .single
            .getComponent<TagComponent>()
            ?.tags,
        {'heat:1'},
      );

      final map = world.query([LevelMapComponent]).single;
      LevelMaps.of(
        world,
        map,
      )!.setTile(ground, const TileCoord(0, 0), TileCell.make(0, 4));
      _run(world, frames: 1);
      expect(
        world
            .query([MapBodyComponent])
            .single
            .getComponent<TagComponent>()
            ?.tags,
        {'heat:2'},
      );
    });
  });

  test('a map that moves takes the same bodies with it', () {
    final (world, map, ground) = _world();
    for (var x = 0; x < 4; x++) {
      ground.cells.setCell(x, 4, TileCell.make(0, 0));
      ground.cells.setCell(x, 8, TileCell.make(0, 1));
    }
    _run(world, frames: 1);
    final before = {
      for (final e in world.query([MapBodyComponent]))
        e.id: Vector3.copy(e.getComponent<TransformComponent>()!.position),
    };
    expect(before, hasLength(2));

    map.getComponent<TransformComponent>()!.setPositionXY(100, -50);
    _run(world, frames: 1);
    final after = world.query([MapBodyComponent]).toList();
    expect({for (final e in after) e.id}, before.keys.toSet());
    for (final e in after) {
      final p = e.getComponent<TransformComponent>()!.position;
      expect(p.x, closeTo(before[e.id]!.x + 100, 1e-9));
      expect(p.y, closeTo(before[e.id]!.y - 50, 1e-9));
    }
    // And the physics bodies went too.
    final body = _body(world, const Offset(130, -30));
    _run(world);
    expect(body.getComponent<RigidBody2DComponent>()!.isGrounded, isTrue);
    expect(
      body.getComponent<TransformComponent>()!.position.y,
      closeTo(64 - 50 - 6, 1.5),
    );
  });

  test('removing the system destroys its bodies; one added again builds '
      'a single set', () {
    final (world, _, ground) = _world();
    for (var x = 0; x < 4; x++) {
      ground.cells.setCell(x, 4, TileCell.make(0, 0));
      ground.cells.setCell(x, 8, TileCell.make(0, 1));
    }
    _run(world, frames: 1);
    expect(world.query([MapBodyComponent]), hasLength(2));

    world.removeSystem(world.systems.whereType<MapCollisionSystem>().single);
    expect(world.query([MapBodyComponent]), isEmpty);

    world.addSystem(MapCollisionSystem());
    _run(world, frames: 1);
    expect(world.query([MapBodyComponent]), hasLength(2));

    // Every system replaced, the entities kept: still one set.
    world.clearSystems();
    expect(world.query([MapBodyComponent]), isEmpty);
    world.addSystem(Physics2DSystem(_physics));
    registerLevelMapSystems(world);
    _run(world, frames: 1);
    expect(world.query([MapBodyComponent]), hasLength(2));
  });
}

// Physics2DSystem's contact events and ground, on both backends: stays come
// once per step that ran — none on an update that ran no step, none for a
// pair that parted in it — and a body's ground is looked at again from
// where it is, so one that first touched a crate from the side and then
// stands on it is grounded — while one running down a ramp of tiles keeps
// the slope's normal where two tiles meet, and stays on the ground.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

final _backends = <String, PhysicsEngine Function()>{
  'native': PhysicsEngine.new,
  'pure Dart': PhysicsEngine.pureDart,
};

({World world, PhysicsEngine physics, Physics2DSystem system}) _setUp(
  PhysicsEngine engine,
) {
  final physics = engine..initialize();
  physics.setGravity(0, 981);
  final world = World()..initialize();
  final system = Physics2DSystem(physics, reportContactStay: true);
  world.addSystem(system);
  addTearDown(() {
    world.dispose();
    physics.dispose();
  });
  return (world: world, physics: physics, system: system);
}

/// A slab whose top is at y = 280.
Entity _ground(World world) => world.createEntityWithComponents([
  TransformComponent(position: Vector3(0, 300, 0)),
  Collider2DComponent(size: Vector2(2000, 40)),
], name: 'Ground');

Entity _crate(World world, {double x = 0, double y = 270}) =>
    world.createEntityWithComponents([
      TransformComponent(position: Vector3(x, y, 0)),
      RigidBody2DComponent(restitution: 0, lockRotation: true, canSleep: false),
      Collider2DComponent(size: Vector2(20, 20)),
    ], name: 'Crate');

/// Runs a body along the ground each frame, as a platformer's controller
/// does: on a slope, along it at [speed] and pressed into it with gravity
/// off; elsewhere, sideways at [speed] with gravity on.
final class _SlopeRunner extends System {
  _SlopeRunner(this.speed);

  double speed;

  @override
  int get priority => SystemPriorities.physics + 5;

  @override
  List<Type> get requiredComponents => const [
    RigidBody2DComponent,
    VelocityComponent,
  ];

  @override
  void update(double deltaTime) {
    forEach((entity) {
      final rigid = entity.getComponent<RigidBody2DComponent>()!;
      final velocity = entity.getComponent<VelocityComponent>()!;
      final n = rigid.groundNormal;
      if (rigid.isGrounded && n.dx.abs() > 0.02 && n.dy < 0) {
        // Along the ground, pressed into it.
        velocity.setVelocityXY(
          -n.dy * speed - n.dx * 120,
          n.dx * speed - n.dy * 120,
        );
        rigid.gravityScale = 0;
      } else {
        velocity.setVelocityXY(speed, velocity.velocity.y);
        rigid.gravityScale = 1;
      }
    });
  }
}

/// A ramp of 45° tiles rising to the right over tiles 5–9 of a level map,
/// flat ground either side — each tile its own body, so a body running
/// down it crosses a seam at every tile.
Entity _ramp(World world) {
  const solid = 0, up = 1;
  final ts = TilesetData(
    name: 's',
    tileWidth: 32,
    tileHeight: 32,
    columns: 2,
    tileCount: 2,
  );
  ts.tileOrNew(solid).collision = TileCollision.full(32, 32);
  ts.tileOrNew(up).collision = TileCollision(
    shapes: [
      const TilePolygonShape([Offset(0, 32), Offset(32, 0), Offset(32, 32)]),
    ],
  );
  world.context.tiles.putTileset('s.tileset.json', ts);
  registerLevelMapSystems(world);
  final data = LevelMapData(tileWidth: 32, tileHeight: 32)
    ..addTileset('s.tileset.json');
  final ground = data.addLayer(name: 'Ground')..collides = true;
  for (var x = 0; x < 20; x++) {
    ground.cells.setCell(x, 12, TileCell.make(0, solid));
  }
  for (var i = 0; i < 5; i++) {
    final x = 5 + i, top = 11 - i;
    ground.cells.setCell(x, top, TileCell.make(0, up));
    for (var y = top + 1; y < 12; y++) {
      ground.cells.setCell(x, y, TileCell.make(0, solid));
    }
  }
  for (var x = 10; x < 20; x++) {
    for (var y = 7; y < 12; y++) {
      ground.cells.setCell(x, y, TileCell.make(0, solid));
    }
  }
  return world.createEntityWithComponents([
    TransformComponent(),
    LevelMapComponent(inline: data),
  ]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final MapEntry(key: name, value: make) in _backends.entries) {
    group('on $name', () {
      test('two overlapping circles touch once and are pushed apart', () {
        final (:world, :physics, :system) = _setUp(make());
        physics.setGravity(0, 0);
        Entity ball(double x) => world.createEntityWithComponents([
          TransformComponent(position: Vector3(x, 0, 0)),
          RigidBody2DComponent(restitution: 0),
          Collider2DComponent(shape: Collider2DShape.circle, radius: 10),
        ]);
        final a = ball(0), b = ball(15);
        final enters = <CollisionEnter2DEvent>[];
        world.events.on<CollisionEnter2DEvent>(enters.add);
        for (var i = 0; i < 10; i++) {
          world.update(1 / 60);
        }
        expect(enters, hasLength(1));
        expect({enters.single.entityA, enters.single.entityB}, {a, b});
        final apart =
            b.getComponent<TransformComponent>()!.position.x -
            a.getComponent<TransformComponent>()!.position.x;
        expect(apart, greaterThan(15), reason: 'pushed apart');
      });

      test('a resting pair gets one stay per step, none without a step', () {
        final (:world, :physics, :system) = _setUp(make());
        _ground(world);
        _crate(world);
        for (var i = 0; i < 60; i++) {
          world.update(1 / 60);
        }
        var stays = 0;
        world.events.on<CollisionStay2DEvent>((_) => stays++);

        // Half-length updates: a step every other one.
        for (var i = 0; i < 60; i++) {
          world.update(1 / 120);
        }
        expect(stays, inInclusiveRange(29, 31));

        // Time stopped: nothing is simulated, nothing stays.
        stays = 0;
        for (var i = 0; i < 10; i++) {
          world.update(0);
        }
        expect(stays, 0);
      });

      test('a pair that parts in a step sends its exit, and no stay', () {
        final (:world, :physics, :system) = _setUp(make());
        _ground(world);
        final crate = _crate(world);
        for (var i = 0; i < 60; i++) {
          world.update(1 / 60);
        }
        final log = <String>[];
        world.events
          ..on<CollisionStay2DEvent>((_) => log.add('stay'))
          ..on<CollisionExit2DEvent>((_) => log.add('exit'));
        crate.getComponent<RigidBody2DComponent>()!.setVelocity(
          const Offset(0, -2000),
        );
        for (var i = 0; i < 10 && !log.contains('exit'); i++) {
          log.clear();
          world.update(1 / 60);
        }
        expect(log, ['exit'], reason: 'the update it parts in');
      });

      test('a body that touched a crate from the side and then stands on it '
          'is grounded', () {
        final (:world, :physics, :system) = _setUp(make());
        // A crate fixed in the air, 40 wide, its top at y = -20.
        final crate = world.createEntityWithComponents([
          TransformComponent(),
          Collider2DComponent(size: Vector2(40, 40)),
        ], name: 'Crate');
        final rigid = RigidBody2DComponent(
          restitution: 0,
          friction: 0,
          lockRotation: true,
          canSleep: false,
        );
        final player = world.createEntityWithComponents([
          TransformComponent(position: Vector3(29.5, 0, 0)),
          rigid,
          Collider2DComponent(size: Vector2(20, 20)),
        ], name: 'Player');
        world.update(1 / 60);
        expect(rigid.isGrounded, isFalse, reason: 'touching its side');

        // Onto its top, still touching: no new begin is reported.
        player.getComponent<TransformComponent>()!.position.setValues(
          10,
          -29.8,
          0,
        );
        rigid.setVelocity(Offset.zero);
        for (var i = 0; i < 10; i++) {
          world.update(1 / 60);
        }
        expect(rigid.isGrounded, isTrue);
        expect(rigid.groundEntity, crate);
        expect(rigid.groundNormal.dy, closeTo(-1, 0.05));
      });
    });
  }

  // On the pure-Dart backend, as the platformer kit runs its slopes: Box2D
  // reports ghost normals where tiles meet, and a body run down a tiled
  // ramp there leaves it with or without the ground being looked at again.
  test('running down a ramp of tiles, a body stays on the ground and on '
      'its slope', () {
    final (:world, :physics, :system) = _setUp(PhysicsEngine.pureDart());
    _ramp(world);
    final runner = _SlopeRunner(0);
    world.addSystem(runner);
    final rigid = RigidBody2DComponent(
      lockRotation: true,
      friction: 0.2,
      restitution: 0,
      linearDamping: 0,
    );
    final body = world.createEntityWithComponents([
      TransformComponent(position: Vector3(9 * 32 + 16, 3 * 32, 0)),
      VelocityComponent(),
      rigid,
      Collider2DComponent(size: Vector2(24, 40)),
    ]);
    for (var i = 0; i < 60; i++) {
      world.update(1 / 60);
    }
    expect(rigid.isGrounded, isTrue, reason: 'settled on the ramp');

    runner.speed = -300;
    var airborne = 0, flat = 0, onRamp = 0;
    for (var i = 0; i < 40; i++) {
      world.update(1 / 60);
      final x = body.getComponent<TransformComponent>()!.position.x;
      if (!rigid.isGrounded) airborne++;
      // Well inside the ramp, the ground under it is the slope: never a
      // near-flat normal from where two tiles meet.
      if (x > 6 * 32 && x < 9 * 32) {
        onRamp++;
        if (rigid.isGrounded && rigid.groundNormal.dx.abs() < 0.5) flat++;
      }
    }
    expect(
      body.getComponent<TransformComponent>()!.position.x,
      lessThan(8 * 32),
      reason: 'it went down',
    );
    expect(onRamp, greaterThan(5));
    expect(flat, 0, reason: 'the slope is the ground on the ramp');
    expect(airborne / 40, lessThan(0.2), reason: 'not skipping down it');
  });
}

// CharacterBody2D through PhysicsSystem: the 2-D twin of the 3-D
// CharacterBody3D — gravity and the ground, walking and jumping, platforms,
// one-way platforms, sensors seeing it, teleports, and saving.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  // The same character, on each backend: they must agree.
  for (final (name, make) in [
    ('native Box2D', () => PhysicsEngine()..initialize()),
    ('pure Dart', () => PhysicsEngine.pureDart()..initialize()),
  ]) {
    group(name, () => _suite(make));
  }
}

void _suite(PhysicsEngine Function() make) {
  late PhysicsEngine physics;
  late World world;

  setUp(() {
    physics = make();
    physics.setGravity(0, 2000);
    world = World()..initialize();
    world.addSystem(PhysicsSystem(physics));
  });
  tearDown(() {
    world.dispose();
    physics.dispose();
  });

  void run([int frames = 60]) {
    for (var i = 0; i < frames; i++) {
      world.update(1 / 60);
    }
  }

  /// A long static floor whose top is at y = 100: a collider alone.
  Entity floor() => world.createEntityWithComponents([
    TransformComponent(position: Vector3(0, 120, 0)),
    Collider2D(size: Vector2(4000, 40)),
  ], name: 'floor');

  Entity hero({
    CharacterShape2D shape = CharacterShape2D.capsule,
    double x = 0,
    double y = 0,
  }) => world.createEntityWithComponents([
    TransformComponent(position: Vector3(x, y, 0)),
    CharacterBody2D(shape: shape),
  ], name: 'hero');

  CharacterBody2D of(Entity e) => e.getComponent<CharacterBody2D>()!;
  Offset at(Entity e) {
    final p = e.getComponent<TransformComponent>()!.position;
    return Offset(p.x, p.y);
  }

  test('it falls, lands on a collider and knows what it stands on', () {
    final ground = floor();
    final h = hero();
    run(90);
    final c = of(h);
    expect(c.isGrounded, isTrue);
    expect(c.groundEntity, same(ground));
    expect(c.groundNormal.dy, closeTo(-1, 1e-3));
    expect(
      at(h).dy,
      closeTo(100 - 24, 1.5),
      reason: 'a 48-tall capsule standing on y = 100',
    );
  });

  test('it walks at moveVelocity and jumps from the ground', () {
    floor();
    final h = hero(y: 70);
    run(20);
    final c = of(h)..moveVelocity = const Offset(240, 0);
    final x0 = at(h).dx;
    run(30);
    expect(at(h).dx - x0, closeTo(120, 6));
    c
      ..moveVelocity = Offset.zero
      ..jump(800);
    run(1);
    expect(c.isGrounded, isFalse);
    expect(c.velocity.dy, lessThan(0), reason: 'up is -Y');
    run(90);
    expect(c.isGrounded, isTrue, reason: 'back down');
  });

  test('a box stands where it was set down', () {
    floor();
    final h = hero(shape: CharacterShape2D.box, y: 70);
    run(30);
    expect(of(h).isGrounded, isTrue);
    expect(at(h).dy, closeTo(76, 1.5));
  });

  test('a moving platform carries it', () {
    floor();
    final platform = world.createEntityWithComponents([
      TransformComponent(position: Vector3(0, 40, 0)),
      VelocityComponent(),
      RigidBody2D(bodyType: BodyType.kinematic),
      Collider2D(size: Vector2(200, 10)),
    ], name: 'platform');
    final h = hero(y: 0);
    run(30);
    expect(of(h).groundEntity, same(platform));
    platform.getComponent<VelocityComponent>()!.velocity.setValues(120, 0, 0);
    final x0 = at(h).dx;
    run(60);
    expect(at(h).dx - x0, closeTo(120, 12), reason: 'carried along');
    expect(of(h).groundVelocity.dx, closeTo(120, 1));
  });

  test('it jumps up through a one-way platform and stands on it', () {
    floor();
    world.createEntityWithComponents([
      TransformComponent(position: Vector3(0, 20, 0)),
      Collider2D(size: Vector2(200, 10), oneWay: true),
    ], name: 'ledge');
    final h = hero(y: 70);
    run(20);
    of(h).jump(1000);
    run(90);
    expect(of(h).isGrounded, isTrue);
    expect(at(h).dy, closeTo(15 - 24, 1.5));
  });

  test(
    'a sensor sees it by its own body, and an undetectable one is not seen',
    () {
      floor();
      world.createEntityWithComponents([
        TransformComponent(position: Vector3(0, 70, 0)),
        RigidBody2D(bodyType: BodyType.static, isSensor: true),
        Collider2D(size: Vector2(40, 40)),
      ], name: 'coin');
      final seen = <Entity>[];
      world.events.on<SensorEnter2DEvent>((e) => seen.add(e.other));
      final h = hero(y: 0);
      run(60);
      expect(seen, [h]);

      final ghost = hero(x: 0, y: 0)
        ..getComponent<CharacterBody2D>()!.detectable = false;
      seen.clear();
      run(60);
      expect(seen, isEmpty, reason: 'nothing of it in the world');
      expect(of(ghost).isGrounded, isTrue, reason: 'it still stands');
      expect(world.getSystem<PhysicsSystem>()!.bodyOf(h), isNotNull);
      expect(world.getSystem<PhysicsSystem>()!.bodyOf(ghost), isNull);
    },
  );

  test('a transform written by gameplay is a teleport', () {
    floor();
    final h = hero(y: 70);
    run(20);
    h.getComponent<TransformComponent>()!.position.setValues(500, -200, 0);
    run(1);
    expect(at(h).dx, closeTo(500, 0.5));
    expect(of(h).isGrounded, isFalse);
    run(90);
    expect(at(h).dx, closeTo(500, 0.5));
    expect(of(h).isGrounded, isTrue);
  });

  test('its body goes with the component', () {
    final h = hero();
    run(1);
    final body = world.getSystem<PhysicsSystem>()!.bodyOf(h)!;
    expect(physics.bodies, contains(body));
    h.removeComponent<CharacterBody2D>();
    run(1);
    expect(physics.bodies, isNot(contains(body)));
  });

  test('MovementSystem leaves it to PhysicsSystem, which fills its velocity component', () {
    world.addSystem(MovementSystem());
    floor();
    final h = hero(y: 70)
      ..addComponent(VelocityComponent(velocity: Vector3(1000, 0, 0)));
    run(30);
    expect(
      at(h).dx,
      closeTo(0, 0.5),
      reason: 'not moved by its velocity component',
    );
    of(h).moveVelocity = const Offset(150, 0);
    run(10);
    expect(
      h.getComponent<VelocityComponent>()!.velocity.x,
      closeTo(150, 1),
      reason: 'the character velocity, for animators',
    );
  });

  test('it is saved field for field', () {
    final definitions = ComponentDefinitionRegistry.core();
    final c = CharacterBody2D(
      shape: CharacterShape2D.box,
      width: 20,
      height: 40,
      offset: const Offset(0, -4),
      stepHeight: 12,
      layer: 3,
      collidesWith: 0x9,
      detectable: false,
      gravityScale: 1.5,
    );
    final json = definitions.encode(c)!;
    expect(json['type'], 'CharacterBody2D');
    final back = definitions.decode(json)! as CharacterBody2D;
    expect(back.shape, CharacterShape2D.box);
    expect(
      (back.width, back.height, back.offset),
      (20.0, 40.0, const Offset(0, -4)),
    );
    expect(
      (
        back.stepHeight,
        back.layer,
        back.collidesWith,
        back.detectable,
        back.gravityScale,
      ),
      (12.0, 3, 0x9, false, 1.5),
    );
    expect(definitions.encode(back), json);
  });
}

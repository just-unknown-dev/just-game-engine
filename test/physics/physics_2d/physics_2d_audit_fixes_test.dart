// Physics fixes from the 2.0.0 final pass: a joint is made again only for
// an anchor it takes — a weld's own, a wheel's axle (F21, PHY-2); the
// prismatic joint's editor groups name only its
// fields (F21); without native wheel joints a wheel is the physics engine's
// own wheel joint, its motor spinning the wheel (F24); a collision event
// needs no penetration (F29).

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_physics_engine/just_physics_engine.dart'
    show WheelJoint2D, WeldJoint2D;

const _frame = 1 / 60;

({World world, Physics2DEngine physics}) _setUp() {
  final physics = Physics2DEngine.pureDart()..initialize();
  physics.setGravity(0, 0);
  final world = World()..initialize();
  world.addSystem(Physics2DSystem(physics));
  addTearDown(() {
    world.dispose();
    physics.dispose();
  });
  return (world: world, physics: physics);
}

Entity _box(
  World world, {
  double x = 0,
  String? name,
  List<Component> extra = const [],
}) => world.createEntityWithComponents([
  TransformComponent(position: Vector3(x, 0, 0)),
  VelocityComponent(),
  RigidBody2DComponent(restitution: 0),
  Collider2DComponent(size: Vector2(20, 20)),
  ...extra,
], name: name);

void main() {
  test('a joint is made again only for an anchor it takes', () {
    final (:world, :physics) = _setUp();
    final weld = FixedJoint2DComponent(
      connectedBody: const EntityTarget.name('B'),
    );
    _box(world, extra: [weld]);
    _box(world, x: 30, name: 'B');
    world.update(_frame);
    final first = physics.joints.single;
    expect(first, isA<WeldJoint2D>());

    world.update(_frame);
    expect(physics.joints.single, same(first), reason: 'nothing changed');

    // A weld takes no connected anchor: nothing to make again for.
    weld.connectedAnchor = const Offset(4, 0);
    world.update(_frame);
    expect(physics.joints.single, same(first));

    // It is welded at its own anchor, on both backends: made again.
    weld.anchor = const Offset(4, 0);
    world.update(_frame);
    final moved = physics.joints.single;
    expect(moved, isNot(same(first)));
    world.update(_frame);
    expect(physics.joints.single, same(moved), reason: 'nothing changed');

    // A wheel's axle is taken (natively): changing it makes it again.
    weld.enabled = false;
    final wheel = WheelJoint2DComponent(
      connectedBody: const EntityTarget.name('B'),
    );
    _box(world, x: 60, extra: [wheel]);
    world.update(_frame);
    final made = physics.joints.single;
    wheel.connectedAnchor = const Offset(2, 0);
    world.update(_frame);
    expect(physics.joints.single, isNot(same(made)));
  });

  test('every field a definition groups or rows is one of its fields', () {
    for (final definition in BuiltInComponents.registry().definitions) {
      final type = definition.type;
      final names = {for (final f in definition.fields) f.name};
      for (final group in (definition.hints.fieldGroups ?? {}).values) {
        for (final name in group) {
          expect(names, contains(name), reason: '$type groups $name');
        }
      }
      for (final row in definition.hints.fieldRows) {
        for (final name in row.cells.keys) {
          expect(names, contains(name), reason: '$type rows $name');
        }
      }
    }
  });

  test('without native wheel joints a wheel is a wheel joint', () {
    final (:world, :physics) = _setUp();
    _box(
      world,
      extra: [
        WheelJoint2DComponent(
          connectedBody: const EntityTarget.name('Wheel'),
          stiffness: 30,
          damping: 0.5,
          motorSpeed: 7,
          motorMaxTorque: 1e6,
        ),
      ],
    );
    _box(world, x: 0, name: 'Wheel');
    world.update(_frame);
    final wheel = physics.joints.single as WheelJoint2D;
    // Hertz and a damping ratio, as Box2D takes them.
    expect((wheel.springHertz, wheel.dampingRatio), (30.0, 0.5));
    // Its motor spins the wheel against the chassis.
    for (var i = 0; i < 10; i++) {
      world.update(_frame);
    }
    expect(
      wheel.bodyB.angularVelocity - wheel.bodyA.angularVelocity,
      closeTo(7, 0.5),
    );
  });

  test('a collision event is made without a depth', () {
    final world = World()..initialize();
    addTearDown(world.dispose);
    final a = world.createEntity();
    final b = world.createEntity();
    final event = CollisionEnter2DEvent(
      entityA: a,
      entityB: b,
      point: Offset.zero,
      normal: const Offset(0, 1),
    );
    expect(event.normal, const Offset(0, 1));
    expect(event.depth, 0);
  });
}

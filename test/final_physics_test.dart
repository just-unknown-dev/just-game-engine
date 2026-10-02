// Physics fixes from the 2.0.0 final pass: a weld is made again when either
// anchor changes (F21); the prismatic joint's editor groups name only its
// fields (F21); without native wheel joints a wheel is the physics engine's
// own wheel joint, its motor spinning the wheel (F24); a ray collider with
// no size is hit by nothing (F28); a collision event needs no penetration
// (F29).

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_physics_engine/just_physics_engine.dart'
    show WheelJoint, WeldJoint;

const _frame = 1 / 60;

({World world, PhysicsEngine physics}) _setUp() {
  final physics = PhysicsEngine.pureDart()..initialize();
  physics.setGravity(0, 0);
  final world = World()..initialize();
  world
    ..addSystem(PhysicsSystem(physics))
    ..addSystem(PhysicsJointBindingSystem(physics));
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
  PhysicsBodyComponent(shape: RectangleShape(20, 20), restitution: 0),
  ...extra,
], name: name);

void main() {
  test('F21 a weld is made again when its second anchor changes', () {
    final (:world, :physics) = _setUp();
    final weld = WeldJointComponent(targetEntityName: 'B');
    _box(world, extra: [weld]);
    _box(world, x: 30, name: 'B');
    world.update(_frame);
    final first = physics.joints.single;
    expect(first, isA<WeldJoint>());

    world.update(_frame);
    expect(physics.joints.single, same(first), reason: 'nothing changed');

    weld.localAnchorB = const Offset(4, 0);
    world.update(_frame);
    expect(physics.joints, hasLength(1));
    expect(physics.joints.single, isNot(same(first)));
  });

  test('F21 every field a definition groups or rows is one of its fields', () {
    for (final definition in ComponentDefinitionRegistry.core().definitions) {
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

  test('F24 without native wheel joints a wheel is a wheel joint', () {
    final (:world, :physics) = _setUp();
    _box(
      world,
      extra: [
        WheelJointComponent(
          targetEntityName: 'Wheel',
          stiffness: 30,
          damping: 0.5,
          motorSpeed: 7,
          maxMotorTorque: 90,
        ),
      ],
    );
    _box(world, x: 0, name: 'Wheel');
    world.update(_frame);
    final wheel = physics.joints.single as WheelJoint;
    expect((wheel.springStiffness, wheel.springDamping), (30.0, 0.5));
    expect(wheel.motorEnabled, isTrue);
    expect((wheel.motorSpeed, wheel.maxMotorTorque), (7.0, 90.0));
  });

  group('F28 ray colliders', () {
    late World world;
    late RaycastSystem rays;

    setUp(() {
      world = World()..initialize();
      rays = RaycastSystem();
      world.addSystem(rays);
    });
    tearDown(() => world.dispose());

    Entity target(RaycastColliderComponent collider) =>
        world.createEntityWithComponents([
          TransformComponent(position: Vector3(50, 0, 0)),
          collider,
        ]);

    Ray rightward() => Ray(origin: Offset.zero, direction: const Offset(1, 0));

    test('one with no size at all is hit by nothing', () {
      target(RaycastColliderComponent());
      expect(rays.castRay(rightward()), isNull);
    });

    test('one with a radius is hit', () {
      final e = target(RaycastColliderComponent(radius: 5));
      expect(rays.castRay(rightward())?.entity, same(e));
    });
  });

  test('F29 a collision event is made without a penetration', () {
    final world = World()..initialize();
    addTearDown(world.dispose);
    final a = world.createEntity();
    final b = world.createEntity();
    final event = CollisionEvent(
      entityA: a,
      entityB: b,
      normal: const Offset(0, 1),
    );
    expect(event.normal, const Offset(0, 1));
  });
}

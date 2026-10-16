// A collider matching the shape its entity is drawn as (any
// SolidShapeSource): made from the shape's convex parts, scaled with the
// entity, made again when the shape changes, and none without a shape.

@Tags(['physics3d'])
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/physics_3d.dart';
import 'package:just_physics_engine/testing.dart';

const _dt = 1 / 60;

/// A look with a shape: a box [size] across, or [steps] boxes like stairs.
class _Look extends Component implements SolidShapeSource {
  _Look({this.size = 1, this.steps = 1});

  double size;
  int steps;

  @override
  Object get solidKey => ('look', size, steps);

  @override
  List<SolidPart> get solidParts => [
    for (var i = 0; i < steps; i++) SolidBox(size / 2, size / 2, size / 2, z: i * size),
  ];
}

void main() {
  late World world;
  late FakePhysicsWorld3D physics;
  late PhysicsSystem3D system;

  setUp(() {
    physics = FakePhysicsWorld3D(PhysicsWorldSettings3D());
    system = PhysicsSystem3D(physics);
    world = World()..initialize();
    world.addSystem(system);
  });
  tearDown(() {
    world.dispose();
    physics.dispose();
  });

  Entity matched(Component look, {Vector3? scale, RigidBody3D? body}) => world.createEntityWithComponents([
    TransformComponent(scale: scale),
    look,
    Collider3D(shape: ColliderShape3D.matchShape),
    ?body,
  ]);

  Shape3D shapeOf(Entity e) => physics.bodies[system.bodyOf(e)]!.shape;

  test('takes the shape its entity is drawn as, scaled with it', () {
    final e = matched(_Look(size: 2), scale: Vector3(1, 3, 1));
    world.update(_dt);
    expect(shapeOf(e), const BoxShape3D(1, 3, 1));
  });

  test('is made again when the shape changes', () {
    final look = _Look();
    final e = matched(look, body: RigidBody3D());
    world.update(_dt);
    final first = system.bodyOf(e);
    look.size = 4;
    world.update(_dt);
    expect(system.bodyOf(e), isNot(first));
    expect(shapeOf(e), const BoxShape3D(2, 2, 2));
  });

  test('several parts are one compound, each part where it is', () {
    final e = matched(_Look(steps: 3), body: RigidBody3D());
    world.update(_dt);
    final shape = shapeOf(e) as CompoundShape3D;
    expect(shape.parts, [
      const BoxShape3D(0.5, 0.5, 0.5),
      const TransformedShape3D(BoxShape3D(0.5, 0.5, 0.5), z: 1),
      const TransformedShape3D(BoxShape3D(0.5, 0.5, 0.5), z: 2),
    ]);
    expect(physics.bodies[system.bodyOf(e)]!.type, BodyType3D.dynamic, reason: 'a compound can move');
  });

  test('an entity with no shape gets no body', () {
    final e = world.createEntityWithComponents([
      TransformComponent(),
      Collider3D(shape: ColliderShape3D.matchShape),
    ]);
    world.update(_dt);
    expect(system.bodyOf(e), 0);
  });

  test('equal shapes share one shape', () {
    final a = matched(_Look(steps: 2));
    final b = matched(_Look(steps: 2));
    world.update(_dt);
    expect(identical(shapeOf(a), shapeOf(b)), isTrue);
  });

  group('parts', () {
    test('each kind, scaled', () {
      expect(ColliderShapes3D.solidPart(const SolidSphere(1, x: 1), 2, 1, 1), const TransformedShape3D(SphereShape3D(2), x: 2));
      expect(ColliderShapes3D.solidPart(const SolidCylinder(1, 0.5), 2, 3, 1), const CylinderShape3D(3, 1));
      expect(ColliderShapes3D.solidPart(const SolidCapsule(1, 0.5), 1, 2, 1), const CapsuleShape3D(2.5, 0.5));
      expect(ColliderShapes3D.solidPart(const SolidCapsule(0, 0.5), 1, 1, 1), const SphereShape3D(0.5));
      final hull = ColliderShapes3D.solidPart(
        SolidHull(Float32List.fromList([0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1])),
        2,
        -1,
        1,
      )! as ConvexHullShape3D;
      expect(hull.points, [0, 0, 0, 2, 0, 0, 0, -1, 0, 0, 0, 1]);
      expect(ColliderShapes3D.solidPart(SolidHull(Float32List(9)), 1, 1, 1), isNull, reason: 'three points are no hull');
    });

    test('the collider\'s own offset still applies', () {
      final shapes = ColliderShapes3D();
      final collider = Collider3D(shape: ColliderShape3D.matchShape, offset: Vector3(0, -1, 0));
      final shape = shapes.build(collider, Vector3(1, 1, 1), source: _Look(size: 2));
      expect(shape, const TransformedShape3D(BoxShape3D(1, 1, 1), y: -1));
    });
  });

  test('saved and loaded as match shape', () {
    final context = EngineContext(extensions: [Physics3D()]);
    final json = context.definitions.encode(Collider3D(shape: ColliderShape3D.matchShape))!;
    final back = context.definitions.decode(json)! as Collider3D;
    expect(back.shape, ColliderShape3D.matchShape);
    context.dispose();
  });
}

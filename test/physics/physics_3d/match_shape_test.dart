// A collider matching the shape its entity is drawn as (any
// SolidShapeSource): made from the shape's convex parts, scaled with the
// entity, made again when the shape changes, and none without a shape.

@Tags(['physics3d'])
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/just_game_engine_3d.dart';
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
  late FakePhysics3DWorld physics;
  late Physics3DSystem system;

  setUp(() {
    physics = FakePhysics3DWorld(Physics3DWorldSettings());
    system = Physics3DSystem(physics);
    world = World()..initialize();
    world.addSystem(system);
  });
  tearDown(() {
    world.dispose();
    physics.dispose();
  });

  Entity matched(Component look, {Vector3? scale, RigidBody3DComponent? body}) => world.createEntityWithComponents([
    TransformComponent(scale: scale),
    look,
    Collider3DComponent(shape: Collider3DShape.matchShape),
    ?body,
  ]);

  Shape3D shapeOf(Entity e) => physics.bodies[system.bodyOf(e)]!.shape;

  test('takes the shape its entity is drawn as, scaled with it', () {
    final e = matched(_Look(size: 2), scale: Vector3(1, 3, 1));
    world.update(_dt);
    expect(shapeOf(e), const Box3DShape(1, 3, 1));
  });

  test('is made again when the shape changes', () {
    final look = _Look();
    final e = matched(look, body: RigidBody3DComponent());
    world.update(_dt);
    final first = system.bodyOf(e);
    look.size = 4;
    world.update(_dt);
    expect(system.bodyOf(e), isNot(first));
    expect(shapeOf(e), const Box3DShape(2, 2, 2));
  });

  test('several parts are one compound, each part where it is', () {
    final e = matched(_Look(steps: 3), body: RigidBody3DComponent());
    world.update(_dt);
    final shape = shapeOf(e) as Compound3DShape;
    expect(shape.parts, [
      const Box3DShape(0.5, 0.5, 0.5),
      const Transformed3DShape(Box3DShape(0.5, 0.5, 0.5), z: 1),
      const Transformed3DShape(Box3DShape(0.5, 0.5, 0.5), z: 2),
    ]);
    expect(physics.bodies[system.bodyOf(e)]!.type, Body3DType.dynamic, reason: 'a compound can move');
  });

  test('an entity with no shape gets no body', () {
    final e = world.createEntityWithComponents([
      TransformComponent(),
      Collider3DComponent(shape: Collider3DShape.matchShape),
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
      expect(Collider3DShapes.solidPart(const SolidSphere(1, x: 1), 2, 1, 1), const Transformed3DShape(Sphere3DShape(2), x: 2));
      expect(Collider3DShapes.solidPart(const SolidCylinder(1, 0.5), 2, 3, 1), const Cylinder3DShape(3, 1));
      expect(Collider3DShapes.solidPart(const SolidCapsule(1, 0.5), 1, 2, 1), const Capsule3DShape(2.5, 0.5));
      expect(Collider3DShapes.solidPart(const SolidCapsule(0, 0.5), 1, 1, 1), const Sphere3DShape(0.5));
      final hull = Collider3DShapes.solidPart(
        SolidHull(Float32List.fromList([0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1])),
        2,
        -1,
        1,
      )! as ConvexHull3DShape;
      expect(hull.points, [0, 0, 0, 2, 0, 0, 0, -1, 0, 0, 0, 1]);
      expect(Collider3DShapes.solidPart(SolidHull(Float32List(9)), 1, 1, 1), isNull, reason: 'three points are no hull');
    });

    test('the collider\'s own offset still applies', () {
      final shapes = Collider3DShapes();
      final collider = Collider3DComponent(shape: Collider3DShape.matchShape, offset: Vector3(0, -1, 0));
      final shape = shapes.build(collider, Vector3(1, 1, 1), source: _Look(size: 2));
      expect(shape, const Transformed3DShape(Box3DShape(1, 1, 1), y: -1));
    });
  });

  test('saved and loaded as match shape', () {
    final context = EngineContext(extensions: [Physics3D()]);
    final json = context.definitions.encode(Collider3DComponent(shape: Collider3DShape.matchShape))!;
    final back = context.definitions.decode(json)! as Collider3DComponent;
    expect(back.shape, Collider3DShape.matchShape);
    context.dispose();
  });
}

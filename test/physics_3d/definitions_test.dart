// The 3-D physics components save, load and describe themselves, and
// colliders become the shapes a backend is given.

@Tags(['physics3d'])
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/physics_3d.dart';

void main() {
  group('definitions', () {
    test(
      'the extension registers every component, 3-D only, with stable ids',
      () {
        final context = EngineContext()..install(Physics3D());
        addTearDown(context.dispose);
        final ids = <String>{};
        for (final schema in Physics3DSchemas.all) {
          expect(context.definitions.definitionByType(schema.type), isNotNull);
          expect(
            schema.hints.dimensions,
            Dimensions.threeD,
            reason: schema.type,
          );
          expect(schema.hints.group, 'Physics', reason: 'with the 2-D ones');
          expect(
            schema.id,
            matches(RegExp(r'^[a-z_0-9]+_3d_[0-9a-f]{8}$')),
            reason: schema.type,
          );
          expect(ids.add(schema.id), isTrue, reason: 'unique id');
        }
        // Bodies, colliders, characters, six joints and camera collision.
        expect(ids, hasLength(10));
      },
    );

    test('every component survives a save and a load', () {
      final samples = <Component>[
        RigidBody3D(
          bodyType: BodyType3D.kinematic,
          continuousCollision: true,
          mass: 3,
          friction: 0.8,
          restitution: 0.25,
          gravityScale: 0.5,
          isSensor: true,
          layer: 3,
          canSleep: false,
          lockRotation: true,
          initialVelocity: Vector3(1, 2, 3),
        ),
        Collider3D(
          shape: ColliderShape3D.heightField,
          size: Vector3(2, 3, 4),
          radius: 0.7,
          model: 'assets/models/rock.glb',
          meshName: 'Rock',
          heights: [0, 1, 2, 3],
          heightFieldSize: 2,
          cellSize: 0.5,
          offset: Vector3(0, -1, 0),
          rotation: Vector3(0, 0.5, 0),
          scale: Vector3(2, 2, 2),
        ),
        CharacterBody3D(
          radius: 0.4,
          height: 2,
          stepHeight: 0.3,
          layer: 2,
          detectable: false,
        ),
        FixedJoint3D(
          connectedBody: const EntityTarget.name('Door'),
          anchor: Vector3(1, 0, 0),
        ),
        PointJoint3D(connectedBody: const EntityTarget.tag('rope')),
        HingeJoint3D(
          axis: Vector3(0, 0, 1),
          useLimits: true,
          minAngle: -1,
          maxAngle: 2,
          motor: MotorState3D.velocity,
          motorTarget: 3,
          motorMaxTorque: 40,
        ),
        SliderJoint3D(
          useLimits: true,
          minPosition: 0,
          maxPosition: 4,
          motor: MotorState3D.position,
        ),
        DistanceJoint3D(
          connectedAnchor: Vector3(0, 2, 0),
          minDistance: 1,
          maxDistance: 3,
          springFrequency: 2,
        ),
        SixDofJoint3D(
          translationX: SixDofAxisMode3D.free,
          rotationY: SixDofAxisMode3D.limited,
          rotationMin: Vector3(0, -1, 0),
          rotationMax: Vector3(0, 1, 0),
        ),
      ];
      for (final component in samples) {
        final schema = Physics3DSchemas.all.firstWhere(
          (s) => s.type == component.runtimeType.toString(),
        );
        final saved = schema.encode(component);
        final json = jsonDecode(jsonEncode(saved)) as Map<String, dynamic>;
        final loaded = schema.decode(json);
        expect(loaded.runtimeType, component.runtimeType);
        expect(
          jsonEncode(schema.encode(loaded)),
          jsonEncode(saved),
          reason: schema.type,
        );
      }
    });

    test('a joint to nobody saves nothing and loads as the world', () {
      final schema = Physics3DSchemas.hingeJoint;
      final loaded = schema.decode(
        jsonDecode(jsonEncode(schema.encode(HingeJoint3D())))
            as Map<String, dynamic>,
      );
      expect(loaded.connectedBody.isNone, isTrue);
    });
  });

  test('the 2-D and 3-D bodies show the same fields, grouped alike', () {
    final context = EngineContext()..install(Physics3D());
    addTearDown(context.dispose);
    final two = context.definitions.definitionByType('RigidBody2D')!;
    final three = context.definitions.definitionByType('RigidBody3D')!;
    final shared = {for (final f in three.fields) f.name};
    expect({for (final f in two.fields) f.name}.containsAll(shared), isTrue, reason: 'every 3-D field has a 2-D twin');
    for (final name in shared) {
      expect(three.hints.fields[name]?.label, two.hints.fields[name]?.label, reason: name);
    }
    expect(three.hints.group, two.hints.group);
    expect(context.definitions.definitionByType('Collider3D')!.hints.group, 'Physics');
  });

  test('the 2-D and 3-D characters show the same fields, grouped alike', () {
    final context = EngineContext()..install(Physics3D());
    addTearDown(context.dispose);
    final two = context.definitions.definitionByType('CharacterBody2D')!;
    final three = context.definitions.definitionByType('CharacterBody3D')!;
    final shared = {for (final f in three.fields) f.name};
    expect({for (final f in two.fields) f.name}.containsAll(shared), isTrue, reason: 'every 3-D field has a 2-D twin');
    for (final name in shared) {
      expect(three.hints.fields[name]?.label, two.hints.fields[name]?.label, reason: name);
      expect(three.hints.fields[name]?.description, two.hints.fields[name]?.description, reason: name);
    }
    for (final group in three.hints.fieldGroups!.keys) {
      expect(two.hints.fieldGroups!.keys, contains(group));
    }
    expect(three.hints.group, two.hints.group);
  });

  group('collider shapes', () {
    final shapes = ColliderShapes3D();

    test('a box takes its size and the entity scale, as half extents', () {
      final shape = shapes.build(
        Collider3D(size: Vector3(2, 4, 6)),
        Vector3(1, 0.5, -2),
      );
      expect(shape, const BoxShape3D(1, 1, 6));
    });

    test('round shapes take the largest scale across them', () {
      expect(
        shapes.build(
          Collider3D(shape: ColliderShape3D.sphere, radius: 1),
          Vector3(1, 3, 2),
        ),
        const SphereShape3D(3),
      );
      expect(
        shapes.build(
          Collider3D(shape: ColliderShape3D.capsule, radius: 0.5, height: 3),
          Vector3(2, 1, 1),
        ),
        const CapsuleShape3D(0.5, 1),
      );
      expect(
        shapes.build(
          Collider3D(shape: ColliderShape3D.cylinder, radius: 0.5, height: 2),
          Vector3(1, 1, 1),
        ),
        const CylinderShape3D(1, 0.5),
      );
    });

    test('a capsule too short for a straight part is a ball', () {
      expect(
        shapes.build(
          Collider3D(shape: ColliderShape3D.capsule, radius: 1, height: 1.5),
          Vector3(1, 1, 1),
        ),
        const SphereShape3D(1),
      );
    });

    test('an offset or a turn places the shape in its entity', () {
      final shape = shapes.build(
        Collider3D(size: Vector3(2, 2, 2), offset: Vector3(0, -1, 0)),
        Vector3(2, 2, 2),
      );
      expect(shape, isA<TransformedShape3D>());
      final placed = shape! as TransformedShape3D;
      expect(placed.shape, const BoxShape3D(2, 2, 2));
      expect(placed.y, -2, reason: 'the offset scales with the entity');
    });

    test(
      'a mesh is shared by bodies of the same model and scale, and a mirror turns it back',
      () {
        final geometry = _Geometry();
        final meshes = ColliderShapes3D(geometry: geometry);
        final collider = Collider3D(
          shape: ColliderShape3D.mesh,
          model: 'a.glb',
        );
        final first = meshes.build(collider, Vector3(1, 1, 1));
        final second = meshes.build(
          Collider3D(shape: ColliderShape3D.mesh, model: 'a.glb'),
          Vector3(1, 1, 1),
        );
        expect(identical(first, second), isTrue);
        final mirrored =
            meshes.build(collider, Vector3(-1, 1, 1))! as MeshShape3D;
        expect(mirrored.indices, [0, 2, 1]);
        expect(mirrored.positions[3], -1);
      },
    );

    test('a mesh waits for its triangles', () {
      final geometry = _Geometry()..ready = false;
      final meshes = ColliderShapes3D(geometry: geometry);
      final collider = Collider3D(
        shape: ColliderShape3D.convexHull,
        model: 'a.glb',
      );
      expect(meshes.build(collider, Vector3(1, 1, 1)), isNull);
      geometry.ready = true;
      expect(
        meshes.build(collider, Vector3(1, 1, 1)),
        isA<ConvexHullShape3D>(),
      );
    });

    test('a height field needs its samples', () {
      final field = Collider3D(
        shape: ColliderShape3D.heightField,
        heights: [for (var i = 0; i < 16; i++) i < 8 ? 0.0 : 1.0],
        heightFieldSize: 4,
        cellSize: 2,
      );
      final shape =
          shapes.build(field, Vector3(1, 3, 1))! as HeightFieldShape3D;
      expect(shape.sampleCount, 4);
      expect(shape.cellSize, 2);
      expect(shape.heights.sublist(6, 10), [0, 0, 3, 3]);
      field.heights = [1];
      expect(shapes.build(field, Vector3(1, 1, 1)), isNull);
    });

    test('merged geometry renumbers each part\'s indices', () {
      final merged = AssetColliderGeometry3D.merge([
        ModelGeometry(
          Float32List.fromList([0, 0, 0, 1, 0, 0, 0, 1, 0]),
          Uint32List.fromList([0, 1, 2]),
        ),
        ModelGeometry(
          Float32List.fromList([5, 0, 0, 6, 0, 0, 5, 1, 0]),
          Uint32List.fromList([0, 1, 2]),
        ),
      ])!;
      expect(merged.positions, hasLength(18));
      expect(merged.indices, [0, 1, 2, 3, 4, 5]);
    });
  });
}

final class _Geometry implements ColliderGeometry3D {
  bool ready = true;

  @override
  ModelGeometry? geometryOf(String model, String meshName) => ready
      ? ModelGeometry(
          Float32List.fromList([0, 0, 0, 1, 0, 0, 0, 1, 0]),
          Uint32List.fromList([0, 1, 2]),
        )
      : null;
}

// The physics field types: what they save, and that the physics feature
// registers them with its definitions — the ECS core knows none of them.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  test('the physics shape field type reads back every kind of shape', () {
    const type = PhysicsDefinitions.shapeType;
    const triangle = [Offset(0, 0), Offset(10, 0), Offset(0, 10)];
    final shapes = <Shape2D>[
      Circle2DShape(5, center: const Offset(1, 2)),
      RoundedPolygon2DShape(triangle, 2),
      Rectangle2DShape(8, 4),
      Polygon2DShape(triangle),
      Capsule2DShape(
        center1: const Offset(0, -5),
        center2: const Offset(0, 5),
        radius: 2,
      ),
      Segment2DShape(Offset.zero, const Offset(10, 0), thickness: 3),
      Chain2DShape(triangle, loop: true, thickness: 1),
    ];
    for (final shape in shapes) {
      final json = type.encode(shape);
      final back = type.decode(json, FieldConstraints.none);
      expect(back.runtimeType, shape.runtimeType, reason: '$json');
      expect(type.encode(back as Shape2D), json);
    }
    expect(type.decode({'kind': 'nope'}, FieldConstraints.none), isNull);
    expect(
      type.decode({'kind': 'polygon', 'vertices': []}, FieldConstraints.none),
      isNull,
    );
  });

  test('a layer reads clamped to 0..15, a mask to 16 bits', () {
    const layer = PhysicsDefinitions.layerType;
    const mask = PhysicsDefinitions.layerMaskType;
    expect(layer.decode(3, FieldConstraints.none), 3);
    expect(layer.decode(40, FieldConstraints.none), 15);
    expect(layer.decode(-2, FieldConstraints.none), 0);
    expect(mask.decode(0x1FFFF, FieldConstraints.none), 0xFFFF);
    expect(mask.encode(0x30005), 0x0005);
    expect(mask.decodeAny(null, FieldConstraints.none), isNull);
  });

  group('registration', () {
    final ids = [for (final t in PhysicsDefinitions.fieldTypes) t.id];

    test('a bare world knows none of them', () {
      final world = World();
      addTearDown(world.dispose);
      for (final id in ids) {
        expect(world.context.fieldTypes.byId(id), isNull, reason: id);
      }
    });

    test('the engine registers them with its definitions', () {
      final world = World(extensions: [BuiltInComponents.extension]);
      addTearDown(world.dispose);
      for (final type in PhysicsDefinitions.fieldTypes) {
        expect(world.context.fieldTypes.byId(type.id), same(type));
      }
      final engine = Engine();
      addTearDown(engine.dispose);
      for (final type in PhysicsDefinitions.fieldTypes) {
        expect(engine.context.fieldTypes.byId(type.id), same(type));
      }
    });

    test("a project's own replacement stays through a refresh", () {
      final context = EngineContext();
      addTearDown(context.dispose);
      const mine = _MyLayerFieldType();
      context.fieldTypes.register(mine);
      context.install(BuiltInComponents.extension);
      expect(context.fieldTypes.byId('physicsLayer'), same(mine));
      context.refreshDefinitions();
      expect(context.fieldTypes.byId('physicsLayer'), same(mine));
      expect(
        context.fieldTypes.byId('physicsLayerMask'),
        same(PhysicsDefinitions.layerMaskType),
      );
    });

    test('every physics field of the engine is of a registered type', () {
      final context = EngineContext(extensions: [BuiltInComponents.extension]);
      addTearDown(context.dispose);
      var seen = 0;
      for (final definition in context.definitions.definitions) {
        for (final field in definition.fields) {
          if (!ids.contains(field.kind.id)) continue;
          seen++;
          expect(
            context.fieldTypes.byId(field.kind.id),
            same(field.kind),
            reason: '${definition.type}.${field.name}',
          );
        }
      }
      expect(seen, greaterThan(0));
    });
  });
}

/// A project's own layer type, under the engine's id.
class _MyLayerFieldType extends PhysicsLayerFieldType {
  const _MyLayerFieldType();
}

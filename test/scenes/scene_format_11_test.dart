// Scene format 11 from the engine's side: a v10 scene naming components by
// their old names — on entities and inside a prefab instance's changes —
// loads as the renamed components with their saved values, and a kit's
// own rename through the context's migration rules is followed too. (Every
// rename target resolving, 3-D ones included, is in
// scene_format_11_3d_test.dart.)

import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_formats/just_game_engine_formats.dart'
    show V10ToV11;

/// [component] saved as the current format does, under the v10 [oldType].
Map<String, dynamic> _asV10(
  ComponentDefinitionRegistry defs,
  Component component,
  String oldType,
) => {...defs.encode(component)!, 'type': oldType};

class _KitThingComponent extends Component {
  int power = 0;
}

final _kitThing = ComponentDefinition<_KitThingComponent>(
  type: 'KitThingComponent',
  create: _KitThingComponent.new,
  fields: [
    FieldDefinition(
      name: 'power',
      kind: FieldTypes.integer,
      read: (c) => (c as _KitThingComponent).power,
      write: (c, v) => (c as _KitThingComponent).power = (v as num).toInt(),
    ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late World world;
  late ComponentDefinitionRegistry defs;
  setUp(() {
    world = World(extensions: [BuiltInComponents.extension]);
    defs = world.context.definitions;
  });
  tearDown(() => world.dispose());

  test('every 2-D rename target is a built-in definition', () {
    // The 3-D ones (named …3D…) need Graphics3D and Physics3D: see the
    // 3-D file.
    final twoD = {
      for (final MapEntry(key: old, value: renamed) in V10ToV11.renames.entries)
        if (!renamed.contains('3D')) old: renamed,
    };
    expect(twoD, hasLength(greaterThan(15)));
    expect([
      for (final MapEntry(key: old, value: renamed) in twoD.entries)
        if (defs.byName(renamed) == null) '$old → $renamed',
    ], isEmpty);
  });

  test('a v10 scene loads under the new names, with its values', () {
    final made = SceneLoader.load(world, {
      'version': 10,
      'entities': [
        {
          'name': 'Ball',
          'components': [
            _asV10(defs, TransformComponent(), 'TransformComponent'),
            _asV10(
              defs,
              RigidBody2DComponent(bodyType: BodyType.kinematic),
              'RigidBody2D',
            ),
            _asV10(defs, Collider2DComponent(), 'Collider2D'),
            _asV10(defs, Circle2DComponent(radius: 7), 'CircleComponent'),
            _asV10(defs, Light2DComponent(radius: 99), 'Light2D'),
          ],
        },
        {
          'name': 'Rope',
          'components': [
            _asV10(
              defs,
              Line2DComponent(end: const Offset(30, -4), strokeWidth: 3),
              'LineComponent',
            ),
          ],
        },
      ],
    });
    final ball = made.first;
    expect(
      ball.getComponent<RigidBody2DComponent>()!.bodyType,
      BodyType.kinematic,
    );
    expect(ball.hasComponent<Collider2DComponent>(), isTrue);
    // Shapes are filed as the entity's RenderableComponent.
    expect(
      (ball.getComponent<RenderableComponent>()! as Circle2DComponent).radius,
      7,
    );
    expect(ball.getComponent<Light2DComponent>()!.radius, 99);
    final rope =
        made.last.getComponent<RenderableComponent>()! as Line2DComponent;
    expect(rope.end, const Offset(30, -4));
    expect(rope.strokeWidth, 3);
  });

  test('a v10 scene\'s old field names load as the renamed members', () {
    final made = SceneLoader.load(world, {
      'version': 10,
      'entities': [
        {
          'name': 'Lamp',
          'components': [
            {
              'type': 'Light2D',
              'fields': {'colour': 0xFFFF0000, 'castsShadows': false},
            },
            {
              'type': 'AudioSourceComponent',
              'fields': {'clipPath': 'a.wav', 'is3d': true},
            },
            {
              'type': 'Material2D',
              'fields': {
                'material': 'm.material2d.json',
                'overrides': {'tint.colour': 0xFF00FF00, 'flash.amount': 1},
              },
            },
          ],
        },
      ],
    });
    final lamp = made.single;
    final light = lamp.getComponent<Light2DComponent>()!;
    expect(light.color, const Color(0xFFFF0000));
    expect(light.castShadows, isFalse, reason: 'the default is true');
    expect(lamp.getComponent<AudioSourceComponent>()!.is3D, isTrue);
    expect(lamp.getComponent<Material2DComponent>()!.overrides, {
      'tint.color': 0xFF00FF00,
      'flash.amount': 1,
    });
  });

  test("a v10 prefab instance's changes name the old types too", () async {
    const path = 'ball.prefab.json';
    world.context.overrideLoaders(
      prefabs: (_) async => PrefabFile(
        name: 'Ball',
        entities: [
          PrefabEntity(
            id: 'ball',
            name: 'Ball',
            components: [
              defs.encode(TransformComponent())!,
              defs.encode(Circle2DComponent(radius: 5))!,
              defs.encode(Collider2DComponent())!,
            ],
          ),
        ],
      ),
    );
    await world.context.prefabLibrary.load(path);
    final made = SceneLoader.load(world, {
      'version': 10,
      'entities': [
        {
          'name': 'Ball',
          'prefab': {
            'path': path,
            'overrides': [
              {
                'target': 'ball',
                'component': 'CircleComponent',
                'field': 'radius',
                'value': 9.0,
              },
            ],
            'addedComponents': [
              {
                'target': 'ball',
                'component': _asV10(defs, Light2DComponent(), 'Light2D'),
              },
            ],
            'removedComponents': [
              {
                'target': 'ball',
                'types': ['Collider2D'],
              },
            ],
          },
        },
      ],
    });
    final ball = made.single;
    expect(
      (ball.getComponent<RenderableComponent>()! as Circle2DComponent).radius,
      9,
    );
    expect(ball.hasComponent<Light2DComponent>(), isTrue);
    expect(ball.hasComponent<Collider2DComponent>(), isFalse);
  });

  test("a kit's rename through the context's rules is followed", () {
    world.context.definitions.register(_kitThing);
    world.context.migrations.renamedTypes['OldKitThing'] = 'KitThingComponent';
    final made = SceneLoader.load(world, {
      'version': 10,
      'entities': [
        {
          'name': 'Thing',
          'components': [
            {
              'type': 'OldKitThing',
              'fields': {'power': 4},
            },
          ],
        },
      ],
    });
    expect(made.single.getComponent<_KitThingComponent>()!.power, 4);
  });
}

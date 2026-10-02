// A physics body's settings, as the simulation takes them: one body type,
// collision layers and the project's grid, a collider that follows its
// entity's scale and offset, a start velocity, and material changes while
// the game runs — plus the v8 migration that brings older scenes along.

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  group('PhysicsLayers', () {
    test('start with Default on layer 0, everything colliding', () {
      final l = PhysicsLayers.defaults;
      expect(l.nameOf(0), 'Default');
      expect(l.labelOf(3), 'Layer 3');
      expect(l.named, [0]);
      expect(l.maskOf(5), PhysicsLayers.all);
      expect(l.collides(2, 9), isTrue);
    });

    test('a pair is set both ways, and survives a round trip', () {
      final l = PhysicsLayers.defaults
          .withName(1, 'Player')
          .withName(2, 'Coins')
          .withCollision(2, 2, false)
          .withCollision(1, 3, false);
      expect(l.collides(3, 1), isFalse);
      expect(l.collides(1, 2), isTrue);
      expect(l.collides(2, 2), isFalse);
      final json = l.toJson();
      expect(
        json['layers'],
        anyElement(
          equals({
            'index': 1,
            'name': 'Player',
            'ignores': [3],
          }),
        ),
      );
      expect(PhysicsLayers.fromJson(jsonDecode(jsonEncode(json))), l);
    });

    test('a layer keeps a colour and a description, and they round-trip', () {
      final l = PhysicsLayers.defaults
          .withName(2, 'Coins')
          .withColor(2, const Color(0xFFFFD54F))
          .withDescription(2, 'Collected by the player');
      expect(l.colorOf(2), const Color(0xFFFFD54F));
      expect(l.colorOf(3), PhysicsLayers.defaultColorOf(3));
      expect(l.descriptionOf(2), 'Collected by the player');
      expect(PhysicsLayers.fromJson(jsonDecode(jsonEncode(l.toJson()))), l);
      expect(l.sameGrid(PhysicsLayers.defaults), isTrue);
    });

    test('names are found case aside, and twins refused', () {
      final l = PhysicsLayers.defaults.withName(1, 'Player');
      expect(l.indexOf('player'), 1);
      expect(l.firstFree, 2);
      expect(l.problemWithName('PLAYER'), contains('already'));
      expect(l.problemWithName('Players'), contains('Too close'));
      expect(l.problemWithName('Player', except: 1), isNull);
      expect(l.problemWithName(''), isNotNull);
      expect(l.problemWithName('x' * 25), contains('24'));
    });

    test('a cleared layer is unused, and collides with everything again', () {
      final l = PhysicsLayers.defaults
          .withName(3, 'Ghost')
          .withColor(3, const Color(0xFF000000))
          .withCollision(3, 0, false)
          .cleared(3);
      expect(l.isNamed(3), isFalse);
      expect(l.ownColorOf(3), isNull);
      expect(l.collides(3, 0), isTrue);
      expect(l, PhysicsLayers.defaults);
    });

    test('unnaming layer 0 gives it its default name back', () {
      expect(PhysicsLayers.defaults.withName(0, '  ').nameOf(0), 'Default');
    });

    test('a file from a newer engine is refused', () {
      expect(
        () => PhysicsLayers.fromJson({'version': 99, 'layers': []}),
        throwsA(isA<UnsupportedFormatVersionException>()),
      );
    });

    test('a context reads them from its bundle, and keeps the defaults '
        'without the file', () async {
      final layers = PhysicsLayers.defaults.withName(4, 'Enemies');
      final ctx = EngineContext(
        bundle: _MapBundle({
          PhysicsLayers.defaultPath: jsonEncode(layers.toJson()),
        }),
      );
      await ctx.loadPhysicsLayers();
      expect(ctx.physicsLayers, layers);

      final bare = EngineContext(bundle: _MapBundle({}));
      await bare.loadPhysicsLayers();
      expect(bare.physicsLayers, PhysicsLayers.defaults);

      final broken = EngineContext(
        bundle: _MapBundle({PhysicsLayers.defaultPath: '{not json'}),
      );
      await broken.loadPhysicsLayers();
      expect(broken.physicsLayers, PhysicsLayers.defaults);
    });
  });

  group('scene format v7 → v8', () {
    Map<String, dynamic> scene(List<Map<String, dynamic>> components) => {
      'version': 7,
      'entities': [
        {'name': 'Box', 'components': components},
      ],
    };
    Map<String, dynamic> bodyOf(Map<String, dynamic> out) =>
        ((out['entities'] as List).single['components'] as List).firstWhere(
              (c) => c['type'] == 'PhysicsBodyComponent',
            )['fields']
            as Map<String, dynamic>;

    test('Static on becomes the static body type', () {
      final out = SceneFormat.migrate(
        scene([
          {
            'type': 'PhysicsBodyComponent',
            'fields': {'isStatic': true, 'bodyType': 'dynamic', 'drag': 0.5},
          },
        ]),
      );
      final f = bodyOf(out);
      expect(f['bodyType'], 'static');
      expect(f.containsKey('isStatic'), isFalse);
      expect(f['drag'], 0.5);
    });

    test('category and mask bits become a layer and its list', () {
      final out = SceneFormat.migrate(
        scene([
          {
            'type': 'PhysicsBodyComponent',
            'fields': {'categoryBits': 4, 'maskBits': 0xFFFF & ~2},
          },
        ]),
      );
      final f = bodyOf(out);
      expect(f['layer'], 2);
      expect(f['collidesWith'], 0xFFFF & ~2);
      expect(f.containsKey('categoryBits'), isFalse);
      // Every layer was the grid's answer anyway: left out.
      final all = bodyOf(
        SceneFormat.migrate(
          scene([
            {
              'type': 'PhysicsBodyComponent',
              'fields': {'categoryBits': 1, 'maskBits': 0xFFFF},
            },
          ]),
        ),
      );
      expect(all.containsKey('collidesWith'), isFalse);
      expect(all.containsKey('layer'), isFalse);
    });

    test('a body saved without drag keeps the old default', () {
      final f = bodyOf(
        SceneFormat.migrate(
          scene([
            {'type': 'PhysicsBodyComponent', 'fields': <String, dynamic>{}},
          ]),
        ),
      );
      expect(f['drag'], 0.98);
    });

    test("a scaled entity's collider is divided by its scale, and noted", () {
      final result = SceneFormat.migrateWithReport(
        scene([
          {
            'type': 'TransformComponent',
            'fields': {
              'scale': {'x': 2.0, 'y': 0.5, 'z': 1.0},
            },
          },
          {
            'type': 'PhysicsBodyComponent',
            'fields': {
              'shape': {'kind': 'rectangle', 'width': 64.0, 'height': 10.0},
            },
          },
        ]),
      );
      final shape = bodyOf(result.scene)['shape'] as Map;
      expect(shape['width'], 32);
      expect(shape['height'], 20);
      expect(result.notes.single.message, contains('scale'));
    });

    test('what it writes decodes through the definition', () {
      final out = SceneFormat.migrate(
        scene([
          {
            'type': 'PhysicsBodyComponent',
            'fields': {
              'shape': {'kind': 'circle', 'radius': 8.0},
              'isStatic': true,
              'categoryBits': 2,
              'maskBits': 1,
            },
          },
        ]),
      );
      final body =
          ComponentDefinitionRegistry.core().decode({
                'type': 'PhysicsBodyComponent',
                'fields': bodyOf(out),
              })
              as PhysicsBodyComponent;
      expect(body.bodyType, BodyType.static);
      expect(body.layer, 1);
      expect(body.collidesWith, 1);
    });
  });

  test('every new field round-trips through the definition', () {
    final registry = ComponentDefinitionRegistry.core();
    final body = PhysicsBodyComponent(
      shape: CircleShape(6, center: const Offset(1, 2)),
      offset: const Offset(3, -4),
      bodyType: BodyType.kinematic,
      friction: 0.7,
      angularDamping: 0.3,
      isBullet: true,
      canSleep: false,
      initialVelocity: const Offset(10, -20),
      initialAngularVelocity: 1.5,
      layer: 5,
      collidesWith: 0x21,
    );
    final json = jsonDecode(jsonEncode(registry.encode(body)));
    final back = registry.decode(json) as PhysicsBodyComponent;
    expect((back.shape as CircleShape).center, const Offset(1, 2));
    expect(back.offset, const Offset(3, -4));
    expect(back.bodyType, BodyType.kinematic);
    expect(back.friction, 0.7);
    expect(back.angularDamping, 0.3);
    expect(back.isBullet, isTrue);
    expect(back.canSleep, isFalse);
    expect(back.initialVelocity, const Offset(10, -20));
    expect(back.initialAngularVelocity, 1.5);
    expect(back.layer, 5);
    expect(back.collidesWith, 0x21);

    final grid =
        registry.decode(
              jsonDecode(
                jsonEncode(
                  registry.encode(PhysicsBodyComponent(shape: CircleShape(4))),
                ),
              ),
            )
            as PhysicsBodyComponent;
    expect(grid.collidesWith, isNull);
    expect(grid.drag, 0);
  });

  group('ColliderGeometry', () {
    test('an off-centre box is a polygon, a centred one stays a box', () {
      final moved = ColliderGeometry.build(
        RectangleShape(10, 4),
        offset: const Offset(5, 0),
      );
      expect(moved, isNot(isA<RectangleShape>()));
      expect(
        ColliderGeometry.boundsOf(moved),
        const Rect.fromLTRB(0, -2, 10, 2),
      );
      expect(
        ColliderGeometry.build(RectangleShape(10, 4), sx: 2),
        isA<RectangleShape>().having((r) => r.width, 'width', 20),
      );
    });

    test('a circle grows by the larger factor; a mirrored polygon keeps '
        'its winding', () {
      final c = ColliderGeometry.build(CircleShape(5), sx: 2, sy: 3);
      expect((c as CircleShape).radius, 15);
      final tri = PolygonShape(const [
        Offset(0, 0),
        Offset(10, 0),
        Offset(0, 10),
      ]);
      final m = ColliderGeometry.build(tri, sx: -1) as PolygonShape;
      expect(m.vertices, const [Offset(0, 10), Offset(-10, 0), Offset(0, 0)]);
    });
  });

  group('PhysicsSystem', () {
    late PhysicsEngine physics;
    late World world;

    setUp(() {
      physics = PhysicsEngine()..initialize();
      physics.setGravity(0, 2200);
      world = World()..initialize();
      world.addSystem(PhysicsSystem(physics));
    });
    tearDown(() {
      world.dispose();
      physics.dispose();
    });

    /// A 200 × 20 floor centred on the origin: its top is at y = −10.
    Entity floor({
      int layer = 0,
      Offset offset = Offset.zero,
      double scaleY = 1,
      double restitution = 0,
    }) => world.createEntityWithComponents([
      TransformComponent(
        position: Vector3(0, 0, 0),
        scale: Vector3(1, scaleY, 1),
      ),
      PhysicsBodyComponent(
        shape: RectangleShape(200, 20),
        bodyType: BodyType.static,
        offset: offset,
        layer: layer,
        restitution: restitution,
      ),
    ], name: 'floor');

    Entity ball({int layer = 0, int? collidesWith, double restitution = 0}) =>
        world.createEntityWithComponents([
          TransformComponent(position: Vector3(0, -150, 0)),
          PhysicsBodyComponent(
            shape: CircleShape(10),
            restitution: restitution,
            layer: layer,
            collidesWith: collidesWith,
            fixedRotation: true,
          ),
        ], name: 'ball');

    double run(Entity e, [int frames = 90]) {
      for (var i = 0; i < frames; i++) {
        world.update(1 / 60);
      }
      return e.getComponent<TransformComponent>()!.position.y;
    }

    test('layers the grid keeps apart pass through each other', () {
      world.context.physicsLayers = PhysicsLayers.defaults.withCollision(
        1,
        2,
        false,
      );
      floor(layer: 1);
      expect(run(ball(layer: 2)), greaterThan(100));
    });

    test("a body's own list wins over the grid, both ways", () {
      floor(layer: 1);
      // Ignores layer 1, though the grid says it collides.
      expect(run(ball(layer: 2, collidesWith: 0xFFFF & ~2)), greaterThan(100));
    });

    test('a new grid refilters bodies already in the game', () {
      floor(layer: 1);
      final b = ball(layer: 2);
      expect(run(b), closeTo(-20, 1));
      world.context.physicsLayers = PhysicsLayers.defaults.withCollision(
        1,
        2,
        false,
      );
      expect(run(b, 60), greaterThan(100));
    });

    test("the collider grows with its entity's scale", () {
      final f = floor(scaleY: 2);
      final b = ball();
      expect(run(b), closeTo(-30, 1));
      // Scaled again while the game runs: built again, lifting the ball.
      f.getComponent<TransformComponent>()!.scale.y = 4;
      expect(run(b, 60), closeTo(-50, 1));
    });

    test('a mirrored box is not built again', () {
      final f = floor();
      run(ball(), 2);
      final before = f.getComponent<PhysicsBodyRefComponent>()!.body;
      f.getComponent<TransformComponent>()!.scale.x = -1;
      run(ball(), 2);
      expect(
        identical(f.getComponent<PhysicsBodyRefComponent>()!.body, before),
        isTrue,
      );
    });

    test('the offset moves the collider off the entity', () {
      floor(offset: const Offset(0, -20));
      expect(run(ball()), closeTo(-40, 1));
    });

    test(
      'a body starts with its start velocity, velocity component and all',
      () {
        final e = world.createEntityWithComponents([
          TransformComponent(position: Vector3(0, 0, 0)),
          VelocityComponent(),
          PhysicsBodyComponent(
            shape: CircleShape(5),
            gravityScale: 0,
            initialVelocity: const Offset(120, 0),
          ),
        ]);
        for (var i = 0; i < 30; i++) {
          world.update(1 / 60);
        }
        expect(
          e.getComponent<TransformComponent>()!.position.x,
          closeTo(60, 3),
        );
      },
    );

    test('bounciness changed while the game runs reaches the simulation', () {
      final f = floor();
      final b = ball();
      world.update(1 / 60);
      f.getComponent<PhysicsBodyComponent>()!.restitution = 1;
      b.getComponent<PhysicsBodyComponent>()!.restitution = 1;
      var rose = false;
      for (var i = 0; i < 90; i++) {
        world.update(1 / 60);
        final v = b.getComponent<PhysicsBodyRefComponent>()!.body.velocity.y;
        if (v < -100) rose = true;
      }
      expect(rose, isTrue);
    });

    test('friction changed while the game runs reaches the simulation', () {
      final f = floor();
      double slide(double friction) {
        final crate = world.createEntityWithComponents([
          TransformComponent(position: Vector3(-80, -20, 0)),
          PhysicsBodyComponent(
            shape: RectangleShape(20, 20),
            restitution: 0,
            fixedRotation: true,
            initialVelocity: const Offset(150, 0),
          ),
        ]);
        f.getComponent<PhysicsBodyComponent>()!.friction = friction;
        crate.getComponent<PhysicsBodyComponent>()!.friction = friction;
        run(crate, 60);
        final out = crate.getComponent<TransformComponent>()!.position.x;
        world.destroyEntity(crate);
        world.update(1 / 60);
        return out;
      }

      final grippy = slide(1);
      final icy = slide(0);
      expect(icy, greaterThan(grippy + 50));
    });

    test('the outline says what kind of body it is', () {
      PhysicsBodyComponent b(BodyType t, {bool sensor = false}) =>
          PhysicsBodyComponent(
            shape: CircleShape(1),
            bodyType: t,
            isSensor: sensor,
          );
      final kinds = {
        for (final t in BodyType.values)
          t: PhysicsSystem.debugPaintFor(b(t)).color,
      };
      expect(kinds.values.toSet(), hasLength(3));
      expect(
        PhysicsSystem.debugPaintFor(b(BodyType.static, sensor: true)).color,
        isNot(kinds[BodyType.static]),
      );
    });
  });
}

/// Files from a map, for a context's bundle.
class _MapBundle extends CachingAssetBundle {
  _MapBundle(this.files);
  final Map<String, String> files;

  @override
  Future<ByteData> load(String key) async {
    final text = files[key];
    if (text == null) throw StateError('no $key');
    return ByteData.sublistView(utf8.encode(text));
  }
}

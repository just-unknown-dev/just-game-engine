// A physics body's settings, as the simulation takes them: one body type,
// collision layers and the project's grid, a collider that follows its
// entity's scale and offset, a start velocity, and material changes while
// the game runs — plus the v8 migration that brings older scenes along.

import 'dart:convert';
import 'dart:math' as math;

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
    // Only the v7 → v8 step: what came after it is checked below.
    (Map<String, dynamic>, MigrationRun) v8(Map<String, dynamic> json) {
      final run = MigrationRun(MigrationHooks.none);
      return (const V7ToV8().apply(jsonDecode(jsonEncode(json)) as Map<String, dynamic>, run), run);
    }

    Map<String, dynamic> bodyOf(Map<String, dynamic> out) =>
        ((out['entities'] as List).single['components'] as List).firstWhere(
              (c) => c['type'] == 'PhysicsBodyComponent',
            )['fields']
            as Map<String, dynamic>;

    test('Static on becomes the static body type', () {
      final (out, _) = v8(
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
      final (out, _) = v8(
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
        v8(
          scene([
            {
              'type': 'PhysicsBodyComponent',
              'fields': {'categoryBits': 1, 'maskBits': 0xFFFF},
            },
          ]),
        ).$1,
      );
      expect(all.containsKey('collidesWith'), isFalse);
      expect(all.containsKey('layer'), isFalse);
    });

    test('a body saved without drag keeps the old default', () {
      final f = bodyOf(
        v8(
          scene([
            {'type': 'PhysicsBodyComponent', 'fields': <String, dynamic>{}},
          ]),
        ).$1,
      );
      expect(f['drag'], 0.98);
    });

    test("a scaled entity's collider is divided by its scale, and noted", () {
      final (out, run) = v8(
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
      final shape = bodyOf(out)['shape'] as Map;
      expect(shape['width'], 32);
      expect(shape['height'], 20);
      expect(run.notes.single.message, contains('scale'));
    });

    test('carried on to v9, what it writes decodes as a rigid body and a collider', () {
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
      final components = (out['entities'] as List).single['components'] as List;
      final registry = ComponentDefinitionRegistry.core();
      final rigid = registry.decode(components[0] as Map<String, dynamic>) as RigidBody2D;
      final collider = registry.decode(components[1] as Map<String, dynamic>) as Collider2D;
      expect(rigid.bodyType, BodyType.static);
      expect(rigid.layer, 1);
      expect(rigid.collidesWith, 1);
      expect(rigid.linearDamping, 0.98, reason: "v7's default drag, kept");
      expect(collider.shape, ColliderShape2D.circle);
      expect(collider.radius, 8);
    });
  });

  group('scene format v8 → v9', () {
    List<Map<String, dynamic>> migrate(Map<String, dynamic> fields, [String type = 'PhysicsBodyComponent']) {
      final out = SceneFormat.migrate({
        'version': 8,
        'entities': [
          {
            'name': 'Box',
            'components': [
              {'type': type, 'fields': fields},
            ],
          },
        ],
      });
      return [...((out['entities'] as List).single['components'] as List).cast<Map<String, dynamic>>()];
    }

    test('a body becomes a rigid body and a collider, under the 3-D names', () {
      final [rigid, collider] = migrate({
        'shape': {'kind': 'rectangle', 'width': 40.0, 'height': 10.0},
        'offset': {'dx': 1.0, 'dy': 2.0},
        'drag': 0.3,
        'fixedRotation': true,
        'isBullet': true,
        'isOneWay': true,
        'oneWayDirection': 'fromBelow',
      });
      expect(rigid['type'], 'RigidBody2D');
      expect(collider['type'], 'Collider2D');
      final r = rigid['fields'] as Map, c = collider['fields'] as Map;
      expect((r['linearDamping'], r['lockRotation'], r['continuousCollision']), (0.3, true, true));
      expect((r['friction'], r['restitution']), (0.2, 0.8), reason: 'the defaults it was saved with');
      expect(c['shape'], 'box');
      expect(c['size'], {'x': 40.0, 'y': 10.0});
      expect(c['offset'], {'dx': 1.0, 'dy': 2.0});
      expect((c['oneWay'], c['oneWayDirection']), (true, 'fromBelow'));
    });

    test("a circle's centre and a capsule's middle join the offset; a lying capsule is turned", () {
      final circle = migrate({
        'shape': {
          'kind': 'circle',
          'radius': 5.0,
          'center': {'dx': 3.0, 'dy': 0.0},
        },
        'offset': {'dx': 1.0, 'dy': 0.0},
      })[1]['fields'] as Map;
      expect(circle['offset'], {'dx': 4.0, 'dy': 0.0});
      final capsule = migrate({
        'shape': {
          'kind': 'capsule',
          'center1': {'dx': -10.0, 'dy': 0.0},
          'center2': {'dx': 10.0, 'dy': 0.0},
          'radius': 4.0,
        },
      })[1]['fields'] as Map;
      expect(capsule['height'], 28.0);
      expect((capsule['rotation'] as double).abs(), closeTo(math.pi / 2, 1e-9));
      final shape = ColliderGeometry.shapeOf(
        ComponentDefinitionRegistry.core().decode({'type': 'Collider2D', 'fields': capsule}) as Collider2D,
      )!;
      final placed = ColliderGeometry.build(shape, rotation: capsule['rotation'] as double) as CapsuleShape;
      expect(placed.center1.dx.abs(), closeTo(10, 1e-9), reason: 'lying as it was');
      expect(placed.center1.dy, closeTo(0, 1e-9));
    });

    test('a rounded rectangle stays a box; polygons and chains keep their points', () {
      final box = migrate({
        'shape': {
          'kind': 'rounded_polygon',
          'vertices': [
            {'dx': -10.0, 'dy': -5.0},
            {'dx': 10.0, 'dy': -5.0},
            {'dx': 10.0, 'dy': 5.0},
            {'dx': -10.0, 'dy': 5.0},
          ],
          'cornerRadius': 2.0,
        },
      })[1]['fields'] as Map;
      expect(box['shape'], 'box');
      expect(box['size'], {'x': 24.0, 'y': 14.0});
      expect(box['cornerRadius'], 2.0);
      final chain = migrate({
        'shape': {
          'kind': 'chain',
          'vertices': [
            {'dx': 0.0, 'dy': 0.0},
            {'dx': 5.0, 'dy': 1.0},
          ],
          'loop': true,
          'thickness': 3.0,
        },
      })[1]['fields'] as Map;
      expect((chain['shape'], chain['loop'], chain['thickness']), ('chain', true, 3.0));
      expect((chain['points'] as List), hasLength(2));
    });

    test('joints take their new names, their target a target', () {
      final [weld] = migrate({'targetEntityName': 'B', 'localAnchorB': {'dx': 4.0, 'dy': 0.0}}, 'WeldJointComponent');
      expect(weld['type'], 'FixedJoint2D');
      expect(weld['fields']['connectedBody'], {'name': 'B'});
      expect(weld['fields']['connectedAnchor'], {'dx': 4.0, 'dy': 0.0});
      final [slider] = migrate({'enableLimit': true, 'lowerTranslation': -3.0, 'maxMotorForce': 9.0}, 'PrismaticJointComponent');
      expect(slider['type'], 'SliderJoint2D');
      expect((slider['fields']['useLimits'], slider['fields']['minPosition'], slider['fields']['motorMaxForce']), (true, -3.0, 9.0));
      final [wheel] = migrate({'targetEntityName': '', 'suspensionAxis': {'dx': 0.0, 'dy': 1.0}}, 'WheelJointComponent');
      expect(wheel['type'], 'WheelJoint2D');
      expect(wheel['fields']['connectedBody'], isNull);
      expect(wheel['fields']['axis'], {'dx': 0.0, 'dy': 1.0});
      final registry = ComponentDefinitionRegistry.core();
      expect(registry.decode(weld), isA<FixedJoint2D>());
      expect((registry.decode(slider) as SliderJoint2D).minPosition, -3);
    });
  });

  test('every field round-trips through the definitions', () {
    final registry = ComponentDefinitionRegistry.core();
    final body = RigidBody2D(
      bodyType: BodyType.kinematic,
      friction: 0.7,
      angularDamping: 0.3,
      continuousCollision: true,
      canSleep: false,
      initialVelocity: const Offset(10, -20),
      initialAngularVelocity: 1.5,
      layer: 5,
      collidesWith: 0x21,
    );
    final back = registry.decode(jsonDecode(jsonEncode(registry.encode(body)))) as RigidBody2D;
    expect(back.bodyType, BodyType.kinematic);
    expect(back.friction, 0.7);
    expect(back.angularDamping, 0.3);
    expect(back.continuousCollision, isTrue);
    expect(back.canSleep, isFalse);
    expect(back.initialVelocity, const Offset(10, -20));
    expect(back.initialAngularVelocity, 1.5);
    expect(back.layer, 5);
    expect(back.collidesWith, 0x21);

    final collider = Collider2D(shape: ColliderShape2D.circle, radius: 6, offset: const Offset(3, -4));
    final c = registry.decode(jsonDecode(jsonEncode(registry.encode(collider)))) as Collider2D;
    expect((c.shape, c.radius, c.offset), (ColliderShape2D.circle, 6.0, const Offset(3, -4)));

    final grid = registry.decode(jsonDecode(jsonEncode(registry.encode(RigidBody2D())))) as RigidBody2D;
    expect(grid.collidesWith, isNull);
    // 3-D's defaults: worked out from the collider, a little damping.
    expect(grid.mass, 0);
    expect(grid.linearDamping, 0.05);
    expect(grid.angularDamping, 0.05);
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

    test("a collider's shape: its own fields, turned, its own scale", () {
      final box = ColliderGeometry.of(Collider2D(size: Vector2(10, 4), rotation: math.pi / 2))!;
      final bounds = ColliderGeometry.boundsOf(box);
      expect(bounds.width, closeTo(4, 1e-9));
      expect(bounds.height, closeTo(10, 1e-9));
      final circle = ColliderGeometry.of(Collider2D(shape: ColliderShape2D.circle, radius: 3, scale: Vector2(2, 1)))!;
      expect((circle as CircleShape).radius, 6);
      final rounded = ColliderGeometry.of(Collider2D(size: Vector2(20, 10), cornerRadius: 2))!;
      expect(ColliderGeometry.boundsOf(rounded).width, closeTo(20, 1e-9), reason: 'rounded inside its size');
      expect(ColliderGeometry.of(Collider2D(shape: ColliderShape2D.polygon, points: const [Offset.zero])), isNull);
    });

    test('matching the shape: what the entity draws', () {
      final world = World()..initialize();
      addTearDown(world.dispose);
      final collider = Collider2D(shape: ColliderShape2D.matchShape);
      final e = world.createEntityWithComponents([
        TransformComponent(),
        CircleComponent(radius: 12),
        collider,
      ]);
      expect((ColliderGeometry.shapeOf(collider, entity: e) as CircleShape).radius, 12);
      final rect = world.createEntityWithComponents([
        TransformComponent(),
        RectangleComponent(width: 30, height: 10),
      ]);
      expect(ColliderGeometry.visualShapeOf(rect), isA<RectangleShape>());
      expect(ColliderGeometry.visualKeyOf(rect), ('box', 30.0, 10.0, 0.0));
      expect(ColliderGeometry.shapeOf(collider), isNull, reason: 'no entity, nothing to match');
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
      RigidBody2D(bodyType: BodyType.static, layer: layer, restitution: restitution),
      Collider2D(size: Vector2(200, 20), offset: offset),
    ], name: 'floor');

    Entity ball({int layer = 0, int? collidesWith, double restitution = 0}) =>
        world.createEntityWithComponents([
          TransformComponent(position: Vector3(0, -150, 0)),
          RigidBody2D(
            restitution: restitution,
            layer: layer,
            collidesWith: collidesWith,
            lockRotation: true,
          ),
          Collider2D(shape: ColliderShape2D.circle, radius: 10),
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

    test('a collider alone is a static body', () {
      world.createEntityWithComponents([TransformComponent(), Collider2D(size: Vector2(200, 20))]);
      expect(run(ball()), closeTo(-20, 1));
    });

    test('a collider matching what its entity draws, following it as it changes', () {
      final rect = RectangleComponent(width: 200, height: 20);
      world.createEntityWithComponents([
        TransformComponent(),
        rect,
        RigidBody2D(bodyType: BodyType.static),
        Collider2D(shape: ColliderShape2D.matchShape),
      ]);
      final b = ball();
      expect(run(b), closeTo(-20, 1));
      rect.height = 60;
      expect(run(b, 60), closeTo(-40, 1));
    });

    test(
      'a body starts with its start velocity, velocity component and all',
      () {
        final e = world.createEntityWithComponents([
          TransformComponent(position: Vector3(0, 0, 0)),
          VelocityComponent(),
          RigidBody2D(gravityScale: 0, initialVelocity: const Offset(120, 0)),
          Collider2D(shape: ColliderShape2D.circle, radius: 5),
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

    test('gameplay moves a body through its rigid body: velocity, impulse, force', () {
      final rigid = RigidBody2D(gravityScale: 0, mass: 1, linearDamping: 0);
      final e = world.createEntityWithComponents([
        TransformComponent(),
        rigid,
        Collider2D(shape: ColliderShape2D.circle, radius: 5),
      ]);
      world.update(1 / 60);
      rigid.setVelocity(const Offset(60, 0));
      run(e, 30);
      expect(e.getComponent<TransformComponent>()!.position.x, closeTo(30, 2));
      expect(rigid.linearVelocity.dx, closeTo(60, 1e-6));
      rigid.addImpulse(const Offset(0, 120));
      world.update(1 / 60);
      expect(rigid.linearVelocity.dy, closeTo(120 / rigid.mass, 1e-6));
      rigid
        ..setVelocity(Offset.zero)
        ..addForce(const Offset(600, 0));
      world.update(1 / 60);
      expect(rigid.linearVelocity.dx, greaterThan(0), reason: 'pushed for one step');
      expect(rigid.pendingForce, Offset.zero, reason: 'used up');
    });

    test('a mass of 0 is worked out from the collider, as in 3-D', () {
      Entity crate(double mass, Collider2D collider) => world.createEntityWithComponents([
        TransformComponent(),
        RigidBody2D(mass: mass, gravityScale: 0),
        collider,
      ]);
      final square = crate(0, Collider2D(size: Vector2(100, 100)));
      final ball = crate(0, Collider2D(shape: ColliderShape2D.circle, radius: 10));
      final set = crate(3, Collider2D(size: Vector2(100, 100)));
      world.update(1 / 60);
      double massOf(Entity e) => e.getComponent<PhysicsBodyRefComponent>()!.body.mass;
      expect(massOf(square), closeTo(1000, 1e-6), reason: 'a 1 m square weighs what a 1 m cube does');
      expect(massOf(ball), closeTo(math.pi * 100 * PhysicsSystem.autoMassPerSquareUnit, 1e-6));
      expect(massOf(set), 3, reason: 'a mass that is set is kept');
    });

    test('a kinematic body keeps its speed: damping slows only a dynamic one', () {
      final platform = RigidBody2D(bodyType: BodyType.kinematic, linearDamping: 1);
      final e = world.createEntityWithComponents([
        TransformComponent(),
        platform,
        Collider2D(size: Vector2(64, 16)),
      ]);
      world.update(1 / 60);
      platform.setVelocity(const Offset(60, 0));
      run(e, 60);
      expect(e.getComponent<PhysicsBodyRefComponent>()!.body.velocity.x, closeTo(60, 1e-6));
    });

    test('bounciness changed while the game runs reaches the simulation', () {
      final f = floor();
      final b = ball();
      world.update(1 / 60);
      f.getComponent<RigidBody2D>()!.restitution = 1;
      b.getComponent<RigidBody2D>()!.restitution = 1;
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
          RigidBody2D(
            restitution: 0,
            lockRotation: true,
            initialVelocity: const Offset(150, 0),
          ),
          Collider2D(size: Vector2(20, 20)),
        ]);
        f.getComponent<RigidBody2D>()!.friction = friction;
        crate.getComponent<RigidBody2D>()!.friction = friction;
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

    test('contacts and sensors are reported as the 3-D ones are', () {
      world.createEntityWithComponents([
        TransformComponent(position: Vector3(0, -60, 0)),
        RigidBody2D(bodyType: BodyType.static, isSensor: true),
        Collider2D(size: Vector2(200, 20)),
      ], name: 'zone');
      floor();
      final b = ball();
      final enters = <CollisionEnter2DEvent>[];
      final sensors = <SensorEnter2DEvent>[];
      final stays = <CollisionStay2DEvent>[];
      world.events
        ..on<CollisionEnter2DEvent>(enters.add)
        ..on<SensorEnter2DEvent>(sensors.add)
        ..on<CollisionStay2DEvent>(stays.add);
      world.getSystem<PhysicsSystem>()!.reportContactStay = true;
      run(b, 90);
      expect(sensors.single.other, b);
      expect(sensors.single.sensor.name, 'zone');
      final hit = enters.firstWhere((e) => e.entityA == b || e.entityB == b);
      expect(hit.point.dy, closeTo(-10, 2), reason: "where the ball meets the floor's top");
      expect(stays, isNotEmpty, reason: 'resting on the floor');
      expect(b.getComponent<RigidBody2D>()!.isGrounded, isTrue);
    });

    test('the outline says what kind of body it is', () {
      RigidBody2D b(BodyType t, {bool sensor = false}) => RigidBody2D(bodyType: t, isSensor: sensor);
      final kinds = {
        for (final t in BodyType.values)
          t: PhysicsSystem.debugPaintFor(b(t)).color,
      };
      expect(kinds.values.toSet(), hasLength(3));
      expect(
        PhysicsSystem.debugPaintFor(b(BodyType.static, sensor: true)).color,
        isNot(kinds[BodyType.static]),
      );
      expect(PhysicsSystem.debugPaintFor(null).color, kinds[BodyType.static], reason: 'a collider alone is static');
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

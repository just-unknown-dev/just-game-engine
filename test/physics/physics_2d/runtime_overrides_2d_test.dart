// Gameplay that changes a 2-D body for a while — a platformer's jump
// gravities, a crumbled platform — sets a run-time override, never the
// saved field. Components are the save format: a level saved mid-jump used
// to keep the gravity scale of the frame it was saved in, and one saved
// mid-collapse a platform that collided with nothing.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

const _frame = 1 / 60;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final (backend, make) in [
    ('native Box2D', PhysicsEngineFactory.create2D),
    ('pure Dart', Physics2DEngine.pureDart),
  ]) {
    group('on $backend', () {
      late Physics2DEngine physics;
      late World world;

      setUp(() {
        physics = make()..initialize();
        physics.setGravity(0, 1000);
        world = World()..initialize();
        world.addSystem(Physics2DSystem(physics));
      });
      tearDown(() {
        world.dispose();
        physics.dispose();
      });

      void step([int frames = 1]) {
        for (var i = 0; i < frames; i++) {
          world.update(_frame);
        }
      }

      Entity box({
        double x = 0,
        double y = 0,
        double gravityScale = 1,
        double? override,
      }) => world.createEntityWithComponents([
        TransformComponent(position: Vector3(x, y, 0)),
        RigidBody2DComponent(
          gravityScale: gravityScale,
          linearDamping: 0,
          restitution: 0,
          lockRotation: true,
        )..gravityScaleOverride = override,
        Collider2DComponent(size: Vector2(20, 20)),
      ]);

      RigidBody2DComponent rigidOf(Entity e) =>
          e.getComponent<RigidBody2DComponent>()!;
      Physics2DBody bodyOf(Entity e) =>
          e.getComponent<Physics2DBodyRefComponent>()!.body;
      double yOf(Entity e) => e.getComponent<TransformComponent>()!.position.y;

      test('a gravity scale override moves a body as that saved scale '
          'would, and is never written into it', () {
        // Each pair far apart: one overridden, its twin saved with the
        // value the override stands for.
        final overridden = box(override: 2.5);
        final twin = box(x: 1000, gravityScale: 2.5);
        expect(rigidOf(overridden).effectiveGravityScale, 2.5);
        step(20);
        expect(bodyOf(overridden).gravityScale, 2.5, reason: 'made with it');
        expect(yOf(overridden), closeTo(yOf(twin), 1e-9));
        expect(yOf(overridden), greaterThan(10));

        // Changed on a live body, as a jump changes it every step.
        rigidOf(overridden).gravityScaleOverride = 0.5;
        rigidOf(twin).gravityScale = 0.5;
        step(20);
        expect(bodyOf(overridden).gravityScale, 0.5);
        expect(yOf(overridden), closeTo(yOf(twin), 1e-9));

        // Cleared: the saved scale again.
        rigidOf(overridden).gravityScaleOverride = null;
        rigidOf(twin).gravityScale = 1;
        step(20);
        expect(bodyOf(overridden).gravityScale, 1);
        expect(yOf(overridden), closeTo(yOf(twin), 1e-9));

        expect(
          rigidOf(overridden).gravityScale,
          1,
          reason: 'the saved scale stays as authored throughout',
        );
      });

      test('a weightless override holds a body still; cleared, it falls', () {
        final floater = box(override: 0);
        step(30);
        expect(yOf(floater), closeTo(0, 1e-6));
        rigidOf(floater).gravityScaleOverride = null;
        step(30);
        expect(yOf(floater), greaterThan(10));
        expect(rigidOf(floater).gravityScale, 1);
      });

      test('a body that collides with nothing lets what falls on it '
          'through; switched back, its saved list is back', () {
        // Its own list (layers 0 and 1), not the grid: what comes back.
        final platform = world.createEntityWithComponents([
          TransformComponent(position: Vector3(0, 200, 0)),
          RigidBody2DComponent(
            bodyType: Body2DType.static,
            restitution: 0,
            collidesWith: 0x3,
          ),
          Collider2DComponent(size: Vector2(400, 20)),
        ], name: 'Platform');
        final rigid = rigidOf(platform);
        rigid.collidesWithNothing = true;
        expect(rigid.effectiveCollidesWith, 0);
        final first = box();
        step(60);
        expect(bodyOf(platform).maskBits, 0);
        expect(yOf(first), greaterThan(260), reason: 'fell through it');
        expect(rigid.collidesWith, 0x3, reason: 'its saved list stays');

        rigid.collidesWithNothing = false;
        expect(rigid.effectiveCollidesWith, 0x3);
        final second = box(x: 100);
        step(90);
        expect(bodyOf(platform).maskBits, 0x3);
        expect(yOf(second), closeTo(180, 1), reason: 'resting on its top');
        expect(rigid.collidesWith, 0x3);
      });

      test('a character with a gravity scale override falls as that saved '
          'scale would, and keeps its own', () {
        Entity hero(double x, {double gravityScale = 1, double? override}) =>
            world.createEntityWithComponents([
              TransformComponent(position: Vector3(x, 0, 0)),
              CharacterBody2DComponent(gravityScale: gravityScale)
                ..gravityScaleOverride = override,
            ]);
        final overridden = hero(0, override: 0.25);
        final twin = hero(1000, gravityScale: 0.25);
        final comp = overridden.getComponent<CharacterBody2DComponent>()!;
        expect(comp.effectiveGravityScale, 0.25);
        step(20);
        expect(yOf(overridden), closeTo(yOf(twin), 1e-9));
        expect(yOf(overridden), greaterThan(1));

        comp.gravityScaleOverride = null;
        twin.getComponent<CharacterBody2DComponent>()!.gravityScale = 1;
        step(20);
        expect(yOf(overridden), closeTo(yOf(twin), 1e-9));
        expect(comp.gravityScale, 1, reason: 'never written');
      });
    });
  }

  group('saving', () {
    final definitions = BuiltInComponents.registry();

    String saved(Component c) => jsonEncode(definitions.encode(c));

    test('a rigid body saves its authored gravity scale and list, '
        'not the overrides', () {
      final overridden =
          RigidBody2DComponent(gravityScale: 0.75, collidesWith: 0x5)
            ..gravityScaleOverride = 2
            ..collidesWithNothing = true;
      final json = definitions.encode(overridden)!;
      final fields = json['fields'] as Map<String, dynamic>;
      expect((fields['gravityScale'], fields['collidesWith']), (0.75, 0x5));
      expect(
        saved(overridden),
        saved(RigidBody2DComponent(gravityScale: 0.75, collidesWith: 0x5)),
        reason: 'exactly what the authored body saves',
      );
      final definition = definitions.definitionFor(overridden)!;
      for (final name in const [
        'gravityScaleOverride',
        'effectiveGravityScale',
        'collidesWithNothing',
        'effectiveCollidesWith',
      ]) {
        expect(definition.fields.map((f) => f.name), isNot(contains(name)));
        expect(definition.hints.fields.keys, isNot(contains(name)));
      }

      final loaded = definitions.decode(json)! as RigidBody2DComponent;
      expect(
        (
          loaded.gravityScale,
          loaded.gravityScaleOverride,
          loaded.effectiveGravityScale,
        ),
        (0.75, null, 0.75),
      );
      expect(
        (
          loaded.collidesWith,
          loaded.collidesWithNothing,
          loaded.effectiveCollidesWith,
        ),
        (0x5, false, 0x5),
      );
    });

    test('a character saves its authored gravity scale, not the override', () {
      final overridden = CharacterBody2DComponent(gravityScale: 1.5)
        ..gravityScaleOverride = 3;
      final json = definitions.encode(overridden)!;
      expect((json['fields'] as Map)['gravityScale'], 1.5);
      expect(
        saved(overridden),
        saved(CharacterBody2DComponent(gravityScale: 1.5)),
      );
      final definition = definitions.definitionFor(overridden)!;
      expect(
        definition.fields.map((f) => f.name),
        isNot(contains('gravityScaleOverride')),
      );
      final loaded = definitions.decode(json)! as CharacterBody2DComponent;
      expect(
        (
          loaded.gravityScale,
          loaded.gravityScaleOverride,
          loaded.effectiveGravityScale,
        ),
        (1.5, null, 1.5),
      );
    });
  });
}

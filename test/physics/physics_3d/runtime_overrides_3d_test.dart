// The 3-D twin of the 2-D run-time overrides: gameplay that changes a
// body's or a character's gravity for a while sets `gravityScaleOverride`,
// and the saved `gravityScale` stays as authored. On the fake backend and
// on Jolt.

@Tags(['physics3d'])
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/just_game_engine_3d.dart';
import 'package:just_physics_engine/testing.dart';

const _dt = 1 / 60;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final (backend, make) in <(String, Physics3DWorld Function())>[
    ('the fake backend', () => FakePhysics3DWorld(Physics3DWorldSettings())),
    ('Jolt', () => JoltPhysicsEngine().createWorld(Physics3DWorldSettings())),
  ]) {
    group('on $backend', () {
      late Physics3DWorld physics;
      late World world;

      setUp(() {
        physics = make();
        world = World()..initialize();
        world.addSystem(Physics3DSystem(physics));
      });
      tearDown(() {
        world.dispose();
        physics.dispose();
      });

      void step(int frames) {
        for (var i = 0; i < frames; i++) {
          world.update(_dt);
        }
      }

      double yOf(Entity e) => e.getComponent<TransformComponent>()!.position.y;

      test('a gravity scale override moves a body as that saved scale '
          'would, and is never written into it', () {
        Entity box(double x, {double gravityScale = 1, double? override}) =>
            world.createEntityWithComponents([
              TransformComponent(position: Vector3(x, 0, 0)),
              Collider3DComponent(),
              RigidBody3DComponent(
                gravityScale: gravityScale,
                linearDamping: 0,
                canSleep: false,
              )..gravityScaleOverride = override,
            ]);
        final overridden = box(0, override: 2.5);
        final twin = box(50, gravityScale: 2.5);
        final rigid = overridden.getComponent<RigidBody3DComponent>()!;
        expect(rigid.effectiveGravityScale, 2.5);
        step(20);
        expect(yOf(overridden), closeTo(yOf(twin), 1e-6));
        expect(yOf(overridden), greaterThan(0.5));

        // Changed on a live body.
        rigid.gravityScaleOverride = 0.5;
        twin.getComponent<RigidBody3DComponent>()!.gravityScale = 0.5;
        step(20);
        expect(yOf(overridden), closeTo(yOf(twin), 1e-6));

        // Cleared: the saved scale again.
        rigid.gravityScaleOverride = null;
        twin.getComponent<RigidBody3DComponent>()!.gravityScale = 1;
        step(20);
        expect(yOf(overridden), closeTo(yOf(twin), 1e-6));
        expect(rigid.gravityScale, 1, reason: 'never written');
      });

      test('a character with a gravity scale override falls as that saved '
          'scale would, and keeps its own', () {
        Entity hero(double x, {double gravityScale = 1, double? override}) =>
            world.createEntityWithComponents([
              TransformComponent(position: Vector3(x, 0, 0)),
              CharacterBody3DComponent(gravityScale: gravityScale)
                ..gravityScaleOverride = override,
            ]);
        final overridden = hero(0, override: 0.25);
        final twin = hero(50, gravityScale: 0.25);
        final comp = overridden.getComponent<CharacterBody3DComponent>()!;
        expect(comp.effectiveGravityScale, 0.25);
        step(20);
        expect(yOf(overridden), closeTo(yOf(twin), 1e-6));
        expect(yOf(overridden), greaterThan(0.05));

        comp.gravityScaleOverride = null;
        twin.getComponent<CharacterBody3DComponent>()!.gravityScale = 1;
        step(20);
        expect(yOf(overridden), closeTo(yOf(twin), 1e-6));
        expect(comp.gravityScale, 1, reason: 'never written');
      });
    });
  }

  test('the fake backend is given the override as the gravity factor', () {
    final physics = FakePhysics3DWorld(Physics3DWorldSettings());
    final system = Physics3DSystem(physics);
    final world = World()..initialize();
    world.addSystem(system);
    addTearDown(() {
      world.dispose();
      physics.dispose();
    });
    final rigid = RigidBody3DComponent(gravityScale: 1)
      ..gravityScaleOverride = 0;
    final box = world.createEntityWithComponents([
      TransformComponent(),
      Collider3DComponent(),
      rigid,
    ]);
    world.update(_dt);
    double factor() => physics.bodies[system.bodyOf(box)]!.gravityFactor;
    expect(factor(), 0, reason: 'made with it');
    rigid.gravityScaleOverride = 3;
    world.update(_dt);
    expect(factor(), 3);
    rigid.gravityScaleOverride = null;
    world.update(_dt);
    expect(factor(), 1);
    expect(rigid.gravityScale, 1);
  });

  group('saving', () {
    String saved(ComponentDefinition schema, Component c) =>
        jsonEncode(schema.encode(c));

    test('a rigid body saves its authored gravity scale, not the override', () {
      final schema = Physics3DDefinitions.rigidBody;
      final body = RigidBody3DComponent(gravityScale: 0.75)
        ..gravityScaleOverride = 2;
      final json = jsonDecode(saved(schema, body)) as Map<String, dynamic>;
      expect((json['fields'] as Map)['gravityScale'], 0.75);
      expect(
        saved(schema, body),
        saved(schema, RigidBody3DComponent(gravityScale: 0.75)),
      );
      expect(
        schema.fields.map((f) => f.name),
        isNot(contains('gravityScaleOverride')),
      );
      final loaded = schema.decode(json);
      expect(
        (
          loaded.gravityScale,
          loaded.gravityScaleOverride,
          loaded.effectiveGravityScale,
        ),
        (0.75, null, 0.75),
      );
    });

    test('a character saves its authored gravity scale, not the override', () {
      final schema = Physics3DDefinitions.characterBody;
      final body = CharacterBody3DComponent(gravityScale: 1.5)
        ..gravityScaleOverride = 3;
      final json = jsonDecode(saved(schema, body)) as Map<String, dynamic>;
      expect((json['fields'] as Map)['gravityScale'], 1.5);
      expect(
        saved(schema, body),
        saved(schema, CharacterBody3DComponent(gravityScale: 1.5)),
      );
      expect(
        schema.fields.map((f) => f.name),
        isNot(contains('gravityScaleOverride')),
      );
      final loaded = schema.decode(json);
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

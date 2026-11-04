// RayTracer2D, multi-bounce rays on the physics ray: a trace hits what
// Physics2DQueries.raycast hits (layers, sensors and the entity looked
// through, on every stretch), is mirrored about the hit normal by a
// collider's reflectivity, goes on with what is left of the ray times it,
// and stops at its bounce cap — on both 2-D backends. A collider's
// reflectivity is saved with the scene, and one saved without it absorbs.

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

final _backends = <String, Physics2DEngine Function()>{
  'native': Physics2DEngine.new,
  'pure Dart': Physics2DEngine.pureDart,
};

void main() {
  for (final MapEntry(key: backend, value: make) in _backends.entries) {
    group(backend, () {
      late Physics2DEngine physics;
      late World world;
      late Physics2DQueries queries;

      setUp(() {
        physics = make()..initialize();
        physics.setGravity(0, 0);
        world = World()..initialize();
        final system = Physics2DSystem(physics);
        world.addSystem(system);
        queries = system.queries;
      });
      tearDown(() {
        world.dispose();
        physics.dispose();
      });

      /// A static wall 10 wide and 200 tall, centred on ([x], 0).
      Entity wall(
        double x, {
        double reflectivity = 0,
        int layer = 0,
        bool sensor = false,
      }) => world.createEntityWithComponents([
        TransformComponent(position: Vector3(x, 0, 0)),
        RigidBody2DComponent(
          bodyType: Body2DType.static,
          layer: layer,
          isSensor: sensor,
        ),
        Collider2DComponent(size: Vector2(10, 200), reflectivity: reflectivity),
      ]);

      // The bodies are made by the first step.
      void step() => world.update(1 / 60);

      test('bounces off a mirror, mirrored about its normal, then misses', () {
        final mirror = wall(100, reflectivity: 0.8); // Its left side at 95.
        step();
        final direction = Offset(math.cos(0.3), math.sin(0.3));
        final trace = RayTracer2D(
          queries,
          maxBounces: 1,
        ).trace(Offset.zero, direction, maxDistance: 1000);
        expect(trace.segments, hasLength(2));
        final first = trace.segments.first;
        expect(first.hit?.entity, mirror);
        expect(first.to.dx, closeTo(95, 0.5));
        expect(first.hit!.normal.dx, closeTo(-1, 1e-6));
        final second = trace.segments[1];
        expect(second.hit, isNull);
        final out = (second.to - second.from) / second.length;
        // Mirrored off the side facing it: x turns round, y goes on.
        expect(out.dx, closeTo(-direction.dx, 1e-6));
        expect(out.dy, closeTo(direction.dy, 1e-6));
      });

      test('a bounce goes on with what is left of the ray, times the '
          'reflectivity', () {
        wall(905, reflectivity: 0.8); // Its left side at 900.
        step();
        final trace = RayTracer2D(
          queries,
          maxBounces: 1,
        ).trace(Offset.zero, const Offset(1, 0), maxDistance: 1000);
        final first = trace.segments.first;
        final reached = first.hit!.distance;
        expect(reached, closeTo(900, 0.5));
        final last = trace.segments.last;
        expect(last.hit, isNull);
        // (1000 − 900) × 0.8 = 80 past the mirror, not 800; the step off
        // the surface counts against it. (The native backend's hit points
        // are single precision.)
        expect(
          (last.to - first.to).distance,
          closeTo((1000 - reached) * 0.8, 1e-3),
        );
        expect(
          trace.totalLength,
          closeTo(
            reached + (1000 - reached) * 0.8 - RayTracer2D.bounceOffset,
            1e-3,
          ),
        );
      });

      test('a trace ends when nothing of the ray is left', () {
        wall(1000, reflectivity: 0.1); // Its left side at 995.
        step();
        final trace = RayTracer2D(
          queries,
        ).trace(Offset.zero, const Offset(1, 0), maxDistance: 1000);
        // (1000 − 995) × 0.1 is less than the step off the surface.
        expect(trace.segments, hasLength(1));
        expect(trace.hits, hasLength(1));
      });

      test('a collider absorbs by default, and below minReflectivity', () {
        final target = wall(100);
        step();
        var trace = RayTracer2D(queries).trace(Offset.zero, const Offset(1, 0));
        expect(trace.segments, hasLength(1));
        expect(trace.hits.single.entity, target);

        target.getComponent<Collider2DComponent>()!.reflectivity = 0.05;
        trace = RayTracer2D(
          queries,
          minReflectivity: 0.1,
        ).trace(Offset.zero, const Offset(1, 0));
        expect(trace.segments, hasLength(1), reason: 'too dull to reflect');
        trace = RayTracer2D(queries).trace(Offset.zero, const Offset(1, 0));
        expect(
          trace.segments,
          hasLength(2),
          reason: 'any reflectivity bounces',
        );
      });

      test('between two mirrors, the trace stops at its bounce cap', () {
        wall(-100, reflectivity: 1);
        wall(100, reflectivity: 1);
        step();
        final trace = RayTracer2D(
          queries,
          maxBounces: 3,
        ).trace(Offset.zero, const Offset(1, 0), maxDistance: 10000);
        expect(trace.segments, hasLength(4), reason: 'the ray and 3 bounces');
        // Each hit faces the ray that made it: right mirror, left, right...
        expect(
          [for (final hit in trace.hits) hit.normal.dx.round()],
          [-1, 1, -1, 1],
        );
        expect(
          RayTracer2D(
            queries,
            maxBounces: 0,
          ).trace(Offset.zero, const Offset(1, 0)).segments,
          hasLength(1),
        );
      });

      test('every stretch sees what the physics ray sees: layers, sensors '
          'and the entity looked through', () {
        final mirror = wall(100, reflectivity: 1);
        final zone = wall(-40, sensor: true);
        wall(-60, layer: 1);
        final turret = wall(-80);
        final back = wall(-100);
        step();
        final tracer = RayTracer2D(queries);
        final trace = tracer.trace(
          Offset.zero,
          const Offset(1, 0),
          layerMask: 1,
          ignore: turret,
        );
        expect([for (final hit in trace.hits) hit.entity], [mirror, back]);
        // The first stretch is the physics ray itself.
        final ray = queries.raycast(
          Offset.zero,
          const Offset(1, 0),
          layerMask: 1,
          ignore: turret,
        )!;
        expect(trace.hits.first.entity, ray.entity);
        expect(trace.hits.first.point, ray.point);
        // Counting sensors, the sensor on the way back stops it.
        expect(
          tracer
              .trace(
                Offset.zero,
                const Offset(1, 0),
                layerMask: 1,
                ignore: turret,
                includeSensors: true,
              )
              .hits
              .last
              .entity,
          zone,
        );
      });

      test('a zero direction or no length traces nothing', () {
        wall(100);
        step();
        final tracer = RayTracer2D(queries);
        expect(tracer.trace(Offset.zero, Offset.zero).segments, isEmpty);
        expect(
          tracer
              .trace(Offset.zero, const Offset(1, 0), maxDistance: 0)
              .segments,
          isEmpty,
        );
      });
    });
  }

  test('a body with no Collider2DComponent absorbs', () {
    final hit = Physics2DHit(
      entity: null,
      body: Physics2DBody(position: Vector2.zero(), shape: Circle2DShape(1)),
      point: Offset.zero,
      normal: const Offset(-1, 0),
      distance: 0,
      fraction: 0,
    );
    expect(RayTracer2D.reflectivityOf(hit), 0);
  });

  group('reflectivity is saved with the scene', () {
    World world() {
      final world = World(extensions: [BuiltInComponents.extension])
        ..initialize();
      addTearDown(world.dispose);
      return world;
    }

    /// [entity] as a scene file holds it, read back from the file's text.
    Map<String, dynamic> saved(Entity entity) {
      final definitions = entity.world!.context.definitions;
      final text = jsonEncode({
        'version': SceneFormat.current,
        'entities': [
          {
            'name': entity.name,
            'components': [
              for (final component in entity.components)
                ?definitions.encode(component),
            ],
          },
        ],
      });
      return jsonDecode(text) as Map<String, dynamic>;
    }

    Map<String, dynamic> colliderFields(Map<String, dynamic> scene) {
      final entity = (scene['entities'] as List).single as Map;
      final collider = (entity['components'] as List).firstWhere(
        (c) => (c as Map)['type'] == 'Collider2DComponent',
      );
      return (collider as Map)['fields'] as Map<String, dynamic>;
    }

    test('a scene saves and loads a collider\'s reflectivity', () {
      final mirror = world().createEntityWithComponents([
        TransformComponent(),
        Collider2DComponent(reflectivity: 0.65),
      ], name: 'Mirror');
      final scene = saved(mirror);
      expect(colliderFields(scene)['reflectivity'], 0.65);
      final loaded = SceneLoader.load(world(), scene).single;
      expect(loaded.getComponent<Collider2DComponent>()!.reflectivity, 0.65);
    });

    test('a collider saved before reflectivity existed absorbs', () {
      final wall = world().createEntityWithComponents([
        TransformComponent(),
        Collider2DComponent(reflectivity: 0.65),
      ], name: 'Wall');
      final scene = saved(wall);
      colliderFields(scene).remove('reflectivity');
      final loaded = SceneLoader.load(world(), scene).single;
      expect(loaded.getComponent<Collider2DComponent>()!.reflectivity, 0);
    });

    test('the inspector shows it, from 0 to 1', () {
      final definition = world().context.definitions.definitionByType(
        'Collider2DComponent',
      )!;
      final field = definition.field('reflectivity')!;
      expect((field.min, field.max), (0, 1));
      expect(definition.hints.fields['reflectivity']?.label, 'Reflectivity');
      expect(definition.hints.fieldGroups!['Rays'], ['reflectivity']);
    });
  });
}

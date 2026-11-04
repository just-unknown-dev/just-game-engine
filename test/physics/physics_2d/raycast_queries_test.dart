// RaycastSystem's queries past raycast: raycastAll's order and tag filter,
// hasLineOfSight — blockers between the two points only, never the viewer's
// or the target's own collider — and RayTracer's bounces, each on what is
// left of the ray.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  late World world;
  late RaycastSystem rays;

  setUp(() {
    world = World()..initialize();
    rays = RaycastSystem();
    world.addSystem(rays);
  });
  tearDown(() => world.dispose());

  Entity collider(
    double x,
    double y, {
    double radius = 0,
    double width = 0,
    double height = 0,
    String? tag,
    bool isBlocker = true,
    bool isReflective = false,
    double reflectivity = 0.8,
    String? name,
  }) => world.createEntityWithComponents([
    TransformComponent(position: Vector3(x, y, 0)),
    RaycastColliderComponent(
      radius: radius,
      width: width,
      height: height,
      tag: tag,
      isBlocker: isBlocker,
      isReflective: isReflective,
      reflectivity: reflectivity,
    ),
  ], name: name);

  group('raycastAll', () {
    test('gives every hit, nearest first, and filters by tag', () {
      final far = collider(150, 0, radius: 5, tag: 'enemy');
      final near = collider(50, 0, radius: 5);
      final middle = collider(100, 0, width: 10, height: 10);
      final ray = Ray(origin: Offset.zero, direction: const Offset(1, 0));
      final hits = rays.raycastAll(ray);
      expect([for (final h in hits) h.entity], [near, middle, far]);
      expect(
        [for (final h in hits) h.distance],
        [closeTo(45, 1e-9), closeTo(95, 1e-9), closeTo(145, 1e-9)],
      );
      expect(hits[1].normal, const Offset(-1, 0));
      expect(
        [for (final h in rays.raycastAll(ray, filterTag: 'enemy')) h.entity],
        [far],
      );
    });

    test('passes over what is switched off, or out of reach', () {
      collider(50, 0, radius: 5).isActive = false;
      final reached = collider(100, 0, radius: 5);
      collider(400, 0, radius: 5);
      final ray = Ray(
        origin: Offset.zero,
        direction: const Offset(1, 0),
        maxDistance: 200,
      );
      expect([for (final h in rays.raycastAll(ray)) h.entity], [reached]);
      expect(rays.raycast(ray)?.entity, reached);
    });
  });

  group('hasLineOfSight', () {
    test('a blocker between the points blocks; a non-blocker does not', () {
      final wall = collider(100, 0, width: 10, height: 40);
      expect(rays.hasLineOfSight(Offset.zero, const Offset(200, 0)), isFalse);
      wall.getComponent<RaycastColliderComponent>()!.isBlocker = false;
      expect(rays.hasLineOfSight(Offset.zero, const Offset(200, 0)), isTrue);
    });

    test('an ignored tag or entity is looked through', () {
      final crate = collider(100, 0, radius: 10, tag: 'crate');
      expect(
        rays.hasLineOfSight(
          Offset.zero,
          const Offset(200, 0),
          ignoreTag: 'crate',
        ),
        isTrue,
      );
      expect(
        rays.hasLineOfSight(Offset.zero, const Offset(200, 0), ignore: {crate}),
        isTrue,
      );
    });

    test("the viewer's and the target's own colliders do not block", () {
      // A guard at (0, 0) looking at the player at (200, 0), nothing between.
      collider(0, 0, radius: 14, tag: 'enemy', name: 'Guard');
      collider(200, 0, radius: 14, tag: 'player', name: 'Player');
      expect(rays.hasLineOfSight(Offset.zero, const Offset(200, 0)), isTrue);
      expect(
        rays.hasLineOfSight(
          Offset.zero,
          const Offset(200, 0),
          ignoreTag: 'enemy',
        ),
        isTrue,
      );
      // Something in between still blocks.
      collider(100, 0, width: 4, height: 60);
      expect(rays.hasLineOfSight(Offset.zero, const Offset(200, 0)), isFalse);
    });

    test('a collider whose edge is exactly at the target does not block', () {
      collider(205, 0, width: 10, height: 10); // Its left side at x = 200.
      expect(rays.hasLineOfSight(Offset.zero, const Offset(200, 0)), isTrue);
    });

    test('a point sees itself', () {
      collider(0, 0, radius: 5);
      expect(rays.hasLineOfSight(Offset.zero, Offset.zero), isTrue);
      expect(
        rays.hasLineOfSight(const Offset(50, 50), const Offset(50, 50)),
        isTrue,
      );
    });
  });

  group('RayTracer', () {
    test('bounces off a reflective wall, mirrored, then misses', () {
      // A mirror facing the ray, its left side at x = 95.
      final mirror = collider(
        100,
        0,
        width: 10,
        height: 200,
        isReflective: true,
        reflectivity: 0.8,
      );
      final tracer = RayTracer(raycastSystem: rays, maxBounces: 1);
      final direction = Offset(math.cos(0.3), math.sin(0.3));
      final trace = tracer.trace(
        Ray(origin: Offset.zero, direction: direction, maxDistance: 1000),
      );
      expect(trace.segments, hasLength(2));
      final first = trace.segments.first;
      expect(first.hit?.entity, mirror);
      expect(first.to.dx, closeTo(95, 1e-9));
      final second = trace.segments[1];
      expect(second.hit, isNull);
      final out = second.to - second.from;
      // Mirrored off the x-facing side: x turns round, y goes on.
      expect(out.dx, lessThan(0));
      expect(out.dy / out.distance, closeTo(direction.dy, 1e-9));
    });

    test('a bounce goes on with what is left of the ray, dimmed', () {
      // The mirror's side at 900 along a 1000-long beam.
      collider(905, 0, width: 10, height: 200, isReflective: true);
      final tracer = RayTracer(raycastSystem: rays, maxBounces: 1);
      final trace = tracer.trace(
        Ray(
          origin: Offset.zero,
          direction: const Offset(1, 0),
          maxDistance: 1000,
        ),
      );
      final hit = trace.segments.first.to;
      final end = trace.segments.last.to;
      // (1000 − 900) × 0.8 = 80 past the mirror — not 800.
      expect((end - hit).distance, closeTo(80, 1e-6));
      expect(
        trace.totalLength,
        closeTo(900 + 80 - RayTracer.bounceOffset, 1e-6),
      );
    });

    test('a surface too dull to reflect ends the trace', () {
      collider(
        100,
        0,
        width: 10,
        height: 200,
        isReflective: true,
        reflectivity: 0.05,
      );
      final tracer = RayTracer(raycastSystem: rays, maxBounces: 3);
      final trace = tracer.trace(
        Ray(origin: Offset.zero, direction: const Offset(1, 0)),
      );
      expect(trace.segments, hasLength(1));
      expect(trace.hits, hasLength(1));
    });
  });
}

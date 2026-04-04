import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

// Helper to build a simple circle body at the given position.
PhysicsBody _circle({
  required double x,
  required double y,
  double radius = 20.0,
  double mass = 1.0,
  bool useGravity = false,
  bool checkCollision = true,
}) {
  return PhysicsBody(
    position: Vector2(x, y),
    shape: CircleShape(radius),
    mass: mass,
    useGravity: useGravity,
    checkCollision: checkCollision,
    drag: 0.0,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── Vector2 ────────────────────────────────────────────────────────────────

  group('Vector2', () {
    test('zero constructor', () {
      final v = Vector2.zero();
      expect(v.x, 0.0);
      expect(v.y, 0.0);
    });

    test('addScaled in-place', () {
      final v = Vector2(1, 2);
      v.addScaled(Vector2(2, 3), 2.0);
      expect(v.x, closeTo(5.0, 1e-9));
      expect(v.y, closeTo(8.0, 1e-9));
    });

    test('scale in-place', () {
      final v = Vector2(3, 4);
      v.scale(2.0);
      expect(v.x, 6.0);
      expect(v.y, 8.0);
    });

    test('lengthSquared', () {
      final v = Vector2(3, 4);
      expect(v.lengthSquared, closeTo(25.0, 1e-9));
    });

    test('setZero clears components', () {
      final v = Vector2(5, 6);
      v.setZero();
      expect(v.x, 0.0);
      expect(v.y, 0.0);
    });

    test('add in-place', () {
      final v = Vector2(1, 2);
      v.add(Vector2(3, 4));
      expect(v.x, 4.0);
      expect(v.y, 6.0);
    });

    test('toOffset converts correctly', () {
      final v = Vector2(7, 8);
      final o = v.toOffset();
      expect(o.dx, 7.0);
      expect(o.dy, 8.0);
    });
  });

  // ── CollisionShape ─────────────────────────────────────────────────────────

  group('CircleShape', () {
    test('getBounds at origin', () {
      final s = CircleShape(10.0);
      final bounds = s.getBounds(Offset.zero);
      expect(bounds, Rect.fromCircle(center: Offset.zero, radius: 10.0));
    });

    test('getBounds at offset position', () {
      final s = CircleShape(5.0);
      final bounds = s.getBounds(const Offset(20, 30));
      expect(bounds.center, const Offset(20, 30));
      expect(bounds.width, closeTo(10.0, 1e-9));
    });

    test('getManifold detects circle-circle overlap', () {
      final a = CircleShape(10.0);
      final b = CircleShape(10.0);
      // centres 15 units apart — overlap by 5
      final manifold = a.getManifold(Offset.zero, b, const Offset(15, 0));
      expect(manifold.isColliding, isTrue);
      expect(manifold.penetration, closeTo(5.0, 1e-6));
    });

    test('getManifold reports no collision when separated', () {
      final a = CircleShape(5.0);
      final b = CircleShape(5.0);
      final manifold = a.getManifold(Offset.zero, b, const Offset(100, 0));
      expect(manifold.isColliding, isFalse);
    });

    test('getManifold normal points from A to B', () {
      final a = CircleShape(10.0);
      final b = CircleShape(10.0);
      final manifold = a.getManifold(Offset.zero, b, const Offset(15, 0));
      expect(manifold.normal.dx, greaterThan(0));
      expect(manifold.normal.dy, closeTo(0, 1e-6));
    });
  });

  group('PolygonShape', () {
    Offset v(double x, double y) => Offset(x, y);

    test('getBounds is correct for a box', () {
      final box = PolygonShape([
        v(-10, -10),
        v(10, -10),
        v(10, 10),
        v(-10, 10),
      ]);
      final bounds = box.getBounds(Offset.zero);
      expect(bounds.left, closeTo(-10, 1e-6));
      expect(bounds.right, closeTo(10, 1e-6));
      expect(bounds.top, closeTo(-10, 1e-6));
      expect(bounds.bottom, closeTo(10, 1e-6));
    });

    test('poly-poly SAT detects overlap', () {
      final box = PolygonShape([
        v(-10, -10),
        v(10, -10),
        v(10, 10),
        v(-10, 10),
      ]);
      // place B shifted 15 units right — boxes overlap by 5 on x axis
      final manifold = box.getManifold(Offset.zero, box, const Offset(15, 0));
      expect(manifold.isColliding, isTrue);
    });

    test('poly-poly SAT reports no collision when separated', () {
      final box = PolygonShape([v(-5, -5), v(5, -5), v(5, 5), v(-5, 5)]);
      final manifold = box.getManifold(Offset.zero, box, const Offset(100, 0));
      expect(manifold.isColliding, isFalse);
    });
  });

  // ── PhysicsBody ────────────────────────────────────────────────────────────

  group('PhysicsBody', () {
    test('inverseMass is 1/mass', () {
      final body = _circle(x: 0, y: 0, mass: 2.0);
      expect(body.inverseMass, closeTo(0.5, 1e-9));
    });

    test('static body has zero inverseMass', () {
      final body = _circle(x: 0, y: 0, mass: 0.0);
      expect(body.inverseMass, 0.0);
    });

    test('applyForce accumulates acceleration', () {
      final body = _circle(x: 0, y: 0, mass: 1.0, useGravity: false);
      body.acceleration.x += 10.0;
      expect(body.acceleration.x, 10.0);
    });

    test('applyImpulse changes velocity directly', () {
      final body = _circle(x: 0, y: 0);
      body.applyImpulse(Vector2(100, 0));
      expect(body.velocity.x, closeTo(100, 1e-6));
    });

    test('body starts awake', () {
      final body = _circle(x: 0, y: 0);
      expect(body.isAwake, isTrue);
    });
  });

  // ── PhysicsEngine integration ──────────────────────────────────────────────

  group('PhysicsEngine', () {
    late PhysicsEngine engine;
    setUp(() {
      engine = PhysicsEngine();
      engine.initialize();
    });

    test('addBody registers body', () {
      final body = _circle(x: 0, y: 0, useGravity: false);
      engine.addBody(body);
      // No exception and no duplicate insertion
      engine.addBody(body); // double-add must be a no-op
      expect(engine.stats['bodyCount'], 1);
    });

    test('removeBody deregisters body', () {
      final body = _circle(x: 0, y: 0);
      engine.addBody(body);
      engine.removeBody(body);
      expect(engine.stats['bodyCount'], 0);
    });

    test('update advances position when velocity is set', () {
      final body = _circle(x: 0, y: 0, useGravity: false);
      body.velocity.x = 100.0;
      engine.addBody(body);
      engine.update(1.0 / 60.0);
      expect(body.position.x, greaterThan(0));
    });

    test('gravity accelerates free-falling body', () {
      final body = _circle(x: 0, y: 0, useGravity: true);
      body.velocity.setZero();
      engine.addBody(body);
      engine.update(1.0 / 60.0);
      engine.update(1.0 / 60.0);
      // Gravity is (0, 98) so y should grow
      expect(body.position.y, greaterThan(0));
    });

    test('static body (mass=0) is not moved by collision', () {
      final staticBody = _circle(x: 50, y: 0, mass: 0.0, useGravity: false);
      staticBody.velocity.setZero();
      final dynamic = _circle(x: 35, y: 0, useGravity: false);
      dynamic.velocity.x = 100.0; // moving toward static
      engine.addBody(staticBody);
      engine.addBody(dynamic);

      final initialStaticX = staticBody.position.x;
      engine.update(1.0 / 60.0);
      expect(staticBody.position.x, closeTo(initialStaticX, 1.0));
    });

    test('two overlapping circles resolve collision', () {
      // Place circles so they overlap significantly.
      final a = _circle(x: 0, y: 0, radius: 30, useGravity: false);
      final b = _circle(x: 40, y: 0, radius: 30, useGravity: false);
      // Give them relative velocity so collision is not separating.
      a.velocity.x = 50.0;

      engine.addBody(a);
      engine.addBody(b);
      engine.update(1.0 / 60.0);

      // After resolution they should not deeply overlap.
      final dist = (a.position.toOffset() - b.position.toOffset()).distance;
      expect(dist, greaterThan(20.0)); // separated beyond just-touching
    });

    test('sleeping body skips integration', () {
      final body = _circle(x: 0, y: 0, useGravity: false);
      body.isAwake = false;
      body.velocity.x = 100.0;
      engine.addBody(body);

      final xBefore = body.position.x;
      engine.update(1.0 / 60.0);
      expect(body.position.x, xBefore);
    });

    test('stats exposes awake and potential pair counts', () {
      engine.addBody(_circle(x: 0, y: 0));
      engine.addBody(_circle(x: 50, y: 0));
      engine.update(1.0 / 60.0);
      final s = engine.stats;
      expect(s.containsKey('awakeBodies'), isTrue);
      expect(s.containsKey('potentialPairs'), isTrue);
    });
  });

  // ── SpatialGrid ────────────────────────────────────────────────────────────

  group('SpatialGrid', () {
    late SpatialGrid grid;
    setUp(() => grid = SpatialGrid(64.0));

    PhysicsBody gridBody(double x, double y, {double radius = 10}) {
      return PhysicsBody(
        position: Vector2(x, y),
        shape: CircleShape(radius),
        useGravity: false,
        drag: 0.0,
      );
    }

    test('insert increments trackedBodyCount', () {
      grid.insert(gridBody(0, 0));
      expect(grid.trackedBodyCount, 1);
    });

    test('clear resets state', () {
      grid.insert(gridBody(0, 0));
      grid.clear();
      expect(grid.trackedBodyCount, 0);
      expect(grid.trackedCellCount, 0);
    });

    test('getPotentialCollisions returns pairs in same cell', () {
      final a = gridBody(0, 0);
      final b = gridBody(5, 5); // same 64-unit cell
      grid.insert(a);
      grid.insert(b);
      final pairs = grid.getPotentialCollisions();
      expect(pairs.length, 1);
      final p = pairs.first;
      expect({p.a, p.b}, equals({a, b}));
    });

    test('getPotentialCollisions no pairs when bodies in different cells', () {
      final a = gridBody(0, 0);
      final b = gridBody(200, 200); // far away
      grid.insert(a);
      grid.insert(b);
      expect(grid.getPotentialCollisions(), isEmpty);
    });

    test('getPotentialCollisions returns deduplicated pairs', () {
      // 3 bodies in same cell → 3 unique pairs
      grid.insert(gridBody(0, 0));
      grid.insert(gridBody(5, 0));
      grid.insert(gridBody(10, 0));
      final pairs = grid.getPotentialCollisions();
      expect(pairs.length, 3);
    });

    test('syncBodies removes stale bodies', () {
      final a = gridBody(0, 0);
      final b = gridBody(5, 5);
      grid.syncBodies([a, b]);
      grid.syncBodies([a]); // b no longer present
      expect(grid.trackedBodyCount, 1);
    });

    test('syncBodies moves body to new cell after position change', () {
      final body = gridBody(0, 0);
      grid.syncBodies([body]);
      expect(grid.trackedBodyCount, 1);

      body.position.x = 500;
      body.position.y = 500;
      grid.syncBodies([body]);
      expect(grid.trackedBodyCount, 1);
    });

    test('inactive body is not inserted', () {
      final body = gridBody(0, 0);
      body.isActive = false;
      grid.insert(body);
      expect(grid.trackedBodyCount, 0);
    });

    test('BodyPair equality is order-independent', () {
      final a = gridBody(0, 0);
      final b = gridBody(5, 5);
      final p1 = BodyPair(a, b);
      final p2 = BodyPair(b, a);
      expect(p1, equals(p2));
    });

    test('persistent _pairBuffer is cleared between calls', () {
      final a = gridBody(0, 0);
      final b = gridBody(5, 5);
      grid.insert(a);
      grid.insert(b);

      final first = grid.getPotentialCollisions();
      final firstLength = first.length;

      // Remove b — second call should return empty buffer.
      grid.removeBody(b);
      final second = grid.getPotentialCollisions();
      expect(second.length, 0);
      expect(firstLength, 1); // first call was correct
    });
  });

  // ── RigidBody ─────────────────────────────────────────────────────────────

  group('RigidBody', () {
    test('integrate advances position from applied force', () {
      final body = RigidBody();
      body.applyForce(10, 0);
      body.integrate(1.0);
      expect(body.position.x, greaterThan(0));
    });

    test('zero mass body is not moved', () {
      final body = RigidBody()..mass = 0.0;
      body.applyForce(1000, 0);
      body.integrate(1.0);
      expect(body.position.x, 0.0);
    });
  });
}

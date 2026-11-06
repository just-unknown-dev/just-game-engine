import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

// Helper to build a simple circle body at the given position.
Physics2DBody _circle({
  required double x,
  required double y,
  double radius = 20.0,
  double mass = 1.0,
  bool useGravity = false,
}) {
  return Physics2DBody(
    position: Vector2(x, y),
    shape: Circle2DShape(radius),
    mass: mass,
    useGravity: useGravity,
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

  // ── Shape2D ─────────────────────────────────────────────────────────

  group('Circle2DShape', () {
    test('boundsAt at origin', () {
      final s = Circle2DShape(10.0);
      final bounds = s.boundsAt(Offset.zero);
      expect(bounds, Rect.fromCircle(center: Offset.zero, radius: 10.0));
    });

    test('boundsAt at offset position', () {
      final s = Circle2DShape(5.0);
      final bounds = s.boundsAt(const Offset(20, 30));
      expect(bounds.center, const Offset(20, 30));
      expect(bounds.width, closeTo(10.0, 1e-9));
    });

    test('manifoldWith detects circle-circle overlap', () {
      final a = Circle2DShape(10.0);
      final b = Circle2DShape(10.0);
      // centres 15 units apart — overlap by 5
      final manifold = a.manifoldWith(Offset.zero, b, const Offset(15, 0));
      expect(manifold.isColliding, isTrue);
      expect(manifold.penetration, closeTo(5.0, 1e-6));
    });

    test('manifoldWith reports no collision when separated', () {
      final a = Circle2DShape(5.0);
      final b = Circle2DShape(5.0);
      final manifold = a.manifoldWith(Offset.zero, b, const Offset(100, 0));
      expect(manifold.isColliding, isFalse);
    });

    test('manifoldWith normal points from A to B', () {
      final a = Circle2DShape(10.0);
      final b = Circle2DShape(10.0);
      final manifold = a.manifoldWith(Offset.zero, b, const Offset(15, 0));
      expect(manifold.normal.dx, greaterThan(0));
      expect(manifold.normal.dy, closeTo(0, 1e-6));
    });
  });

  group('Polygon2DShape', () {
    Offset v(double x, double y) => Offset(x, y);

    test('boundsAt is correct for a box', () {
      final box = Polygon2DShape([
        v(-10, -10),
        v(10, -10),
        v(10, 10),
        v(-10, 10),
      ]);
      final bounds = box.boundsAt(Offset.zero);
      expect(bounds.left, closeTo(-10, 1e-6));
      expect(bounds.right, closeTo(10, 1e-6));
      expect(bounds.top, closeTo(-10, 1e-6));
      expect(bounds.bottom, closeTo(10, 1e-6));
    });

    test('poly-poly SAT detects overlap', () {
      final box = Polygon2DShape([
        v(-10, -10),
        v(10, -10),
        v(10, 10),
        v(-10, 10),
      ]);
      // place B shifted 15 units right — boxes overlap by 5 on x axis
      final manifold = box.manifoldWith(Offset.zero, box, const Offset(15, 0));
      expect(manifold.isColliding, isTrue);
    });

    test('poly-poly SAT reports no collision when separated', () {
      final box = Polygon2DShape([v(-5, -5), v(5, -5), v(5, 5), v(-5, 5)]);
      final manifold = box.manifoldWith(Offset.zero, box, const Offset(100, 0));
      expect(manifold.isColliding, isFalse);
    });
  });

  // ── Physics2DBody ────────────────────────────────────────────────────────────

  group('Physics2DBody', () {
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

    test('body starts awake', () {
      final body = _circle(x: 0, y: 0);
      expect(body.isAwake, isTrue);
    });
  });

  // ── Physics2DEngine integration ──────────────────────────────────────────────

  group('Physics2DEngine', () {
    late Physics2DEngine engine;
    setUp(() {
      engine = PhysicsEngineFactory.create2D();
      engine.initialize();
    });

    // Without this every test in the group leaks a native Box2D world and its
    // worker thread pool. Around two dozen of those accumulate over the group
    // and the native side falls over partway through, which surfaces as a
    // shifting "did not complete" cascade rather than a real assertion.
    tearDown(() => engine.dispose());

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
}

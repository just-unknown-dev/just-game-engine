// What a 2-D shape draws, as one cheap value (Shape2DLook.look): the same
// object while nothing it draws changes, a different one as soon as
// anything does — a size, a style, the outline, a vertex edited in place,
// the renderable.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

const _red = ShapePaintStyle(color: Color(0xFFFF0000));

/// Checks [shape]'s look stays put while untouched, and moves with each of
/// [changes] (each applied in turn).
void _expectLook(Shape2DLook shape, List<void Function()> changes) {
  var before = shape.look;
  expect(shape.look, same(before), reason: 'nothing changed');
  for (var i = 0; i < changes.length; i++) {
    changes[i]();
    final after = shape.look;
    expect(after, isNot(equals(before)), reason: 'change $i');
    expect(shape.look, same(after), reason: 'change $i, asked again');
    before = after;
  }
}

void main() {
  test('a rectangle', () {
    final r = Rectangle2DComponent(width: 10, height: 20);
    _expectLook(r, [
      () => r.width = 11,
      () => r.height = 21,
      () => r.fillStyle = _red,
      () => r.strokeStyle = _red,
      () => r.filled = false,
      () => r.strokeWidth = 3,
      () => r.cornerRadius = 2,
      () => r.renderable = CustomRenderable(onRender: (_, _) {}),
    ]);
  });

  test('a circle', () {
    final c = Circle2DComponent(radius: 5);
    _expectLook(c, [
      () => c.radius = 6,
      () => c.fillStyle = _red,
      () => c.strokeStyle = _red,
      () => c.filled = false,
      () => c.strokeWidth = 2,
    ]);
  });

  test('a capsule', () {
    final c = Capsule2DComponent(width: 10, height: 30);
    _expectLook(c, [
      () => c.width = 12,
      () => c.height = 31,
      () => c.fillStyle = _red,
      () => c.strokeStyle = _red,
      () => c.filled = false,
      () => c.strokeWidth = 2,
    ]);
  });

  test('a line', () {
    final l = Line2DComponent(end: const Offset(10, 0));
    _expectLook(l, [
      () => l.start = const Offset(1, 1),
      () => l.end = const Offset(9, 9),
      () => l.strokeStyle = _red,
      () => l.strokeWidth = 4,
      () => l.roundCaps = true,
    ]);
  });

  test('a polygon, its vertices edited in place too', () {
    final points = [Offset.zero, const Offset(10, 0), const Offset(0, 10)];
    final p = Polygon2DComponent(vertices: points);
    _expectLook(p, [
      () => points[1] = const Offset(12, 0),
      () => points.add(const Offset(-4, 4)),
      () => p.vertices = [Offset.zero, const Offset(1, 1), const Offset(2, 0)],
      () => p.fillStyle = _red,
      () => p.strokeStyle = _red,
      () => p.filled = false,
      () => p.strokeWidth = 2,
    ]);
    final settled = p.look;
    p.vertices = [Offset.zero, const Offset(1, 1), const Offset(2, 0)];
    expect(p.look, same(settled), reason: 'a new list with the same points');
  });

  test('a look that comes back equals the one it was', () {
    final r = Rectangle2DComponent(width: 10, height: 20);
    final first = r.look;
    r.width = 30;
    expect(r.look, isNot(equals(first)));
    r.width = 10;
    expect(r.look, equals(first));
  });
}

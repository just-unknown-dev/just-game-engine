// A line's bounds — what culling, picking and a 2-D material's sheet of
// it go by — hold the whole line, its width and its caps, whichever way it
// runs.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  test('a line drawn right to left is held by its bounds', () {
    final l = Line2DComponent(
      start: const Offset(100, 0),
      end: Offset.zero,
      strokeWidth: 4,
    );
    expect(
      l.renderable.bounds,
      const Rect.fromLTRB(-4, -4, 104, 4),
      reason: 'the line spans 0-100, and its caps and width past that',
    );
  });

  test('a line drawn upwards is held by its bounds', () {
    final l = Line2DComponent(
      start: const Offset(0, 50),
      end: const Offset(20, -10),
      strokeWidth: 2,
      roundCaps: true,
    );
    expect(l.renderable.bounds, const Rect.fromLTRB(-2, -12, 22, 52));
  });
}

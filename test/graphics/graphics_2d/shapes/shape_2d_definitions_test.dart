// The five 2-D shapes saved and read back, every field set away from its
// default — a field a codec does not write is lost on every save.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

const _gradient = ShapePaintStyle(
  color: Color(0xFF336699),
  gradient: ShapeGradient.linear(
    colors: [Color(0xFFFF0000), Color(0xFF0000FF)],
    stops: [0.25, 0.75],
  ),
  blendMode: BlendMode.multiply,
);
const _radial = ShapePaintStyle(
  gradient: ShapeGradient.radial(
    colors: [Color(0xFF00FF00), Color(0x0000FF00)],
    radius: 0.8,
  ),
);
const _plain = ShapePaintStyle(color: Color(0x80FFCC00));

void main() {
  final definitions = EngineContext(
    extensions: [BuiltInComponents.extension],
  ).definitions;

  /// [component] saved, through JSON, and read back.
  T roundTrip<T extends Component>(T component) {
    final saved = jsonDecode(jsonEncode(definitions.encode(component)));
    return definitions.decode(saved as Map<String, dynamic>)! as T;
  }

  void expectStyle(ShapePaintStyle back, ShapePaintStyle was, String name) {
    expect(back.color, was.color, reason: '$name colour');
    expect(back.blendMode, was.blendMode, reason: '$name blend mode');
    final g = was.gradient;
    if (g == null) {
      expect(back.gradient, isNull, reason: '$name gradient');
      return;
    }
    final b = back.gradient!;
    expect(b.kind, g.kind, reason: '$name gradient kind');
    expect(b.colors, g.colors, reason: '$name gradient colours');
    expect(b.stops, g.stops, reason: '$name gradient stops');
    expect(b.radius, g.radius, reason: '$name gradient radius');
  }

  test('a rectangle, with a gradient fill, unfilled, rounded', () {
    final back = roundTrip(
      Rectangle2DComponent(
        width: 12.5,
        height: 30,
        fillStyle: _gradient,
        strokeStyle: _plain,
        filled: false,
        strokeWidth: 3,
        cornerRadius: 6,
      ),
    );
    expect(back.width, 12.5);
    expect(back.height, 30);
    expectStyle(back.fillStyle, _gradient, 'fill');
    expectStyle(back.strokeStyle, _plain, 'stroke');
    expect(back.filled, isFalse);
    expect(back.strokeWidth, 3);
    expect(back.cornerRadius, 6);
  });

  test('a circle', () {
    final back = roundTrip(
      Circle2DComponent(
        radius: 7.5,
        fillStyle: _radial,
        strokeStyle: _gradient,
        filled: false,
        strokeWidth: 2.5,
      ),
    );
    expect(back.radius, 7.5);
    expectStyle(back.fillStyle, _radial, 'fill');
    expectStyle(back.strokeStyle, _gradient, 'stroke');
    expect(back.filled, isFalse);
    expect(back.strokeWidth, 2.5);
  });

  test('a capsule', () {
    final back = roundTrip(
      Capsule2DComponent(
        width: 14,
        height: 40,
        fillStyle: _plain,
        strokeStyle: _radial,
        filled: false,
        strokeWidth: 4,
      ),
    );
    expect(back.width, 14);
    expect(back.height, 40);
    expectStyle(back.fillStyle, _plain, 'fill');
    expectStyle(back.strokeStyle, _radial, 'stroke');
    expect(back.filled, isFalse);
    expect(back.strokeWidth, 4);
  });

  test('a line: both ends, its style, width and caps', () {
    final back = roundTrip(
      Line2DComponent(
        start: const Offset(1, 2),
        end: const Offset(30, -4),
        strokeStyle: _gradient,
        strokeWidth: 3,
        roundCaps: true,
      ),
    );
    expect(back.start, const Offset(1, 2));
    expect(back.end, const Offset(30, -4));
    expectStyle(back.strokeStyle, _gradient, 'stroke');
    expect(back.strokeWidth, 3);
    expect(back.roundCaps, isTrue);
  });

  test('a polygon', () {
    final back = roundTrip(
      Polygon2DComponent(
        vertices: const [Offset(0, 0), Offset(20, 4), Offset(6, 18)],
        fillStyle: _plain,
        strokeStyle: _gradient,
        filled: false,
        strokeWidth: 2,
      ),
    );
    expect(back.vertices, const [Offset(0, 0), Offset(20, 4), Offset(6, 18)]);
    expectStyle(back.fillStyle, _plain, 'fill');
    expectStyle(back.strokeStyle, _gradient, 'stroke');
    expect(back.filled, isFalse);
    expect(back.strokeWidth, 2);
  });
}

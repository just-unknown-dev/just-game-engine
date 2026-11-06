// Every built-in component saves and loads every field it writes: for each
// definition and each field a codec reads back, a value changed within the
// field's limits is written, read and written again unchanged — the class
// of bug where a field "came back as its default after an editor save".
// Also each type's default round-trips whole, and the few codecs no other
// test ever ran have explicit cases. (The physics shape field type's own
// test is test/physics/physics_field_types_test.dart.)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

import 'definitions_round_trip.dart';

/// Fields whose saved value is not what was written, on purpose — each
/// with why. A field listed here is still decoded by the whole-component
/// round trip below.
const Map<String, String> _notRoundTripped = {};

void main() {
  final world = World(extensions: [BuiltInComponents.extension]);
  final defs = world.context.definitions;

  var checked = 0;
  group('every field of every built-in definition round-trips', () {
    for (final definition in defs.definitions) {
      test(definition.type, () {
        checked += expectFieldsRoundTrip(definition, exempt: _notRoundTripped);
      });
    }

    test('(and that is most of them)', () {
      expect(checked, greaterThan(150), reason: 'the check checked little');
    });
  });

  test('every type saved at its defaults reads back the same', () {
    expectDefaultsRoundTrip(defs, defs.definitions);
  });

  group('codecs no other test runs', () {
    T roundTrip<T extends Component>(T component) =>
        defs.decode(defs.encode(component)!) as T;

    test('Line2DComponent, every field', () {
      final line = roundTrip(
        Line2DComponent(
          start: const Offset(1, 2),
          end: const Offset(30, -4),
          strokeWidth: 3,
          roundCaps: true,
        ),
      );
      expect(line.start, const Offset(1, 2));
      expect(line.end, const Offset(30, -4));
      expect(line.strokeWidth, 3);
      expect(line.roundCaps, isTrue);
    });

    test('Rectangle2DComponent with a gradient, unfilled, rounded', () {
      const gradient = ShapePaintStyle(
        color: Color(0xFF112233),
        gradient: ShapeGradient.linear(
          colors: [Color(0xFF000000), Color(0xFFFFFFFF)],
        ),
      );
      final rect = roundTrip(
        Rectangle2DComponent(
          width: 20,
          height: 10,
          fillStyle: gradient,
          filled: false,
          cornerRadius: 6,
        ),
      );
      expect(rect.filled, isFalse);
      expect(rect.cornerRadius, 6);
      const style = FieldTypes.shapePaintStyle;
      expect(style.encode(rect.fillStyle), style.encode(gradient));
      expect(rect.fillStyle.gradient?.colors, gradient.gradient!.colors);
    });

    test('ParentComponent keeps inheritTransform', () {
      final link = roundTrip(ParentComponent(inheritTransform: false));
      expect(link.inheritTransform, isFalse);
      final old = defs.decode({'type': 'ParentComponent'}) as ParentComponent;
      expect(old.inheritTransform, isTrue, reason: 'a file without it');
    });
  });
}

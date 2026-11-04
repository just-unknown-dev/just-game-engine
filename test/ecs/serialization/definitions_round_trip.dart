// Support for definitions_round_trip_test.dart (the engine's own components)
// and definitions_3d_round_trip_test.dart (Graphics3D's and Physics3D's):
// a field's value changed within its limits, and the checks both run. Not a
// test itself.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// [value] changed within [field]'s limits, or null when there is no simple
/// way to change it (structured values have their own cases in the tests).
Object? perturbed(FieldDefinition field, Object? value) {
  final kind = field.kind;
  num clamp(num v) {
    var out = v;
    if (field.min != null && out < field.min!) out = field.min!;
    if (field.max != null && out > field.max!) out = field.max!;
    return out;
  }

  double moved(num n) {
    final up = clamp(n + 1.25).toDouble();
    return up != n ? up : clamp(n - 1.25).toDouble();
  }

  switch (value) {
    case final bool b:
      return !b;
    case final int n when kind.id == 'color':
      return n == 0 ? 1 : n - 1; // another colour, still 32 bits
    case final int n when kind.id == 'physicsLayerMask':
      return n ^ 1; // another set of layers, still 16 bits
    case final int n when kind.id == 'physicsLayer':
      return n < 15 ? n + 1 : n - 1; // another of the 16 layers
    case final num n when kind.id == 'integer' || n is int:
      // Saved as a whole number (a count, a layer index): changed by one.
      final up = clamp(n.toInt() + 1).toInt();
      return up != n ? up : clamp(n.toInt() - 1).toInt();
    case final num n:
      return moved(n);
    case final String s when kind is EnumFieldType:
      final other = kind.names.where((name) => name != s);
      return other.isEmpty ? null : other.first;
    case final String s when kind.id == 'text' || kind.id == 'assetRef':
      return '${s}x';
    case final Map<String, Object?> channels
        when _vectors.contains(kind.id) &&
            channels.isNotEmpty &&
            channels.values.every((v) => v is num):
      // A vector, a rotation or an offset: every channel changed.
      return {
        for (final MapEntry(:key, :value) in channels.entries)
          key: moved(value! as num),
      };
    default:
      return null;
  }
}

/// The field types saved as a map of numbers, one per channel.
const _vectors = {'vector2', 'vector3', 'euler', 'offset'};

/// [changed] as a matcher: a vector's channels may come back through
/// single precision or a unit conversion, so they match within 1e-4.
Object? _matcher(Object? changed) => switch (changed) {
  final Map<String, Object?> channels => {
    for (final MapEntry(:key, :value) in channels.entries)
      key: closeTo(value! as num, 1e-4),
  },
  _ => changed,
};

/// Checks that each field of [definition] a codec reads back keeps a value
/// changed within its limits through a read and a write, except the
/// [exempt] ones (keyed `'Type.field'`). Returns how many it checked.
int expectFieldsRoundTrip(
  ComponentDefinition definition, {
  Map<String, String> exempt = const {},
}) {
  var checked = 0;
  for (final field in definition.fields) {
    if (field.write == null) continue;
    final key = '${definition.type}.${field.name}';
    if (exempt.containsKey(key)) continue;
    final value = field.encodeFrom(definition.create());
    final changed = perturbed(field, value);
    if (changed == null) continue;
    final into = definition.create();
    field.decodeInto(into, changed);
    expect(field.encodeFrom(into), _matcher(changed), reason: key);
    checked++;
  }
  return checked;
}

/// Checks that each of [definitions], saved through [registry] at its
/// defaults, reads back the same.
void expectDefaultsRoundTrip(
  ComponentDefinitionRegistry registry,
  Iterable<ComponentDefinition> definitions,
) {
  for (final definition in definitions) {
    final saved = registry.encode(definition.create());
    if (saved == null) continue;
    final again = registry.encode(registry.decode(saved)!);
    expect(again, saved, reason: definition.type);
  }
}

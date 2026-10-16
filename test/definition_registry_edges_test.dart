// ComponentDefinitionRegistry's by-Dart-type index after an override with
// another Dart type and after unregister; a real type name winning over an
// alias of the same spelling; the built-ins registered twice still
// refreshing; gradients and enums that would not survive a save.

import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

class Foo extends Component {}

class Bar extends Component {}

ComponentDefinition<T> _def<T extends Component>(
  String type,
  T Function() create, {
  List<String> aliases = const [],
}) => ComponentDefinition<T>(
  type: type,
  aliases: aliases,
  create: create,
  fields: const [],
);

void main() {
  test('an override with another Dart type drops the old type', () {
    final registry = ComponentDefinitionRegistry()
      ..register(_def<Foo>('X', Foo.new));
    registry.register(_def<Bar>('X', Bar.new), override: true);
    expect(registry.definitionFor(Foo()), isNull);
    expect(registry.definitionFor(Bar())?.type, 'X');
  });

  test('unregister leaves another registration of the Dart type', () {
    final registry = ComponentDefinitionRegistry()
      ..register(_def<Foo>('Y', Foo.new))
      ..register(_def<Foo>('X', Foo.new));
    registry.unregister('X');
    expect(registry.canEncode(Foo()), isTrue);
    expect(registry.definitionFor(Foo())?.type, 'Y');
  });

  test('a registered type wins over an alias of the same name', () {
    final registry = ComponentDefinitionRegistry()
      ..register(_def<Foo>('X', Foo.new, aliases: ['Y']))
      ..register(_def<Bar>('Y', Bar.new));
    expect(registry.decode({'type': 'Y', 'fields': {}}), isA<Bar>());
  });

  test('registering the built-ins again keeps them refreshable', () {
    final registry = ComponentDefinitionRegistry.core();
    registerCoreCodecs(registry);
    final before = registry.definitionByType('TransformComponent');
    registry.refresh(CoreDefinitions.all);
    expect(
      identical(registry.definitionByType('TransformComponent'), before),
      isFalse,
      reason: 'a second registerCoreCodecs must not pin the definitions',
    );
  });

  test('a gradient that could not paint is dropped on load', () {
    ShapeGradient? gradient(Map<String, Object?> raw) =>
        ShapePaintStyleFieldType.decodeStyle({
          'color': 0xFF000000,
          'gradient': raw,
        }, fallbackColor: const Color(0xFF000000)).gradient;
    // One colour: no gradient.
    expect(
      gradient({
        'kind': 'linear',
        'colors': [0xFFFF0000],
      }),
      isNull,
    );
    // Stops that don't pair with the colours: even spacing instead.
    final g = gradient({
      'kind': 'linear',
      'colors': [0xFFFF0000, 0xFF0000FF],
      'stops': [0.0, null],
    })!;
    expect(g.colors, [const Color(0xFFFF0000), const Color(0xFF0000FF)]);
    expect(g.stops, isNull);
  });

  test('an enum that overrides toString saves its name', () {
    expect(FieldTypes.enumeration.encodeAny(_Shown.loud), 'loud');
  });
}

enum _Shown {
  loud;

  @override
  String toString() => 'LOUD!';
}

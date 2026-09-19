// One description per component: the definition is the codec, the registry
// never clobbers silently, and a subclass either has its own definition or
// is refused rather than quietly saved as its base.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

class ShieldedHealth extends HealthComponent {
  ShieldedHealth({super.maxHealth = 100, this.shield = 0});
  double shield;
}

/// A field type the engine has never heard of: a grid coordinate.
class CellFieldType extends FieldType<(int, int)> {
  const CellFieldType();
  @override
  String get id => 'test.cell';
  @override
  Object? encode((int, int) value) => '${value.$1},${value.$2}';
  @override
  Object? decode(Object? json, FieldConstraints c) {
    final parts = (json as String).split(',');
    return (int.parse(parts[0]), int.parse(parts[1]));
  }
}

class _OtherCell extends CellFieldType {
  const _OtherCell();
}

class Marker extends Component {
  (int, int) cell = (0, 0);
}

void main() {
  late ComponentDefinitionRegistry registry;
  setUp(() {
    registry = ComponentDefinitionRegistry()..registerAll(CoreDefinitions.all);
  });

  test('re-registering the same instance is a no-op', () {
    expect(() => registry.register(CoreDefinitions.health), returnsNormally);
  });

  test('a different definition for the same type throws unless overridden', () {
    final mine = ComponentDefinition<HealthComponent>(
      type: 'HealthComponent',
      create: () => HealthComponent(maxHealth: 1),
      fields: const [],
    );
    expect(() => registry.register(mine), throwsStateError);
    registry.register(mine, override: true);
    expect(registry.definitionByType('HealthComponent'), same(mine));
    // Core re-registration must not undo the override.
    registerCoreCodecs(registry);
    expect(registry.definitionByType('HealthComponent'), same(mine));
  });

  test('the definition is the wire format', () {
    registerCoreCodecs(registry);
    final health = HealthComponent(maxHealth: 5)..health = 2;
    final json = registry.encode(health)!;
    expect(json.keys, unorderedEquals(['type', 'fields']));
    expect(json['fields'], containsPair('maxHealth', 5.0));
    expect(registry.definitionFor(health), same(CoreDefinitions.health));
  });

  test('aliases resolve to the definition', () {
    final def = ComponentDefinition<Marker>(
      type: 'MarkerComponent',
      aliases: const ['OldMarker', 'marker_ab12'],
      create: Marker.new,
      fields: const [],
    );
    registry.register(def);
    expect(registry.definitionByType('OldMarker'), same(def));
    expect(
      registry.decode({'type': 'marker_ab12', 'fields': {}}),
      isA<Marker>(),
    );
  });

  test('an undefined subclass is not silently saved as its base', () {
    final c = ShieldedHealth(shield: 7);
    expect(registry.forComponent(c), isNull);
    expect(registry.definitionFor(c), isNull);
    expect(
      registry.nearestFor(c),
      same(CoreDefinitions.health),
      reason: 'so the editor can name the base it would lose fields to',
    );
  });

  test('extend() round-trips the subclass fields', () {
    final def = ComponentDefinition<ShieldedHealth>.extend(
      CoreDefinitions.health,
      type: 'ShieldedHealth',
      create: ShieldedHealth.new,
      extraFields: [
        SchemaField(
          name: 'shield',
          kind: FieldTypes.decimal,
          read: (c) => (c as ShieldedHealth).shield,
          write: (c, v) => (c as ShieldedHealth).shield = v as double,
        ),
      ],
    );
    registry.register(def);
    final source = ShieldedHealth(maxHealth: 40, shield: 9)..health = 12;
    final back = registry.decode(registry.encode(source)!)! as ShieldedHealth;
    expect((back.maxHealth, back.health, back.shield), (40.0, 12.0, 9.0));
    expect(def.parent, same(CoreDefinitions.health));
    expect(def.hints.group, 'Gameplay', reason: 'inherited');
  });

  test('a custom field type round-trips through a definition', () {
    final def = ComponentDefinition<Marker>(
      type: 'Marker',
      create: Marker.new,
      fields: [
        SchemaField(
          name: 'cell',
          kind: const CellFieldType(),
          read: (c) => (c as Marker).cell,
          write: (c, v) => (c as Marker).cell = v as (int, int),
        ),
      ],
    );
    final json = def.encode(Marker()..cell = (3, -4));
    expect(json['fields'], {'cell': '3,-4'});
    expect(def.decode(json).cell, (3, -4));
  });

  test('the field type registry refuses a duplicate id unless overridden', () {
    final types = FieldTypeRegistry()..register(const CellFieldType());
    expect(types.byId('test.cell'), isA<CellFieldType>());
    expect(() => types.register(const _OtherCell()), throwsStateError);
    types.register(const _OtherCell(), override: true);
    expect(types.byId('test.cell'), isA<_OtherCell>());
  });

  test('an enum type knows its names and falls back on an unknown one', () {
    const t = EnumFieldType(BodyType.values, fallback: BodyType.static);
    expect(t.names, ['static', 'kinematic', 'dynamic']);
    expect(t.decode('kinematic', FieldConstraints.none), BodyType.kinematic);
    expect(t.decode('bogus', FieldConstraints.none), BodyType.static);
  });
}

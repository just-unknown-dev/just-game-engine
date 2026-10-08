// Definitions put in place again after a hot reload.
//
// Definitions are built when a context is made. An editor that keeps one
// engine running across hot reloads asks for them again
// (EngineContext.refreshDefinitions), so a field just added to a component
// shows without a restart — while a project's own replacement of a
// definition stays where the project put it.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

class Gem extends Component {
  int value = 1;
  double shine = 0;
}

ComponentDefinition<Gem> gemDefinition({
  bool withShine = false,
  List<String> aliases = const [],
}) => ComponentDefinition<Gem>(
  type: 'GemComponent',
  aliases: aliases,
  create: Gem.new,
  fields: [
    SchemaField(
      name: 'value',
      kind: FieldTypes.integer,
      read: (c) => (c as Gem).value,
      write: (c, v) => (c as Gem).value = v as int,
    ),
    if (withShine)
      SchemaField(
        name: 'shine',
        kind: FieldTypes.decimal,
        read: (c) => (c as Gem).shine,
        write: (c, v) => (c as Gem).shine = v as double,
      ),
  ],
);

/// An extension whose code "changes" between installs, as a hot reload
/// would change it.
final class GemKit implements RefreshableExtension {
  GemKit();

  bool withShine = false;
  int refreshes = 0;

  @override
  String get id => 'test.gems';

  @override
  void install(EngineContext context) => context.definitions.registerAll([
    gemDefinition(withShine: withShine),
  ], ifAbsent: true);

  @override
  void refresh(EngineContext context) {
    refreshes++;
    context.definitions.refresh([gemDefinition(withShine: withShine)]);
  }
}

final class PlainKit implements ContextExtension {
  @override
  String get id => 'test.plain';

  @override
  void install(EngineContext context) {}
}

class Step extends System {
  Step(this.label, int priority) {
    this.priority = priority;
  }

  final String label;

  @override
  List<Type> get requiredComponents => const [];
}

List<String> fieldNames(ComponentDefinition? d) => [
  for (final f in d?.fields ?? const <SchemaField>[]) f.name,
];

void main() {
  group('ComponentDefinitionRegistry.refresh', () {
    test('replaces a definition, so its new field is read and written', () {
      final registry = ComponentDefinitionRegistry()..register(gemDefinition());
      registry.refresh([gemDefinition(withShine: true)]);

      final def = registry.definitionByType('GemComponent');
      expect(fieldNames(def), ['value', 'shine']);
      expect(registry.definitionFor(Gem()), same(def));
      final gem = Gem()..shine = 0.5;
      final back = registry.decode(registry.encode(gem)!)! as Gem;
      expect(back.shine, 0.5);
    });

    test('adds a type it has not seen', () {
      final registry = ComponentDefinitionRegistry()
        ..refresh([gemDefinition()]);
      expect(registry.definitionByType('GemComponent'), isNotNull);
    });

    test('takes the old aliases away with the old definition', () {
      final registry = ComponentDefinitionRegistry()
        ..register(gemDefinition(aliases: const ['OldGem']));
      registry.refresh([
        gemDefinition(aliases: const ['Jewel']),
      ]);
      expect(registry.definitionByType('OldGem'), isNull);
      expect(registry.definitionByType('Jewel'), isNotNull);
    });

    test("leaves a project's override alone — unless asked", () {
      final mine = gemDefinition(withShine: true);
      final registry = ComponentDefinitionRegistry()
        ..register(gemDefinition())
        ..register(mine, override: true);

      registry.refresh([gemDefinition()]);
      expect(registry.definitionByType('GemComponent'), same(mine));

      final next = gemDefinition(withShine: true);
      registry.refresh([next], override: true);
      expect(registry.definitionByType('GemComponent'), same(next));
    });

    test('keeps one a project registered before an ifAbsent registration', () {
      final mine = gemDefinition(withShine: true);
      final registry = ComponentDefinitionRegistry()
        ..register(mine)
        ..registerAll([gemDefinition()], ifAbsent: true);

      registry.refresh([gemDefinition()]);
      expect(registry.definitionByType('GemComponent'), same(mine));
    });
  });

  group('EngineContext.refreshDefinitions', () {
    test("refreshes each refreshable extension's definitions", () {
      final kit = GemKit();
      final context = EngineContext(extensions: [kit, PlainKit()]);
      expect(fieldNames(context.definitions.definitionByType('GemComponent')), [
        'value',
      ]);

      kit.withShine = true; // the code "changed"
      context.refreshDefinitions();

      expect(kit.refreshes, 1);
      expect(fieldNames(context.definitions.definitionByType('GemComponent')), [
        'value',
        'shine',
      ]);
    });

    test("puts the engine's own definitions in place again", () {
      final context = EngineContext();
      final before = context.definitions.definitionByType('HealthComponent');
      context.refreshDefinitions();
      final after = context.definitions.definitionByType('HealthComponent');
      expect(after, isNotNull);
      expect(identical(before, after), isFalse, reason: 'built again');
      expect(fieldNames(after), fieldNames(before));
    });

    test("keeps a project's replacement of an engine definition", () {
      final context = EngineContext();
      final mine = ComponentDefinition<HealthComponent>.extend(
        CoreDefinitions.health,
        type: 'HealthComponent',
        create: () => HealthComponent(maxHealth: 1),
        extraFields: const [],
      );
      context.definitions.register(mine, override: true);
      context.refreshDefinitions();
      expect(
        context.definitions.definitionByType('HealthComponent'),
        same(mine),
      );
    });
  });

  test('World.sortSystems puts a changed priority in effect', () {
    final world = World();
    final a = Step('a', 10);
    final b = Step('b', 5);
    world
      ..addSystem(a)
      ..addSystem(b);
    expect([for (final s in world.systems) (s as Step).label], ['a', 'b']);

    b.priority = 20; // as an edited getter would, after a hot reload
    world.sortSystems();
    expect([for (final s in world.systems) (s as Step).label], ['b', 'a']);
    world.dispose();
  });

  test('no engine definition is a static final, which a reload would keep', () {
    // A static final is built once and never again: an edited field would
    // not show until a restart. Each must be a getter.
    final offenders = <String>[];
    final pattern = RegExp(
      r'^\s*static final \w+ =\s*Component(Definition|Schema)<',
      multiLine: true,
    );
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      if (pattern.hasMatch(file.readAsStringSync())) offenders.add(file.path);
    }
    expect(offenders, isEmpty);
  });
}

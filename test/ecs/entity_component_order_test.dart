// An entity keeps its components in its own order: as they were added, or
// as reorderComponents put them — whatever order the archetype it shares
// with every entity of the same types keeps. What an editor lists, and what
// a scene saves; systems find components by type, so nothing else changes.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

List<Type> typesOf(Entity e) => [for (final c in e.components) c.componentType];

void main() {
  late World world;
  setUp(() => world = World()..initialize());
  tearDown(() => world.dispose());

  test('components come in the order they were added, per entity', () {
    final a = world.createEntity()
      ..addComponent(TransformComponent())
      ..addComponent(VelocityComponent())
      ..addComponent(HealthComponent(maxHealth: 3));
    // The same types, so the same archetype — added in another order.
    final b = world.createEntity()
      ..addComponent(HealthComponent(maxHealth: 3))
      ..addComponent(TransformComponent())
      ..addComponent(VelocityComponent());

    expect(typesOf(a), [
      TransformComponent,
      VelocityComponent,
      HealthComponent,
    ]);
    expect(typesOf(b), [
      HealthComponent,
      TransformComponent,
      VelocityComponent,
    ]);
    expect(b.componentTypes, typesOf(b));
  });

  test('an entity made with its components keeps the order given', () {
    final e = world.createEntityWithComponents([
      LifetimeComponent(5),
      TransformComponent(),
      VelocityComponent(),
    ]);
    expect(typesOf(e), [
      LifetimeComponent,
      TransformComponent,
      VelocityComponent,
    ]);
  });

  test('a replaced component keeps its place; a new one goes last', () {
    final e = world.createEntityWithComponents([
      TransformComponent(),
      HealthComponent(maxHealth: 3),
      VelocityComponent(),
    ]);
    e.addComponent(HealthComponent(maxHealth: 9));
    expect(typesOf(e), [
      TransformComponent,
      HealthComponent,
      VelocityComponent,
    ]);
    expect(e.getComponent<HealthComponent>()!.maxHealth, 9);

    e.addComponent(LifetimeComponent(1));
    expect(typesOf(e).last, LifetimeComponent);
  });

  test('a removed component leaves the others in their order', () {
    final e = world.createEntityWithComponents([
      TransformComponent(),
      HealthComponent(maxHealth: 3),
      VelocityComponent(),
    ]);
    e.removeComponent<HealthComponent>();
    expect(typesOf(e), [TransformComponent, VelocityComponent]);
    e.removeComponent<TransformComponent>();
    e.removeComponent<VelocityComponent>();
    expect(e.components, isEmpty);
    expect(e.componentTypes, isEmpty);
  });

  test('reorderComponents puts the listed first, the rest as they were', () {
    final e = world.createEntityWithComponents([
      TransformComponent(),
      HealthComponent(maxHealth: 3),
      VelocityComponent(),
      LifetimeComponent(1),
    ]);
    e.reorderComponents([LifetimeComponent, HealthComponent, TagComponent]);
    expect(typesOf(e), [
      LifetimeComponent,
      HealthComponent,
      TransformComponent,
      VelocityComponent,
    ], reason: 'a type it has none of is passed over');
  });

  test('reordering changes nothing a system sees', () {
    final e = world.createEntityWithComponents([
      TransformComponent(),
      VelocityComponent(),
    ]);
    final before = world.query([TransformComponent, VelocityComponent]).length;
    e.reorderComponents([VelocityComponent, TransformComponent]);
    expect(world.query([TransformComponent, VelocityComponent]).length, before);
    expect(e.getComponent<VelocityComponent>(), isNotNull);
  });

  test('an iteration is not disturbed by a change made during it', () {
    final e = world.createEntityWithComponents([
      TransformComponent(),
      VelocityComponent(),
    ]);
    final seen = <Type>[];
    for (final c in e.components) {
      seen.add(c.componentType);
      if (seen.length == 1) {
        e.reorderComponents([VelocityComponent, TransformComponent]);
      }
    }
    expect(seen, [TransformComponent, VelocityComponent]);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  late World world;
  late EntitySpatialGrid grid;

  setUp(() {
    world = World();
    grid = EntitySpatialGrid(cellSize: 100);
  });

  Rect pointBoundsAt(Offset position) =>
      Rect.fromCenter(center: position, width: 1, height: 1);

  test('query finds an entity whose cell overlaps the query rect', () {
    final entity = world.createEntity(name: 'a');
    final positions = <Entity, Offset>{entity: const Offset(50, 50)};

    grid.sync(world.entities, (e) => pointBoundsAt(positions[e]!));

    final candidates = grid.query(const Rect.fromLTWH(0, 0, 200, 200));
    expect(candidates, contains(entity));
  });

  test('query does not find an entity far outside the query rect', () {
    final entity = world.createEntity(name: 'a');
    final positions = <Entity, Offset>{entity: const Offset(5000, 5000)};

    grid.sync(world.entities, (e) => pointBoundsAt(positions[e]!));

    final candidates = grid.query(const Rect.fromLTWH(0, 0, 200, 200));
    expect(candidates, isNot(contains(entity)));
  });

  test(
    'moving within the same cell does not change the tracked entity count',
    () {
      final entity = world.createEntity(name: 'a');
      var position = const Offset(10, 10);

      grid.sync(world.entities, (e) => pointBoundsAt(position));
      expect(grid.trackedEntityCount, 1);

      // Still inside the same 100x100 cell (0,0)..(99,99).
      position = const Offset(20, 30);
      grid.sync(world.entities, (e) => pointBoundsAt(position));
      expect(grid.trackedEntityCount, 1);

      final candidates = grid.query(const Rect.fromLTWH(0, 0, 100, 100));
      expect(candidates, contains(entity));
    },
  );

  test('an entity that crosses a cell boundary is relocated correctly', () {
    final entity = world.createEntity(name: 'a');
    var position = const Offset(10, 10); // cell (0,0)

    grid.sync(world.entities, (e) => pointBoundsAt(position));
    expect(grid.query(const Rect.fromLTWH(0, 0, 50, 50)), contains(entity));

    // Jump far away into a completely different cell.
    position = const Offset(1010, 1010); // cell (10,10)
    grid.sync(world.entities, (e) => pointBoundsAt(position));

    // No longer found at the old location...
    expect(
      grid.query(const Rect.fromLTWH(0, 0, 50, 50)),
      isNot(contains(entity)),
    );
    // ...but found at the new one.
    expect(
      grid.query(const Rect.fromLTWH(950, 950, 150, 150)),
      contains(entity),
    );
  });

  test('an entity removed from the source set is cleaned out of the grid', () {
    final entity = world.createEntity(name: 'a');
    const position = Offset(10, 10);

    grid.sync([entity], (e) => pointBoundsAt(position));
    expect(grid.trackedEntityCount, 1);

    // Sync again with an empty entity set — simulates the entity despawning.
    grid.sync(const <Entity>[], (e) => pointBoundsAt(position));
    expect(grid.trackedEntityCount, 0);
    expect(
      grid.query(const Rect.fromLTWH(0, 0, 100, 100)),
      isNot(contains(entity)),
    );
  });

  test('query deduplicates an entity whose bounds span multiple cells', () {
    final entity = world.createEntity(name: 'a');
    // A wide bounds box straddling several 100-unit cells.
    final bounds = const Rect.fromLTWH(0, 0, 350, 10);

    grid.sync(world.entities, (e) => bounds);

    final candidates = grid.query(const Rect.fromLTWH(0, 0, 400, 400));
    expect(candidates.where((e) => e == entity).length, 1);
  });
}

// More audit fixes: a spatial grid that survives bad bounds. (The reactive
// system's and 3-D culling's are in reactive/reactive_system_watch_test.dart
// and rendering/culling_3d_columns_test.dart.)

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('spatial grid with bad bounds', () {
    late World world;
    setUp(() => world = World(extensions: [BuiltInComponents.extension]));
    tearDown(() => world.dispose());

    test('non-finite bounds are left out instead of throwing', () {
      final grid = EntitySpatialGrid(cellSize: 10);
      final good = world.createEntity();
      final nan = world.createEntity();
      final inf = world.createEntity();
      final bounds = {
        good: const Rect.fromLTWH(0, 0, 5, 5),
        nan: const Rect.fromLTWH(double.nan, 0, 5, 5),
        inf: const Rect.fromLTRB(0, 0, double.infinity, 5),
      };
      grid.sync([good, nan, inf], (e) => bounds[e]!);
      expect(grid.trackedEntityCount, 1);
      expect(grid.query(const Rect.fromLTWH(-1, -1, 3, 3)), [good]);

      // Finite again: tracked again.
      bounds[nan] = const Rect.fromLTWH(100, 100, 5, 5);
      grid.sync([good, nan, inf], (e) => bounds[e]!);
      expect(grid.query(const Rect.fromLTWH(99, 99, 3, 3)), [nan]);
    });

    test('huge bounds do not hang, and are found everywhere', () {
      final grid = EntitySpatialGrid(cellSize: 10, maxCellSpan: 8);
      final huge = world.createEntity();
      final small = world.createEntity();
      final far = world.createEntity();
      Rect boundsOf(Entity e) => e == huge
          ? const Rect.fromLTRB(-1e300, -1e300, 1e300, 1e300)
          : e == far
          ? const Rect.fromLTWH(1e15, 1e15, 1, 1)
          : const Rect.fromLTWH(0, 0, 5, 5);
      final watch = Stopwatch()..start();
      grid.sync([huge, small, far], boundsOf);
      expect(watch.elapsedMilliseconds, lessThan(1000));
      expect(grid.trackedEntityCount, 3);
      expect(
        grid.query(const Rect.fromLTWH(500, 500, 1, 1)),
        containsAll([huge, far]),
      );
      expect(
        grid.query(const Rect.fromLTWH(0, 0, 1, 1)),
        containsAll([huge, small]),
      );
      // Shrinking it files it in cells again.
      grid.sync([small], boundsOf);
      expect(grid.trackedEntityCount, 1);
      expect(grid.query(const Rect.fromLTWH(500, 500, 1, 1)), isEmpty);
    });

    test('an infinite query finds everything; a NaN one nothing', () {
      final grid = EntitySpatialGrid(cellSize: 10);
      final a = world.createEntity();
      final b = world.createEntity();
      grid.sync([a, b], (e) {
        return e == a
            ? const Rect.fromLTWH(0, 0, 5, 5)
            : const Rect.fromLTWH(1000, 1000, 5, 5);
      });
      expect(
        grid.query(
          const Rect.fromLTRB(
            double.negativeInfinity,
            double.negativeInfinity,
            double.infinity,
            double.infinity,
          ),
        ),
        unorderedEquals([a, b]),
      );
      expect(grid.query(Rect.largest), unorderedEquals([a, b]));
      expect(grid.query(const Rect.fromLTWH(double.nan, 0, 1, 1)), isEmpty);
    });
  });
}

// More audit fixes: a reactive system that lets go of what it watches and
// watches what comes later, a spatial grid that survives bad bounds, and
// 3-D culling that reads only the columns with an extent.

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// Counts the listeners on it.
class Hp extends Component with ReactiveComponent {
  Hp(this._hp);
  double _hp;
  int listeners = 0;

  double get hp => _hp;
  set hp(double v) {
    if (_hp == v) return;
    _hp = v;
    notifyChange('hp');
  }

  @override
  void addChangeListener(VoidCallback listener) {
    listeners++;
    super.addChangeListener(listener);
  }

  @override
  void removeChangeListener(VoidCallback listener) {
    listeners--;
    super.removeChangeListener(listener);
  }
}

class _Tracking extends ReactiveSystem {
  final List<EntityId> processed = [];

  @override
  List<Type> get requiredComponents => const [Hp];

  @override
  void processEntity(Entity entity, double dt) => processed.add(entity.id);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('reactive system watches (C15)', () {
    late World world;
    late WorldSignal signal;
    late _Tracking system;
    setUp(() {
      world = World()..initialize();
      signal = WorldSignal(world);
      system = _Tracking()..setWorldSignal(signal);
    });
    tearDown(() {
      signal.dispose();
      world.dispose();
    });

    test('lets go of every listener when removed', () {
      final hp = Hp(10);
      world.createEntityWithComponents([hp]);
      world.addSystem(system);
      expect(hp.listeners, 1);
      world.removeSystem(system);
      expect(hp.listeners, 0);
    });

    test('watching twice does not listen twice', () {
      final hp = Hp(10);
      final e = world.createEntityWithComponents([hp]);
      world.addSystem(system);
      system.watchEntity(e);
      system.watchEntity(e);
      expect(hp.listeners, 1);
    });

    test('watches entities made later, and lets destroyed ones go', () {
      world.addSystem(system);
      world.update(0.016); // the first run
      system.processed.clear();

      final hp = Hp(10);
      final e = world.createEntityWithComponents([hp]);
      world.update(0.016);
      expect(system.processed, [e.id], reason: 'processed once, arriving');
      expect(hp.listeners, 1);

      system.processed.clear();
      hp.hp = 5;
      world.update(0.016);
      expect(system.processed, [e.id], reason: 'a change is seen');

      world.destroyEntity(e);
      world.update(0.016);
      expect(hp.listeners, 0);
    });

    test('a replaced component is watched instead of the old one', () {
      final old = Hp(10);
      final e = world.createEntityWithComponents([old]);
      world.addSystem(system);
      world.update(0.016);
      final next = Hp(20);
      e.addComponent(next);
      world.update(0.016);
      expect(old.listeners, 0);
      expect(next.listeners, 1);
      system.processed.clear();
      next.hp = 1;
      world.update(0.016);
      expect(system.processed, [e.id]);
    });
  });

  group('spatial grid with bad bounds (C16)', () {
    late World world;
    setUp(() => world = World());
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

  group('3-D culling by the columns with an extent (P5)', () {
    late World world;
    setUp(() {
      world = World();
      world.addSystem(
        ViewCullingSystem(
          camera: Camera(
            viewportSize: const Size(400, 400),
            z: -10,
            lens: const CameraLens.perspective(fieldOfView: math.pi / 2),
          ),
        )..activeDistance = 1,
      );
    });
    tearDown(() => world.dispose());

    test('an entity outside the view but reaching into it is visible, and '
        'a size change is seen', () {
      // At x 200, far beyond the view's edge (10 at this distance) —
      // unless its rectangle reaches back into it.
      final rect = RectangleComponent(width: 500, height: 4);
      final e = world.createEntityWithComponents([
        TransformComponent(position: Vector3(200, 0, 0)),
        CullStateComponent(),
        rect,
        TagComponent('wide'),
      ]);
      final cull = e.getComponent<CullStateComponent>()!;
      world.update(1 / 60);
      expect(cull.isVisible, isTrue);

      // A smaller rectangle in its place: out of view.
      e.addComponent(RectangleComponent(width: 2, height: 2));
      world.update(1 / 60);
      expect(cull.isVisible, isFalse);
    });

    test('several shapes in one column are each measured', () {
      final wide = world.createEntityWithComponents([
        TransformComponent(position: Vector3(200, 0, 0)),
        CullStateComponent(),
        RectangleComponent(width: 500, height: 4),
      ]);
      final round = world.createEntityWithComponents([
        TransformComponent(position: Vector3(200, 0, 0)),
        CullStateComponent(),
        CircleComponent(radius: 1),
      ]);
      world.update(1 / 60);
      expect(wide.getComponent<CullStateComponent>()!.isVisible, isTrue);
      expect(round.getComponent<CullStateComponent>()!.isVisible, isFalse);
    });
  });
}

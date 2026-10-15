// Per-query versions: each cached query's version moves on only when what
// it matches changes, so a system rebuilding what it keeps per entity does
// it when its own queries changed — not on every structural change in the
// world.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

class A extends Component {}

class B extends Component {}

class Other extends Component {}

class Unrelated extends Component {}

void main() {
  late World world;
  setUp(() => world = World());
  tearDown(() => world.dispose());

  /// Whether [types]' version moved since [seen] last looked.
  bool Function() watcher(List<Type> types) {
    var seen = world.queryVersion(types);
    return () {
      final now = world.queryVersion(types);
      final moved = now != seen;
      seen = now;
      return moved;
    };
  }

  test('moves on every change to what the query matches, not on reads', () {
    final moved = watcher([A]);

    final e = world.createEntity(name: 'a');
    expect(moved(), isFalse, reason: 'an entity with no A');
    e.addComponent(A());
    expect(moved(), isTrue, reason: 'gained A');
    world.query([A]);
    world.queryArchetypes([A]);
    expect(moved(), isFalse, reason: 'a query is not a change');
    e.addComponent(B());
    expect(moved(), isTrue, reason: 'a member gained another component');
    e.addComponent(B());
    expect(moved(), isTrue, reason: 'a member had a component replaced');
    e.isActive = false;
    expect(moved(), isTrue, reason: 'switched off');
    e.isActive = true;
    expect(moved(), isTrue, reason: 'switched on');
    e.removeComponent<B>();
    expect(moved(), isTrue, reason: 'a member lost another component');
    e.removeComponent<A>();
    expect(moved(), isTrue, reason: 'lost A');
    e.addComponent(A());
    moved();
    world.destroyEntity(e);
    expect(moved(), isTrue, reason: 'destroyed');
    world.createEntityWithComponents([A(), B()]);
    expect(moved(), isTrue, reason: 'created with A');
  });

  test('an unrelated structural change leaves the query alone', () {
    world.createEntityWithComponents([A()]);
    final busy = world.createEntityWithComponents([Other()]);
    final moved = watcher([A]);

    // What a frame of unrelated gameplay does.
    busy.addComponent(Unrelated());
    busy.removeComponent<Unrelated>();
    busy.isActive = false;
    busy.isActive = true;
    final made = world.createEntityWithComponents([Other(), Unrelated()]);
    world.destroyEntity(made);
    world.createEntity();

    expect(moved(), isFalse);
    expect(world.query([A]), hasLength(1));
  });

  test('versions are unique world-wide, and go up', () {
    final a = world.queryVersion([A]);
    final b = world.queryVersion([B]);
    expect(a, isNot(b));
    world.createEntityWithComponents([A()]);
    final a2 = world.queryVersion([A]);
    expect(a2, greaterThan(a));
    expect(a2, greaterThan(b), reason: 'the largest of several moves on');
    // The same query asked with the types in another order.
    expect(world.queryVersion([A, B]), world.queryVersion([B, A]));
  });

  test('a query asked for again after destroyAllEntities is new', () {
    world.createEntityWithComponents([A()]);
    final before = world.queryVersion([A]);
    world.destroyAllEntities();
    expect(world.queryVersion([A]), isNot(before));
  });

  group('the systems built on them still see what they read', () {
    test('the render system draws what comes and stops drawing what goes', () {
      final render = RenderSystem();
      world.addSystem(render);
      final first = world.createEntityWithComponents([
        TransformComponent(),
        RectangleComponent(width: 4, height: 4),
      ]);
      expect(render.debugDrawOrder().map((d) => d.$1), [first]);

      // Unrelated churn: nothing to rebuild, nothing changes.
      final other = world.createEntityWithComponents([Other()]);
      other.addComponent(Unrelated());
      expect(render.debugDrawOrder().map((d) => d.$1), [first]);

      final second = world.createEntityWithComponents([
        TransformComponent(),
        CircleComponent(radius: 2),
      ]);
      expect(render.debugDrawOrder().map((d) => d.$1), [first, second]);

      // A renderable replaced is drawn as the new one.
      final replacement = RectangleComponent(width: 8, height: 8);
      first.addComponent(replacement);
      expect(
        render.debugDrawOrder().map((d) => d.$1),
        containsAll([first, second]),
      );

      world.destroyEntity(second);
      expect(render.debugDrawOrder().map((d) => d.$1), [first]);
    });

    test('physics makes a body for a collider added after unrelated churn', () {
      final physics = PhysicsEngine()..initialize();
      addTearDown(physics.dispose);
      world.addSystem(PhysicsSystem(physics));
      world.update(1 / 60);
      final other = world.createEntityWithComponents([Other()]);
      other.addComponent(Unrelated());
      world.update(1 / 60);
      final box = world.createEntityWithComponents([
        TransformComponent(),
        Collider2D(size: Vector2(4, 4)),
      ]);
      world.update(1 / 60);
      expect(box.hasComponent<PhysicsBodyRefComponent>(), isTrue);
      box.removeComponent<Collider2D>();
      world.update(1 / 60);
      expect(box.hasComponent<PhysicsBodyRefComponent>(), isFalse);
    });
  });
}

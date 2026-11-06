// FlowFieldSystem: following the field reaches the target around an
// obstacle; outside the window, or with no target, there is no direction;
// the field is recomputed only on its interval; a switched-off entity of
// the target's name is not chased.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  late World world;
  late FlowFieldSystem field;

  setUp(() {
    world = World()..initialize();
    field = FlowFieldSystem(cellSize: 10, activeWindowSize: 600);
    world.addSystem(field);
  });
  tearDown(() => world.dispose());

  Entity place(String? name, double x, double y, [List<Component>? more]) =>
      world.createEntityWithComponents([
        TransformComponent(position: Vector3(x, y, 0)),
        ...?more,
      ], name: name);

  /// Follows the field from [from], one cell at a time, until it runs out;
  /// the cells visited.
  List<Offset> follow(Offset from, {int maxSteps = 200}) {
    final path = [from];
    var at = from;
    for (var i = 0; i < maxSteps; i++) {
      final dir = field.directionAt(at);
      if (dir == null) break;
      final step = dir / dir.distance * 10;
      at = at + step;
      path.add(at);
    }
    return path;
  }

  test('following it reaches the player without entering the obstacle', () {
    place('Player', 0, 0);
    final obstacle = place(null, 100, 0, [
      NavigationObstacleComponent(radius: 30),
    ]);
    world.update(1 / 60);
    final path = follow(const Offset(200, 5));
    expect((path.last - Offset.zero).distance, lessThan(15));
    final centre = obstacle
        .getComponent<TransformComponent>()!
        .position
        .toOffset();
    for (final point in path) {
      expect(
        (point - centre).distance,
        greaterThan(20),
        reason: 'went through the obstacle at $point',
      );
    }
  });

  test('outside the window, or with no player, there is no direction', () {
    place('Player', 0, 0);
    world.update(1 / 60);
    expect(field.directionAt(const Offset(1000, 0)), isNull);

    final other = World()..initialize();
    addTearDown(other.dispose);
    final lonely = FlowFieldSystem(cellSize: 10, activeWindowSize: 400);
    other.addSystem(lonely);
    other.update(1 / 60);
    expect(lonely.directionAt(const Offset(50, 0)), isNull);
  });

  test('the field is recomputed only once the interval has passed', () {
    place('Player', 0, 0);
    final obstacle = place(null, 100, 0, [
      NavigationObstacleComponent(radius: 30),
    ]);
    world.update(1 / 60);
    final before = field.directionAt(const Offset(135, 5));
    // The obstacle goes; within the interval the field stays as it was.
    obstacle.getComponent<TransformComponent>()!.position.x = 1000;
    world.update(0.05);
    expect(field.directionAt(const Offset(135, 5)), before);
    world.update(0.2);
    final after = field.directionAt(const Offset(135, 5))!;
    expect(after.dx, lessThan(0), reason: 'straight at the player now');
    expect(after.dy.abs(), lessThan(1e-9));
  });

  test('a switched-off entity named Player is not chased', () {
    final corpse = place('Player', 0, 0);
    corpse.isActive = false;
    place('Player', 300, 0); // the live one
    world.update(1 / 60);
    final dir = field.directionAt(const Offset(250, 0))!;
    expect(dir.dx, greaterThan(0), reason: 'towards the live player');
  });
}

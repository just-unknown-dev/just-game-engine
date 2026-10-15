// One number of a vector field, written by a timeline: straight into the
// value, without the saved form — the other parts kept, and a field that
// hands out the value it holds still given a value of its own.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  late World world;
  setUp(() => world = World());

  test('a channel of a Vector3 and of Euler angles', () {
    final transform = TransformComponent(position: Vector3(1, 2, 3));
    final entity = world.createEntityWithComponents([transform]);
    final x = PropertyAccess.of(entity, 'TransformComponent', 'position', 'x')!;
    final z = PropertyAccess.of(entity, 'TransformComponent', 'position', 'z')!;
    for (var i = 0; i < 3; i++) {
      x.write(10.0 + i);
      z.write(-5.0 - i);
    }
    expect([transform.position.x, transform.position.y, transform.position.z], [12.0, 2.0, -7.0]);

    final turn = PropertyAccess.of(entity, 'TransformComponent', 'rotation', 'z')!;
    turn.write(0.5);
    expect((transform.eulerX, transform.eulerY, transform.angle), (0.0, 0.0, 0.5));
  });

  test('a field that hands out the Vector2 it holds', () {
    final collider = Collider2D(size: Vector2(4, 6));
    final entity = world.createEntityWithComponents([TransformComponent(), collider]);
    final x = PropertyAccess.of(entity, 'Collider2D', 'size', 'x')!;
    final y = PropertyAccess.of(entity, 'Collider2D', 'size', 'y')!;
    x.write(-3);
    expect([collider.size.x, collider.size.y], [3.0, 6.0], reason: 'through its own write');
    y.write(8);
    x.write(5);
    expect([collider.size.x, collider.size.y], [5.0, 8.0]);
  });

  test('a channel of an Offset', () {
    final collider = Collider2D(offset: const Offset(1, 2));
    final entity = world.createEntityWithComponents([TransformComponent(), collider]);
    PropertyAccess.of(entity, 'Collider2D', 'offset', 'dy')!.write(7);
    expect(collider.offset, const Offset(1, 7));
  });
}

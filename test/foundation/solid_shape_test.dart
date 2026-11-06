import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

class _Shaped extends Component implements SolidShapeSource {
  _Shaped(this.size);

  double size;

  @override
  Object get solidKey => ('shaped', size);

  @override
  List<SolidPart> get solidParts => [SolidBox(size / 2, size / 2, size / 2)];
}

void main() {
  test('parts are equal by value, hulls point by point', () {
    expect(const SolidBox(1, 2, 3, y: 1), const SolidBox(1, 2, 3, y: 1));
    expect(const SolidBox(1, 2, 3), isNot(const SolidBox(1, 2, 3, x: 1)));
    expect(const SolidSphere(1).hashCode, const SolidSphere(1).hashCode);
    expect(const SolidCapsule(0.5, 0.3), const SolidCapsule(0.5, 0.3));
    expect(const SolidCylinder(0.5, 0.3), isNot(const SolidCapsule(0.5, 0.3)));
    final a = SolidHull(Float32List.fromList([0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1]));
    final b = SolidHull(Float32List.fromList([0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1]));
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a.length, 4);
  });

  test('a source is found among an entity\'s components and keys its shape', () {
    final world = World();
    final entity = world.createEntity(name: 'box')..addComponent(_Shaped(2));
    final source = entity.components.whereType<SolidShapeSource>().single;
    final key = source.solidKey;
    expect(source.solidParts, [const SolidBox(1, 1, 1)]);
    (source as _Shaped).size = 3;
    expect(source.solidKey, isNot(key));
  });
}

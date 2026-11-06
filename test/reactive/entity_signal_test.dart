// EntitySignal: isActive starts as the entity is, and sync finds a component
// by the type it is filed under.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

class _Base extends Component {}

/// Filed under [_Base], as a component standing in for another does.
class _Stand extends _Base {
  @override
  Type get componentType => _Base;
}

void main() {
  group('EntitySignal', () {
    late World world;

    setUp(() => world = World()..initialize());
    tearDown(() => world.dispose());

    test('isActive starts as the entity is', () {
      final off = world.createEntity()..isActive = false;
      expect(EntitySignal(off).isActive.value, isFalse);
      final on = world.createEntity();
      expect(EntitySignal(on).isActive.value, isTrue);
    });

    test('sync finds a component by the type it is filed under', () {
      final stand = _Stand();
      final entity = world.createEntityWithComponents([stand]);
      final signal = EntitySignal(entity);
      expect(signal.get<_Base>(), same(stand));
      signal.sync();
      expect(signal.get<_Base>(), same(stand), reason: 'sync lost it');
      entity.removeComponentByType(_Base);
      signal.sync();
      expect(signal.get<_Base>(), isNull);
    });
  });
}

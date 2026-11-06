// A reactive system lets go of what it watches, and watches what comes later.

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
  group('reactive system watches', () {
    late World world;
    late WorldSignal signal;
    late _Tracking system;
    setUp(() {
      world = World(extensions: [BuiltInComponents.extension])..initialize();
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
}

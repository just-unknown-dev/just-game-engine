// Nothing one SystemManager does leaks into another's.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  group('SystemManager', () {
    test('unregisterSystem by name removes the typed entry', () {
      final manager = SystemManager();
      final subsystem = _Subsystem();
      manager.registerSystem('sub', subsystem);
      expect(manager.getSystem<_Subsystem>(), same(subsystem));

      expect(manager.unregisterSystem('sub'), isTrue);
      expect(manager.getSystem<_Subsystem>(), isNull);
      expect(manager.hasSystemOfType<_Subsystem>(), isFalse);
    });

    test('a system is keyed by its declared type', () {
      final manager = SystemManager();
      final custom = _CustomSubsystem();
      manager.registerSystem<_Subsystem>('sub', custom);
      expect(manager.getSystem<_Subsystem>(), same(custom));
      expect(manager.getSystem<_CustomSubsystem>(), isNull);

      manager.unregisterSystem('sub');
      expect(manager.getSystem<_Subsystem>(), isNull);
    });

    test('unregistering a name leaves a newer typed entry alone', () {
      final manager = SystemManager();
      final first = _Subsystem();
      final second = _Subsystem();
      manager
        ..registerSystem('a', first)
        ..registerSystem('b', second); // Takes over the typed entry.
      manager.unregisterSystem('a');
      expect(manager.getSystem<_Subsystem>(), same(second));
    });
  });
}

/// Any engine subsystem: SystemManager keeps objects of any type.
class _Subsystem {}

class _CustomSubsystem extends _Subsystem {}

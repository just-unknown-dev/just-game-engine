// ServiceHost: a service whose start() replaces an earlier one does not make
// the next service in line go unstarted.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

class _Plain extends EngineService {
  _Plain(this.name, this.log);
  final String name;
  final List<String> log;
  @override
  Future<void> start(ServiceContext context) async => log.add('start $name');
  @override
  Future<void> stop() async => log.add('stop $name');
}

class _First extends _Plain {
  _First(super.name, super.log);
}

/// Replaces the [_First] when it starts.
class _Replacer extends _Plain {
  _Replacer(super.name, super.log);
  @override
  Future<void> start(ServiceContext context) async {
    await super.start(context);
    await context.engine.services.add(_First('first again', log));
  }
}

class _Last extends _Plain {
  _Last(super.name, super.log);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'every service starts, also after one replaced an earlier one',
    () async {
      final log = <String>[];
      final engine = Engine(
        config: EngineConfig(
          services: [
            _First('first', log),
            _Replacer('replacer', log),
            _Last('last', log),
          ],
        ),
      );
      addTearDown(engine.dispose);
      await engine.initialize();
      expect(log, containsAllInOrder(['start first', 'start replacer']));
      expect(log, contains('stop first'));
      expect(log, contains('start last'), reason: 'not skipped');
      expect(log, contains('start first again'));
      expect(
        engine.services.all.whereType<_First>().single.name,
        'first again',
      );
    },
  );
}

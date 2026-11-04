// PrefabLibrary loads that cross: a second load of a prefab waits for the
// prefabs nested in it; a loop of nested prefabs still ends, also across
// two loads at once; a reload during a read does not put the old file back;
// and the library is the context's own.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

const _outer = 'outer.prefab.json';
const _inner = 'inner.prefab.json';

PrefabFile _file(String name, {String? nests}) => PrefabFile(
  name: name,
  entities: [
    PrefabEntity(
      id: 'top',
      name: name,
      components: const [
        {'type': 'TransformComponent', 'fields': <String, dynamic>{}},
      ],
    ),
    if (nests != null)
      PrefabEntity(
        id: 'nested',
        name: 'Nested',
        parent: 'top',
        prefab: PrefabInstance(path: nests),
      ),
  ],
);

/// Serves prefab files, each read held until its gate is opened.
class _GatedFiles {
  _GatedFiles(this.files);

  final Map<String, PrefabFile> files;
  final Map<String, Completer<void>> gates = {};
  final List<String> reads = [];

  Future<PrefabFile> read(String path) async {
    reads.add(path);
    await (gates[path] ??= Completer<void>()).future;
    return files[path]!;
  }

  void open(String path) => (gates[path] ??= Completer<void>()).complete();
}

void main() {
  late World world;
  late _GatedFiles files;

  setUp(() {
    world = World(extensions: [BuiltInComponents.extension]);
    files = _GatedFiles({
      _outer: _file('Outer', nests: _inner),
      _inner: _file('Inner'),
    });
    world.context.overrideLoaders(prefabs: files.read);
  });
  tearDown(() => world.dispose());

  test('a second load waits for the nested prefabs', () async {
    final library = world.context.prefabLibrary;
    var firstDone = false, secondDone = false;
    unawaited(library.load(_outer).then((_) => firstDone = true));
    files.open(_outer);
    await pumpEventQueue();
    // The outer file is read; its nested one is still being read. A scene
    // asking for the outer prefab now must not get it half-loaded.
    unawaited(library.load(_outer).then((_) => secondDone = true));
    await pumpEventQueue();
    expect(secondDone, isFalse);
    expect(library.loaded(_inner), isNull);

    files.open(_inner);
    await pumpEventQueue();
    expect(firstDone, isTrue);
    expect(secondDone, isTrue);
    expect(library.loaded(_inner), isNotNull);
    expect(files.reads, [_outer, _inner], reason: 'each read once');
  });

  test('loadAll and loadScene wait for a load under way too', () async {
    final library = world.context.prefabLibrary;
    unawaited(library.load(_outer));
    files.open(_outer);
    await pumpEventQueue();
    var done = false;
    unawaited(
      library
          .loadScene({
            'entities': [
              {
                'name': 'A',
                'prefab': {'path': _outer},
              },
            ],
          })
          .then((_) => done = true),
    );
    await pumpEventQueue();
    expect(done, isFalse);
    files.open(_inner);
    await pumpEventQueue();
    expect(done, isTrue);
  });

  test('a loop of nested prefabs ends, also with two loads at once', () async {
    files.files
      ..[_outer] = _file('Outer', nests: _inner)
      ..[_inner] = _file('Inner', nests: _outer);
    final library = world.context.prefabLibrary;
    final a = library.load(_outer);
    final b = library.load(_inner);
    files
      ..open(_outer)
      ..open(_inner);
    await Future.wait([a, b]).timeout(const Duration(seconds: 2));
    expect(library.loaded(_outer), isNotNull);
    expect(library.loaded(_inner), isNotNull);
  });

  test('a reload during a read does not keep the old file', () async {
    final library = world.context.prefabLibrary;
    files.files[_outer] = _file('Old');
    final first = library.load(_outer);
    library.reload(_outer); // the file changed on disk meanwhile
    files.files[_outer] = _file('New');
    files.open(_outer);
    expect((await first).name, 'New', reason: 'read again');
    expect(library.loaded(_outer)!.name, 'New');
  });

  test('the library is the context\'s own', () {
    expect(
      identical(world.context.prefabLibrary, world.context.prefabLibrary),
      isTrue,
    );
    final other = World(extensions: [BuiltInComponents.extension]);
    addTearDown(other.dispose);
    expect(
      identical(other.context.prefabLibrary, world.context.prefabLibrary),
      isFalse,
    );
  });
}

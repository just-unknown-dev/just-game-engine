// A scene with a value of the wrong type fails with a FormatException that
// names where it is, and leaves the world untouched; a loop of parents is
// left out instead of hanging the hierarchy; the scene list skips what is
// not a name.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

Map<String, dynamic> _scene(List<Object?> entities) => {
  'version': SceneFormat.current,
  'name': 'test',
  'entities': entities,
};

Map<String, dynamic> _rect(Object? width) => {
  'type': 'RectangleComponent',
  'fields': {'width': width, 'height': 10},
};

class _Bundle extends CachingAssetBundle {
  _Bundle(this.text);

  final String text;

  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(Uint8List.fromList(text.codeUnits));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late World world;
  setUp(() {
    world = World()..initialize();
    addTearDown(world.dispose);
  });

  test('a value of the wrong type names the entity and the field', () {
    final scene = _scene([
      {
        'name': 'Fine',
        'components': [_rect(10)],
      },
      {
        'name': 'Crate',
        'components': [_rect(null)],
      },
    ]);
    expect(
      () => SceneLoader.load(world, scene),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('Entity #1 "Crate"'),
            contains('RectangleComponent.width'),
          ),
        ),
      ),
    );
    expect(world.entities, isEmpty, reason: 'nothing is half-loaded');
  });

  test('an entry that is not an object is a FormatException', () {
    expect(
      () => SceneLoader.load(world, _scene([null])),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => SceneLoader.load(world, {
        ..._scene([]),
        'entities': [
          {'name': 5},
        ],
      }),
      throwsA(isA<FormatException>()),
    );
  });

  test('an unknown component type is still its own exception', () {
    expect(
      () => SceneLoader.load(
        world,
        _scene([
          {
            'name': 'X',
            'components': [
              {'type': 'NoSuchComponent', 'fields': {}},
            ],
          },
        ]),
      ),
      throwsA(isA<UnknownComponentTypeException>()),
    );
  });

  test('a loop of parents is left out', () {
    final created = SceneLoader.load(
      world,
      _scene([
        {'name': 'A', 'parentName': 'B', 'components': []},
        {'name': 'B', 'parentName': 'A', 'components': []},
      ]),
    );
    expect(created, hasLength(2));
    final links = [
      for (final e in created) e.getComponent<ParentComponent>()?.parentId,
    ];
    // At most one of the two links is made, so there is no loop.
    expect(links.where((id) => id != null).length, lessThan(2));
    // The hierarchy settles.
    world.update(1 / 60);
  });

  test('the scene list skips entries that are not names', () async {
    final names = await SceneLoader.loadManifest(
      bundle: _Bundle('{"scenes": ["level_01", 7, null, "level_02"]}'),
    );
    expect(names, ['level_01', 'level_02']);
    expect(await SceneLoader.loadManifest(bundle: _Bundle('not json')), []);
  });
}

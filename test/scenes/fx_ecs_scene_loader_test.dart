// Loading scenes: parents linked to the right entity when names repeat,
// entities with no components kept, and files from a newer engine refused
// rather than misread.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

Map<String, dynamic> entry(String? name, {String? parent, bool bare = false}) =>
    {
      'name': name,
      'parentName': parent,
      'components': bare
          ? <Map<String, dynamic>>[]
          : [
              {'type': 'TransformComponent', 'fields': <String, dynamic>{}},
            ],
    };

Map<String, dynamic> scene(List<Map<String, dynamic>> entities) => {
  'version': SceneFormat.current,
  'name': 'test',
  'entities': entities,
};

void main() {
  late World world;
  setUp(() => world = World());
  tearDown(() => world.dispose());

  List<EntityId> childrenOf(Entity e) =>
      e.getComponent<ChildrenComponent>()?.childIds ?? const [];
  EntityId? parentOf(Entity e) => e.getComponent<ParentComponent>()?.parentId;

  group('parents (C17)', () {
    test('two parents with a child of the same name each keep theirs', () {
      final made = SceneLoader.load(
        world,
        scene([
          entry('CarA'),
          entry('Wheel', parent: 'CarA'),
          entry('CarB'),
          entry('Wheel', parent: 'CarB'),
        ]),
      );
      final [carA, wheelA, carB, wheelB] = made;
      expect(childrenOf(carA), [wheelA.id]);
      expect(childrenOf(carB), [wheelB.id]);
      expect(parentOf(wheelA), carA.id);
      expect(parentOf(wheelB), carB.id);
    });

    test('parents that share a name are told apart by the file order', () {
      final made = SceneLoader.load(
        world,
        scene([
          entry('Car'),
          entry('Wheel', parent: 'Car'),
          entry('Hub', parent: 'Wheel'),
          entry('Car'),
          entry('Wheel', parent: 'Car'),
          entry('Hub', parent: 'Wheel'),
        ]),
      );
      final [car1, wheel1, hub1, car2, wheel2, hub2] = made;
      expect(parentOf(wheel1), car1.id);
      expect(parentOf(hub1), wheel1.id);
      expect(parentOf(wheel2), car2.id);
      expect(parentOf(hub2), wheel2.id);
      expect(childrenOf(car1), [wheel1.id]);
      expect(childrenOf(car2), [wheel2.id]);
    });

    test('an entity with no components is kept, and so are its links', () {
      final made = SceneLoader.load(
        world,
        scene([entry('Folder', bare: true), entry('Inside', parent: 'Folder')]),
      );
      expect(made, hasLength(2));
      final [folder, inside] = made;
      expect(folder.name, 'Folder');
      expect(parentOf(inside), folder.id);
      expect(childrenOf(folder), [inside.id]);
    });

    test('a child with no name is still linked', () {
      final [parent, child] = SceneLoader.load(
        world,
        scene([entry('P'), entry(null, parent: 'P')]),
      );
      expect(parentOf(child), parent.id);
    });

    test('parentIndices reads a file written in any order', () {
      expect(
        SceneLoader.parentIndices([
          entry('Child', parent: 'P'),
          entry('P'),
          entry('Solo'),
          entry('Self', parent: 'Self'),
        ]),
        [1, null, null, null],
      );
    });
  });

  group('a newer format is refused (C16)', () {
    test('a scene', () {
      final newer = {
        ...scene([entry('A')]),
        'version': SceneFormat.current + 1,
      };
      expect(
        () => SceneLoader.load(world, newer),
        throwsA(
          isA<UnsupportedFormatVersionException>()
              .having((e) => e.kind, 'kind', 'scene')
              .having((e) => e.found, 'found', SceneFormat.current + 1)
              .having((e) => e.supported, 'supported', SceneFormat.current),
        ),
      );
      expect(world.entities, isEmpty);
    });

    test('is a FormatException with a plain message', () {
      try {
        SceneFormat.migrate({'version': 99, 'entities': <dynamic>[]});
        fail('should throw');
      } on FormatException catch (e) {
        expect(e.message, contains('v99'));
        expect(e.message, contains('v${SceneFormat.current}'));
      }
    });

    test('the current scene format still loads unchanged', () {
      final json = scene([entry('A')]);
      expect(SceneFormat.migrate(json), same(json));
    });

    test('a tag library', () {
      expect(
        () => TagLibrary.fromJson({
          'version': TagLibrary.formatVersion + 1,
          'tags': ['a'],
        }),
        throwsA(isA<UnsupportedFormatVersionException>()),
      );
      expect(
        TagLibrary.fromJson({
          'version': TagLibrary.formatVersion,
          'tags': ['a'],
        }).names,
        ['a'],
      );
      // The oldest forms: no version, or a bare list.
      expect(
        TagLibrary.fromJson({
          'tags': ['b'],
        }).names,
        ['b'],
      );
      expect(TagLibrary.fromJson(['c']).names, ['c']);
    });
  });
}

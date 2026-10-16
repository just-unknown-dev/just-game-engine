// A package's migration rules belong to one engine, and what a migration
// finds belongs to that migration.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

Map<String, dynamic> _v5WithStaleOffset(String child) => {
  'version': 5,
  'name': 's',
  'entities': [
    {
      'name': 'P',
      'components': [
        {
          'type': 'TransformComponent',
          'fields': {
            'position': {'x': 0.0, 'y': 0.0},
          },
        },
      ],
    },
    {
      'name': child,
      'parentName': 'P',
      'components': [
        {
          'type': 'TransformComponent',
          'fields': {
            'position': {'x': 10.0, 'y': 0.0},
          },
        },
        {
          'type': 'ParentComponent',
          'fields': {
            'parentId': 0,
            'localOffset': {'dx': 99.0, 'dy': 0.0},
          },
        },
      ],
    },
  ],
};

void main() {
  test('each migration keeps its own notes', () {
    final a = SceneFormat.migrateWithReport(_v5WithStaleOffset('A'));
    final b = SceneFormat.migrateWithReport(_v5WithStaleOffset('B'));
    expect(a.notes.single.message, startsWith('A:'));
    expect(b.notes.single.message, startsWith('B:'));
    expect(a.migrated, isTrue);
    expect(a.fromVersion, 5);
    expect(a.scene['version'], SceneFormat.current);
  });

  test('a current scene is not migrated, and says so', () {
    final json = {'version': SceneFormat.current, 'entities': <dynamic>[]};
    final result = SceneFormat.migrateWithReport(json);
    expect(result.migrated, isFalse);
    expect(result.scene, same(json));
  });

  test('MigrationHooks.none adds nothing and takes nothing', () {
    expect(MigrationHooks.none.perEntity(1), isEmpty);
    expect(
      () => MigrationHooks.none.perEntity(1).add((e, s) {}),
      throwsUnsupportedError,
    );
    expect(
      () => MigrationHooks.none.v0Components['x'] = (c) => c,
      throwsUnsupportedError,
    );
    expect(() => MigrationHooks().perEntity(9), throwsRangeError);
  });

  test("a context's rules reach its loader, and no other engine's", () {
    final seen = <String>[];
    final a = World();
    final b = World();
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    a.context.migrations
        .perEntity(6)
        .add((entity, scene) => seen.add('${entity['name']}'));

    MigrationResult? heard;
    final scene = {
      'version': 6,
      'entities': [
        {'name': 'E', 'components': <dynamic>[]},
      ],
    };
    SceneLoader.load(a, scene, onMigrated: (r) => heard = r);
    expect(seen, ['E']);
    expect(heard!.fromVersion, 6);

    SceneLoader.load(b, scene);
    expect(seen, ['E'], reason: "b's context has no such rule");
  });

  test("a context's timeline loader migrates with its rules", () async {
    final context = EngineContext();
    addTearDown(context.dispose);
    context.migrations.perTrack.add((track) => {...track, 'name': 'moved'});
    final asset = TimelineAsset.fromJson({
      'tracks': [
        {'kind': 'event', 'events': <dynamic>[]},
      ],
    }, migrations: context.migrations);
    expect(asset.tracks.single.name, 'moved');
  });
}

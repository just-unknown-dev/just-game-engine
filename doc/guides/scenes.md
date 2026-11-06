# Scenes & saving

_Core_ · Load levels from JSON scene files, describe your own components so scenes can hold them, and handle format versions and loading errors.

A level is a scene: a JSON file listing entities and their components. The [editor](/editor) writes these files, and they are plain JSON, so you can also write them by hand. Your game loads them at run time with `SceneLoader`.

## Scene files and the manifest

Scenes live in `assets/scenes/` as `<name>.scene.json`. `assets/scenes/scenes.json` lists them in play order, for example `{ "scenes": ["level_01", "level_02"] }`. Declare the folder under `flutter: assets:` in your `pubspec.yaml`; a folder entry does not include its subfolders.

```json assets/scenes/level_01.scene.json
{
  "version": 11,
  "name": "level_01",
  "mode": "2d",
  "entities": [
    {
      "name": "Ground",
      "components": [
        { "type": "TransformComponent", "fields": { "position": { "x": 0, "y": 300, "z": 0 } } },
        { "type": "Rectangle2DComponent", "fields": { "width": 1200, "height": 40 } },
        { "type": "Collider2DComponent", "fields": { "shape": "matchShape" } }
      ]
    },
    {
      "name": "PlayerSpawn",
      "components": [
        { "type": "TransformComponent", "fields": { "position": { "x": 0, "y": 200, "z": 0 } } },
        { "type": "SpawnComponent", "fields": { "spawner": "player" } }
      ]
    }
  ]
}
```

- Each component is `{"type": ..., "fields": {...}}`. A field left out keeps the component's default.
- A child names its parent with `"parentName"`, listed after the parent. `"enabled": false` loads an entity switched off.
- `"mode"` is `2d` or `3d`. It tells the editor which view to show; the runtime treats both alike.

## Loading scenes

`SceneLoader` loads a scene into a world and returns the entities it created, in file order:

- `SceneLoader.loadAsset(world, path)` reads an asset through `world.context.bundle`, without caching.
- `SceneLoader.loadString(world, json)` takes JSON text, and `SceneLoader.load(world, map)` a decoded map.

`SceneLoader.loadManifest()` reads `scenes.json` and returns the scene names. Unlike `loadAsset`, it reads from Flutter's `rootBundle`, not the context's bundle, unless you pass `bundle:`. `SceneAssets.pathFor(name)` turns a name into `assets/scenes/<name>.scene.json`.

```dart
import 'package:just_game_engine/just_game_engine.dart';

/// Loads [name], or the first scene in scenes.json, into the world.
Future<void> startLevel(
  Engine engine,
  List<Spawner> spawners, {
  String? name,
}) async {
  final world = engine.world;
  final scene = name ?? (await SceneLoader.loadManifest()).first;
  await SceneLoader.loadAsset(world, SceneAssets.pathFor(scene));

  // Maps and their tile collision, before the first frame: otherwise the
  // player can fall through ground that is still loading.
  await LevelMaps.preload(world);

  // Spawn points name what to create; the game says how.
  SpawnPoints.spawnAll(world, spawners);
}

/// Replaces the current level with [name].
Future<void> changeLevel(
  Engine engine,
  List<Spawner> spawners,
  String name,
) async {
  engine.world.destroyAllEntities(); // the camera brain starts over too
  await startLevel(engine, spawners, name: name);
  engine.releaseUnused(); // let go of what only the old level used
}
```

`LevelMaps.preload` returns the maps that failed to load as a list of `LevelMapLoadFailure`s. Spawners are covered in [Tags & spawners](/docs/tags-spawners) and maps in [Level maps](/docs/level-maps).

Loading decodes every component before it creates anything, so a scene that fails to load leaves the world untouched.

## Your own components in scenes

A scene can only hold components the engine has a `ComponentDefinition` for. The engine's own are always known. For your own component, write a definition and install it through an extension:

```dart
import 'package:just_game_engine/just_game_engine.dart';

class SpeedBoostComponent extends Component {
  SpeedBoostComponent({this.factor = 1.5});

  double factor;
}

final speedBoostDefinition = ComponentDefinition<SpeedBoostComponent>(
  type: 'SpeedBoostComponent', // the saved type: keep it stable
  create: SpeedBoostComponent.new,
  fields: [
    FieldDefinition(
      name: 'factor',
      kind: FieldTypes.decimal,
      read: (c) => (c as SpeedBoostComponent).factor,
      write: (c, v) =>
          (c as SpeedBoostComponent).factor = (v as num).toDouble(),
      min: 1,
    ),
  ],
);

final class MyGameExtension implements ContextExtension {
  const MyGameExtension();

  @override
  String get id => 'my_game';

  @override
  void install(EngineContext context) {
    context.definitions.register(speedBoostDefinition);
  }
}

final engine = Engine(
  config: const EngineConfig(
    extensions: [MyGameExtension()],
    defaultSystems: DefaultSystems.all,
  ),
);
```

- `type` is the string written to scenes. Renaming it orphans saved levels; list old names in `aliases` instead.
- `create` makes a component with default values, which loading then overwrites field by field.
- Each `FieldDefinition` has a `name` (the JSON key, also stable), a `kind`, a `read` and a `write`. `min` and `max` clamp numbers as they load. A field with no `write` is saved but never restored.
- `FieldTypes` holds the kinds: `boolean`, `integer`, `decimal`, `text`, `assetRef`, `entityRef`, `tagRef`, `tagList`, `spawnerRef`, `target`, `enumeration`, `list`, `map`, `vector2`, `vector3`, `euler`, `color`, `offset`, `shapePaintStyle` and more. A feature's own kinds live with its definitions: a field that holds an input action's name is `InputDefinitions.actionType` (several: `actionListType`), saved as text all the same, so the editor offers the project's actions for it and the Input Actions editor finds it when an action is renamed.
- `ComponentDefinition.extend(base, ...)` defines a subclass of an engine component, keeping the base's fields and adding yours.
- `hints` (`ComponentHints`, `FieldHint`) only shape how an editor's inspector shows the component.

`context.definitions.registerAll(list)` registers several at once. The same definition is what an editor uses to save and inspect the component, so the game and the editor always agree on the format.

## Format versions and migrations

Every scene carries a `version`. `SceneFormat.current` is the newest format the engine knows: 11, where every component's name ends in `Component`; 10 in 2.0.0-dev.2 and dev.3, which added prefab instances; and 9 in 2.0.0-dev.1. A file at an older version is migrated in memory as it loads; the file on disk is never rewritten. Pass `onMigrated` to hear about it: the `SceneMigrationResult` has `fromVersion` and `notes` worth showing a developer.

A package adds its own rules to the engine's migration steps through `context.migrations` (a `MigrationHooks`), usually from its extension. Those rules run as part of the engine's steps, so they only apply to files saved at an older format. The exception is a package's renamed components and fields (`renamedTypes`, `renamedFields`): they are renamed at every load, whatever the file's format, so a package can rename a saved component at any time. `onMigrated` hears about that too.

## When a scene does not load

| Exception | Cause |
|---|---|
| `UnknownComponentTypeException` | A component `type` nobody registered. Its `type` and `entityName` say which; install the extension that defines it. 3-D components need `Graphics3D()` or `Physics3D()` in `EngineConfig(services: …)`. |
| `UnsupportedFormatVersionException` | The file was saved by a newer engine. `found` and `supported` give both versions. |
| `FormatException` | A value has the wrong type. The message names the entity, the component and the field. |

`UnsupportedFormatVersionException` is itself a `FormatException`, so catch it first:

```dart
Future<bool> tryLoad(World world, String name) async {
  try {
    await SceneLoader.loadAsset(world, SceneAssets.pathFor(name));
    return true;
  } on UnknownComponentTypeException catch (e) {
    debugPrint('No definition for ${e.type} (entity ${e.entityName})');
  } on UnsupportedFormatVersionException catch (e) {
    debugPrint('Saved by a newer engine: ${e.found} > ${e.supported}');
  } on FormatException catch (e) {
    debugPrint('Broken scene: ${e.message}');
  }
  return false;
}
```

## Prefab files

2.0.0-dev.2 adds prefab files (`.prefab.json`): a scene entry can place an instance of one, with its own changes kept as overrides, and prefabs can nest. `SceneLoader.loadAsset` reads the prefabs a scene uses before it loads the scene. To make one at run time, load it with `engine.context.prefabLibrary.load(path)` and then call `instantiate(world, path, position: ...)`; `Spawner.prefab(id: ..., path: ...)` places one at every matching spawn point. For prefabs built in code, see [EntityPrefab](/docs/ecs).

## Saving

The engine reads scenes; it has no API that writes a world back to a scene file. The editor is what saves levels.

For save games, keep your own state, and store it with `engine.cache.setJson(key, data)` and read it back with `getJson(key)`. If you want to reuse the scene format for a component, `engine.context.definitions.encode(component)` returns its `{"type", "fields"}` map (or null when nothing defines it), and `decode(json)` turns such a map back into a component.

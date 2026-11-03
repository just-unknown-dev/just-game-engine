# Tags, targets & spawners

_Gameplay_ · Label entities with tags, point at entities by name or tag with EntityTarget, and create players and enemies at spawn points with your own spawners.

Tags label entities so systems can find them: `player`, `enemy`, `boss`. Targets name an entity instead of holding it, so a camera or trigger authored in a level can find a player that is spawned later. Spawn points say what to create, and your game's spawners say how.

## Tags

A `TagComponent` holds any number of tags. The world keeps an index of them, so looking tagged entities up is cheap; don't query `TagComponent` and compare strings yourself.

```dart lib/tags.dart
void tagsAndTargets(World world) {
  final boss = world.createEntityWithComponents([
    TransformComponent(position: Vector3(900, 0, 0)),
    TagComponent.of(['enemy', 'boss']),
  ], name: 'Boss');
  boss.addTag('armored');

  final enemies = world.allTagged('enemy'); // switched-on ones, oldest first
  final player = world.findTagged('player'); // the oldest, or null
  debugPrint('${enemies.length} enemies; player: ${player?.name}');

  const target = EntityTarget.tag('boss');
  final found = target.resolve(world, null);
  debugPrint('the boss is ${found?.name}, armored: ${found?.hasTag('armored')}');
}
```

- `TagComponent('enemy')` holds one tag and `TagComponent.of([...])` several; blanks and repeats are dropped.
- On an entity, `hasTag`, `addTag` (which adds a `TagComponent` if there is none), `removeTag` and `tags` work directly. On the component, use `tags`, `has`, `add` and `remove`; the single `tag` getter is deprecated.
- `world.findTagged(tag)` returns the oldest switched-on entity with the tag, or null, and `world.allTagged(tag)` returns all of them, oldest first. Pass `includeInactive: true` to include switched-off entities. `world.tagsInUse` lists every tag in use.
- Switched-off entities (`entity.isActive = false`) are left out of tag lookups and targets, and so is everything under them in the hierarchy (`entity.isActiveInHierarchy`).
- Tag names use letters, digits, `_` and `-`, and are case-sensitive (`TagNames.isValid`).

`EngineTags.player` (`player`) is the tag the engine looks for by default: cameras, trigger zones, checkpoints and [dialogue](/docs/dialogue) find the player by it unless told otherwise.

## Targets

An `EntityTarget` names who a component means, and is looked up when it is needed:

| Target | Means | Saved as |
|---|---|---|
| `EntityTarget.name('Door')` | the oldest entity with that name | `{"name": "Door"}` |
| `EntityTarget.tag('player')` | the oldest entity with that tag, or all of them where several make sense | `{"tag": "player"}` |
| `EntityTarget.self()` | the component's own entity | `"self"` |
| `EntityTarget.none` | nobody | `null` |

Late binding is on purpose: a level's camera is authored long before the player it follows is spawned, and a respawn makes a new player entity. A stored entity id would be wrong both times; a name or a tag is right.

`resolve(world, owner)` returns one entity and `resolveAll(world, owner)` returns every entity a tag means. `EntityTarget.parse` reads the short text form: `self`, `#enemy` for a tag, and anything else as a name. Cameras (`VirtualCameraComponent.follow`), joints (`connectedBody`) and timeline bindings all take targets; see [Cameras](/docs/cameras) and [Timelines](/docs/timelines).

## Spawn points and spawners

A spawn point is an entity with a `SpawnComponent`. Its `spawner` field (`player` by default) names one of your game's `Spawner`s, which creates the entity. The spawn point is never consumed: it stays where it is, and the spawner reads its position and any tuning components beside it.

```dart lib/spawners.dart
final List<Spawner> spawners = [
  Spawner(
    id: 'player',
    label: 'Player',
    tags: const {'player'}, // what the spawned entity will carry
    spawn: (world, point) => world.createEntityWithComponents([
      // The spawn point's position; TransformComponent copies it.
      TransformComponent(
        position: point.getComponent<TransformComponent>()?.position,
      ),
      VelocityComponent(),
      InputComponent(),
      Rectangle2DComponent(width: 32, height: 48),
      RigidBody2DComponent(friction: 0, lockRotation: true),
      Collider2DComponent(shape: ColliderShape2D.matchShape),
      TagComponent('player'),
    ], name: 'Player'),
  ),
];

Future<void> loadLevel(Engine engine, String path) async {
  await SceneLoader.loadAsset(engine.world, path);
  await LevelMaps.preload(engine.world);
  SpawnPoints.spawnAll(
    engine.world,
    spawners,
    onMissing: (point, id) => debugPrint('No spawner for "$id"'),
  );
}
```

`SpawnPoints.spawnAll` calls the matching spawner for every switched-on spawn point, oldest first, and returns what it created; a spawn point whose spawner is not in the list is skipped and reported to `onMissing`. `SpawnPoints.of(world, 'enemy')` lists the spawn points for one spawner and `SpawnPoints.first(world, 'player')` finds one. A spawner's `label`, `description` and `tags` are for editors and pickers; the editor's Play button calls your spawners the same way.

In a scene file a spawn point is an entity with two components:

```json
{
  "name": "PlayerSpawn",
  "components": [
    { "type": "TransformComponent", "fields": { "position": { "x": 0, "y": 200, "z": 0 } } },
    { "type": "SpawnComponent", "fields": { "spawner": "player" } }
  ]
}
```

## The project's tag library

A project keeps its tags, with a colour and a description for each, in `assets/project/tags.json` (`TagLibrary.defaultPath`): `{"version": 1, "tags": [{"name": "enemy", "description": "Hurts the player"}]}`, with colours as ARGB integers. The [editor](/editor) reads and writes it to offer tag pickers and to warn about near-duplicates such as `Players` beside `player`.

The engine does not need the file to run: tags on entities are plain strings. Tags that code relies on are declared rather than read from the file (`EngineTags.declared`), so an editor will not let you rename or delete `player`. A spawner's `tags` tell the editor that a tag is real in a level that has only a spawn point for it so far. In code, `TagLibrary.fromJson`, `withDeclared` and `TagNames.closest` (the tag a typo most likely meant) are there for tools of your own.

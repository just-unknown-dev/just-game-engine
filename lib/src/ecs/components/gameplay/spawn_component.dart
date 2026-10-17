library;

import '../../../ecs/ecs.dart';
import '../../serialization/prefab_library.dart';
import '../components.dart';

/// Marks an entity as a spawn point: where the app creates something when
/// the level starts. *What* is created is up to the app — the [spawner]
/// names one of its [Spawner]s.
///
/// The editor's Play button and the shipped game both find spawn points
/// through [SpawnPoints] and call the matching spawner, passing this entity
/// so it can read its [TransformComponent] position and any tuning
/// components attached alongside this one.
///
/// The spawn point itself is never touched by spawning — it is not consumed
/// or destroyed when something is created at its position.
///
/// ```dart
/// world.createEntityWithComponents([
///   TransformComponent(position: Vector3.fromXY(200, 400)),
///   SpawnComponent(spawner: 'player'),
/// ], name: 'PlayerSpawn');
/// ```
class SpawnComponent extends Component {
  /// A spawn point for the spawner named [spawner]; the `player` one by
  /// default.
  SpawnComponent({this.spawner = 'player'});

  /// The [Spawner.id] of what is created here.
  String spawner;

  @override
  String toString() => 'Spawn($spawner)';
}

/// Creates the entity for a spawn point: the player, an enemy wave, a pickup.
typedef SpawnFunction = Entity Function(World world, Entity spawnPoint);

/// Something a spawn point can create, as the app registers it.
///
/// The [tags] are what the spawned entity will carry. They are how an editor
/// knows that `player` is a real tag in a level that has no player in it
/// yet — only a spawn point that will make one.
class Spawner {
  /// A spawner saved in levels as [id] that makes entities with [spawn];
  /// [label], [description] and [tags] are for pickers and editors only.
  const Spawner({
    required this.id,
    required this.spawn,
    this.label,
    this.description = '',
    this.tags = const {},
  });

  /// What a [SpawnComponent.spawner] names. Stable: it is saved in levels.
  final String id;

  /// Creates the entity at a spawn point.
  final SpawnFunction spawn;

  /// What a person reads in a picker; [id] when unset.
  final String? label;

  /// A short note on what it makes, for people and tools; empty by
  /// default.
  final String description;

  /// The tags the entity [spawn] creates carries.
  final Set<String> tags;

  /// The name to show: [label], or [id] when it has none.
  String get displayName => label ?? id;

  /// A spawner placing an instance of the prefab file at [path] at each
  /// spawn point: its top entity where the point is, the rest keeping
  /// their places against it. The prefab must have been read — a scene's
  /// own prefabs are, by `SceneLoader.loadAsset`; any other through
  /// `PrefabLibrary.load` first.
  factory Spawner.prefab({
    required String id,
    required String path,
    String? label,
    String description = '',
    Set<String> tags = const {},
  }) => Spawner(
    id: id,
    label: label,
    description: description,
    tags: tags,
    spawn: (world, point) => PrefabLibrary.of(world.context).instantiate(
      world,
      path,
      position: point.getComponent<TransformComponent>()?.position,
    ),
  );

  /// Spawners without descriptions, from an old `id → function` map.
  static List<Spawner> fromMap(Map<String, SpawnFunction> registry) => [
    for (final e in registry.entries) Spawner(id: e.key, spawn: e.value),
  ];
}

/// Finding spawn points, the same way everywhere.
abstract final class SpawnPoints {
  /// Every spawn point for [spawner], oldest first. Switched-off ones are
  /// left out.
  static List<Entity> of(World world, String spawner) {
    final points = [
      for (final entity in world.query([SpawnComponent]))
        if (entity.isActive &&
            entity.getComponent<SpawnComponent>()!.spawner == spawner)
          entity,
    ]..sort((a, b) => a.id.compareTo(b.id));
    return points;
  }

  /// The first spawn point for [spawner], or null.
  static Entity? first(World world, String spawner) {
    final points = of(world, spawner);
    return points.isEmpty ? null : points.first;
  }

  /// Calls the matching spawner for every spawn point in [world], oldest
  /// first, and returns what was created. A spawn point whose spawner is
  /// not in [spawners] is skipped and reported to [onMissing].
  static List<Entity> spawnAll(
    World world,
    Iterable<Spawner> spawners, {
    void Function(Entity spawnPoint, String spawner)? onMissing,
  }) {
    final byId = {for (final s in spawners) s.id: s};
    final points = [
      for (final entity in world.query([SpawnComponent]))
        if (entity.isActive) entity,
    ]..sort((a, b) => a.id.compareTo(b.id));
    final spawned = <Entity>[];
    for (final point in points) {
      final id = point.getComponent<SpawnComponent>()!.spawner;
      final spawner = byId[id];
      if (spawner == null) {
        onMissing?.call(point, id);
        continue;
      }
      spawned.add(spawner.spawn(world, point));
    }
    return spawned;
  }
}

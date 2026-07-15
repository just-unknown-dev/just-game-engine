library;

import '../../../ecs/ecs.dart';

/// Marks an entity as a spawn point for a named "tag" — what actually gets
/// created there is entirely up to the app.
///
/// The editor's Play button looks up each [SpawnComponent] entity's [tag]
/// in an app-provided spawn registry (a `Map<String, Entity Function(World,
/// Entity)>`) and calls the matching function, passing this entity so the
/// spawner can read its [TransformComponent] position and any other
/// tag-specific tuning components attached alongside this one.
///
/// The spawn point entity itself is never touched by spawning — it's not
/// consumed/destroyed when something is created at its position.
///
/// ```dart
/// world.createEntityWithComponents([
///   TransformComponent(position: Vector3.fromXY(200, 400)),
///   SpawnComponent(tag: 'player'),
/// ], name: 'PlayerSpawn');
/// ```
class SpawnComponent extends Component {
  /// Identifies which registered spawner function creates the entity here.
  String tag;

  SpawnComponent({this.tag = 'player'});

  @override
  String toString() => 'Spawn(tag: $tag)';
}

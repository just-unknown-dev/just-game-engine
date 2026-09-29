/// Finding what a camera is told to look at.
library;

import 'package:flutter/painting.dart' show Offset;

import '../../ecs/components/components.dart';
import '../../ecs/ecs.dart';

/// Resolves a target named by entity name or tag to an entity, once a frame.
///
/// Targets are late-bound on purpose. A level's camera is authored long
/// before the player it follows is spawned, and a respawn makes a *new*
/// player entity; a stored entity id would be wrong in both cases, a name or
/// a tag is right in both.
class CameraTargetResolver {
  final Map<String, Entity?> _byName = {};
  final Map<String, Entity?> _byTag = {};
  final Map<String, List<Entity>> _allByTag = {};
  World? _world;

  /// Forgets last frame's lookups. Called by the brain before it evaluates.
  void beginFrame(World world) {
    _world = world;
    _byName.clear();
    _byTag.clear();
    _allByTag.clear();
  }

  /// The active entity called [name], else the first active one tagged
  /// [tag], else null.
  Entity? resolve({String name = '', String tag = ''}) {
    final world = _world;
    if (world == null) return null;
    if (name.isNotEmpty) {
      final entity = _byName.putIfAbsent(name, () {
        final found = world.findEntityByName(name);
        return found != null && found.isActive ? found : null;
      });
      if (entity != null) return entity;
    }
    if (tag.isEmpty) return null;
    return _byTag.putIfAbsent(tag, () {
      for (final entity in world.query([TagComponent])) {
        if (entity.isActive &&
            entity.getComponent<TagComponent>()!.tag == tag) {
          return entity;
        }
      }
      return null;
    });
  }

  /// Every active entity tagged [tag] — all the players, not just the
  /// first.
  List<Entity> resolveAll(String tag) {
    final world = _world;
    if (world == null || tag.isEmpty) return const [];
    return _allByTag.putIfAbsent(
      tag,
      () => [
        for (final entity in world.query([TagComponent]))
          if (entity.isActive &&
              entity.getComponent<TagComponent>()!.tag == tag)
            entity,
      ],
    );
  }

  /// What a member naming [name] and [tag] stands for: the entity called
  /// [name] if there is one, else every entity tagged [tag].
  List<Entity> resolveMembers({String name = '', String tag = ''}) {
    if (name.isNotEmpty) {
      final named = resolve(name: name);
      if (named != null) return [named];
    }
    return resolveAll(tag);
  }

  /// Where [entity] is, or null without a transform.
  static Offset? positionOf(Entity entity) =>
      entity.getComponent<TransformComponent>()?.position.toOffset();

  /// How fast [entity] says it is moving, or null when it does not say.
  static Offset? velocityOf(Entity entity) =>
      entity.getComponent<VelocityComponent>()?.velocity.toOffset();
}

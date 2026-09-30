/// Finding what a camera is told to look at.
library;

import 'package:flutter/painting.dart' show Offset;

import '../../ecs/components/components.dart';
import '../../ecs/ecs.dart';

/// Resolves the [EntityTarget]s cameras name to entities, once a frame.
///
/// Targets are late-bound on purpose. A level's camera is authored long
/// before the player it follows is spawned, and a respawn makes a *new*
/// player entity; a stored entity id would be wrong in both cases, a name or
/// a tag is right in both. Tags come from the world's index; names are
/// remembered for the frame.
class CameraTargetResolver {
  final Map<String, Entity?> _byName = {};
  World? _world;

  /// Forgets last frame's lookups. Called by the brain before it evaluates.
  void beginFrame(World world) {
    _world = world;
    _byName.clear();
  }

  /// The entity [target] means — the one by that name, or the first active
  /// one with that tag — or null. [owner] is what `self` means.
  Entity? resolveTarget(EntityTarget target, {Entity? owner}) {
    final world = _world;
    if (world == null) return null;
    return switch (target.kind) {
      EntityTargetKind.self => owner,
      EntityTargetKind.name => _named(world, target.value),
      EntityTargetKind.tag =>
        target.value.isEmpty ? null : world.findTagged(target.value),
    };
  }

  /// Every active entity [target] means: all of them for a tag — all the
  /// players, not just the first — at most one otherwise.
  List<Entity> resolveTargetAll(EntityTarget target, {Entity? owner}) {
    final world = _world;
    if (world == null) return const [];
    if (target.isTag) {
      return target.value.isEmpty ? const [] : world.allTagged(target.value);
    }
    final one = resolveTarget(target, owner: owner);
    return one == null ? const [] : [one];
  }

  /// The active entity called [name], else the first active one tagged
  /// [tag], else null.
  Entity? resolve({String name = '', String tag = ''}) {
    final world = _world;
    if (world == null) return null;
    final named = _named(world, name);
    if (named != null || tag.isEmpty) return named;
    return world.findTagged(tag);
  }

  /// Every active entity tagged [tag].
  List<Entity> resolveAll(String tag) {
    final world = _world;
    if (world == null || tag.isEmpty) return const [];
    return world.allTagged(tag);
  }

  /// The entity called [name] if there is one, else every entity tagged
  /// [tag].
  @Deprecated('Use resolveTargetAll.')
  List<Entity> resolveMembers({String name = '', String tag = ''}) {
    if (name.isNotEmpty) {
      final named = resolve(name: name);
      if (named != null) return [named];
    }
    return resolveAll(tag);
  }

  Entity? _named(World world, String name) {
    if (name.isEmpty) return null;
    return _byName.putIfAbsent(name, () {
      final found = world.findEntityByName(name);
      return found != null && found.isActive ? found : null;
    });
  }

  /// Where [entity] is, or null without a transform.
  static Offset? positionOf(Entity entity) =>
      entity.getComponent<TransformComponent>()?.position.toOffset();

  /// How fast [entity] says it is moving, or null when it does not say.
  static Offset? velocityOf(Entity entity) =>
      entity.getComponent<VelocityComponent>()?.velocity.toOffset();
}

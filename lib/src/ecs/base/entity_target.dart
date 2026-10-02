part of '../ecs.dart';

// ════════════════════════════════════════════════════════════════════════════
// EntityTarget
// ════════════════════════════════════════════════════════════════════════════

/// How an [EntityTarget] picks its entity.
enum EntityTargetKind {
  /// The entity holding the component (or playing the timeline) itself.
  self,

  /// The entity with this name.
  name,

  /// Entities with this tag: the first for one target, all of them where a
  /// target may mean several (a camera group, a trigger zone).
  tag,
}

/// Who a component means — the entity a camera follows, what sets a trigger
/// off — named rather than referenced, and looked up when it is needed.
///
/// Late-bound on purpose: a level's camera is authored long before the
/// player it follows is spawned, and a respawn makes a *new* player entity.
/// A stored entity id would be wrong both times; a name or a tag is right.
///
/// Saved as `'self'`, `{'name': 'Door'}` or `{'tag': 'player'}`; [none] as
/// null.
class EntityTarget {
  /// The entity that holds the component itself.
  const EntityTarget.self() : kind = EntityTargetKind.self, value = '';

  /// The entity named [value]; an empty name is [none].
  const EntityTarget.name(this.value) : kind = EntityTargetKind.name;

  /// The entity, or entities, tagged [value] (without the `#`).
  const EntityTarget.tag(this.value) : kind = EntityTargetKind.tag;

  /// Nobody: a camera that follows nothing.
  static const EntityTarget none = EntityTarget.name('');

  /// Whether this means the owner itself, a name, or a tag.
  final EntityTargetKind kind;

  /// The name or the tag; empty for [EntityTargetKind.self].
  final String value;

  /// Whether this means the owner itself.
  bool get isSelf => kind == EntityTargetKind.self;

  /// Whether this names an entity (true for [none] too).
  bool get isName => kind == EntityTargetKind.name;

  /// Whether this names a tag.
  bool get isTag => kind == EntityTargetKind.tag;

  /// Whether it names nobody.
  bool get isNone => !isSelf && value.isEmpty;

  /// The entity this means for [owner] — the first (oldest) with that name,
  /// or with that tag — or null. Entities switched off are passed over
  /// unless [includeInactive]: a switched-off entity does not hide a
  /// switched-on one of the same name.
  Entity? resolve(World world, Entity? owner, {bool includeInactive = false}) {
    switch (kind) {
      case EntityTargetKind.self:
        return owner;
      case EntityTargetKind.name:
        if (value.isEmpty) return null;
        return world.findEntityByName(value, includeInactive: includeInactive);
      case EntityTargetKind.tag:
        if (value.isEmpty) return null;
        return world.findTagged(value, includeInactive: includeInactive);
    }
  }

  /// Every entity this means: all of them for a tag, at most one otherwise.
  List<Entity> resolveAll(
    World world,
    Entity? owner, {
    bool includeInactive = false,
  }) {
    if (isTag) {
      return value.isEmpty
          ? const []
          : world.allTagged(value, includeInactive: includeInactive);
    }
    final one = resolve(world, owner, includeInactive: includeInactive);
    return one == null ? const [] : [one];
  }

  /// What a person reads: `Self`, `Door`, `#enemy`; empty for [none].
  String get label => switch (kind) {
    EntityTargetKind.self => 'Self',
    EntityTargetKind.name => value,
    EntityTargetKind.tag => '#$value',
  };

  /// The saved form: `'self'`, `{'name': value}` or `{'tag': value}`;
  /// null for [none].
  Object? toJson() => switch (kind) {
    _ when isNone => null,
    EntityTargetKind.self => 'self',
    EntityTargetKind.name => {'name': value},
    EntityTargetKind.tag => {'tag': value},
  };

  /// Reads what [toJson] wrote. Also takes the short text forms [parse]
  /// does, for a hand-edited file. Anything else is [fallback].
  static EntityTarget fromJson(
    Object? json, {
    EntityTarget fallback = EntityTarget.none,
  }) {
    if (json is Map) {
      if (json['name'] is String) return EntityTarget.name(json['name']);
      if (json['tag'] is String) return EntityTarget.tag(json['tag']);
    }
    if (json is String) return parse(json);
    return fallback;
  }

  /// `self` → [EntityTarget.self], `#enemy` → a tag, anything else → a
  /// name, blank → [none].
  static EntityTarget parse(String text) {
    final t = text.trim();
    if (t.isEmpty) return none;
    if (t == 'self') return const EntityTarget.self();
    if (t.startsWith('#')) return EntityTarget.tag(t.substring(1).trim());
    return EntityTarget.name(t);
  }

  /// The target an old pair of fields meant — a name tried before a tag —
  /// now that there is one: the name when it is set, else the tag.
  static EntityTarget fromNameOrTag(String name, String tag) {
    if (name.trim().isNotEmpty) return EntityTarget.name(name.trim());
    if (tag.trim().isNotEmpty) return EntityTarget.tag(tag.trim());
    return none;
  }

  @override
  bool operator ==(Object other) =>
      other is EntityTarget && other.kind == kind && other.value == value;

  @override
  int get hashCode => Object.hash(kind, value);

  @override
  String toString() => 'EntityTarget(${isNone ? 'none' : label})';
}

part of '../ecs.dart';

// ════════════════════════════════════════════════════════════════════════════
// Tags
// ════════════════════════════════════════════════════════════════════════════

/// The labels an entity carries — `player`, `enemy`, `boss` — for systems,
/// cameras and triggers to find it by.
///
/// An entity may carry several: an enemy can be `enemy` and `boss` at once.
/// Find tagged entities through the world's index ([World.findTagged],
/// [World.allTagged]) rather than by querying this component and comparing
/// strings; the index is kept up to date for you.
///
/// ```dart
/// world.createEntityWithComponents([
///   TransformComponent(),
///   TagComponent.of(['enemy', 'boss']),
/// ]);
/// final boss = world.findTagged('boss');
/// ```
class TagComponent extends Component {
  /// One tag, or none when [tag] is empty.
  TagComponent([String tag = ''])
    : _tags = {
        ...TagNames.normalize([tag]),
      };

  /// Several tags. Blanks and repeats are dropped.
  TagComponent.of(Iterable<String> tags)
    : _tags = {...TagNames.normalize(tags)};

  /// The entity this is attached to, so its world's tag index hears of
  /// every change. A tag component belongs to one entity at a time.
  Entity? _owner;

  /// The tag index of the world [_owner] lives in, if any.
  _TagIndex? get _index => _owner?._world?._tagIndex;

  final Set<String> _tags;

  /// The tags, in the order they were added.
  Set<String> get tags => UnmodifiableSetView(_tags);

  /// Replaces every tag. Blanks and repeats are dropped.
  set tags(Iterable<String> value) {
    final next = TagNames.normalize(value).toList();
    if (next.length == _tags.length && _tags.containsAll(next)) return;
    final index = _index;
    final before = index == null ? null : Set.of(_tags);
    _tags
      ..clear()
      ..addAll(next);
    if (index == null) return;
    for (final tag in before!) {
      if (!_tags.contains(tag)) index.untag(_owner!, tag);
    }
    for (final tag in _tags) {
      if (!before.contains(tag)) index.tag(_owner!, tag);
    }
  }

  /// Whether it carries [tag].
  bool has(String tag) => _tags.contains(tag);

  /// Adds [tag]; false when it was blank or already there.
  bool add(String tag) {
    final name = tag.trim();
    if (name.isEmpty || !_tags.add(name)) return false;
    _index?.tag(_owner!, name);
    return true;
  }

  /// Removes [tag]; false when it was not there.
  bool remove(String tag) {
    if (!_tags.remove(tag)) return false;
    _index?.untag(_owner!, tag);
    return true;
  }

  /// Whether it carries no tag at all.
  bool get isEmpty => _tags.isEmpty;

  /// The first tag, or empty.
  @Deprecated('An entity can carry several tags: use tags, has() or add().')
  String get tag => _tags.isEmpty ? '' : _tags.first;

  /// Replaces every tag with [value].
  @Deprecated('An entity can carry several tags: use tags, add() or remove().')
  set tag(String value) => tags = [value];

  @override
  String toString() => 'Tag(${_tags.join(', ')})';
}

/// Tagging straight from an entity.
extension EntityTags on Entity {
  /// Its tags; empty without a [TagComponent].
  Set<String> get tags => getComponent<TagComponent>()?.tags ?? const {};

  /// Whether it carries [tag].
  bool hasTag(String tag) => getComponent<TagComponent>()?.has(tag) ?? false;

  /// Adds [tag], adding a [TagComponent] first if it has none.
  void addTag(String tag) {
    final existing = getComponent<TagComponent>();
    if (existing != null) {
      existing.add(tag);
    } else if (tag.trim().isNotEmpty) {
      addComponent(TagComponent(tag));
    }
  }

  /// Removes [tag], if it has it. An emptied [TagComponent] stays.
  void removeTag(String tag) => getComponent<TagComponent>()?.remove(tag);
}

/// What makes a good tag name, and what is probably a typo of one.
abstract final class TagNames {
  static final RegExp _valid = RegExp(r'^[A-Za-z0-9_-]+$');

  /// Whether [name] is a tag a person can create: letters, digits, `_` and
  /// `-`, nothing else. Tags are case-sensitive.
  static bool isValid(String name) => _valid.hasMatch(name);

  /// What is wrong with [name] as a new tag, or null when nothing is.
  static String? problemWith(String name) {
    if (name.trim().isEmpty) return 'A tag needs a name.';
    if (!isValid(name)) {
      return 'Use letters, digits, "_" and "-" only — no spaces.';
    }
    return null;
  }

  /// [names] trimmed, without blanks or repeats, in order.
  static Iterable<String> normalize(Iterable<String> names) sync* {
    final seen = <String>{};
    for (final raw in names) {
      final name = raw.trim();
      if (name.isNotEmpty && seen.add(name)) yield name;
    }
  }

  /// Whether [a] and [b] are different names a person would take for the
  /// same one: only case, a plural `s`, or `_` against `-` apart.
  static bool areNearDuplicates(String a, String b) {
    if (a == b) return false;
    return _fold(a) == _fold(b);
  }

  /// The name in [known] that [name] most likely meant, or null when none
  /// is close. A near duplicate wins; failing that, the nearest within two
  /// edits, for names long enough that two edits is still a typo.
  static String? closest(String name, Iterable<String> known) {
    if (name.isEmpty) return null;
    String? best;
    var bestDistance = 1 << 30;
    for (final candidate in known) {
      if (candidate == name) return null;
      if (areNearDuplicates(name, candidate)) return candidate;
      final d = _distance(name.toLowerCase(), candidate.toLowerCase());
      if (d < bestDistance) {
        bestDistance = d;
        best = candidate;
      }
    }
    final allowed = name.length <= 3 ? 1 : 2;
    return bestDistance <= allowed ? best : null;
  }

  static String _fold(String s) {
    var f = s.toLowerCase().replaceAll('-', '_');
    if (f.length > 1 && f.endsWith('s')) f = f.substring(0, f.length - 1);
    return f;
  }

  /// Levenshtein distance.
  static int _distance(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    var previous = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final current = List<int>.filled(b.length + 1, 0)..[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        current[j] = min(
          min(current[j - 1] + 1, previous[j] + 1),
          previous[j - 1] + cost,
        );
      }
      previous = current;
    }
    return previous[b.length];
  }
}

/// A world's tag → entities index, kept up to date as tags come and go:
/// each change touches only the tags it concerns.
///
/// Each tag's entities are kept oldest first, so "the first tagged" is the
/// same entity every run. [all]'s lists are made once and reused until
/// that tag's entities change or one of them is switched on or off
/// ([Entity.isActiveInHierarchy]).
class _TagIndex {
  final Map<String, List<Entity>> _byTag = {};
  final Map<String, UnmodifiableListView<Entity>> _all = {};
  final Map<String, UnmodifiableListView<Entity>> _active = {};

  /// [tags] was attached to [entity].
  void attach(Entity entity, TagComponent tags) {
    if (identical(tags._owner, entity)) return; // Put back as it was.
    tags._owner = entity;
    for (final tag in tags._tags) {
      this.tag(entity, tag);
    }
  }

  /// [tags] was detached from [entity].
  void detach(Entity entity, TagComponent tags) {
    if (identical(tags._owner, entity)) tags._owner = null;
    for (final tag in tags._tags) {
      untag(entity, tag);
    }
  }

  void tag(Entity entity, String tag) {
    _insertById(_byTag[tag] ??= [], entity);
    _forget(tag);
  }

  void untag(Entity entity, String tag) {
    final list = _byTag[tag];
    if (list == null) return;
    _removeById(list, entity);
    if (list.isEmpty) _byTag.remove(tag);
    _forget(tag);
  }

  /// [entity], which carries tags, was switched on or off in the hierarchy.
  void activeChanged(Entity entity) {
    final tags = entity.getComponent<TagComponent>();
    if (tags == null) return;
    for (final tag in tags._tags) {
      _active.remove(tag);
    }
  }

  void _forget(String tag) {
    _all.remove(tag);
    _active.remove(tag);
  }

  void clear() {
    _byTag.clear();
    _all.clear();
    _active.clear();
  }

  Entity? first(String tag, bool includeInactive) {
    final tagged = _byTag[tag];
    if (tagged == null) return null;
    for (final entity in tagged) {
      if (includeInactive || entity._activeInHierarchy) return entity;
    }
    return null;
  }

  List<Entity> all(String tag, bool includeInactive) {
    final tagged = _byTag[tag];
    if (tagged == null) return const [];
    if (includeInactive) {
      return _all[tag] ??= UnmodifiableListView(
        List<Entity>.of(tagged, growable: false),
      );
    }
    return _active[tag] ??= UnmodifiableListView([
      for (final entity in tagged)
        if (entity._activeInHierarchy) entity,
    ]);
  }

  Set<String> get tagsInUse => _byTag.keys.toSet();
}

part of '../ecs.dart';

// ════════════════════════════════════════════════════════════════════════════
// Archetype – dense storage for entities sharing the same component set
// ════════════════════════════════════════════════════════════════════════════

/// An [Archetype] groups all entities that share the exact same set of
/// component types. Components of each type are stored in contiguous lists
/// (one "column" per type), giving systems cache-friendly iteration.
///
/// Only its [World] adds and removes rows. Systems read it — through
/// [World.queryArchetypes] — and must skip rows whose entity is not
/// [Entity.isActive] ([entityAt]).
class Archetype {
  /// The canonical set of component types in this archetype.
  Set<Type> get types => _typesView;

  final Set<Type> _typeSet;
  late final Set<Type> _typesView = UnmodifiableSetView(_typeSet);

  /// [_typeSet] in order, parallel to [_columnList].
  final List<Type> _typeList;

  /// Deterministic string key derived from [types], from their sorted type
  /// names. For display and debugging: two different types can share a
  /// name, so the world does not key archetypes by it.
  late final String signature = _computeSignature(_typeSet);

  // Dense component arrays – one list per component type.
  final Map<Type, List<Component>> _columns;
  final List<List<Component>> _columnList;

  // Parallel arrays of entity IDs and entities (same index as each row).
  final List<EntityId> _entityIds = [];
  final List<Entity> _entities = [];

  /// Where an entity lands when a component type is added to, or removed
  /// from, one of these — so a migration is a map lookup, not a search.
  final Map<Type, Archetype> _addEdges = {};
  final Map<Type, Archetype?> _removeEdges = {};

  /// The cached queries this archetype matches, told when its rows change.
  final List<_QueryCacheEntry> _queries = [];

  /// Number of entities stored in this archetype.
  int get length => _entityIds.length;

  /// Create an archetype for the given component [types].
  Archetype(Set<Type> types) : this._(types.toList(growable: false));

  Archetype._(List<Type> typeList)
    : _typeList = typeList,
      _typeSet = Set<Type>.of(typeList),
      _columnList = [for (final _ in typeList) <Component>[]],
      _columns = {} {
    for (var i = 0; i < typeList.length; i++) {
      _columns[typeList[i]] = _columnList[i];
    }
  }

  /// Get a typed component for [row].
  T? getComponent<T extends Component>(int row) {
    final col = _columns[T];
    if (col == null || row < 0 || row >= col.length) return null;
    return col[row] as T;
  }

  /// Get a component by runtime [type] for [row].
  Component? getComponentByType(Type type, int row) {
    final col = _columns[type];
    if (col == null || row < 0 || row >= col.length) return null;
    return col[row];
  }

  /// Get all components for [row].
  Iterable<Component> getComponents(int row) {
    return _columnList.map((col) => col[row]);
  }

  /// Direct access to a column for tight system loops. Read it; never
  /// resize it.
  List<Component>? getColumn(Type type) => _columns[type];

  /// The entity IDs stored in insertion order. Read it; never resize it.
  List<EntityId> get entityIds => _entityIds;

  /// The entity in [row] — to check [Entity.isActive] while walking the
  /// columns.
  Entity entityAt(int row) => _entities[row];

  /// Whether this holds exactly [types] (in any order).
  bool _hasExactly(Iterable<Type> types, int count) =>
      count == _typeSet.length && types.every(_typeSet.contains);

  /// Append [entity] with [components] — one per type, in [_typeList]
  /// order — and return its row.
  int _appendRow(Entity entity, List<Component> components) {
    final row = _entityIds.length;
    _entityIds.add(entity.id);
    _entities.add(entity);
    for (var i = 0; i < _columnList.length; i++) {
      _columnList[i].add(components[i]);
    }
    return row;
  }

  /// Remove [row] by swap-and-pop, keeping the arrays dense. The entity
  /// moved into [row], if any, is told its new row.
  void _removeRow(int row) {
    final lastRow = _entityIds.length - 1;
    if (row != lastRow) {
      final moved = _entities[lastRow];
      _entityIds[row] = _entityIds[lastRow];
      _entities[row] = moved;
      moved._archetypeRow = row;
      for (final col in _columnList) {
        col[row] = col[lastRow];
      }
    }
    _entityIds.removeLast();
    _entities.removeLast();
    for (final col in _columnList) {
      col.removeLast();
    }
  }

  /// Empty every row (the world is being cleared).
  void _clearRows() {
    _entityIds.clear();
    _entities.clear();
    for (final col in _columnList) {
      col.clear();
    }
  }

  /// Canonical string key for a set of types: the sorted type names.
  static String _computeSignature(Set<Type> types) {
    final names = types.map((t) => t.toString()).toList()..sort();
    return names.join('\x00');
  }
}

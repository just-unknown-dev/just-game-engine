part of '../ecs.dart';

// ════════════════════════════════════════════════════════════════════════════
// Archetype – dense storage for entities sharing the same component set
// ════════════════════════════════════════════════════════════════════════════

/// An [Archetype] groups all entities that share the exact same set of
/// component types. Components of each type are stored in contiguous lists
/// (one "column" per type), giving systems cache-friendly iteration.
class Archetype {
  /// The canonical set of component types in this archetype.
  final Set<Type> types;

  /// Deterministic string key derived from [types] (used as map key).
  ///
  /// Computed from sorted type names, which is collision-free.
  final String signature;

  // Dense component arrays – one list per component type.
  final Map<Type, List<Component>> _columns;

  // Parallel array of entity IDs (same index as each column row).
  final List<EntityId> _entityIds = [];

  // Fast lookup: entity ID → row index.
  final Map<EntityId, int> _rowIndex = {};

  /// Number of entities stored in this archetype.
  int get length => _entityIds.length;

  /// Create an archetype for the given component [types].
  Archetype(this.types)
    : signature = _computeSignature(types),
      _columns = {for (final t in types) t: <Component>[]};

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
    return _columns.values.map((col) => col[row]);
  }

  /// Direct access to a column for tight system loops.
  List<Component>? getColumn(Type type) => _columns[type];

  /// The entity IDs stored in insertion order.
  List<EntityId> get entityIds => _entityIds;

  /// Add an entity with its [components] and return the assigned row index.
  ///
  /// Validates that every type in this archetype is present in [components]
  /// before mutating state, ensuring atomicity on mismatch.
  int addEntity(EntityId id, Map<Type, Component> components) {
    // Pre-validate before any mutation so state stays consistent on mismatch.
    for (final type in types) {
      if (!components.containsKey(type)) {
        throw ArgumentError(
          'Archetype mismatch: component map is missing type $type. '
          'Expected types: $types, got: ${components.keys.toSet()}',
        );
      }
    }
    final row = _entityIds.length;
    _entityIds.add(id);
    _rowIndex[id] = row;
    for (final type in types) {
      _columns[type]!.add(components[type]!);
    }
    return row;
  }

  /// Remove an entity. Returns the removed entity's components.
  ///
  /// Uses swap-and-pop to keep arrays dense. When a swap occurs the moved
  /// entity's row reference is updated via [entityMap].
  Map<Type, Component> removeEntity(
    EntityId id,
    Map<EntityId, Entity> entityMap,
  ) {
    final row = _rowIndex.remove(id)!;
    final result = <Type, Component>{};
    final lastRow = _entityIds.length - 1;

    // Collect the removed entity's components.
    for (final type in types) {
      result[type] = _columns[type]![row];
    }

    // Swap-and-pop when removing from the middle.
    if (row != lastRow) {
      final movedId = _entityIds[lastRow];
      _entityIds[row] = movedId;
      _rowIndex[movedId] = row;
      entityMap[movedId]?._archetypeRow = row;
      for (final type in types) {
        _columns[type]![row] = _columns[type]![lastRow];
      }
    }

    _entityIds.removeLast();
    for (final type in types) {
      _columns[type]!.removeLast();
    }

    return result;
  }

  /// Canonical string key for a set of types.
  ///
  /// Sorts the type names alphabetically and joins them. This is
  /// order-independent and collision-free (two different type sets always
  /// produce different keys, unlike integer hash approaches that can collide
  /// in Dart web due to JS float-precision loss).
  static String _computeSignature(Set<Type> types) {
    final names = types.map((t) => t.toString()).toList()..sort();
    return names.join('\x00');
  }
}

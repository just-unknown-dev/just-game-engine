/// Entity Spatial Grid
///
/// Generic broad-phase spatial index for ECS entities.
library;

import 'package:flutter/material.dart';

import '../ecs.dart';

/// A uniform grid for fast "which entities are roughly near this rect"
/// broad-phase queries — the same technique `just_physics_engine`'s
/// `SpatialGrid` uses for collision broad-phase, generalized here to any ECS
/// [Entity] instead of a physics body.
///
/// Call [sync] once per frame with the full candidate entity set and a bounds
/// callback; only entities whose cell range actually changed since the last
/// sync are touched (removed from their old cells, inserted into new ones) —
/// not a full rebuild. Then [query] a rect to get back a small candidate
/// list. This only guarantees "might overlap" — callers must still run their
/// own precise overlap check on the result.
///
/// Positions are never cached inside the grid itself — only entity
/// references — so whatever reads a queried entity's `TransformComponent`
/// afterwards always sees its true current position.
class EntitySpatialGrid {
  final double cellSize;

  final Map<int, List<Entity>> _cells = {};
  final List<List<Entity>> _listPool = [];
  final Map<Entity, _CellRange> _tracked = {};
  final Set<Entity> _seen = <Entity>{};
  final List<Entity> _removedScratch = [];

  EntitySpatialGrid({this.cellSize = 256});

  static int _hash(int x, int y) => (x * 73856093) ^ (y * 83492791);

  List<Entity> _acquireList() =>
      _listPool.isNotEmpty ? _listPool.removeLast() : <Entity>[];

  _CellRange _rangeOf(Rect bounds) => _CellRange(
    minX: (bounds.left / cellSize).floor(),
    minY: (bounds.top / cellSize).floor(),
    maxX: (bounds.right / cellSize).floor(),
    maxY: (bounds.bottom / cellSize).floor(),
  );

  void _insertIntoRange(Entity entity, _CellRange range) {
    for (var x = range.minX; x <= range.maxX; x++) {
      for (var y = range.minY; y <= range.maxY; y++) {
        final hash = _hash(x, y);
        (_cells[hash] ??= _acquireList()).add(entity);
      }
    }
  }

  void _removeFromRange(Entity entity, _CellRange range) {
    for (var x = range.minX; x <= range.maxX; x++) {
      for (var y = range.minY; y <= range.maxY; y++) {
        final hash = _hash(x, y);
        final bucket = _cells[hash];
        if (bucket == null) continue;
        bucket.remove(entity);
        if (bucket.isEmpty) {
          _cells.remove(hash);
          _listPool.add(bucket);
        }
      }
    }
  }

  /// Incrementally sync the grid to [entities]' current bounds ([boundsOf],
  /// world-space). Entities whose cell range hasn't changed since the last
  /// call are left untouched; entities no longer present in [entities] are
  /// removed from the grid.
  void sync(Iterable<Entity> entities, Rect Function(Entity) boundsOf) {
    _seen.clear();

    for (final entity in entities) {
      _seen.add(entity);
      final nextRange = _rangeOf(boundsOf(entity));
      final previousRange = _tracked[entity];

      if (previousRange == nextRange) continue;

      if (previousRange != null) {
        _removeFromRange(entity, previousRange);
      }
      _insertIntoRange(entity, nextRange);
      _tracked[entity] = nextRange;
    }

    _removedScratch.clear();
    for (final entity in _tracked.keys) {
      if (!_seen.contains(entity)) _removedScratch.add(entity);
    }
    for (final entity in _removedScratch) {
      final previousRange = _tracked.remove(entity);
      if (previousRange != null) _removeFromRange(entity, previousRange);
    }
  }

  /// Broad-phase candidates whose tracked cell range overlaps [queryRect].
  /// Deduplicated — an entity spanning multiple cells is returned once.
  /// Callers must still do a precise bounds check on the result.
  List<Entity> query(Rect queryRect) {
    final range = _rangeOf(queryRect);
    final results = <Entity>{};
    for (var x = range.minX; x <= range.maxX; x++) {
      for (var y = range.minY; y <= range.maxY; y++) {
        final bucket = _cells[_hash(x, y)];
        if (bucket != null) results.addAll(bucket);
      }
    }
    return results.toList();
  }

  /// Reset to empty, returning all cell lists to the pool.
  void clear() {
    for (final list in _cells.values) {
      list.clear();
      _listPool.add(list);
    }
    _cells.clear();
    _tracked.clear();
    _seen.clear();
  }

  /// Number of entities currently tracked (diagnostics/tests).
  int get trackedEntityCount => _tracked.length;
}

class _CellRange {
  final int minX;
  final int minY;
  final int maxX;
  final int maxY;

  const _CellRange({
    required this.minX,
    required this.minY,
    required this.maxX,
    required this.maxY,
  });

  @override
  bool operator ==(Object other) =>
      other is _CellRange &&
      other.minX == minX &&
      other.minY == minY &&
      other.maxX == maxX &&
      other.maxY == maxY;

  @override
  int get hashCode => Object.hash(minX, minY, maxX, maxY);
}

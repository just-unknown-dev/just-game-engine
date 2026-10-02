/// Entity Spatial Grid
///
/// Generic broad-phase spatial index for ECS entities.
library;

import 'dart:ui' show Rect;

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
/// Steady state allocates nothing: each tracked entity has one record,
/// made when it is first seen, holding its cell range and the stamps that
/// replace per-call sets; [query] can fill a list the caller keeps.
///
/// Positions are never cached inside the grid itself — only entity
/// references — so whatever reads a queried entity's `TransformComponent`
/// afterwards always sees its true current position.
class EntitySpatialGrid {
  /// Side of one square cell, in world units. Bounds much larger than a
  /// cell are filed in many cells, which costs more each time they move.
  final double cellSize;

  final Map<int, List<_Tracked>> _cells = {};
  final List<List<_Tracked>> _listPool = [];
  final Map<Entity, _Tracked> _tracked = {};
  final List<_Tracked> _removedScratch = [];
  int _syncStamp = 0;
  int _queryStamp = 0;

  /// An empty grid of [cellSize]-unit cells, 256 by default.
  EntitySpatialGrid({this.cellSize = 256});

  static int _hash(int x, int y) => (x * 73856093) ^ (y * 83492791);

  List<_Tracked> _acquireList() =>
      _listPool.isNotEmpty ? _listPool.removeLast() : <_Tracked>[];

  void _insert(_Tracked t) {
    for (var x = t.minX; x <= t.maxX; x++) {
      for (var y = t.minY; y <= t.maxY; y++) {
        (_cells[_hash(x, y)] ??= _acquireList()).add(t);
      }
    }
  }

  void _remove(_Tracked t) {
    for (var x = t.minX; x <= t.maxX; x++) {
      for (var y = t.minY; y <= t.maxY; y++) {
        final hash = _hash(x, y);
        final bucket = _cells[hash];
        if (bucket == null) continue;
        bucket.remove(t);
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
    final stamp = ++_syncStamp;

    for (final entity in entities) {
      final bounds = boundsOf(entity);
      final minX = (bounds.left / cellSize).floor();
      final minY = (bounds.top / cellSize).floor();
      final maxX = (bounds.right / cellSize).floor();
      final maxY = (bounds.bottom / cellSize).floor();

      final known = _tracked[entity];
      if (known == null) {
        final t = _Tracked(entity, minX, minY, maxX, maxY)..synced = stamp;
        _tracked[entity] = t;
        _insert(t);
        continue;
      }
      known.synced = stamp;
      if (known.minX == minX &&
          known.minY == minY &&
          known.maxX == maxX &&
          known.maxY == maxY) {
        continue;
      }
      _remove(known);
      known
        ..minX = minX
        ..minY = minY
        ..maxX = maxX
        ..maxY = maxY;
      _insert(known);
    }

    _removedScratch.clear();
    for (final t in _tracked.values) {
      if (t.synced != stamp) _removedScratch.add(t);
    }
    for (final t in _removedScratch) {
      _tracked.remove(t.entity);
      _remove(t);
    }
    _removedScratch.clear();
  }

  /// Broad-phase candidates whose tracked cell range overlaps [queryRect].
  /// Deduplicated — an entity spanning multiple cells is returned once.
  /// Callers must still do a precise bounds check on the result.
  ///
  /// Given [out], the candidates are added to it and it is returned, so a
  /// caller querying every frame can reuse one list.
  List<Entity> query(Rect queryRect, [List<Entity>? out]) {
    final results = out ?? <Entity>[];
    final stamp = ++_queryStamp;
    final minX = (queryRect.left / cellSize).floor();
    final minY = (queryRect.top / cellSize).floor();
    final maxX = (queryRect.right / cellSize).floor();
    final maxY = (queryRect.bottom / cellSize).floor();
    for (var x = minX; x <= maxX; x++) {
      for (var y = minY; y <= maxY; y++) {
        final bucket = _cells[_hash(x, y)];
        if (bucket == null) continue;
        for (final t in bucket) {
          if (t.queried == stamp) continue;
          t.queried = stamp;
          results.add(t.entity);
        }
      }
    }
    return results;
  }

  /// Reset to empty, returning all cell lists to the pool.
  void clear() {
    for (final list in _cells.values) {
      list.clear();
      _listPool.add(list);
    }
    _cells.clear();
    _tracked.clear();
  }

  /// Number of entities currently tracked (diagnostics/tests).
  int get trackedEntityCount => _tracked.length;
}

/// One tracked entity: the cells it covers, and when it was last synced
/// and last returned by a query.
class _Tracked {
  _Tracked(this.entity, this.minX, this.minY, this.maxX, this.maxY);

  final Entity entity;
  int minX;
  int minY;
  int maxX;
  int maxY;
  int synced = 0;
  int queried = 0;
}

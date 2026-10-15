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
///
/// Bounds that are not finite (NaN or infinite) are left out — such an
/// entity is in no cell, and no query returns it. Bounds spanning more
/// than [maxCellSpan] cells on an axis, or lying further out than the grid
/// can number its cells, are not filed cell by cell: such an entity is
/// returned by every query instead, which a broad phase allows.
class EntitySpatialGrid {
  /// Side of one square cell, in world units. Bounds much larger than a
  /// cell are filed in many cells, which costs more each time they move.
  final double cellSize;

  /// The most cells an entity is filed in along each axis; one spanning
  /// more is returned by every query instead.
  final int maxCellSpan;

  /// Cell coordinates beyond this (either sign) are not numbered: an
  /// entity out there is returned by every query.
  static const double _maxCell = 1e9;

  final Map<int, List<_Tracked>> _cells = {};
  final List<List<_Tracked>> _listPool = [];
  final Map<Entity, _Tracked> _tracked = {};
  final List<_Tracked> _removedScratch = [];

  /// The tracked entities too large or too far out for cells, returned by
  /// every query.
  final List<_Tracked> _everywhere = [];
  int _syncStamp = 0;
  int _queryStamp = 0;

  /// An empty grid of [cellSize]-unit cells, 256 by default, filing an
  /// entity in at most [maxCellSpan] cells along each axis (64 by default).
  EntitySpatialGrid({this.cellSize = 256, this.maxCellSpan = 64})
    : assert(maxCellSpan > 0);

  /// Whether cell coordinates [minX]..[maxX] × [minY]..[maxY] (as doubles,
  /// already floored) can be filed cell by cell.
  bool _fits(double minX, double minY, double maxX, double maxY) =>
      minX >= -_maxCell &&
      minY >= -_maxCell &&
      maxX <= _maxCell &&
      maxY <= _maxCell &&
      maxX - minX < maxCellSpan &&
      maxY - minY < maxCellSpan;

  static int _hash(int x, int y) => (x * 73856093) ^ (y * 83492791);

  List<_Tracked> _acquireList() =>
      _listPool.isNotEmpty ? _listPool.removeLast() : <_Tracked>[];

  void _insert(_Tracked t) {
    if (t.everywhere) {
      _everywhere.add(t);
      return;
    }
    for (var x = t.minX; x <= t.maxX; x++) {
      for (var y = t.minY; y <= t.maxY; y++) {
        (_cells[_hash(x, y)] ??= _acquireList()).add(t);
      }
    }
  }

  void _remove(_Tracked t) {
    if (t.everywhere) {
      _everywhere.remove(t);
      return;
    }
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
      // Not finite: in no cell. Left unstamped, it is dropped below.
      if (!bounds.isFinite) continue;
      final fl = (bounds.left / cellSize).floorToDouble();
      final ft = (bounds.top / cellSize).floorToDouble();
      final fr = (bounds.right / cellSize).floorToDouble();
      final fb = (bounds.bottom / cellSize).floorToDouble();
      final everywhere = !_fits(fl, ft, fr, fb);
      final minX = everywhere ? 0 : fl.toInt();
      final minY = everywhere ? 0 : ft.toInt();
      final maxX = everywhere ? -1 : fr.toInt();
      final maxY = everywhere ? -1 : fb.toInt();

      final known = _tracked[entity];
      if (known == null) {
        final t = _Tracked(entity, minX, minY, maxX, maxY)
          ..everywhere = everywhere
          ..synced = stamp;
        _tracked[entity] = t;
        _insert(t);
        continue;
      }
      known.synced = stamp;
      if (known.everywhere == everywhere &&
          known.minX == minX &&
          known.minY == minY &&
          known.maxX == maxX &&
          known.maxY == maxY) {
        continue;
      }
      _remove(known);
      known
        ..everywhere = everywhere
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
  ///
  /// A rect with a NaN side finds nothing. One covering more cells than
  /// the grid tracks entities — an infinite one, say — is answered by
  /// looking at each tracked entity rather than at each cell.
  List<Entity> query(Rect queryRect, [List<Entity>? out]) {
    final results = out ?? <Entity>[];
    if (queryRect.hasNaN) return results;
    final stamp = ++_queryStamp;
    for (final t in _everywhere) {
      t.queried = stamp;
      results.add(t.entity);
    }
    final fl = (queryRect.left / cellSize).floorToDouble();
    final ft = (queryRect.top / cellSize).floorToDouble();
    final fr = (queryRect.right / cellSize).floorToDouble();
    final fb = (queryRect.bottom / cellSize).floorToDouble();
    if (fr < fl || fb < ft) return results;
    final cellsAsked = (fr - fl + 1) * (fb - ft + 1);
    if (!cellsAsked.isFinite || cellsAsked > _tracked.length) {
      // Cheaper to look at every tracked entity than at every cell asked.
      for (final t in _tracked.values) {
        if (t.queried == stamp) continue;
        if (t.maxX < fl || t.minX > fr || t.maxY < ft || t.minY > fb) {
          continue;
        }
        t.queried = stamp;
        results.add(t.entity);
      }
      return results;
    }
    final minX = fl.toInt(), minY = ft.toInt();
    final maxX = fr.toInt(), maxY = fb.toInt();
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
    _everywhere.clear();
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

  /// Too large or too far out for cells: returned by every query.
  bool everywhere = false;
}

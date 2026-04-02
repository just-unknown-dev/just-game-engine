part of '../physics_engine.dart';

/// Pair of physics bodies for collision checking.
class BodyPair {
  final PhysicsBody a;
  final PhysicsBody b;
  BodyPair(this.a, this.b);

  @override
  bool operator ==(Object other) =>
      other is BodyPair &&
      ((other.a == a && other.b == b) || (other.a == b && other.b == a));

  @override
  int get hashCode => a.hashCode ^ b.hashCode;
}

/// A uniform grid for broad-phase collision detection.
///
/// Cell lists are pooled and reused between frames to avoid per-frame GC
/// pressure from Map reallocation.
class SpatialGrid {
  final double cellSize;
  final Map<int, List<PhysicsBody>> cells = {};

  /// Pool of previously allocated cell lists, reused on next rebuild.
  final List<List<PhysicsBody>> _listPool = [];

  /// Tracks the last occupied cell range for each body.
  final Map<PhysicsBody, _CellRange> _trackedBodies = {};
  final Set<PhysicsBody> _seenBodies = <PhysicsBody>{};

  int _lastDirtyBodyCount = 0;

  SpatialGrid(this.cellSize);

  int _hash(int x, int y) {
    // A simple hash function for 2D grids (using prime numbers)
    return (x * 73856093) ^ ((y * 19349663) >> 1);
  }

  /// Clear all cells, returning their lists to the pool for reuse.
  void clear() {
    for (final list in cells.values) {
      list.clear();
      _listPool.add(list);
    }
    cells.clear();
    _trackedBodies.clear();
    _seenBodies.clear();
    _lastDirtyBodyCount = 0;
  }

  /// Obtain a list from the pool or allocate a new one.
  List<PhysicsBody> _acquireList() {
    return _listPool.isNotEmpty ? _listPool.removeLast() : <PhysicsBody>[];
  }

  void insert(PhysicsBody body) {
    final range = _computeRange(body);
    if (range == null) return;

    _insertIntoRange(body, range);
    _trackedBodies[body] = range;
  }

  void syncBodies(Iterable<PhysicsBody> bodies) {
    _seenBodies.clear();
    var dirtyBodies = 0;

    for (final body in bodies) {
      _seenBodies.add(body);

      final nextRange = _computeRange(body);
      final previousRange = _trackedBodies[body];

      if (nextRange == null) {
        if (previousRange != null) {
          _removeFromRange(body, previousRange);
          _trackedBodies.remove(body);
          dirtyBodies++;
        }
        continue;
      }

      if (previousRange == nextRange) {
        continue;
      }

      if (previousRange != null) {
        _removeFromRange(body, previousRange);
      }
      _insertIntoRange(body, nextRange);
      _trackedBodies[body] = nextRange;
      dirtyBodies++;
    }

    final removedBodies = <PhysicsBody>[];
    for (final body in _trackedBodies.keys) {
      if (!_seenBodies.contains(body)) {
        removedBodies.add(body);
      }
    }

    for (final body in removedBodies) {
      final previousRange = _trackedBodies.remove(body);
      if (previousRange != null) {
        _removeFromRange(body, previousRange);
        dirtyBodies++;
      }
    }

    _lastDirtyBodyCount = dirtyBodies;
  }

  void removeBody(PhysicsBody body) {
    final previousRange = _trackedBodies.remove(body);
    if (previousRange != null) {
      _removeFromRange(body, previousRange);
    }
  }

  _CellRange? _computeRange(PhysicsBody body) {
    if (!body.isActive || !body.checkCollision) return null;

    final bounds = body.shape.getBounds(body.position.toOffset());
    return _CellRange(
      minX: (bounds.left / cellSize).floor(),
      minY: (bounds.top / cellSize).floor(),
      maxX: (bounds.right / cellSize).floor(),
      maxY: (bounds.bottom / cellSize).floor(),
    );
  }

  void _insertIntoRange(PhysicsBody body, _CellRange range) {
    for (int x = range.minX; x <= range.maxX; x++) {
      for (int y = range.minY; y <= range.maxY; y++) {
        final hash = _hash(x, y);
        (cells[hash] ?? (cells[hash] = _acquireList())).add(body);
      }
    }
  }

  void _removeFromRange(PhysicsBody body, _CellRange range) {
    for (int x = range.minX; x <= range.maxX; x++) {
      for (int y = range.minY; y <= range.maxY; y++) {
        final hash = _hash(x, y);
        final bucket = cells[hash];
        if (bucket == null) continue;

        bucket.remove(body);
        if (bucket.isEmpty) {
          cells.remove(hash);
          _listPool.add(bucket);
        }
      }
    }
  }

  /// Get potentially colliding pairs.
  Set<BodyPair> getPotentialCollisions() {
    final pairs = <BodyPair>{};
    for (final bin in cells.values) {
      if (bin.length > 1) {
        for (int i = 0; i < bin.length; i++) {
          for (int j = i + 1; j < bin.length; j++) {
            pairs.add(BodyPair(bin[i], bin[j]));
          }
        }
      }
    }
    return pairs;
  }

  int get dirtyBodyCount => _lastDirtyBodyCount;

  int get trackedCellCount => cells.length;

  int get trackedBodyCount => _trackedBodies.length;
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
  bool operator ==(Object other) {
    return other is _CellRange &&
        other.minX == minX &&
        other.minY == minY &&
        other.maxX == maxX &&
        other.maxY == maxY;
  }

  @override
  int get hashCode => Object.hash(minX, minY, maxX, maxY);
}

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
  }

  /// Obtain a list from the pool or allocate a new one.
  List<PhysicsBody> _acquireList() {
    return _listPool.isNotEmpty ? _listPool.removeLast() : <PhysicsBody>[];
  }

  void insert(PhysicsBody body) {
    if (!body.isActive || !body.checkCollision) return;

    final bounds = body.shape.getBounds(body.position.toOffset());
    final minX = (bounds.left / cellSize).floor();
    final minY = (bounds.top / cellSize).floor();
    final maxX = (bounds.right / cellSize).floor();
    final maxY = (bounds.bottom / cellSize).floor();

    for (int x = minX; x <= maxX; x++) {
      for (int y = minY; y <= maxY; y++) {
        final hash = _hash(x, y);
        (cells[hash] ?? (cells[hash] = _acquireList())).add(body);
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
}

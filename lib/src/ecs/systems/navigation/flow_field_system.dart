library;

import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart' show Offset, Rect;

import '../../ecs.dart';
import '../../components/components.dart';

/// Grid-based "flow field" pathfinding toward a named target entity (the
/// player, by default), routing around any entity carrying a
/// [NavigationObstacleComponent].
///
/// Rather than solving a path per agent (expensive with a horde of zombies
/// all chasing the same point), this rasterizes a walkability grid over a
/// bounded [activeWindowSize] region centered on the target, runs a single
/// multi-source BFS from the target's cell outward, and derives a
/// steepest-descent flow direction per cell. Every agent then just samples
/// its own cell via [directionAt] — O(1) per agent per frame, with the one
/// shared BFS recomputed on a throttle (see [recomputeInterval]) rather than
/// every frame, since a horde-steering signal doesn't need per-frame
/// precision.
///
/// Bounding the grid to a window around the target (rather than the whole
/// map) keeps recompute cost independent of total map size — obstacles and
/// agents far outside it just fall back to a direct seek (see
/// [directionAt]).
class FlowFieldSystem extends System {
  /// Name of the entity BFS expands from — matches `world.findEntityByName`
  /// usage elsewhere in this codebase (e.g. `'Player'`).
  final String targetName;

  /// World-space size (both dimensions) of one grid cell. Should roughly
  /// match a typical obstacle's diameter so a blocked cell ≈ one obstacle
  /// footprint, rather than either swallowing several obstacles into one
  /// cell or leaving a single obstacle spread thinly across many.
  final double cellSize;

  /// World-space size (both dimensions) of the moving window centered on the
  /// target that the field covers. Agents outside it get `null` from
  /// [directionAt] and should fall back to a direct seek.
  final double activeWindowSize;

  /// Minimum real time between BFS recomputes.
  final Duration recomputeInterval;

  FlowFieldSystem({
    this.targetName = 'Player',
    this.cellSize = 48.0,
    this.activeWindowSize = 4000.0,
    this.recomputeInterval = const Duration(milliseconds: 150),
  });

  @override
  int get priority => 86; // Above ZombieAISystem (85), below Physics (90).

  @override
  List<Type> get requiredComponents => const [];

  double _timeSinceRecompute = double.infinity;

  Rect? _bounds;
  int _cols = 0;
  int _rows = 0;

  /// Flattened flow direction per cell, `Offset.zero` where unresolved.
  List<Offset>? _flow;

  @override
  void update(double deltaTime) {
    _timeSinceRecompute += deltaTime;
    if (_timeSinceRecompute < recomputeInterval.inMilliseconds / 1000.0) {
      return;
    }
    _timeSinceRecompute = 0;

    final target = world.findEntityByName(targetName);
    final targetPos = target?.getComponent<TransformComponent>()?.position;
    if (targetPos == null) {
      _bounds = null;
      return;
    }

    _recompute(targetPos.toOffset());
  }

  /// Sampled flow direction at [worldPos] (normalized-ish, not guaranteed
  /// unit length — callers that need a unit vector should normalize),
  /// or `null` if outside the current active window / not yet computed.
  Offset? directionAt(Offset worldPos) {
    final bounds = _bounds;
    final flow = _flow;
    if (bounds == null || flow == null || !bounds.contains(worldPos)) {
      return null;
    }

    final col = ((worldPos.dx - bounds.left) / cellSize).floor();
    final row = ((worldPos.dy - bounds.top) / cellSize).floor();
    if (col < 0 || col >= _cols || row < 0 || row >= _rows) return null;

    final dir = flow[row * _cols + col];
    return dir == Offset.zero ? null : dir;
  }

  void _recompute(Offset targetPos) {
    final cols = (activeWindowSize / cellSize).ceil();
    final rows = cols;
    final bounds = Rect.fromCenter(
      center: targetPos,
      width: cols * cellSize,
      height: rows * cellSize,
    );

    final cellCount = cols * rows;
    final walkable = Uint8List(cellCount)..fillRange(0, cellCount, 1);

    for (final entity in world.query(const [
      TransformComponent,
      NavigationObstacleComponent,
    ])) {
      final pos = entity
          .getComponent<TransformComponent>()!
          .position
          .toOffset();
      final radius = entity
          .getComponent<NavigationObstacleComponent>()!
          .radius;

      final obstacleBounds = Rect.fromCircle(center: pos, radius: radius);
      if (!bounds.overlaps(obstacleBounds)) continue;

      final minCol = math.max(
        0,
        ((obstacleBounds.left - bounds.left) / cellSize).floor(),
      );
      final maxCol = math.min(
        cols - 1,
        ((obstacleBounds.right - bounds.left) / cellSize).floor(),
      );
      final minRow = math.max(
        0,
        ((obstacleBounds.top - bounds.top) / cellSize).floor(),
      );
      final maxRow = math.min(
        rows - 1,
        ((obstacleBounds.bottom - bounds.top) / cellSize).floor(),
      );

      for (var row = minRow; row <= maxRow; row++) {
        for (var col = minCol; col <= maxCol; col++) {
          final cellCenter = Offset(
            bounds.left + (col + 0.5) * cellSize,
            bounds.top + (row + 0.5) * cellSize,
          );
          if ((cellCenter - pos).distance <= radius) {
            walkable[row * cols + col] = 0;
          }
        }
      }
    }

    final distance = Int32List(cellCount)..fillRange(0, cellCount, -1);
    final targetCol = ((targetPos.dx - bounds.left) / cellSize)
        .floor()
        .clamp(0, cols - 1);
    final targetRow = ((targetPos.dy - bounds.top) / cellSize)
        .floor()
        .clamp(0, rows - 1);
    final targetIndex = targetRow * cols + targetCol;

    // The target's own cell must be walkable to seed the BFS, regardless of
    // rasterization above (the target itself is never a
    // NavigationObstacleComponent, but stray overlap near its edge shouldn't
    // strand the search).
    walkable[targetIndex] = 1;
    distance[targetIndex] = 0;

    final queue = Queue<int>()..add(targetIndex);
    while (queue.isNotEmpty) {
      final index = queue.removeFirst();
      final row = index ~/ cols;
      final col = index % cols;
      final dist = distance[index];

      void visit(int nRow, int nCol) {
        if (nRow < 0 || nRow >= rows || nCol < 0 || nCol >= cols) return;
        final nIndex = nRow * cols + nCol;
        if (walkable[nIndex] == 0 || distance[nIndex] != -1) return;
        distance[nIndex] = dist + 1;
        queue.add(nIndex);
      }

      visit(row - 1, col);
      visit(row + 1, col);
      visit(row, col - 1);
      visit(row, col + 1);
    }

    final flow = List<Offset>.filled(cellCount, Offset.zero);
    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols; col++) {
        final index = row * cols + col;
        if (distance[index] <= 0) continue; // unreached, or the target cell

        var bestDist = distance[index];
        var bestRow = row;
        var bestCol = col;

        void consider(int nRow, int nCol) {
          if (nRow < 0 || nRow >= rows || nCol < 0 || nCol >= cols) return;
          final nIndex = nRow * cols + nCol;
          final nDist = distance[nIndex];
          if (nDist != -1 && nDist < bestDist) {
            bestDist = nDist;
            bestRow = nRow;
            bestCol = nCol;
          }
        }

        consider(row - 1, col);
        consider(row + 1, col);
        consider(row, col - 1);
        consider(row, col + 1);

        if (bestRow == row && bestCol == col) continue;
        flow[index] = Offset(
          (bestCol - col).toDouble(),
          (bestRow - row).toDouble(),
        );
      }
    }

    _bounds = bounds;
    _cols = cols;
    _rows = rows;
    _flow = flow;
  }
}

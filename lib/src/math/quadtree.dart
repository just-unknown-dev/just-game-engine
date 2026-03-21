/// A lightweight axis-aligned quadtree for spatial queries.
///
/// Stores items associated with [Rect] bounds. Supports efficient
/// [queryRect] to find all items whose bounds intersect a given region
/// (e.g. a camera viewport), reducing culling from O(n) to O(log n + k).
library;

import 'dart:ui' show Rect;

/// A spatial quadtree that indexes items by their bounding rectangle.
///
/// Usage:
/// ```dart
/// final tree = Quadtree<Sprite>(bounds: Rect.fromLTWH(0, 0, 4096, 4096));
/// tree.insert(sprite, sprite.getBounds());
/// final visible = tree.queryRect(camera.visibleRect);
/// ```
class Quadtree<T> {
  /// World-space bounds of this node.
  final Rect bounds;

  /// Maximum items per leaf before subdividing.
  final int maxItems;

  /// Maximum tree depth.
  final int maxDepth;

  final int _depth;
  final List<_QuadEntry<T>> _items = [];
  List<Quadtree<T>>? _children;

  /// Create a quadtree covering [bounds].
  Quadtree({required this.bounds, this.maxItems = 16, this.maxDepth = 8})
    : _depth = 0;

  Quadtree._child({
    required this.bounds,
    required this.maxItems,
    required this.maxDepth,
    required int depth,
  }) : _depth = depth;

  /// Remove all items and collapse children.
  void clear() {
    _items.clear();
    _children = null;
  }

  /// Insert an [item] with [rect] bounds.
  void insert(T item, Rect? rect) {
    if (rect == null) return;
    if (!bounds.overlaps(rect)) return;

    if (_children != null) {
      for (final child in _children!) {
        if (child.bounds.overlaps(rect)) {
          child.insert(item, rect);
        }
      }
      return;
    }

    _items.add(_QuadEntry(item, rect));

    if (_items.length > maxItems && _depth < maxDepth) {
      _subdivide();
    }
  }

  /// Return all items whose bounds intersect [region].
  ///
  /// The [result] list is appended to (not cleared) so callers can
  /// accumulate across multiple queries.
  void queryRect(Rect region, List<T> result) {
    if (!bounds.overlaps(region)) return;

    for (final entry in _items) {
      if (entry.rect.overlaps(region)) {
        result.add(entry.item);
      }
    }

    if (_children != null) {
      for (final child in _children!) {
        child.queryRect(region, result);
      }
    }
  }

  void _subdivide() {
    final mx = bounds.left + bounds.width / 2;
    final my = bounds.top + bounds.height / 2;
    final nextDepth = _depth + 1;

    _children = [
      Quadtree._child(
        bounds: Rect.fromLTRB(bounds.left, bounds.top, mx, my),
        maxItems: maxItems,
        maxDepth: maxDepth,
        depth: nextDepth,
      ),
      Quadtree._child(
        bounds: Rect.fromLTRB(mx, bounds.top, bounds.right, my),
        maxItems: maxItems,
        maxDepth: maxDepth,
        depth: nextDepth,
      ),
      Quadtree._child(
        bounds: Rect.fromLTRB(bounds.left, my, mx, bounds.bottom),
        maxItems: maxItems,
        maxDepth: maxDepth,
        depth: nextDepth,
      ),
      Quadtree._child(
        bounds: Rect.fromLTRB(mx, my, bounds.right, bounds.bottom),
        maxItems: maxItems,
        maxDepth: maxDepth,
        depth: nextDepth,
      ),
    ];

    // Redistribute existing items into children.
    for (final entry in _items) {
      for (final child in _children!) {
        if (child.bounds.overlaps(entry.rect)) {
          child._items.add(entry);
        }
      }
    }
    _items.clear();
  }
}

class _QuadEntry<T> {
  final T item;
  final Rect rect;
  _QuadEntry(this.item, this.rect);
}

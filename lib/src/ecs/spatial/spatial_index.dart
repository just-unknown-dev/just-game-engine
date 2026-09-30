/// Finding entities by where they are.
library;

import 'dart:ui';

import 'package:just_dart/just_dart.dart';

import '../ecs.dart';
import 'entity_spatial_grid.dart';

/// An index of entities by their bounds in the world, in 3-D.
///
/// What a culler or a picking pass asks "what is near here?" A 2-D game's
/// is [PlanarSpatialIndex], over the uniform grid it has always used; a 3-D
/// one can index depth too, behind the same two calls.
abstract interface class SpatialIndex {
  /// Rebuild from [entities], each where [boundsOf] puts it.
  void sync(
    Iterable<Entity> entities,
    void Function(Entity entity, Aabb3 out) boundsOf,
  );

  /// Add to [out] every entity whose bounds may overlap [region].
  void query(Aabb3 region, List<Entity> out);
}

/// A [SpatialIndex] over the x/y footprint of everything — an
/// [EntitySpatialGrid] — ignoring depth, as 2-D does.
class PlanarSpatialIndex implements SpatialIndex {
  PlanarSpatialIndex({double cellSize = 256.0})
    : grid = EntitySpatialGrid(cellSize: cellSize);

  /// The grid underneath.
  final EntitySpatialGrid grid;

  final Aabb3 _box = Aabb3();

  @override
  void sync(
    Iterable<Entity> entities,
    void Function(Entity entity, Aabb3 out) boundsOf,
  ) {
    grid.sync(entities, (e) {
      boundsOf(e, _box);
      return _box.isEmpty ? Rect.zero : _box.toRect();
    });
  }

  @override
  void query(Aabb3 region, List<Entity> out) {
    if (region.isEmpty) return;
    out.addAll(grid.query(region.toRect()));
  }
}

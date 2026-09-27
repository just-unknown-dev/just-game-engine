/// Marks a static body built from a map layer's tiles.
library;

import '../../../subsystems/level_map/tile_cell.dart';
import '../../ecs.dart';

/// On each body a map's collision is built from: which map and layer it
/// came from, what kind of collision, and which cells.
///
/// A collision handler asking "what did the player land on?" reads it —
/// the kind (`hazard`), the class, the cells, and through the map their
/// properties. Runtime only; the body is rebuilt, never saved.
class MapBodyComponent extends Component {
  MapBodyComponent({
    required this.mapEntityId,
    required this.layerId,
    required this.kind,
    this.className = '',
    this.cells = const [],
  });

  /// The entity carrying the `LevelMapComponent`.
  final int mapEntityId;

  /// The layer, by its id within the map.
  final int layerId;

  /// The collision kind's id.
  final String kind;

  /// The class of the tiles it was built from.
  final String className;

  /// The cells it covers.
  final List<TileCoord> cells;

  @override
  String toString() => 'MapBody($kind, layer $layerId, ${cells.length} cells)';
}

/// Tiled map ECS components.
///
/// Components for integrating Tiled map data with the Entity-Component System.
library;

import 'package:just_tiled/just_tiled.dart';
import '../../ecs.dart';

/// Component for entities representing an entire tile layer.
///
/// Each tile layer is mapped to a single entity (rather than one entity
/// per tile) to prevent entity bloat. The [TileMapRenderer] handles
/// GPU-batched rendering of the entire layer.
class TileMapLayerComponent extends Component {
  /// The parsed tile layer data.
  final TileLayer tileLayer;

  /// The GPU-batched renderer for this layer.
  final TileMapRenderer renderer;

  /// The parent map metadata (for orientation, tile size, etc.).
  final TiledMap map;

  /// Create a tile map layer component.
  TileMapLayerComponent({
    required this.tileLayer,
    required this.renderer,
    required this.map,
  });

  @override
  String toString() => 'TileMapLayer(${tileLayer.name})';
}

/// Component for entities representing a Tiled map object.
///
/// Each `object` in an `objectgroup` spawns an individual entity with
/// this component attached, providing access to the object's metadata
/// and custom properties.
class TiledObjectComponent extends Component {
  /// The parsed object data.
  final TiledObject tiledObject;

  /// Create a tiled object component.
  TiledObjectComponent({required this.tiledObject});

  /// Shorthand for accessing custom properties.
  TiledProperties get properties => tiledObject.properties;

  /// Shorthand for the object's type/class name.
  String get type => tiledObject.type;

  /// Shorthand for the object's name.
  String get name => tiledObject.name;

  @override
  String toString() =>
      'TiledObject(${tiledObject.name}, type: ${tiledObject.type})';
}

/// Factory for translating a parsed TiledMap DOM into ECS entities.
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:just_tiled/just_tiled.dart';

import '../../ecs.dart';
import '../../components/components.dart';

/// Callback for mapping Tiled custom properties to engine components.
///
/// Receives the object's type/class name and its custom properties.
/// Returns a component to attach to the entity, or null to skip.
typedef ComponentMapper =
    Component? Function(String className, TiledProperties properties);

/// Factory that spawns ECS entities from a parsed [TiledMap].
///
/// ## Usage
/// ```dart
/// final entities = TiledMapFactory.spawnMap(
///   world,
///   tiledMap,
///   atlasCollection,
///   componentMapper: (className, props) {
///     if (className == 'enemy') {
///       return HealthComponent(maxHealth: props.getDouble('hp') ?? 100);
///     }
///     return null;
///   },
/// );
/// ```
class TiledMapFactory {
  TiledMapFactory._();

  /// Spawn all tile layers and object groups from [map] into [world].
  ///
  /// Returns a list of all spawned entities.
  ///
  /// - **Tile layers** → one Entity with [TileMapLayerComponent] + [TransformComponent]
  /// - **Object groups** → one Entity per [TiledObject] with [TransformComponent] + [TiledObjectComponent]
  ///
  /// [atlasCollection] provides the texture atlas for each tileset.
  /// [componentMapper] optionally maps custom properties to additional components.
  static List<Entity> spawnMap(
    World world,
    TiledMap map,
    TextureAtlasCollection atlasCollection, {
    ComponentMapper? componentMapper,
  }) {
    final entities = <Entity>[];

    for (final layer in map.layers) {
      entities.addAll(
        _spawnLayer(world, map, layer, atlasCollection, componentMapper),
      );
    }

    return entities;
  }

  /// Recursively spawn entities from a layer.
  static List<Entity> _spawnLayer(
    World world,
    TiledMap map,
    Layer layer,
    TextureAtlasCollection atlasCollection,
    ComponentMapper? componentMapper,
  ) {
    final entities = <Entity>[];

    if (layer is TileLayer) {
      entities.add(_spawnTileLayer(world, map, layer, atlasCollection));
    } else if (layer is ObjectGroup) {
      entities.addAll(_spawnObjectGroup(world, map, layer, componentMapper));
    } else if (layer is GroupLayer) {
      for (final child in layer.layers) {
        entities.addAll(
          _spawnLayer(world, map, child, atlasCollection, componentMapper),
        );
      }
    }
    // ImageLayer entities could be added here if needed

    return entities;
  }

  /// Spawn a single entity for a tile layer.
  static Entity _spawnTileLayer(
    World world,
    TiledMap map,
    TileLayer tileLayer,
    TextureAtlasCollection atlasCollection,
  ) {
    // Find the appropriate atlas for this layer's tiles
    // Use the first non-empty tile to determine the atlas
    TextureAtlas? layerAtlas;
    for (final gid in tileLayer.data) {
      if (gid > 0) {
        final result = atlasCollection.lookup(gid);
        if (result != null) {
          layerAtlas = result.atlas;
          break;
        }
      }
    }

    // Create the renderer (even if no atlas found, to avoid null checks)
    late final TileMapRenderer renderer;
    if (layerAtlas != null) {
      renderer = TileMapRenderer(
        tileLayer: tileLayer,
        map: map,
        atlas: layerAtlas,
      );
      renderer.compile();
    } else {
      // Create a dummy renderer that won't render
      // This should only happen if the layer has no visible tiles
      renderer = TileMapRenderer(
        tileLayer: tileLayer,
        map: map,
        atlas: atlasCollection.isNotEmpty
            ? atlasCollection.atlases.first
            : throw StateError('No texture atlases available'),
      );
    }

    final entity = world.createEntity(name: 'tilelayer_${tileLayer.name}');
    entity.addComponent(
      TransformComponent(
        position: Offset(tileLayer.offsetX, tileLayer.offsetY),
      ),
    );
    entity.addComponent(
      TileMapLayerComponent(tileLayer: tileLayer, renderer: renderer, map: map),
    );

    return entity;
  }

  /// Spawn individual entities for each object in an object group.
  static List<Entity> _spawnObjectGroup(
    World world,
    TiledMap map,
    ObjectGroup objectGroup,
    ComponentMapper? componentMapper,
  ) {
    final entities = <Entity>[];

    for (final obj in objectGroup.objects) {
      if (!obj.visible) continue;

      final entity = world.createEntity(
        name: obj.name.isNotEmpty ? obj.name : 'object_${obj.id}',
      );

      // Add TransformComponent from object position
      entity.addComponent(
        TransformComponent(
          position: Offset(obj.x, obj.y),
          rotation: obj.rotation * math.pi / 180.0, // degrees to radians
        ),
      );

      // Add TiledObjectComponent for metadata access
      entity.addComponent(TiledObjectComponent(tiledObject: obj));

      // Apply custom property mapping
      if (componentMapper != null && obj.type.isNotEmpty) {
        final component = componentMapper(obj.type, obj.properties);
        if (component != null) {
          entity.addComponent(component);
        }
      }

      entities.add(entity);
    }

    return entities;
  }
}

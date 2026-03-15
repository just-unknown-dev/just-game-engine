/// ECS render system for Tiled map layers.
///
/// Queries entities with [TileMapLayerComponent] and renders them
/// using the GPU-batched [TileMapRenderer], with camera frustum culling.
library;

import 'package:flutter/material.dart';
import 'package:just_tiled/just_tiled.dart';

import 'ecs.dart';
import 'tiled_components.dart';
import '../rendering/camera.dart';

/// System that renders tile map layers within the ECS world.
///
/// Uses [Camera.getVisibleBounds] for viewport frustum culling so that
/// only tiles within the camera view are processed.
///
/// Add this system to your [World] after loading a Tiled map:
/// ```dart
/// world.addSystem(TileMapRenderSystem(camera: engine.rendering.camera));
/// ```
class TileMapRenderSystem extends System {
  /// Reference to the game camera for frustum culling.
  final Camera camera;

  /// Create a tile map render system.
  TileMapRenderSystem({required this.camera});

  @override
  List<Type> get requiredComponents => [TileMapLayerComponent];

  /// Higher priority so tile layers render before other entities.
  @override
  int get priority => 100;

  @override
  void render(Canvas canvas, Size size) {
    // Get visible world bounds from camera
    camera.viewportSize = size;
    final visibleBounds = camera.getVisibleBounds();

    forEach((entity) {
      final tileMapComp = entity.getComponent<TileMapLayerComponent>()!;

      // Skip invisible layers
      if (!tileMapComp.tileLayer.visible) return;

      // Quick bounds check — skip layers entirely outside the viewport
      final layerBounds = tileMapComp.renderer.worldBounds;
      if (!layerBounds.overlaps(visibleBounds)) return;

      // Delegate to the just_tiled renderer
      tileMapComp.renderer.render(
        canvas,
        Offset(camera.position.dx, camera.position.dy),
        visibleBounds,
      );
    });
  }
}

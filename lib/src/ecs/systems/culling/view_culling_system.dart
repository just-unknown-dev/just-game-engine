library;

import 'package:flutter/material.dart';

import '../../ecs.dart';
import '../../components/components.dart';
import '../../spatial/spatial.dart';
import '../../../interfaces/interfaces.dart';

/// Opt-in view culling — tracks which entities are near the camera and marks
/// them accordingly on their `CullStateComponent`.
///
/// Two separate radii are used rather than one shared threshold:
/// - [renderRadiusMultiplier] (default `1.2`) — a tight radius matching what's
///   actually on screen. `ViewCullingSystem` mirrors the result onto
///   `RenderableComponent.renderable.visible`, so `RenderSystem` skips
///   drawing culled entities automatically — no extra wiring needed.
/// - [activeRadiusMultiplier] (default `2.0`) — a larger radius used for
///   simulation. This engine's `MovementSystem`/`PhysicsSystem` skip any
///   entity whose `CullStateComponent.isActive` is `false`, and game-specific
///   systems (AI, etc.) should check the same flag. The gap between the two
///   radii means entities approaching the screen are already moving by the
///   time they scroll into view, instead of snapping to life at the edge.
///
/// A broad-phase [EntitySpatialGrid] (synced every frame — cheap, since only
/// entities that actually changed grid cell are touched) narrows the exact
/// bounds-overlap check down to a small candidate set instead of scanning
/// every opted-in entity in full each frame.
///
/// Entities must explicitly carry a [CullStateComponent] to participate —
/// nothing else is affected. The [hysteresisMargin] avoids visibility
/// flicker for entities sitting right on the render boundary (e.g. during
/// camera spring micro-movement): once visible, an entity needs to cross
/// slightly further out before it's culled back out.
///
/// ```dart
/// world.addSystem(ViewCullingSystem(camera: engine.cameraSystem.mainCamera));
/// enemy.addComponent(CullStateComponent()); // opt in — the player shouldn't get one
/// ```
class ViewCullingSystem extends System {
  final GameCamera camera;
  final double renderRadiusMultiplier;
  final double activeRadiusMultiplier;
  final double hysteresisMargin;

  final EntitySpatialGrid _grid;

  ViewCullingSystem({
    required this.camera,
    this.renderRadiusMultiplier = 1.2,
    this.activeRadiusMultiplier = 2.0,
    this.hysteresisMargin = 24.0,
    double gridCellSize = 256.0,
  }) : _grid = EntitySpatialGrid(cellSize: gridCellSize);

  @override
  int get priority => 91; // above PhysicsSystem(90)/MovementSystem(80) so they see this frame's fresh flags

  @override
  List<Type> get requiredComponents => [TransformComponent, CullStateComponent];

  @override
  void update(double deltaTime) {
    final visible = camera.getVisibleBounds();
    final center = visible.center;

    final renderRect = Rect.fromCenter(
      center: center,
      width: visible.width * renderRadiusMultiplier,
      height: visible.height * renderRadiusMultiplier,
    );
    final renderRectHysteresis = renderRect.inflate(hysteresisMargin);
    final activeRect = Rect.fromCenter(
      center: center,
      width: visible.width * activeRadiusMultiplier,
      height: visible.height * activeRadiusMultiplier,
    );

    final candidateEntities = entities;
    _grid.sync(candidateEntities, _worldBoundsOf);
    final nearby = _grid.query(activeRect).toSet();

    for (final entity in candidateEntities) {
      final cull = entity.getComponent<CullStateComponent>()!;
      final renderable = entity.getComponent<RenderableComponent>();

      if (!nearby.contains(entity)) {
        // Definitely outside the active (and therefore render) rect — no
        // need for a precise check.
        cull.isVisible = false;
        cull.isActive = false;
        if (renderable != null) renderable.renderable.visible = false;
        continue;
      }

      final worldBounds = _worldBoundsOf(entity);
      final renderTestRect = cull.isVisible ? renderRectHysteresis : renderRect;
      cull.isVisible = renderTestRect.overlaps(worldBounds);
      cull.isActive = activeRect.overlaps(worldBounds);
      if (renderable != null) renderable.renderable.visible = cull.isVisible;
    }
  }

  Rect _worldBoundsOf(Entity entity) {
    final position = entity.getComponent<TransformComponent>()!.position.toOffset();
    final renderable = entity.getComponent<RenderableComponent>()?.renderable;
    final bounds = renderable?.getBounds();
    if (bounds == null) {
      return Rect.fromCenter(center: position, width: 1, height: 1);
    }
    // Renderables like Sprite already center getBounds() on their own
    // (world-synced) position — shifting those again by the transform
    // position would double-count it. Only local/origin-centered bounds
    // (CustomRenderable-based shapes) need the shift. See
    // Renderable.boundsAreWorldSpace.
    if (renderable!.boundsAreWorldSpace) return bounds;
    return bounds.shift(position);
  }
}

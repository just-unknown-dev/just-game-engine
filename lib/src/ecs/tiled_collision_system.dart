/// Collision system for loading Tiled map collision objects into the physics engine.
///
/// Converts TMX `objectgroup` collision shapes (rectangle, polygon, ellipse)
/// into just_game_engine [PhysicsBody] instances with the appropriate
/// [CollisionShape] and registers them with the [PhysicsEngine].
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:just_tiled/just_tiled.dart';

import 'ecs.dart';
import 'tiled_components.dart';
import '../physics/physics_engine.dart';

/// System that loads TMX collision objects into the physics engine.
///
/// Call [loadCollisions] after spawning the map to convert Tiled
/// object group collision shapes into static [PhysicsBody] instances.
///
/// ```dart
/// final collisionSystem = TiledCollisionSystem(physicsEngine: engine.physics);
/// world.addSystem(collisionSystem);
/// collisionSystem.loadCollisions(tiledMap);
/// ```
class TiledCollisionSystem extends System {
  /// Reference to the game's physics engine.
  final PhysicsEngine physicsEngine;

  /// Optional spatial hash grid for fast proximity queries.
  final SpatialHashGrid<PhysicsBody>? spatialGrid;

  /// Bodies created by this system (for cleanup).
  final List<PhysicsBody> _bodies = [];

  /// Collision layer for tiled collision bodies.
  final int collisionLayer;

  /// Create a tiled collision system.
  TiledCollisionSystem({
    required this.physicsEngine,
    this.spatialGrid,
    this.collisionLayer = 1,
  });

  @override
  List<Type> get requiredComponents => [TiledObjectComponent];

  /// Load all collision objects from a [TiledMap] into the physics engine.
  ///
  /// Iterates through all object groups and creates static [PhysicsBody]
  /// instances for collision-type objects (rectangles, polygons, ellipses).
  void loadCollisions(TiledMap map) {
    for (final objectGroup in map.objectGroups) {
      for (final obj in objectGroup.objects) {
        _loadObjectCollision(obj);
      }
    }
  }

  /// Load collision objects from a specific [ObjectGroup].
  void loadObjectGroupCollisions(ObjectGroup objectGroup) {
    for (final obj in objectGroup.objects) {
      _loadObjectCollision(obj);
    }
  }

  /// Create a physics body from a single Tiled object.
  void _loadObjectCollision(TiledObject obj) {
    CollisionShape? shape;
    Offset position;

    if (obj.polygon != null && obj.polygon!.isNotEmpty) {
      // Polygon collision shape
      shape = PolygonShape(obj.polygon!);
      position = Offset(obj.x, obj.y);
    } else if (obj.isEllipse) {
      // Ellipse → approximate as circle using average radius
      final radius = math.min(obj.width, obj.height) / 2;
      shape = CircleShape(radius);
      position = Offset(obj.x + obj.width / 2, obj.y + obj.height / 2);
    } else if (obj.isPoint) {
      // Points don't have collision geometry
      return;
    } else if (obj.polyline != null) {
      // Polylines are edges, not closed shapes — skip for now
      // Could be converted to chain shapes in the future
      return;
    } else if (obj.width > 0 && obj.height > 0) {
      // Rectangle collision shape
      shape = RectangleShape(obj.width, obj.height);
      position = Offset(obj.x + obj.width / 2, obj.y + obj.height / 2);
    } else {
      return; // No collision geometry
    }

    // Create a static physics body
    final body = PhysicsBody(
      position: position,
      shape: shape,
      mass: 0.0, // Static body (infinite mass)
      restitution: _getRestitution(obj),
      friction: _getFriction(obj),
      isActive: true,
      checkCollision: true,
      useGravity: false,
      isAwake: true,
    );

    _bodies.add(body);
    physicsEngine.addBody(body);

    // Also insert into the spatial hash grid if available
    if (spatialGrid != null) {
      final bounds = shape.getBounds(position);
      spatialGrid!.insert(body, bounds);
    }
  }

  /// Extract restitution from custom properties (default 0.0 for walls).
  double _getRestitution(TiledObject obj) {
    return obj.properties.getDouble('restitution') ?? 0.0;
  }

  /// Extract friction from custom properties (default 0.5).
  double _getFriction(TiledObject obj) {
    return obj.properties.getDouble('friction') ?? 0.5;
  }

  /// Remove all collision bodies created by this system.
  void clearCollisions() {
    for (final body in _bodies) {
      physicsEngine.removeBody(body);
      if (spatialGrid != null) {
        spatialGrid!.remove(body);
      }
    }
    _bodies.clear();
  }

  @override
  void dispose() {
    clearCollisions();
    super.dispose();
  }

  /// Get the number of collision bodies loaded.
  int get bodyCount => _bodies.length;
}

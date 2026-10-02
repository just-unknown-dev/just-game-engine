part of '../ecs.dart';

// ════════════════════════════════════════════════════════════════════════════
// System
// ════════════════════════════════════════════════════════════════════════════

/// Base class for all systems
///
/// Systems contain logic and operate on entities with specific components.
/// Override update() to implement system logic.
abstract class System {
  /// World this system belongs to
  late World world;

  /// Required component types for this system
  List<Type> get requiredComponents;

  /// Whether this system is active
  bool isActive = true;

  /// Priority for system execution order (higher = earlier)
  int priority = 0;

  /// What [World.stats] files this system's time under — its type's name,
  /// worked out once rather than every frame.
  late final String _profileName = runtimeType.toString();

  /// Initialize the system
  void initialize() {}

  /// Update the system
  void update(double deltaTime) {}

  /// Render the system (optional)
  void render(Canvas canvas, Size size) {}

  /// Called when system is added to world
  void onAddedToWorld() {}

  /// Called when system is removed from world
  void onRemovedFromWorld() {}

  /// Dispose system resources
  void dispose() {}

  /// Get all entities that match this system's requirements
  Iterable<Entity> get entities {
    return world.query(requiredComponents);
  }

  /// Execute a function for each matching entity
  void forEach(void Function(Entity entity) action) {
    for (final entity in entities) {
      action(entity);
    }
  }
}

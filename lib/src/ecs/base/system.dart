part of '../ecs.dart';

// ════════════════════════════════════════════════════════════════════════════
// System
// ════════════════════════════════════════════════════════════════════════════

/// A [System] that also runs once per rendered frame, after the frame's
/// fixed updates and before it is drawn — for what must move at the
/// display's rate rather than the simulation's: a camera following a body
/// between physics steps, a look that reads this frame's mouse movement.
///
/// Implement it alongside [System] (`class MySystem extends System
/// implements FrameSystem`). Systems that don't implement it pay nothing,
/// and none of the engine's 2-D systems do.
abstract interface class FrameSystem {
  /// One rendered frame: [deltaTime] seconds since the last (scaled by the
  /// game's time scale); [alpha] how far the frame lies between the last
  /// two fixed updates (0..1), for blending a pose from its previous step to
  /// its current one.
  void frame(double deltaTime, double alpha);
}

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

  /// Priority for system execution order (higher = earlier). Systems of
  /// the same priority run in the order they were added.
  int priority = 0;

  /// The world this system is in — set by [World.addSystem], cleared by
  /// [World.removeSystem] — so a world can tell a system removed while the
  /// systems run from one still there.
  World? _addedTo;

  /// When this system was added among its world's: the tie-break between
  /// equal priorities.
  int _addOrder = 0;

  /// What [World.stats] files this system's time under (`systemTimesMs`).
  ///
  /// Its type's name by default, worked out once. A release build for the
  /// web shortens type names to something unreadable; a system whose
  /// timings are read there can override this with a fixed name.
  String get profileName => _profileName;

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

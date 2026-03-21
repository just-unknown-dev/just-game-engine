/// Well-known system execution priorities.
///
/// Systems with **higher** priority values run **earlier** in the frame.
/// Use these constants when constructing or registering systems so the
/// update order is explicit and discoverable in one place.
///
/// Canonical order per frame:
///
///  Input (100) → Physics (90) → Movement (80) → Animation (70)
///  → Gameplay (60) → Hierarchy (50) → Render (40) → Audio (−10)
library;

/// Named priority constants for [System.priority].
abstract final class SystemPriorities {
  /// Tile-map layers — painted first (background).
  static const int tileMap = 110;

  /// Parallax backgrounds — rendered just after tile maps, before input.
  static const int parallax = 105;

  /// Input processing — must run before any simulation systems.
  static const int input = 100;

  /// Physics (broad-phase + narrow-phase + resolution).
  static const int physics = 90;

  /// Movement — applies velocity to transform.
  static const int movement = 80;

  /// Animation state advance.
  static const int animation = 70;

  /// Gameplay logic (health, lifetime, scoring, …).
  static const int gameplay = 60;

  /// Parent–child hierarchy propagation.
  static const int hierarchy = 50;

  /// Rendering ECS entities.
  static const int render = 40;

  /// Boundary enforcement (wrap / clamp / bounce / destroy).
  static const int boundary = 30;

  /// Debug / diagnostics / engine-stats overlays.
  static const int debug = 10;

  /// Audio — runs late so world transforms are up to date.
  static const int audio = -10;
}

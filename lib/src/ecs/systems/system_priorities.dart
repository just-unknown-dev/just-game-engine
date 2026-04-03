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

  /// Deterministic property effects (Move, Scale, Shake, …).
  ///
  /// Runs after animation so sprite-driven positions are settled before
  /// effects apply their deltas, and before gameplay so logic sees the
  /// final positions for this frame.
  static const int effects = 65;

  /// Gameplay logic (health, lifetime, scoring, …).
  static const int gameplay = 60;

  /// Parent–child hierarchy propagation.
  static const int hierarchy = 50;

  /// Particle emitter update — advances [ParticleEmitter.update] for all
  /// [ParticleEmitterComponent] entities.
  ///
  /// Runs after [hierarchy] (50) so parent-propagated positions are settled,
  /// and before [render] (40) so particles are current when drawn.
  static const int particles = 48;

  /// Rendering ECS entities.
  static const int render = 40;

  /// Camera follow — repositions the camera based on [CameraFollowComponent]
  /// entities. Runs after [render] so the camera position update does not
  /// lag the current frame's rendering by one frame.
  static const int camera = 45;

  /// Fullscreen post-process shader passes — runs after [render] to apply
  /// screen-space effects (bloom, chromatic aberration, vignette, …).
  /// Lower priority value = later execution in the ECS update loop means
  /// [PostProcessSystem.update] runs after [RenderSystem.render], which is
  /// the correct order: passes are synced with [RenderingEngine] after the
  /// scene is queued for rendering.
  static const int postProcess = 35;

  /// Boundary enforcement (wrap / clamp / bounce / destroy).
  static const int boundary = 30;

  /// Debug / diagnostics / engine-stats overlays.
  static const int debug = 10;

  /// Audio — runs late so world transforms are up to date.
  static const int audio = -10;

  /// Narrative / Dialogue — updates NPC interactability and auto-advance
  /// timers.  Runs just after [gameplay] so quest/inventory state is settled
  /// before proximity is checked.
  static const int dialogue = gameplay - 1;
}

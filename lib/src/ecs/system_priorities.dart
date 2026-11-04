/// Well-known system execution priorities.
///
/// Systems with **higher** priority values run **earlier** in the frame.
/// Use these constants when constructing or registering systems so the
/// update order is explicit and discoverable in one place.
///
/// The order per frame, from the constants below: level maps (110), map
/// collision (108), parallax (105), input (100), player control (95),
/// moving platforms (92), physics (90), movement (80), animation (70),
/// effects (65), gameplay (60, then genre rules 59, dialogue 59 and
/// checkpoints 58), the hierarchy (50), particles (48), the camera (45),
/// rendering (40), post-processing (35), boundaries (30), debug drawing (10)
/// and audio (−10). Systems with equal priorities run in the order they
/// were added.
library;

/// Named priority constants for [System.priority].
abstract final class SystemPriorities {
  /// Level maps — loaded, and their layers kept current for drawing.
  static const int levelMap = 110;

  /// Map collision — bodies built from map layers' tiles, after
  /// [levelMap] has
  /// loaded the map and before [physics] steps.
  static const int mapCollision = 108;

  /// Parallax backgrounds — rendered just after level maps, before input.
  static const int parallax = 105;

  /// Input processing — must run before any simulation systems.
  static const int input = 100;

  /// Character control — reads input, writes velocity.
  ///
  /// Sits between [input] and [physics] deliberately: a jump pressed this
  /// frame must reach this frame's simulation step, not the next one, or the
  /// controls feel a frame behind at every press.
  static const int playerControl = 95;

  /// Physics (broad-phase + narrow-phase + resolution).
  static const int physics = 90;

  /// Moving platforms — steers kinematic bodies along their paths.
  ///
  /// Just above [physics] so the platform's velocity for this frame is set
  /// before the step that carries its riders along.
  static const int movingPlatform = 92;

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

  /// Genre rules layered on top of [gameplay] — hazards, pickups, goals,
  /// destructible geometry, kill planes. Just below [gameplay] so health
  /// changes it causes are seen by [checkpoint] in the same frame.
  ///
  /// This is the slot a genre package (`just_platformer_kit` and friends)
  /// runs its rule system in.
  static const int genreRules = 59;

  /// Checkpoint / respawn — runs just after gameplay so the checkpoint can
  /// react to player state (e.g. health reaching zero) within the same frame.
  static const int checkpoint = 58;

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

  /// The camera brain — picks and blends virtual cameras once everything
  /// has moved for the frame, so a shot frames where its target *is*.
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

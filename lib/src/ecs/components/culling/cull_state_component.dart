library;

import '../../ecs.dart';

/// Opt-in view-culling state, maintained each frame by `ViewCullingSystem`.
///
/// Add this component to any entity that should be culled based on distance
/// from the camera. Entities without it are never touched by culling — the
/// player, for instance, should simply never get one.
///
/// [isVisible] and [isActive] are two separate radii rather than one shared
/// threshold: [isVisible] uses a tight radius matching what's actually on
/// screen (an entity leaving it is hidden — `RenderableComponent.renderable
/// .visible` set false by `ViewCullingSystem`, and shown again when it comes
/// back — so `RenderSystem` skips drawing it with no extra wiring), while
/// [isActive] uses a larger radius so simulation (this
/// engine's `MovementSystem`/`PhysicsSystem`, and any game-specific system
/// that checks it, e.g. AI) keeps running for entities approaching the
/// screen — they arrive already moving instead of snapping to life right at
/// the visible edge.
class CullStateComponent extends Component {
  /// Within the tighter render radius this frame.
  ///
  /// Defaults to `false` (not `true`) so a brand-new entity's very first
  /// check can't accidentally benefit from `ViewCullingSystem`'s hysteresis
  /// margin (which only widens the boundary for entities *already* known to
  /// be visible) before it's ever actually been confirmed visible.
  bool isVisible = false;

  /// Within the larger active/simulation radius this frame. Built-in
  /// `MovementSystem`/`PhysicsSystem` skip entities where this is `false`.
  ///
  /// Defaults to `true` so a freshly-spawned entity still simulates for the
  /// one frame (if any) before `ViewCullingSystem` next runs and corrects it.
  bool isActive = true;

  /// Whether `ViewCullingSystem` is what holds the entity's renderable
  /// hidden: it set `visible` false when the entity left the render radius,
  /// and will set it true when it comes back. False while the entity is in
  /// view, and while the game itself has it hidden.
  ///
  /// Maintained by the system. Clear it to keep an entity the culler has
  /// hidden hidden when it comes back into view.
  bool hidesRenderable = false;
}

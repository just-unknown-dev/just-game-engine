library;

import '../../ecs.dart';

/// Runs an animation state machine on this entity: the graph decides which
/// clip the entity's [SpriteAnimationComponent] plays.
///
/// The graph is an `.animator.json` asset. Its parameters are the knobs —
/// some bound to the entity itself (speed, grounded) and filled in by
/// [AnimatorSystem], the rest set from game code with [setFloat] and
/// friends.
class AnimatorComponent extends Component {
  AnimatorComponent({
    this.graphPath = '',
    this.enabled = true,
    this.faceVelocity = false,
  });

  /// Asset path of the graph (e.g. `assets/sprites/hero.animator.json`).
  String graphPath;

  /// When false the animator holds its state and changes nothing.
  bool enabled;

  /// Flip the sprite to face the way the entity moves horizontally, keeping
  /// the last direction while it stands still.
  bool faceVelocity;

  // ── Runtime state (driven by AnimatorSystem) ─────────────────────────────

  /// Current parameter values, by name. Filled from the graph's defaults
  /// when it loads; values set before that are kept.
  final Map<String, Object> parameters = {};

  /// The state being played; empty until the graph has loaded.
  String currentState = '';

  /// The state before this one; empty at the start.
  String previousState = '';

  /// Seconds spent in [currentState].
  double stateTime = 0.0;

  void setFloat(String name, double value) => parameters[name] = value;
  void setInt(String name, int value) => parameters[name] = value;
  void setBool(String name, bool value) => parameters[name] = value;

  /// Sets a trigger; the transition that uses it switches it off again.
  void setTrigger(String name) => parameters[name] = true;
  void resetTrigger(String name) => parameters[name] = false;

  double getFloat(String name) => (parameters[name] as num?)?.toDouble() ?? 0.0;
  int getInt(String name) => (parameters[name] as num?)?.toInt() ?? 0;
  bool getBool(String name) => parameters[name] == true;

  /// Forgets the current state, so the animator starts again from the
  /// graph's entry.
  void restart() {
    currentState = '';
    previousState = '';
    stateTime = 0.0;
  }

  @override
  String toString() => 'Animator($graphPath, state: $currentState)';
}

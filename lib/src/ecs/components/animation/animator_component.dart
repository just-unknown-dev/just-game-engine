library;

import '../../../subsystems/animation/animator/animator_graph.dart'
    show AnimatorParameter;
import '../../ecs.dart';

/// Runs an animation state machine on this entity: the graph decides which
/// clip the entity's [SpriteAnimationComponent] plays.
///
/// The graph is an `.animator.json` asset. Its parameters are the knobs —
/// some bound to the entity itself (speed, grounded) and filled in by
/// [AnimatorSystem], the rest set from game code with [setFloat] and
/// friends.
class AnimatorComponent extends Component {
  /// An animator running the graph at [graphPath] — none while it is empty
  /// — switched on, and not flipping the sprite to face its velocity.
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

  /// Sets the parameter called [name] to [value]. A parameter bound to a
  /// source is overwritten each frame that source reads a value.
  void setFloat(String name, double value) => parameters[name] = value;

  /// Sets the parameter called [name] to [value]. A parameter bound to a
  /// source is overwritten each frame that source reads a value.
  void setInt(String name, int value) => parameters[name] = value;

  /// Sets the parameter called [name] to [value]. A parameter bound to a
  /// source is overwritten each frame that source reads a value.
  void setBool(String name, bool value) => parameters[name] = value;

  /// Sets a trigger; the transition that uses it switches it off again.
  void setTrigger(String name) => parameters[name] = true;

  /// Switches the trigger called [name] off without any transition having
  /// taken it.
  void resetTrigger(String name) => parameters[name] = false;

  /// The parameter called [name] as a double; 0 when it is unset. Read as
  /// [AnimatorParameter.asNumber] reads it, as conditions do: a bool
  /// (a trigger, say) is 1 or 0.
  double getFloat(String name) => AnimatorParameter.asNumber(parameters[name]);

  /// The parameter called [name] as an int (a double is truncated); 0 when
  /// it is unset. Read as [getFloat] reads it: a bool is 1 or 0.
  int getInt(String name) =>
      AnimatorParameter.asNumber(parameters[name]).toInt();

  /// Whether the parameter called [name] is on. Read as
  /// [AnimatorParameter.asBool] reads it, as conditions do: `true`, or a
  /// number other than 0. False when it is unset.
  bool getBool(String name) => AnimatorParameter.asBool(parameters[name]);

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

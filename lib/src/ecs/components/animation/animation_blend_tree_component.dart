/// Animation Blend Tree Component
///
/// Attach alongside a `RenderableComponent` whose `renderable` is a
/// `BlendSprite` to drive Unity-Animator-style state/blend-tree playback.
/// `AnimationBlendTreeSystem` (`lib/src/ecs/systems/animation/`) reads this
/// every frame, advances phases/transitions, and writes the resulting
/// weighted frames into the `BlendSprite`.
library;

import '../../ecs.dart';
import 'blend_clip.dart';
import 'blend_state_machine.dart';

class AnimationBlendTreeComponent extends Component {
  AnimationBlendTreeComponent({
    required this.machine,
    String? initialState,
    Map<String, BlendClip>? clips,
  }) : clips = clips ?? {},
       currentStateName = initialState ?? machine.defaultState;

  /// The state graph this component plays. Swappable at runtime (e.g. on
  /// weapon change) — the next [play] call starts fresh in the new machine.
  BlendStateMachine machine;

  /// Clip name -> playback metadata + frame source, resolved/loaded by
  /// game code (see `ANIMATION_BLEND_TREE.md`, "clip/image loading").
  final Map<String, BlendClip> clips;

  /// Directional row applied uniformly to every blended layer this frame
  /// (e.g. an 8-way facing octant) — orthogonal to blending itself; see
  /// `ANIMATION_BLEND_TREE.md`, "why clips blend but facing rows don't".
  int directionRow = 0;

  final Map<String, double> _floats = {};

  void setFloat(String name, double value) => _floats[name] = value;

  double getFloat(String name, [double fallback = 0.0]) =>
      _floats[name] ?? fallback;

  // ── Public playback request ─────────────────────────────────────────────

  /// Requests a transition to [stateName], crossfaded over
  /// `machine.durationFor`. A no-op if [stateName] is already the current
  /// state and not mid-transition, unless [restart] is set. Silently
  /// ignored if [stateName] isn't in [machine]'s states (mirrors
  /// `AnimatedSpriteComponent.switchClip`'s existing "unknown name is a
  /// no-op" convention elsewhere in this engine).
  ///
  /// [play] never checks [isLocked] itself — a one-shot state (attack,
  /// death, ...) plays to completion regardless of how many times [play]
  /// is called for something else while it's in flight. Callers that want
  /// the old "can't interrupt a one-shot" behavior should check [isLocked]
  /// before calling [play], the same way game code used to guard
  /// `_chooseSheet` on `lockUntilFinished`.
  void play(String stateName, {bool restart = false}) {
    if (!machine.states.containsKey(stateName)) return;
    if (stateName == currentStateName && !isTransitioning && !restart) return;
    requestedState = stateName;
    requestedRestart = restart;
  }

  // ── Runtime state ───────────────────────────────────────────────────────
  // requestedState/requestedRestart: written by [play], consumed and
  // cleared by AnimationBlendTreeSystem. Everything below is written only
  // by AnimationBlendTreeSystem.

  String? requestedState;
  bool requestedRestart = false;

  String currentStateName;
  String? targetStateName;
  double transitionElapsed = 0.0;
  double transitionDuration = 0.0;

  /// Normalized playhead for [currentStateName]: `[0,1)` wrapping while
  /// looping, clamped `[0,1]` (not wrapping) while one-shot.
  double currentPhase = 0.0;

  /// Normalized playhead for [targetStateName] while [isTransitioning].
  double targetPhase = 0.0;

  bool get isTransitioning => targetStateName != null;

  BlendState get _currentState => machine.states[currentStateName]!;

  bool get isOneShot => !_currentState.loop;

  /// Whether a one-shot [currentStateName] has finished playing (always
  /// `false` for looping states).
  bool get isCurrentStateComplete => isOneShot && currentPhase >= 1.0;

  /// Whether [currentStateName] is a still-playing one-shot — mirrors the
  /// old `PlayerAnimationComponent.lockUntilFinished` convention for
  /// gating re-selection in calling code.
  bool get isLocked => isOneShot && !isCurrentStateComplete;

  @override
  String toString() =>
      'AnimationBlendTree($currentStateName'
      '${isTransitioning ? ' -> $targetStateName' : ''})';
}

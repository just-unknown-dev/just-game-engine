/// Blend State Machine
///
/// A named graph of [BlendState]s (each playing a [BlendMotion]) connected
/// by crossfade [BlendTransition]s. Pure data — see
/// `AnimationBlendTreeComponent` for the attached runtime/playback state
/// and `AnimationBlendTreeSystem` for the per-frame evaluation.
library;

import 'blend_motion.dart';

/// One node in a [BlendStateMachine]: what it plays and whether it loops.
class BlendState {
  const BlendState({required this.motion, this.loop = true});

  final BlendMotion motion;

  /// Looping states share a normalized phase across their contributing
  /// clips (see `AnimationBlendTreeSystem`); non-looping states play once
  /// and clamp at the end (e.g. an attack swing or a death clip).
  final bool loop;

  factory BlendState.fromJson(Map<String, dynamic> json) => BlendState(
    motion: BlendMotion.fromJson(
      (json['motion'] as Map).cast<String, dynamic>(),
    ),
    loop: json['loop'] as bool? ?? true,
  );

  Map<String, dynamic> toJson() => {'motion': motion.toJson(), 'loop': loop};
}

/// An explicit crossfade-duration override for one (or any) state pair.
///
/// [from] is nullable — `null` matches *any* current state transitioning to
/// [to], letting a machine override just a handful of pairs instead of
/// authoring every legal (from, to) combination.
class BlendTransition {
  const BlendTransition({
    this.from,
    required this.to,
    required this.duration,
  });

  final String? from;
  final String to;
  final double duration;

  factory BlendTransition.fromJson(Map<String, dynamic> json) =>
      BlendTransition(
        from: json['from'] as String?,
        to: json['to'] as String,
        duration: (json['duration'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {
    if (from != null) 'from': from,
    'to': to,
    'duration': duration,
  };
}

/// A named set of [BlendState]s, any of which can be requested via `play`
/// on `AnimationBlendTreeComponent` — crossfaded over [durationFor], not
/// restricted to an authored whitelist of legal transitions.
class BlendStateMachine {
  BlendStateMachine({
    required this.states,
    List<BlendTransition>? transitions,
    required this.defaultState,
    this.defaultTransitionDuration = 0.15,
  }) : transitions = transitions ?? const [];

  final Map<String, BlendState> states;

  /// Sparse duration overrides — see [BlendTransition.from].
  final List<BlendTransition> transitions;
  final String defaultState;
  final double defaultTransitionDuration;

  /// The crossfade duration for a `from -> to` transition: the most
  /// specific matching override in [transitions] (an exact [BlendTransition.from]
  /// match beats a wildcard `from: null` match), falling back to
  /// [defaultTransitionDuration] when nothing matches.
  double durationFor(String from, String to) {
    BlendTransition? wildcard;
    for (final t in transitions) {
      if (t.to != to) continue;
      if (t.from == from) return t.duration;
      if (t.from == null) wildcard ??= t;
    }
    return wildcard?.duration ?? defaultTransitionDuration;
  }

  factory BlendStateMachine.fromJson(Map<String, dynamic> json) =>
      BlendStateMachine(
        states: {
          for (final e
              in (json['states'] as Map).cast<String, dynamic>().entries)
            e.key: BlendState.fromJson((e.value as Map).cast<String, dynamic>()),
        },
        transitions: (json['transitions'] as List?)
            ?.map(
              (t) => BlendTransition.fromJson((t as Map).cast<String, dynamic>()),
            )
            .toList(),
        defaultState: json['defaultState'] as String,
        defaultTransitionDuration:
            (json['defaultTransitionDuration'] as num?)?.toDouble() ?? 0.15,
      );

  Map<String, dynamic> toJson() => {
    'states': {for (final e in states.entries) e.key: e.value.toJson()},
    if (transitions.isNotEmpty)
      'transitions': transitions.map((t) => t.toJson()).toList(),
    'defaultState': defaultState,
    'defaultTransitionDuration': defaultTransitionDuration,
  };
}

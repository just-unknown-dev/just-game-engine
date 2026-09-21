/// The animation state machine's data: what an `.animator.json` holds.
///
/// A graph is states (each playing one clip), transitions between them that
/// fire when their conditions hold, and the parameters those conditions
/// read. It knows nothing of entities; [AnimatorSystem] runs it.
library;

import 'dart:convert';

/// What kind of value a parameter holds.
enum AnimatorParameterType {
  float,
  int,
  bool,

  /// A bool that a transition using it switches back off: "jumped", "hit".
  trigger,
}

/// A named value transitions are conditioned on.
class AnimatorParameter {
  const AnimatorParameter({
    required this.name,
    this.type = AnimatorParameterType.float,
    this.defaultValue,
    this.binding,
  });

  final String name;
  final AnimatorParameterType type;

  /// A `num` or `bool` matching [type]; null is zero / false.
  final Object? defaultValue;

  /// The id of an [AnimatorBindings] source that writes this parameter every
  /// frame — `speedX`, `grounded` — so no game code has to. Null leaves it
  /// to the game.
  final String? binding;

  /// The value a fresh animator starts this parameter at.
  Object get initialValue => switch (type) {
    AnimatorParameterType.float => (defaultValue as num?)?.toDouble() ?? 0.0,
    AnimatorParameterType.int => (defaultValue as num?)?.toInt() ?? 0,
    AnimatorParameterType.bool ||
    AnimatorParameterType.trigger => defaultValue == true,
  };

  factory AnimatorParameter.fromJson(Map<String, dynamic> json) =>
      AnimatorParameter(
        name: json['name'] as String? ?? '',
        type:
            AnimatorParameterType.values.asNameMap()[json['type']] ??
            AnimatorParameterType.float,
        defaultValue: json['default'],
        binding: (json['binding'] as String?)?.trim().isEmpty ?? true
            ? null
            : (json['binding'] as String).trim(),
      );

  Map<String, dynamic> toJson() => {
    'name': name,
    'type': type.name,
    if (defaultValue != null) 'default': defaultValue,
    if (binding != null) 'binding': binding,
  };

  AnimatorParameter copyWith({
    String? name,
    AnimatorParameterType? type,
    Object? defaultValue,
    String? binding,
    bool clearBinding = false,
  }) => AnimatorParameter(
    name: name ?? this.name,
    type: type ?? this.type,
    defaultValue: defaultValue ?? this.defaultValue,
    binding: clearBinding ? null : binding ?? this.binding,
  );
}

/// How a condition compares its parameter with its value.
enum AnimatorOp {
  greater('>'),
  greaterOrEqual('>='),
  less('<'),
  lessOrEqual('<='),
  equals('=='),
  notEquals('!=');

  const AnimatorOp(this.symbol);

  final String symbol;

  static AnimatorOp parse(Object? raw) {
    for (final op in values) {
      if (op.symbol == raw || op.name == raw) return op;
    }
    return AnimatorOp.equals;
  }
}

/// One test a transition makes: `speed > 10`, `grounded == true`. For a
/// trigger the op and value are ignored — it holds while the trigger is set.
class AnimatorCondition {
  const AnimatorCondition({
    required this.parameter,
    this.op = AnimatorOp.equals,
    this.value = true,
  });

  final String parameter;
  final AnimatorOp op;

  /// A `num` or a `bool`.
  final Object value;

  /// Whether this holds for [current], the parameter's value now.
  bool holds(Object? current, AnimatorParameterType type) {
    if (type == AnimatorParameterType.trigger) return current == true;
    if (type == AnimatorParameterType.bool) {
      final wanted = value == true;
      final now = current == true;
      return op == AnimatorOp.notEquals ? now != wanted : now == wanted;
    }
    final a = (current as num?)?.toDouble() ?? 0.0;
    final b = (value is num) ? (value as num).toDouble() : 0.0;
    return switch (op) {
      AnimatorOp.greater => a > b,
      AnimatorOp.greaterOrEqual => a >= b,
      AnimatorOp.less => a < b,
      AnimatorOp.lessOrEqual => a <= b,
      AnimatorOp.equals => a == b,
      AnimatorOp.notEquals => a != b,
    };
  }

  factory AnimatorCondition.fromJson(Map<String, dynamic> json) =>
      AnimatorCondition(
        parameter: json['param'] as String? ?? '',
        op: AnimatorOp.parse(json['op']),
        value: json['value'] as Object? ?? true,
      );

  Map<String, dynamic> toJson() => {
    'param': parameter,
    'op': op.symbol,
    'value': value,
  };
}

/// A state: one clip, playing.
class AnimatorState {
  const AnimatorState({
    required this.name,
    this.clip = '',
    this.speed = 1.0,
    this.loop,
    this.timeline = '',
    this.x = 0,
    this.y = 0,
  });

  final String name;

  /// The clip to play; empty plays the clip named like the state.
  final String clip;
  final double speed;

  /// Overrides whether the clip loops; null takes the clip's own.
  final bool? loop;

  /// A `.timeline.json` the entity's Timeline Player plays from its start
  /// on entering this state; a transition's exit time then reads the
  /// timeline's progress, not the clip's. Empty for none.
  final String timeline;

  /// Where the node sits in a graph editor. Means nothing at runtime.
  final double x;
  final double y;

  /// The clip this state plays.
  String get clipName => clip.isEmpty ? name : clip;

  factory AnimatorState.fromJson(Map<String, dynamic> json) => AnimatorState(
    name: json['name'] as String? ?? '',
    clip: json['clip'] as String? ?? '',
    speed: (json['speed'] as num?)?.toDouble() ?? 1.0,
    loop: json['loop'] as bool?,
    timeline: json['timeline'] as String? ?? '',
    x: (json['x'] as num?)?.toDouble() ?? 0,
    y: (json['y'] as num?)?.toDouble() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    if (clip.isNotEmpty) 'clip': clip,
    if (speed != 1.0) 'speed': speed,
    if (loop != null) 'loop': loop,
    if (timeline.isNotEmpty) 'timeline': timeline,
    'x': x,
    'y': y,
  };

  AnimatorState copyWith({
    String? name,
    String? clip,
    double? speed,
    bool? loop,
    bool clearLoop = false,
    String? timeline,
    double? x,
    double? y,
  }) => AnimatorState(
    name: name ?? this.name,
    clip: clip ?? this.clip,
    speed: speed ?? this.speed,
    loop: clearLoop ? null : loop ?? this.loop,
    timeline: timeline ?? this.timeline,
    x: x ?? this.x,
    y: y ?? this.y,
  );
}

/// A way from one state to another, taken when every condition holds.
class AnimatorTransition {
  const AnimatorTransition({
    required this.from,
    required this.to,
    this.conditions = const [],
    this.hasExitTime = false,
    this.exitTime = 1.0,
    this.priority = 0,
  });

  /// [from] for a transition that can leave any state.
  static const String anyState = '*';

  final String from;
  final String to;
  final List<AnimatorCondition> conditions;

  /// Wait until the playing clip has reached [exitTime] before leaving. A
  /// transition with no conditions and an exit time is "when it finishes".
  final bool hasExitTime;

  /// How far through the clip, 0–1. One pass for a looping clip.
  final double exitTime;

  /// Among transitions that could fire, the highest goes; ties go to the
  /// one listed first.
  final int priority;

  bool get isFromAny => from == anyState;

  factory AnimatorTransition.fromJson(Map<String, dynamic> json) =>
      AnimatorTransition(
        from: json['from'] as String? ?? anyState,
        to: json['to'] as String? ?? '',
        conditions: [
          for (final c in (json['conditions'] as List?) ?? const [])
            if (c is Map) AnimatorCondition.fromJson(c.cast<String, dynamic>()),
        ],
        hasExitTime: json['hasExitTime'] as bool? ?? false,
        exitTime: (json['exitTime'] as num?)?.toDouble() ?? 1.0,
        priority: (json['priority'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
    'from': from,
    'to': to,
    'conditions': [for (final c in conditions) c.toJson()],
    if (hasExitTime) 'hasExitTime': true,
    if (hasExitTime) 'exitTime': exitTime,
    if (priority != 0) 'priority': priority,
  };

  AnimatorTransition copyWith({
    String? from,
    String? to,
    List<AnimatorCondition>? conditions,
    bool? hasExitTime,
    double? exitTime,
    int? priority,
  }) => AnimatorTransition(
    from: from ?? this.from,
    to: to ?? this.to,
    conditions: conditions ?? this.conditions,
    hasExitTime: hasExitTime ?? this.hasExitTime,
    exitTime: exitTime ?? this.exitTime,
    priority: priority ?? this.priority,
  );
}

/// A whole state machine. Immutable: an editor replaces it.
class AnimatorGraph {
  const AnimatorGraph({
    this.parameters = const [],
    this.states = const [],
    this.transitions = const [],
    this.entry = '',
    this.atlasPath = '',
  });

  /// The file format's version, written as `version`.
  static const int formatVersion = 1;

  final List<AnimatorParameter> parameters;
  final List<AnimatorState> states;
  final List<AnimatorTransition> transitions;

  /// The state an animator starts in; empty starts in the first.
  final String entry;

  /// The atlas the clips were picked from. A hint for tools — the entity's
  /// own sprite animation says what actually plays.
  final String atlasPath;

  AnimatorState? stateNamed(String name) {
    for (final s in states) {
      if (s.name == name) return s;
    }
    return null;
  }

  AnimatorParameter? parameterNamed(String name) {
    for (final p in parameters) {
      if (p.name == name) return p;
    }
    return null;
  }

  /// Where an animator starts: [entry], else the first state.
  AnimatorState? get entryState =>
      stateNamed(entry) ?? (states.isEmpty ? null : states.first);

  /// What is wrong with this graph, in words an author can act on. Empty
  /// when nothing is.
  List<String> validate() {
    final problems = <String>[];
    final names = <String>{};
    for (final s in states) {
      if (s.name.isEmpty) problems.add('A state has no name.');
      if (!names.add(s.name)) problems.add('Two states are named "${s.name}".');
    }
    if (entry.isNotEmpty && stateNamed(entry) == null) {
      problems.add('The entry state "$entry" does not exist.');
    }
    for (final t in transitions) {
      if (!t.isFromAny && stateNamed(t.from) == null) {
        problems.add('A transition leaves "${t.from}", which does not exist.');
      }
      if (stateNamed(t.to) == null) {
        problems.add('A transition goes to "${t.to}", which does not exist.');
      }
      if (t.conditions.isEmpty && !t.hasExitTime) {
        problems.add(
          '${t.from} → ${t.to} has no conditions and no exit time, so it '
          'fires at once.',
        );
      }
      for (final c in t.conditions) {
        if (parameterNamed(c.parameter) == null) {
          problems.add(
            '${t.from} → ${t.to} tests "${c.parameter}", which is not a '
            'parameter.',
          );
        }
      }
    }
    return problems;
  }

  factory AnimatorGraph.fromJson(Map<String, dynamic> json) => AnimatorGraph(
    parameters: [
      for (final p in (json['parameters'] as List?) ?? const [])
        if (p is Map) AnimatorParameter.fromJson(p.cast<String, dynamic>()),
    ],
    states: [
      for (final s in (json['states'] as List?) ?? const [])
        if (s is Map) AnimatorState.fromJson(s.cast<String, dynamic>()),
    ],
    transitions: [
      for (final t in (json['transitions'] as List?) ?? const [])
        if (t is Map) AnimatorTransition.fromJson(t.cast<String, dynamic>()),
    ],
    entry: json['entry'] as String? ?? '',
    atlasPath: json['atlas'] as String? ?? '',
  );

  factory AnimatorGraph.parse(String source) =>
      AnimatorGraph.fromJson(jsonDecode(source) as Map<String, dynamic>);

  Map<String, dynamic> toJson() => {
    'version': formatVersion,
    if (atlasPath.isNotEmpty) 'atlas': atlasPath,
    'entry': entry,
    'parameters': [for (final p in parameters) p.toJson()],
    'states': [for (final s in states) s.toJson()],
    'transitions': [for (final t in transitions) t.toJson()],
  };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  AnimatorGraph copyWith({
    List<AnimatorParameter>? parameters,
    List<AnimatorState>? states,
    List<AnimatorTransition>? transitions,
    String? entry,
    String? atlasPath,
  }) => AnimatorGraph(
    parameters: parameters ?? this.parameters,
    states: states ?? this.states,
    transitions: transitions ?? this.transitions,
    entry: entry ?? this.entry,
    atlasPath: atlasPath ?? this.atlasPath,
  );
}

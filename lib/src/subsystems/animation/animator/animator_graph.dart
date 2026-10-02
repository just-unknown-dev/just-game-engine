/// The animation state machine's data: what an `.animator.json` holds.
///
/// A graph is states (each playing one clip), transitions between them that
/// fire when their conditions hold, and the parameters those conditions
/// read. It knows nothing of entities; [AnimatorSystem] runs it.
library;

import 'dart:convert';

import '../../../foundation/unsupported_format_version.dart';

/// What kind of value a parameter holds.
enum AnimatorParameterType {
  /// A number, compared as a double.
  float,

  /// A whole number; a fractional default is truncated.
  int,

  /// True or false, staying as it was set.
  bool,

  /// A bool that a transition using it switches back off: "jumped", "hit".
  trigger,
}

/// A named value transitions are conditioned on.
class AnimatorParameter {
  /// A parameter called [name] — a float unless [type] says otherwise —
  /// starting at [defaultValue] (zero / false when null), and left to the
  /// game unless [binding] names a source.
  const AnimatorParameter({
    required this.name,
    this.type = AnimatorParameterType.float,
    this.defaultValue,
    this.binding,
  });

  /// What conditions and game code call it. The first parameter of a name
  /// is the one a graph uses.
  final String name;

  /// What kind of value it holds, which decides how a condition on it
  /// compares.
  final AnimatorParameterType type;

  /// A `num` or `bool` matching [type]; null is zero / false.
  final Object? defaultValue;

  /// The id of an [AnimatorBindings] source that writes this parameter every
  /// frame — `speedX`, `grounded` — so no game code has to. Null leaves it
  /// to the game.
  final String? binding;

  /// The value a fresh animator starts this parameter at. A default of the
  /// wrong kind — `true` on a number, say — is read as [asNumber] and
  /// [asBool] read it.
  Object get initialValue => switch (type) {
    AnimatorParameterType.float => asNumber(defaultValue),
    AnimatorParameterType.int => asNumber(defaultValue).toInt(),
    AnimatorParameterType.bool => asBool(defaultValue),
    AnimatorParameterType.trigger => defaultValue == true,
  };

  /// [value] as a number, whatever it holds: a number as itself, a bool as
  /// 1 or 0, anything else as 0. A parameter bound to a source of the other
  /// kind — a float bound to `grounded` — reads this way rather than
  /// failing.
  static double asNumber(Object? value) => switch (value) {
    num() => value.toDouble(),
    true => 1.0,
    _ => 0.0,
  };

  /// [value] as a bool, whatever it holds: true, or a number other than 0.
  static bool asBool(Object? value) =>
      value == true || (value is num && value != 0);

  /// Reads [toJson]'s shape. A missing `name` is empty, a missing or
  /// unknown `type` is [AnimatorParameterType.float], and a blank
  /// `binding` is none.
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

  /// This parameter as a JSON map: `name` and `type` (the value's name),
  /// with `default` and `binding` only when set.
  Map<String, dynamic> toJson() => {
    'name': name,
    'type': type.name,
    if (defaultValue != null) 'default': defaultValue,
    if (binding != null) 'binding': binding,
  };

  /// A copy with the given fields replaced. A null argument keeps the old
  /// value, so [clearDefaultValue] is how the default is taken away (back
  /// to zero / false) and [clearBinding] how the binding is.
  AnimatorParameter copyWith({
    String? name,
    AnimatorParameterType? type,
    Object? defaultValue,
    bool clearDefaultValue = false,
    String? binding,
    bool clearBinding = false,
  }) => AnimatorParameter(
    name: name ?? this.name,
    type: type ?? this.type,
    defaultValue: clearDefaultValue ? null : defaultValue ?? this.defaultValue,
    binding: clearBinding ? null : binding ?? this.binding,
  );
}

/// How a condition compares its parameter with its value.
enum AnimatorOp {
  /// The parameter is above the value.
  greater('>'),

  /// The parameter is at or above the value.
  greaterOrEqual('>='),

  /// The parameter is below the value.
  less('<'),

  /// The parameter is at or below the value.
  lessOrEqual('<='),

  /// The parameter equals the value — exactly, for a float. A bool
  /// parameter tests this for every op but [notEquals].
  equals('=='),

  /// The parameter differs from the value.
  notEquals('!=');

  const AnimatorOp(this.symbol);

  /// The op as written, `>` to `!=`: what a condition's `op` key holds.
  final String symbol;

  /// The op [raw] names, by [symbol] (`>=`) or by name (`greaterOrEqual`);
  /// [equals] for anything else, null included.
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
  /// A test of [parameter] by [op] against [value]; `== true` by default,
  /// which is what a bool or a trigger wants.
  const AnimatorCondition({
    required this.parameter,
    this.op = AnimatorOp.equals,
    this.value = true,
  });

  /// The name of the parameter tested. A condition on a parameter the
  /// graph lacks never holds.
  final String parameter;

  /// How the parameter is compared with [value]: as doubles for a number
  /// parameter (a bool reading as 1 or 0), as truth for a bool one.
  /// Ignored for a trigger.
  final AnimatorOp op;

  /// A `num` or a `bool`.
  final Object value;

  /// Whether this holds for [current], the parameter's value now.
  bool holds(Object? current, AnimatorParameterType type) {
    if (type == AnimatorParameterType.trigger) return current == true;
    if (type == AnimatorParameterType.bool) {
      final wanted = AnimatorParameter.asBool(value);
      final now = AnimatorParameter.asBool(current);
      return op == AnimatorOp.notEquals ? now != wanted : now == wanted;
    }
    // A number parameter may hold a bool — bound to a bool source — and a
    // condition's value may be one: both read as 1 or 0, never a failure.
    final a = AnimatorParameter.asNumber(current);
    final b = AnimatorParameter.asNumber(value);
    return switch (op) {
      AnimatorOp.greater => a > b,
      AnimatorOp.greaterOrEqual => a >= b,
      AnimatorOp.less => a < b,
      AnimatorOp.lessOrEqual => a <= b,
      AnimatorOp.equals => a == b,
      AnimatorOp.notEquals => a != b,
    };
  }

  /// Reads [toJson]'s shape. A missing `param` is empty, an unknown `op` is
  /// [AnimatorOp.equals] and a missing `value` is true.
  factory AnimatorCondition.fromJson(Map<String, dynamic> json) =>
      AnimatorCondition(
        parameter: json['param'] as String? ?? '',
        op: AnimatorOp.parse(json['op']),
        value: json['value'] as Object? ?? true,
      );

  /// This condition as a JSON map: `param`, `op` (its symbol) and `value`.
  Map<String, dynamic> toJson() => {
    'param': parameter,
    'op': op.symbol,
    'value': value,
  };
}

/// A state: one clip, playing.
class AnimatorState {
  /// A state called [name] playing the clip of the same name at normal
  /// speed, looping as the clip does, with no timeline, drawn at the
  /// editor's origin.
  const AnimatorState({
    required this.name,
    this.clip = '',
    this.speed = 1.0,
    this.loop,
    this.timeline = '',
    this.x = 0,
    this.y = 0,
  });

  /// What transitions and the graph's entry call it. Names should be
  /// unique: the first state of a name is the one a graph uses.
  final String name;

  /// The clip to play; empty plays the clip named like the state.
  final String clip;

  /// How fast the clip plays, given to the sprite animation on entry; 1
  /// is as authored.
  final double speed;

  /// Overrides whether the clip loops; null takes the clip's own.
  final bool? loop;

  /// A `.timeline.json` the entity's Timeline Player plays from its start
  /// on entering this state; a transition's exit time then reads the
  /// timeline's progress, not the clip's. Empty for none.
  final String timeline;

  /// Where the node sits in a graph editor. Means nothing at runtime.
  final double x;

  /// The other half of [x]: where the node sits in a graph editor. Means
  /// nothing at runtime.
  final double y;

  /// The clip this state plays.
  String get clipName => clip.isEmpty ? name : clip;

  /// Reads [toJson]'s shape; a missing key takes the constructor's
  /// default.
  factory AnimatorState.fromJson(Map<String, dynamic> json) => AnimatorState(
    name: json['name'] as String? ?? '',
    clip: json['clip'] as String? ?? '',
    speed: (json['speed'] as num?)?.toDouble() ?? 1.0,
    loop: json['loop'] as bool?,
    timeline: json['timeline'] as String? ?? '',
    x: (json['x'] as num?)?.toDouble() ?? 0,
    y: (json['y'] as num?)?.toDouble() ?? 0,
  );

  /// This state as a JSON map: `name`, `x` and `y` always; `clip`,
  /// `speed`, `loop` and `timeline` only when not the default.
  Map<String, dynamic> toJson() => {
    'name': name,
    if (clip.isNotEmpty) 'clip': clip,
    if (speed != 1.0) 'speed': speed,
    if (loop != null) 'loop': loop,
    if (timeline.isNotEmpty) 'timeline': timeline,
    'x': x,
    'y': y,
  };

  /// A copy with the given fields replaced. A null argument keeps the old
  /// value, so [clearLoop] is how [loop] goes back to the clip's own.
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
  /// A transition from [from] — [anyState] for any — to [to], taken when
  /// every one of [conditions] holds; no exit time and priority 0 unless
  /// given.
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

  /// The state it leaves, or [anyState].
  final String from;

  /// The state it enters. A transition into a state the graph lacks is
  /// never taken.
  final String to;

  /// The tests that must all hold. With none it fires on its exit time —
  /// or, without one, at once.
  final List<AnimatorCondition> conditions;

  /// Wait until the playing clip has reached [exitTime] before leaving. A
  /// transition with no conditions and an exit time is "when it finishes".
  final bool hasExitTime;

  /// How far through the clip, 0–1. One pass for a looping clip.
  final double exitTime;

  /// Among transitions that could fire, the highest goes; ties go to the
  /// one listed first.
  final int priority;

  /// Whether it can leave any state ([from] is [anyState]). It is never
  /// taken into the state the animator is already in.
  bool get isFromAny => from == anyState;

  /// Reads [toJson]'s shape. A missing `from` is [anyState], a missing
  /// `to` is empty, and entries of `conditions` that are not maps are
  /// skipped.
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

  /// This transition as a JSON map: `from`, `to` and `conditions`;
  /// `hasExitTime` and `exitTime` only with an exit time, `priority` only
  /// when not 0.
  Map<String, dynamic> toJson() => {
    'from': from,
    'to': to,
    'conditions': [for (final c in conditions) c.toJson()],
    if (hasExitTime) 'hasExitTime': true,
    if (hasExitTime) 'exitTime': exitTime,
    if (priority != 0) 'priority': priority,
  };

  /// A copy with the given fields replaced; the [conditions] list is
  /// shared, not copied.
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
  /// A graph of [states] joined by [transitions] that read [parameters],
  /// starting in [entry]. Empty by default.
  const AnimatorGraph({
    this.parameters = const [],
    this.states = const [],
    this.transitions = const [],
    this.entry = '',
    this.atlasPath = '',
  });

  /// The file format's version, written as `version`.
  static const int formatVersion = 1;

  /// The values its transitions' conditions read.
  final List<AnimatorParameter> parameters;

  /// Its states. The first is where an animator starts when [entry] is
  /// empty.
  final List<AnimatorState> states;

  /// Its transitions. Their order breaks ties of priority.
  final List<AnimatorTransition> transitions;

  /// The state an animator starts in; empty starts in the first.
  final String entry;

  /// The atlas the clips were picked from. A hint for tools — the entity's
  /// own sprite animation says what actually plays.
  final String atlasPath;

  // What a running animator looks up every frame, worked out once per
  // graph. A graph is not changed once made — an editor makes a new one —
  // but a list changed in place under it is noticed by its length.
  static final Expando<_GraphIndex> _indexes = Expando('AnimatorGraph index');

  _GraphIndex get _index {
    final known = _indexes[this];
    if (known != null && known.fits(this)) return known;
    return _indexes[this] = _GraphIndex(this);
  }

  /// The first state called [name], or null.
  AnimatorState? stateNamed(String name) => _index.states[name];

  /// The first parameter called [name], or null.
  AnimatorParameter? parameterNamed(String name) => _index.parameters[name];

  /// The transitions an animator in [state] may take, in the order they are
  /// tried: those from Any State (except into [state] itself), then
  /// [state]'s own; within each, the highest priority first and, among
  /// equals, the one listed first. Only transitions into a state that
  /// exists. Worked out once per state.
  List<AnimatorTransition> transitionsFrom(String state) =>
      _index.from.putIfAbsent(state, () => _order(state));

  List<AnimatorTransition> _order(String state) {
    final all = transitions;
    int rank(int i) => all[i].isFromAny ? 0 : 1;
    final order =
        [
          for (var i = 0; i < all.length; i++)
            if (stateNamed(all[i].to) != null &&
                (all[i].isFromAny ? all[i].to != state : all[i].from == state))
              i,
        ]..sort((a, b) {
          if (rank(a) != rank(b)) return rank(a) - rank(b);
          final byPriority = all[b].priority.compareTo(all[a].priority);
          return byPriority != 0 ? byPriority : a - b;
        });
    return List.unmodifiable([for (final i in order) all[i]]);
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

  /// Reads the `.animator.json` form ([toJson]'s shape). Missing lists are
  /// empty and entries that are not maps are skipped. A file with no
  /// `version` is read as [formatVersion]; one declaring a newer version
  /// throws an [UnsupportedFormatVersionException] rather than be misread.
  factory AnimatorGraph.fromJson(Map<String, dynamic> json) {
    final version = json['version'];
    if (version is num && version > formatVersion) {
      throw UnsupportedFormatVersionException(
        'animator graph',
        version.toInt(),
        formatVersion,
      );
    }
    return AnimatorGraph._fromJson(json);
  }

  factory AnimatorGraph._fromJson(Map<String, dynamic> json) => AnimatorGraph(
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

  /// Reads [source], the text of an `.animator.json`. Throws a
  /// [FormatException] when it is not JSON (an
  /// [UnsupportedFormatVersionException] when it is from a newer engine),
  /// and a [TypeError] when it is not a JSON object.
  factory AnimatorGraph.parse(String source) =>
      AnimatorGraph.fromJson(jsonDecode(source) as Map<String, dynamic>);

  /// The `.animator.json` form: `version` ([formatVersion]), `atlas` when
  /// set, `entry`, `parameters`, `states` and `transitions`.
  Map<String, dynamic> toJson() => {
    'version': formatVersion,
    if (atlasPath.isNotEmpty) 'atlas': atlasPath,
    'entry': entry,
    'parameters': [for (final p in parameters) p.toJson()],
    'states': [for (final s in states) s.toJson()],
    'transitions': [for (final t in transitions) t.toJson()],
  };

  /// [toJson] as text indented by two spaces: what an `.animator.json`
  /// file holds.
  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// A copy with the given fields replaced; the lists are shared, not
  /// copied.
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

/// A graph's lookups by name, and the order its transitions are tried in.
class _GraphIndex {
  _GraphIndex(AnimatorGraph graph)
    : _states = graph.states.length,
      _parameters = graph.parameters.length,
      _transitions = graph.transitions.length {
    for (final state in graph.states) {
      states.putIfAbsent(state.name, () => state);
    }
    for (final parameter in graph.parameters) {
      parameters.putIfAbsent(parameter.name, () => parameter);
    }
  }

  final int _states;
  final int _parameters;
  final int _transitions;
  final Map<String, AnimatorState> states = {};
  final Map<String, AnimatorParameter> parameters = {};
  final Map<String, List<AnimatorTransition>> from = {};

  bool fits(AnimatorGraph graph) =>
      graph.states.length == _states &&
      graph.parameters.length == _parameters &&
      graph.transitions.length == _transitions;
}

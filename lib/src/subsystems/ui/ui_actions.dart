/// What a button does when it is pressed.
///
/// A scene cannot save a Dart closure, so it saves what to do by name — a
/// built-in like "play this timeline", or a name the game has registered:
///
/// ```dart
/// UiActions.register('start_game', (context) => game.start());
/// ```
library;

import '../../ecs/ecs.dart';
import '../../ecs/components/animation/timeline_player_component.dart';
import '../timeline/timeline_signals.dart';

/// What an action is told when it runs.
class UiActionContext {
  const UiActionContext({
    required this.world,
    this.entity,
    this.argument = '',
    this.value,
  });

  final World world;

  /// The entity whose UI ran this — a button, a slider.
  final Entity? entity;

  /// What the action was given in the scene: a scene name, a timeline path,
  /// the name of another UI entity.
  final String argument;

  /// What changed, for the events that carry something: a slider's number,
  /// a toggle's flag, a field's text.
  final Object? value;

  /// [value] as a number, when it is one.
  double? get number => value is num ? (value! as num).toDouble() : null;
}

/// Runs an action.
typedef UiActionHandler = void Function(UiActionContext context);

/// One thing to do, as it is saved: a kind, and what it acts on.
///
/// `UiAction('timeline.play', 'assets/timelines/open.timeline.json')`
class UiAction {
  const UiAction(this.kind, [this.argument = '']);

  /// A built-in's name, or `custom:<name>` for one the game registered.
  final String kind;
  final String argument;

  /// The name a game registered, for a `custom:` action.
  String? get customName =>
      kind.startsWith('custom:') ? kind.substring(7) : null;

  UiAction copyWith({String? kind, String? argument}) =>
      UiAction(kind ?? this.kind, argument ?? this.argument);

  Map<String, dynamic> toJson() => {
    'kind': kind,
    if (argument.isNotEmpty) 'arg': argument,
  };

  factory UiAction.fromJson(Map<String, dynamic> json) =>
      UiAction(json['kind'] as String? ?? '', json['arg'] as String? ?? '');

  @override
  bool operator ==(Object other) =>
      other is UiAction && other.kind == kind && other.argument == argument;

  @override
  int get hashCode => Object.hash(kind, argument);

  @override
  String toString() =>
      'UiAction($kind${argument.isEmpty ? '' : ': $argument'})';
}

/// A list of actions, as a field holds it — what one event sets off.
class UiActionList {
  const UiActionList(this.actions);

  static const UiActionList empty = UiActionList([]);

  final List<UiAction> actions;

  bool get isEmpty => actions.isEmpty;
  bool get isNotEmpty => actions.isNotEmpty;

  /// Runs them in order.
  void run(UiActionContext context) {
    for (final action in actions) {
      UiActions.run(action, context);
    }
  }

  UiActionList copyWith({List<UiAction>? actions}) =>
      UiActionList(actions ?? this.actions);

  List<Map<String, dynamic>> toJson() => [for (final a in actions) a.toJson()];

  factory UiActionList.fromJson(Object? json) => UiActionList([
    if (json is List)
      for (final a in json)
        if (a is Map) UiAction.fromJson(a.cast<String, dynamic>()),
  ]);

  @override
  bool operator ==(Object other) =>
      other is UiActionList &&
      other.actions.length == actions.length &&
      _same(other.actions, actions);

  static bool _same(List<UiAction> a, List<UiAction> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(actions);

  @override
  String toString() => 'UiActionList($actions)';
}

/// What a built-in action needs from whoever is hosting the game: loading a
/// scene, pausing, quitting. The engine cannot do these by itself, so a
/// host offers what it can and the rest do nothing.
class UiActionHost {
  const UiActionHost({
    this.loadScene,
    this.pause,
    this.resume,
    this.quit,
    this.playSound,
    this.showUi,
    this.pushScreen,
    this.back,
  });

  final void Function(String scene)? loadScene;
  final void Function()? pause;
  final void Function()? resume;
  final void Function()? quit;
  final void Function(String path)? playSound;

  /// Shows, hides or flips a UI entity by name; null shows, false hides.
  final void Function(String entityName, bool? visible)? showUi;

  final void Function(String entityName)? pushScreen;
  final void Function()? back;
}

abstract final class UiActions {
  static final Map<String, UiActionHandler> _handlers = {};

  /// What a built-in reaches the game through. A host sets this once.
  static UiActionHost host = const UiActionHost();

  /// Makes [name] usable as `custom:name`.
  static void register(String name, UiActionHandler handler) =>
      _handlers[name] = handler;

  static void unregister(String name) => _handlers.remove(name);

  static bool has(String name) => _handlers.containsKey(name);

  /// The names a game has registered, for an editor to offer.
  static List<String> get customNames => _handlers.keys.toList()..sort();

  static void clear() {
    _handlers.clear();
    host = const UiActionHost();
  }

  /// Every built-in, and what its argument means — an editor reads this to
  /// offer the right picker.
  static const Map<String, String> builtIns = {
    'none': '',
    'signal': 'A timeline signal to emit',
    'timeline.play': 'An entity whose timeline plays',
    'timeline.stop': 'An entity whose timeline stops',
    'scene.load': 'A scene to open',
    'ui.show': 'A UI entity to show',
    'ui.hide': 'A UI entity to hide',
    'ui.toggle': 'A UI entity to show or hide',
    'ui.push': 'A screen to open over this one',
    'ui.back': '',
    'game.pause': '',
    'game.resume': '',
    'game.quit': '',
    'audio.play': 'A sound to play',
  };

  /// Does [action]. An action nobody can carry out is quietly nothing —
  /// a button with a missing handler must not take the game down. The
  /// editor's Problems dock is where that is reported instead.
  static void run(UiAction action, UiActionContext context) {
    final argument = action.argument.isEmpty
        ? context.argument
        : action.argument;
    final scoped = UiActionContext(
      world: context.world,
      entity: context.entity,
      argument: argument,
      value: context.value,
    );
    final custom = action.customName;
    if (custom != null) {
      _handlers[custom]?.call(scoped);
      return;
    }
    switch (action.kind) {
      case 'none' || '':
        break;
      case 'signal':
        TimelineSignals.emit(argument);
      case 'timeline.play':
        _timelineOf(scoped)?.restart();
      case 'timeline.stop':
        _timelineOf(scoped)?.stop();
      case 'scene.load':
        host.loadScene?.call(argument);
      case 'ui.show':
        host.showUi?.call(argument, true);
      case 'ui.hide':
        host.showUi?.call(argument, false);
      case 'ui.toggle':
        host.showUi?.call(argument, null);
      case 'ui.push':
        host.pushScreen?.call(argument);
      case 'ui.back':
        host.back?.call();
      case 'game.pause':
        host.pause?.call();
      case 'game.resume':
        host.resume?.call();
      case 'game.quit':
        host.quit?.call();
      case 'audio.play':
        host.playSound?.call(argument);
      default:
        // An unknown kind: a scene from a newer engine, or a typo.
        break;
    }
  }

  /// The timeline player an action names, or the acting entity's own.
  static TimelinePlayerComponent? _timelineOf(UiActionContext context) {
    if (context.argument.isEmpty) {
      return context.entity?.getComponent<TimelinePlayerComponent>();
    }
    final named = context.world.findEntityByName(context.argument);
    return named?.getComponent<TimelinePlayerComponent>();
  }
}

/// Main facade for the Narrative/Dialogue System.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:just_signals/just_signals.dart';

import 'core/dialogue_graph.dart';
import 'core/dialogue_variable_store.dart';
import 'localization/dialogue_localizer.dart';
import 'parser/yarn_parser.dart';
import 'runtime/dialogue_command_registry.dart';
import 'runtime/dialogue_condition_registry.dart';
import 'runtime/dialogue_runner.dart';
import 'signals/narrative_signals.dart';

/// Central service for the Narrative/Dialogue System.
///
/// Manages [DialogueGraph] registration, [DialogueRunner] lifecycle, global
/// variables, localization, conditions, and commands.
///
/// **Typical setup**
/// ```dart
/// final narrative = DialogueManager();
///
/// // Load localized strings
/// await narrative.localizer.loadLocale(const Locale('en'));
///
/// // Load dialogue assets
/// await narrative.loadGraph('assets/dialogue/innkeeper.yarn');
///
/// // Register custom conditions
/// narrative.conditions.register('playerHasKey', (vars) => player.hasKey);
///
/// // Register custom commands
/// narrative.commands.register('fade_out', (ctx) async => camera.fadeOut());
///
/// // Create a runner and start dialogue
/// final runner = narrative.createRunner('innkeeper');
/// runner.signals.currentLine.addListener(() { ... });
/// await runner.start('Start');
/// ```
class DialogueManager {
  /// A manager with no graphs and empty condition and command registries.
  /// [localizer] defaults to a [DialogueLocalizer] with a manager of its own
  /// (not the engine's), [globalVariables] to an empty store.
  DialogueManager({
    DialogueLocalizer? localizer,
    DialogueVariableStore? globalVariables,
  }) : localizer = localizer ?? DialogueLocalizer(),
       globalVariables = globalVariables ?? DialogueVariableStore() {
    conditions = DialogueConditionRegistry();
    commands = DialogueCommandRegistry();
  }

  // ---- Shared services -----------------------------------------------------

  /// Global variable store shared across **all** runners created by this
  /// manager.  Persists between individual dialogue sessions.
  final DialogueVariableStore globalVariables;

  /// Localizer used by all runners.  Load locales early in your boot sequence.
  final DialogueLocalizer localizer;

  /// Registry for named Dart condition predicates (`[conditionName]` in Yarn).
  late final DialogueConditionRegistry conditions;

  /// Registry for custom `<<commandName args>>` handlers.
  late final DialogueCommandRegistry commands;

  // ---- Reactive state ------------------------------------------------------

  /// Emits the [DialogueGraph.id] of the currently active graph, or `null`.
  final activeGraphId = Signal<String?>(null);

  /// `true` when at least one runner created by this manager is active.
  final isAnyDialogueActive = Signal<bool>(false);

  // ---- Internal state ------------------------------------------------------

  final Map<String, DialogueGraph> _graphs = {};
  final Map<int, DialogueRunner> _entityRunners = {};
  final Set<DialogueRunner> _runners = {};

  /// Runners nobody else holds on to — started by [startDialogue], or
  /// replaced or released for their entity — which are let go as soon as
  /// their dialogue ends. Kept, they piled up for the whole session.
  final Set<DialogueRunner> _transient = {};

  // ---------------------------------------------------------------------------
  // Graph management
  // ---------------------------------------------------------------------------

  /// Parses a Yarn Spinner source string and registers the resulting graph.
  ///
  /// [id] is used to look up the graph later.
  DialogueGraph parseAndRegister(String yarnSource, {required String id}) {
    final graph = YarnParser.parse(yarnSource, id: id);
    _graphs[id] = graph;
    return graph;
  }

  /// Loads a `.yarn` asset from [assetPath] and registers it.
  ///
  /// [id] defaults to the asset file name without its extension.
  Future<DialogueGraph> loadGraph(
    String assetPath, {
    String? id,
    AssetBundle? bundle,
  }) async {
    final graphId = id ?? _extractId(assetPath);
    final source = await (bundle ?? rootBundle).loadString(assetPath);
    return parseAndRegister(source, id: graphId);
  }

  /// Manually registers a [graph] (e.g. built programmatically or from tests).
  void registerGraph(DialogueGraph graph) => _graphs[graph.id] = graph;

  /// Returns the registered graph for [id], or `null` if not found.
  DialogueGraph? getGraph(String id) => _graphs[id];

  /// `true` if a graph with [id] has been registered.
  bool hasGraph(String id) => _graphs.containsKey(id);

  /// Merges [graph] into an existing graph by the same id, or registers it.
  void mergeGraph(DialogueGraph graph) {
    final existing = _graphs[graph.id];
    _graphs[graph.id] = existing != null ? existing.merge(graph) : graph;
  }

  // ---------------------------------------------------------------------------
  // Runner management
  // ---------------------------------------------------------------------------

  /// Creates a new [DialogueRunner] for the graph registered under [graphId].
  ///
  /// The runner uses the manager's shared [globalVariables], [conditions],
  /// [commands], and [localizer].
  ///
  /// Dispose the runner (via [disposeRunner]) when the dialogue scene ends.
  DialogueRunner createRunner(String graphId, {NarrativeSignals? signals}) {
    final graph = _graphs[graphId];
    if (graph == null) {
      throw ArgumentError(
        'No graph registered with id "$graphId". '
        'Did you forget to call loadGraph / parseAndRegister?',
      );
    }

    final runner = DialogueRunner(
      graph: graph,
      variables: globalVariables,
      conditions: conditions,
      commands: commands,
      localizer: localizer,
      signals: signals,
    );

    _runners.add(runner);

    // Keep aggregate active-state signal in sync
    runner.signals.isDialogueActive.addListener(() {
      final active = runner.signals.isDialogueActive.value;
      if (active) {
        // Tracked again if it was let go and has now been restarted.
        _runners.add(runner);
      } else {
        _releaseIfFinished(runner);
      }
      _syncGlobalState(active: active, graphId: graphId);
    });

    return runner;
  }

  /// Creates a runner **bound to an ECS entity** (keyed by [entityId]).
  ///
  /// The [DialogueSystem] uses this to retrieve runners by entity ID.
  ///
  /// A runner already bound to [entityId] is replaced. It is not stopped: it
  /// is let go once its dialogue ends, or at once if it is not running.
  DialogueRunner createRunnerForEntity(
    int entityId,
    String graphId, {
    NarrativeSignals? signals,
  }) {
    final runner = createRunner(graphId, signals: signals);
    final previous = _entityRunners[entityId];
    _entityRunners[entityId] = runner;
    if (previous != null) _letGo(previous);
    return runner;
  }

  /// The entity ids with a runner bound by [createRunnerForEntity].
  Iterable<int> get boundEntityIds => _entityRunners.keys;

  /// Unbinds the runner for [entityId] — say, when the entity is destroyed —
  /// without cutting its dialogue short: it is let go once the dialogue
  /// ends, or at once if it is not running. [DialogueSystem] calls this for
  /// entities that no longer exist.
  void releaseRunnerForEntity(int entityId) {
    final runner = _entityRunners.remove(entityId);
    if (runner != null) _letGo(runner);
  }

  /// Returns the runner bound to [entityId], or `null`.
  DialogueRunner? getRunnerForEntity(int entityId) => _entityRunners[entityId];

  /// Removes and disposes the runner for [entityId].
  Future<void> disposeRunnerForEntity(int entityId) async {
    final runner = _entityRunners.remove(entityId);
    if (runner != null) await _disposeRunner(runner);
  }

  /// Stops and removes [runner] from internal tracking.
  Future<void> disposeRunner(DialogueRunner runner) async {
    _entityRunners.removeWhere((_, v) => v == runner);
    await _disposeRunner(runner);
  }

  /// The runners this manager is tracking: every runner it created that has
  /// not been disposed, except those started by [startDialogue] (or replaced
  /// for their entity) whose dialogue has ended.
  Iterable<DialogueRunner> get runners => _runners;

  // ---------------------------------------------------------------------------
  // Convenience
  // ---------------------------------------------------------------------------

  /// Convenience: creates a runner, starts dialogue from [startNode], and
  /// returns the runner.
  ///
  /// The returned [Future] resolves immediately — the dialogue runs
  /// asynchronously.  Await `runner.signals.isDialogueActive` to know when it
  /// ends.
  ///
  /// The manager stops tracking the runner once its dialogue ends; the
  /// runner itself stays usable for whoever holds it.
  Future<DialogueRunner> startDialogue({
    required String graphId,
    String startNode = 'Start',
  }) async {
    final runner = createRunner(graphId);
    _transient.add(runner);
    // Fire-and-forget the long-running session; caller gets runner for
    // control. Let go when it ends — also when it fails to start at all.
    unawaited(
      runner.start(startNode).whenComplete(() => _releaseIfFinished(runner)),
    );
    return runner;
  }

  // ---------------------------------------------------------------------------
  // Dispose
  // ---------------------------------------------------------------------------

  /// Stops all active runners and clears all state.
  Future<void> dispose() async {
    for (final runner in List.of(_runners)) {
      await _disposeRunner(runner);
    }
    _runners.clear();
    _transient.clear();
    _entityRunners.clear();
    _graphs.clear();
    activeGraphId.dispose();
    isAnyDialogueActive.dispose();
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  Future<void> _disposeRunner(DialogueRunner runner) async {
    await runner.stop();
    _runners.remove(runner);
    _transient.remove(runner);
    runner.signals.dispose();
  }

  /// Marks [runner] as held by nobody: let go now if it is not running, or
  /// as soon as its dialogue ends.
  void _letGo(DialogueRunner runner) {
    _transient.add(runner);
    _releaseIfFinished(runner);
  }

  void _releaseIfFinished(DialogueRunner runner) {
    if (runner.isRunning || !_transient.contains(runner)) return;
    _runners.remove(runner);
    _transient.remove(runner);
  }

  void _syncGlobalState({required bool active, required String graphId}) {
    isAnyDialogueActive.value = _runners.any(
      (r) => r.signals.isDialogueActive.value,
    );
    if (active) {
      activeGraphId.value = graphId;
    } else if (!isAnyDialogueActive.value) {
      activeGraphId.value = null;
    }
  }

  static String _extractId(String assetPath) {
    final filename = assetPath.split('/').last;
    final dot = filename.lastIndexOf('.');
    return dot > 0 ? filename.substring(0, dot) : filename;
  }
}

/// Main facade for the Narrative/Dialogue System.
library;

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
  final List<DialogueRunner> _runners = [];

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
      _syncGlobalState(
        active: runner.signals.isDialogueActive.value,
        graphId: graphId,
      );
    });

    return runner;
  }

  /// Creates a runner **bound to an ECS entity** (keyed by [entityId]).
  ///
  /// The [DialogueSystem] uses this to retrieve runners by entity ID.
  DialogueRunner createRunnerForEntity(
    int entityId,
    String graphId, {
    NarrativeSignals? signals,
  }) {
    final runner = createRunner(graphId, signals: signals);
    _entityRunners[entityId] = runner;
    return runner;
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

  // ---------------------------------------------------------------------------
  // Convenience
  // ---------------------------------------------------------------------------

  /// Convenience: creates a runner, starts dialogue from [startNode], and
  /// returns the runner.
  ///
  /// The returned [Future] resolves immediately — the dialogue runs
  /// asynchronously.  Await [runner.signals.isDialogueActive] to know when it
  /// ends.
  Future<DialogueRunner> startDialogue({
    required String graphId,
    String startNode = 'Start',
  }) async {
    final runner = createRunner(graphId);
    // Fire-and-forget the long-running session; caller gets runner for control
    runner.start(startNode);
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
    runner.signals.dispose();
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

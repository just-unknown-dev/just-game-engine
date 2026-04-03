/// Narrative / Dialogue System — public barrel.
///
/// Exports the full Narrative API:
/// - [DialogueManager] — top-level facade
/// - [DialogueGraph], [DialogueNode] — data model
/// - [DialogueLine], [DialogueChoice] — resolved display types
/// - [DialogueVariableStore] — Yarn variable storage
/// - [YarnParser] — `.yarn` source parser
/// - [YarnTokenizer], [YarnToken], [TokenType] — tokenizer primitives
/// - [YarnParseException] — parse errors
/// - [DialogueRunner] — execution engine
/// - [ExpressionEvaluator] — condition/expression evaluation
/// - [DialogueConditionRegistry], [DialoguePredicate] — Dart predicates
/// - [DialogueCommandRegistry], [DialogueCommandContext],
///   [DialogueCommandHandler] — custom commands
/// - [DialogueLocalizer] — i18n / string table
/// - [NarrativeSignals], [DialogueEvent], [DialogueEventType] — reactive state
/// - [DialogueComponent], [DialogueTriggerComponent] — ECS components
/// - [DialogueSystem] — ECS system
/// - [DialogueBoxWidget] — default dialogue UI widget
/// - [DialogueChoicesWidget] — default choice-list UI widget
library;

// Core data model
export 'core/dialogue_graph.dart';
export 'core/dialogue_statement.dart';
export 'core/dialogue_line.dart';
export 'core/dialogue_choice.dart';
export 'core/dialogue_variable_store.dart';

// Parser
export 'parser/yarn_tokenizer.dart';
export 'parser/yarn_parser.dart';

// Runtime
export 'runtime/expression_evaluator.dart';
export 'runtime/dialogue_condition_registry.dart';
export 'runtime/dialogue_command_registry.dart';
export 'runtime/dialogue_runner.dart';

// Localization
export 'localization/dialogue_localizer.dart';

// Reactive signals
export 'signals/narrative_signals.dart';

// Manager (facade)
export 'dialogue_manager.dart';

// ECS integration
export 'ecs/dialogue_component.dart';
export 'ecs/dialogue_system.dart';

// UI widgets
export 'ui/dialogue_box_widget.dart';
export 'ui/dialogue_choices_widget.dart';

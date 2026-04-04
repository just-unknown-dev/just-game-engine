/// Dialogue graph data model — nodes (knots) and graph containers.
library;

import 'dialogue_statement.dart';

// ---------------------------------------------------------------------------
// DialogueNode  (a "knot" in Yarn Spinner terminology)
// ---------------------------------------------------------------------------

/// An individual narrative unit inside a [DialogueGraph].
///
/// Each node has a unique [title], optional [tags] and header [metadata], and
/// a list of [statements] that are executed in order.
///
/// In Yarn Spinner a node looks like:
/// ```yarn
/// title: Innkeeper_Hub
/// tags: hub npc
/// ---
/// Innkeeper: Good day, traveler.
/// -> Ask about quest.
///     <<jump Innkeeper_Quest>>
/// -> Farewell.
/// ===
/// ```
class DialogueNode {
  const DialogueNode({
    required this.title,
    this.tags = const [],
    this.metadata = const {},
    required this.statements,
  });

  /// Unique identifier used by `<<jump>>` and [DialogueGraph.getNode].
  final String title;

  /// Space-separated tags declared in the `tags:` header line.
  final List<String> tags;

  /// All other header key/value pairs beyond `title` and `tags`.
  final Map<String, String> metadata;

  /// Ordered list of parsed statements in this node's content block.
  final List<DialogueStatement> statements;

  @override
  String toString() => 'DialogueNode($title, ${statements.length} stmts)';
}

// ---------------------------------------------------------------------------
// DialogueGraph
// ---------------------------------------------------------------------------

/// A collection of [DialogueNode]s that together form a complete dialogue.
///
/// Typically parsed from one `.yarn` file, though multiple files can be
/// [merged][DialogueGraph.merge] into a single graph.
///
/// ```dart
/// final graph = YarnParser.parse(yarnSource, id: 'innkeeper');
/// final runner = DialogueRunner(graph: graph, ...);
/// await runner.start('Start');
/// ```
class DialogueGraph {
  DialogueGraph({required this.id, required Map<String, DialogueNode> nodes})
    : _nodes = Map.unmodifiable(nodes);

  /// Identifier for this graph — usually the asset file name without extension.
  final String id;

  final Map<String, DialogueNode> _nodes;

  /// Read-only view of all nodes keyed by their [DialogueNode.title].
  Map<String, DialogueNode> get nodes => _nodes;

  /// Looks up a node by [title]. Returns `null` if not found.
  DialogueNode? getNode(String title) => _nodes[title];

  /// Returns `true` if a node with [title] exists.
  bool hasNode(String title) => _nodes.containsKey(title);

  /// The conventional entry-point node (`'Start'`), falling back to whichever
  /// node was parsed first, or `null` if the graph is empty.
  DialogueNode? get startNode =>
      _nodes['Start'] ?? (_nodes.isNotEmpty ? _nodes.values.first : null);

  /// Returns a new [DialogueGraph] with all nodes from [other] merged in.
  ///
  /// Nodes from [other] with duplicate titles overwrite existing ones.
  DialogueGraph merge(DialogueGraph other) {
    return DialogueGraph(id: id, nodes: {..._nodes, ...other._nodes});
  }

  @override
  String toString() => 'DialogueGraph($id, ${_nodes.length} nodes)';
}

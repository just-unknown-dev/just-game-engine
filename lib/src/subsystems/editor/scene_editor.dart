import 'dart:convert';

import 'package:flutter/material.dart';

import '../rendering/impl/renderable.dart';
import '_io_native.dart' if (dart.library.html) '_io_stub.dart';

/// Main scene editor class
class SceneEditor {
  /// Active scene
  Scene? activeScene;

  /// All loaded scenes
  final Map<String, Scene> _scenes = {};

  /// Initialize the scene editor
  void initialize() {
    debugPrint('Scene Editor initialized');
  }

  /// Create a new scene
  Scene createScene(String name) {
    final scene = Scene(name: name);
    _scenes[name] = scene;
    activeScene ??= scene;
    return scene;
  }

  /// Load a scene
  void loadScene(String name) {
    if (_scenes.containsKey(name)) {
      activeScene = _scenes[name];
    }
  }

  /// Save the active scene as JSON to [path].
  ///
  /// All scene-graph transforms and node hierarchy are persisted.
  /// Attached [Renderable] instances (which are runtime objects) are not
  /// serialised; recreate them after loading with [loadSceneFromFile].
  ///
  /// Throws [StateError] if there is no active scene.
  /// Throws [UnsupportedError] on web (file I/O unavailable).
  void saveScene(String path) {
    if (activeScene == null) {
      throw StateError('SceneEditor.saveScene: no active scene to save.');
    }
    final json = const JsonEncoder.withIndent(
      '  ',
    ).convert(activeScene!.toJson());
    writeFile(path, json);
    debugPrint('Scene "${activeScene!.name}" saved to $path');
  }

  /// Load a scene that was previously saved with [saveScene].
  ///
  /// The loaded scene is registered under its original name and becomes the
  /// [activeScene].  Returns the loaded [Scene].
  ///
  /// Throws [UnsupportedError] on web (file I/O unavailable).
  Scene loadSceneFromFile(String path) {
    final raw = readFile(path);
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final scene = Scene.fromJson(json);
    _scenes[scene.name] = scene;
    activeScene = scene;
    debugPrint('Scene "${scene.name}" loaded from $path');
    return scene;
  }

  /// Update the active scene
  void update(double deltaTime) {
    activeScene?.update(deltaTime);
  }

  /// Render the active scene
  void render(Canvas canvas, Size size) {
    activeScene?.render(canvas, size);
  }

  /// Clean up editor resources
  void dispose() {
    _scenes.clear();
    activeScene = null;
    debugPrint('Scene Editor disposed');
  }

  /// Get all scene names
  List<String> get sceneNames => _scenes.keys.toList();
}

/// Represents a scene/level in the game
class Scene {
  /// Scene name
  final String name;

  /// Root node of the scene graph
  final SceneNode root = SceneNode('root');

  /// Create a scene
  Scene({required this.name});

  /// Serialise this scene to a JSON-compatible map.
  Map<String, dynamic> toJson() => {'name': name, 'root': root.toJson()};

  /// Restore a [Scene] from a map produced by [toJson].
  factory Scene.fromJson(Map<String, dynamic> json) {
    final scene = Scene(name: json['name'] as String);
    final rootJson = json['root'] as Map<String, dynamic>;
    // Restore root properties.
    final pos = rootJson['localPosition'] as Map<String, dynamic>;
    scene.root
      ..localPosition = Offset(
        (pos['dx'] as num).toDouble(),
        (pos['dy'] as num).toDouble(),
      )
      ..localRotation = (rootJson['localRotation'] as num).toDouble()
      ..localScale = (rootJson['localScale'] as num).toDouble()
      ..isActive = rootJson['isActive'] as bool;
    // Restore children.
    for (final child in rootJson['children'] as List<dynamic>) {
      scene.root.addChild(SceneNode.fromJson(child as Map<String, dynamic>));
    }
    return scene;
  }

  /// Add a node to the root
  void addNode(SceneNode node) {
    root.addChild(node);
  }

  /// Remove a node from the root
  void removeNode(SceneNode node) {
    root.removeChild(node);
  }

  /// Find a node by name
  SceneNode? findNode(String name) {
    return root.findChild(name);
  }

  /// Update the scene
  void update(double deltaTime) {
    root.update(deltaTime);
  }

  /// Render the scene
  void render(Canvas canvas, Size size) {
    root.render(canvas, size);
  }

  /// Get all nodes as a flat list
  List<SceneNode> getAllNodes() {
    final nodes = <SceneNode>[];
    _collectNodes(root, nodes);
    return nodes;
  }

  void _collectNodes(SceneNode node, List<SceneNode> list) {
    list.add(node);
    for (final child in node.children) {
      _collectNodes(child, list);
    }
  }
}

/// Node in the scene graph (hierarchical)
class SceneNode {
  /// Node name
  final String name;

  /// Parent node
  SceneNode? parent;

  /// Child nodes
  final List<SceneNode> _children = [];

  /// Local position
  Offset localPosition = Offset.zero;

  /// Local rotation
  double localRotation = 0.0;

  /// Local scale
  double localScale = 1.0;

  /// Is active
  bool isActive = true;

  /// Attached renderable
  Renderable? renderable;

  /// Custom update callback
  void Function(double deltaTime)? onUpdate;

  /// Create a scene node
  SceneNode(this.name);

  /// Serialise this node and its entire subtree to a JSON-compatible map.
  ///
  /// Attached [Renderable] instances are not included; restore them after
  /// calling [SceneNode.fromJson] when loading a scene.
  Map<String, dynamic> toJson() => {
    'name': name,
    'localPosition': {'dx': localPosition.dx, 'dy': localPosition.dy},
    'localRotation': localRotation,
    'localScale': localScale,
    'isActive': isActive,
    'children': _children.map((c) => c.toJson()).toList(),
  };

  /// Restore a [SceneNode] subtree from a map produced by [toJson].
  factory SceneNode.fromJson(Map<String, dynamic> json) {
    final node = SceneNode(json['name'] as String);
    final pos = json['localPosition'] as Map<String, dynamic>;
    node
      ..localPosition = Offset(
        (pos['dx'] as num).toDouble(),
        (pos['dy'] as num).toDouble(),
      )
      ..localRotation = (json['localRotation'] as num).toDouble()
      ..localScale = (json['localScale'] as num).toDouble()
      ..isActive = json['isActive'] as bool;
    for (final child in json['children'] as List<dynamic>) {
      node.addChild(SceneNode.fromJson(child as Map<String, dynamic>));
    }
    return node;
  }

  /// Get children
  List<SceneNode> get children => List.unmodifiable(_children);

  /// Add a child node
  void addChild(SceneNode child) {
    if (child.parent != null) {
      child.parent!.removeChild(child);
    }
    child.parent = this;
    _children.add(child);
  }

  /// Remove a child node
  void removeChild(SceneNode child) {
    if (_children.remove(child)) {
      child.parent = null;
    }
  }

  /// Find a child by name (recursive)
  SceneNode? findChild(String name) {
    if (this.name == name) return this;

    for (final child in _children) {
      final found = child.findChild(name);
      if (found != null) return found;
    }

    return null;
  }

  /// Get world position
  Offset get worldPosition {
    if (parent == null) return localPosition;
    return parent!.worldPosition + localPosition;
  }

  /// Get world rotation
  double get worldRotation {
    if (parent == null) return localRotation;
    return parent!.worldRotation + localRotation;
  }

  /// Get world scale
  double get worldScale {
    if (parent == null) return localScale;
    return parent!.worldScale * localScale;
  }

  /// Update this node and its children
  void update(double deltaTime) {
    if (!isActive) return;

    // Custom update
    onUpdate?.call(deltaTime);

    // Update renderable
    if (renderable != null) {
      renderable!.position = worldPosition;
      renderable!.rotation = worldRotation;
      renderable!.scale = worldScale;
    }

    // Update children
    for (final child in _children) {
      child.update(deltaTime);
    }
  }

  /// Render this node and its children
  void render(Canvas canvas, Size size) {
    if (!isActive) return;

    // Render attached renderable
    if (renderable != null && renderable!.visible) {
      renderable!.render(canvas, size);
    }

    // Render children
    for (final child in _children) {
      child.render(canvas, size);
    }
  }

  /// Get depth in tree
  int get depth {
    if (parent == null) return 0;
    return parent!.depth + 1;
  }
}

/// Base class for game objects in a scene
class GameObject {
  /// Object name
  String name = '';

  /// Object position
  double x = 0.0, y = 0.0, z = 0.0;

  /// Object rotation
  double rotX = 0.0, rotY = 0.0, rotZ = 0.0;

  /// Object scale
  double scaleX = 1.0, scaleY = 1.0, scaleZ = 1.0;

  /// Update the game object
  void update(double deltaTime) {
    // TODO: Implement object update
  }
}

/// Manages object hierarchy and transforms
class SceneGraph {
  /// Build scene hierarchy
  void buildHierarchy() {
    // TODO: Implement scene graph
  }
}

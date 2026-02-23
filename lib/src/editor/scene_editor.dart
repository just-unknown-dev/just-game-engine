/// Scene/Level Editor
///
/// A GUI tool for assembling scenes, placing objects, and designing levels.
/// This module provides tools for scene creation and manipulation with hierarchical scene graph.
library;

import 'package:flutter/material.dart';
import '../rendering/renderable.dart';

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

  /// Save the current scene
  void saveScene(String path) {
    // TODO: Implement scene serialization
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

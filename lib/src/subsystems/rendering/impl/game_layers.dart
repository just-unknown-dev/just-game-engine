/// Widgets a package draws over the game — the in-game interface, a debug
/// view — without the engine knowing what they are.
library;

import 'package:flutter/widgets.dart';

import '../../../core/engine.dart';

/// Something drawn over the game as real Flutter widgets.
///
/// Registered once on [Engine.layers]; every [GameWidget] showing that
/// engine then asks it for a [GameLayerController] of its own, so two views
/// of one engine never share widget state.
///
/// A layer sits *outside* the game widget's own focus node — which keeps
/// everything inside it unfocusable, by design — so a text field in a layer
/// can be typed into and a menu walked with the arrow keys. Keys a layer
/// does not want bubble on to the game's input.
abstract class GameLayer {
  const GameLayer();

  /// Names the layer; registering another with the same id replaces it.
  String get id;

  /// Stacking among layers: lower is drawn first, underneath. All of them
  /// sit over the game and under the engine's own dev tools.
  int get order => 0;

  /// The per-view half, for one [GameWidget] showing [engine].
  GameLayerController createController(Engine engine);
}

/// One view's instance of a [GameLayer].
abstract class GameLayerController {
  /// The widgets drawn over the game, filling it.
  Widget build(BuildContext context);

  /// Once a frame, from the game widget's ticker, after the game has
  /// stepped — whether or not the engine is running.
  void onFrame() {}

  void dispose() {}
}

/// The layers registered on an engine, and which are switched off.
///
/// A listenable: a game widget already on screen picks up a layer
/// registered after it, and drops one unregistered.
class GameLayers extends ChangeNotifier {
  final List<GameLayer> _layers = [];
  final Set<String> _off = {};

  /// Every registered layer, bottom first.
  List<GameLayer> get all => List.unmodifiable(_layers);

  /// The layer called [id], or null.
  GameLayer? byId(String id) {
    for (final layer in _layers) {
      if (layer.id == id) return layer;
    }
    return null;
  }

  /// Adds [layer], replacing any with its id.
  void register(GameLayer layer) {
    _layers
      ..removeWhere((l) => l.id == layer.id)
      ..add(layer);
    _sort();
    notifyListeners();
  }

  /// Removes the layer called [id], if there is one.
  void unregister(String id) {
    final before = _layers.length;
    _layers.removeWhere((l) => l.id == id);
    _off.remove(id);
    if (_layers.length != before) notifyListeners();
  }

  /// Removes every layer — when the engine shuts down.
  void clear() {
    if (_layers.isEmpty && _off.isEmpty) return;
    _layers.clear();
    _off.clear();
    notifyListeners();
  }

  /// Whether the layer called [id] is drawn. A layer switched off keeps its
  /// controllers — and their state — and is simply not built or ticked.
  bool isEnabled(String id) => !_off.contains(id);

  /// Switches the layer called [id] on or off — how an editor hides the
  /// game's interface while a level is being built.
  void setEnabled(String id, bool enabled) {
    final changed = enabled ? _off.remove(id) : _off.add(id);
    if (changed) notifyListeners();
  }

  void _sort() {
    final indexed = [for (var i = 0; i < _layers.length; i++) (i, _layers[i])];
    indexed.sort((a, b) {
      final byOrder = a.$2.order.compareTo(b.$2.order);
      return byOrder != 0 ? byOrder : a.$1.compareTo(b.$1);
    });
    _layers
      ..clear()
      ..addAll(indexed.map((e) => e.$2));
  }
}

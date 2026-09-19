library;

import 'dart:ui';

import 'engine.dart';

/// Something that attaches to a running [Engine] to observe or extend it —
/// a debug editor, a profiler, a replay recorder.
///
/// Plugins are registered with [Engine.plugins] and receive [update] once per
/// frame and [renderOverlay] after the world has drawn.
/// Several can coexist; each gets every call.
abstract class EnginePlugin {
  /// Stable identifier. Registering twice with the same id replaces the
  /// earlier plugin, after detaching it.
  String get id;

  /// Called once, when registered against a running or initialized engine.
  Future<void> attach(Engine engine) async {}

  /// Called once per frame with the unscaled frame time, whether or not the
  /// game is paused or its time scale is zero. Fixed-step simulation is for
  /// systems; a plugin observes the engine on wall-clock time.
  void update(double dt) {}

  /// Called after the world has rendered, in screen space.
  void renderOverlay(Canvas canvas, Size size) {}

  /// Called when unregistered or when the engine disposes.
  void detach() {}
}

/// The plugins attached to one engine.
class PluginHost {
  PluginHost(this._engine);

  final Engine _engine;
  final Map<String, EnginePlugin> _plugins = {};

  /// Every attached plugin, in registration order.
  Iterable<EnginePlugin> get all => _plugins.values;

  /// The plugin with [id], or null.
  EnginePlugin? byId(String id) => _plugins[id];

  /// Attaches [plugin], replacing (and detaching) any earlier one with the
  /// same id.
  Future<void> register(EnginePlugin plugin) async {
    _plugins.remove(plugin.id)?.detach();
    _plugins[plugin.id] = plugin;
    await plugin.attach(_engine);
  }

  /// Detaches and forgets the plugin with [id].
  void unregister(String id) => _plugins.remove(id)?.detach();

  /// Forwards an engine update to every plugin.
  void update(double dt) {
    for (final plugin in _plugins.values) {
      plugin.update(dt);
    }
  }

  /// Forwards an overlay render to every plugin.
  void renderOverlay(Canvas canvas, Size size) {
    for (final plugin in _plugins.values) {
      plugin.renderOverlay(canvas, size);
    }
  }

  /// Detaches everything.
  void detachAll() {
    for (final plugin in _plugins.values) {
      plugin.detach();
    }
    _plugins.clear();
  }
}

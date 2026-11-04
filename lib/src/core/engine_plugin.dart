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
  void update(double deltaTime) {}

  /// Called after the world has rendered, in screen space.
  void renderOverlay(Canvas canvas, Size size) {}

  /// Called when unregistered or when the engine disposes.
  void detach() {}
}

/// The plugins attached to one engine.
///
/// A plugin may register or unregister plugins — itself included — from
/// its own [EnginePlugin.update] or [EnginePlugin.renderOverlay]: one
/// unregistered before its turn is not called, and one registered is
/// called from the next frame on.
class PluginHost {
  /// An empty host for the given engine; each plugin registered is attached
  /// to it.
  PluginHost(this._engine);

  final Engine _engine;
  final Map<String, EnginePlugin> _plugins = {};

  /// [_plugins]' values as of its last change: what a frame walks.
  List<EnginePlugin>? _snapshot;

  List<EnginePlugin> get _current =>
      _snapshot ??= List<EnginePlugin>.unmodifiable(_plugins.values);

  /// Whether [plugin] is still the one registered under its id.
  bool _isRegistered(EnginePlugin plugin) =>
      identical(_plugins[plugin.id], plugin);

  /// Every attached plugin, in registration order. A snapshot: registering
  /// or unregistering while walking it is safe.
  Iterable<EnginePlugin> get all => _current;

  /// The plugin with [id], or null.
  EnginePlugin? byId(String id) => _plugins[id];

  /// Attaches [plugin], replacing (and detaching) any earlier one with the
  /// same id.
  Future<void> register(EnginePlugin plugin) async {
    _plugins.remove(plugin.id)?.detach();
    _plugins[plugin.id] = plugin;
    _snapshot = null;
    await plugin.attach(_engine);
  }

  /// Detaches and forgets the plugin with [id].
  void unregister(String id) {
    final plugin = _plugins.remove(id);
    if (plugin == null) return;
    _snapshot = null;
    plugin.detach();
  }

  /// Forwards an engine update to every plugin.
  void update(double deltaTime) {
    for (final plugin in _current) {
      if (_isRegistered(plugin)) plugin.update(deltaTime);
    }
  }

  /// Forwards an overlay render to every plugin.
  void renderOverlay(Canvas canvas, Size size) {
    for (final plugin in _current) {
      if (_isRegistered(plugin)) plugin.renderOverlay(canvas, size);
    }
  }

  /// Detaches everything. A plugin whose [EnginePlugin.detach] throws does
  /// not keep the others attached: each is detached, and the first error is
  /// rethrown afterwards.
  void detachAll() {
    final all = _current;
    _plugins.clear();
    _snapshot = null;
    Object? firstError;
    StackTrace? firstStack;
    for (final plugin in all) {
      try {
        plugin.detach();
      } catch (error, stack) {
        if (firstError == null) {
          firstError = error;
          firstStack = stack;
        }
      }
    }
    if (firstError != null) Error.throwWithStackTrace(firstError, firstStack!);
  }
}

library;

import 'dart:ui';

/// A render callback in screen or world space.
typedef RenderHook = void Function(Canvas canvas, Size size);

/// Several render callbacks called in order.
///
/// Replaces the single nullable `onRenderOverlay` / `onRenderBackground`
/// fields, where the first writer won and a second plugin's rendering was
/// silently dropped. Hooks run in ascending [order]; ties keep insertion
/// order.
class RenderHookChain {
  final List<({RenderHook hook, int order})> _hooks = [];

  /// Adds [hook]. The same function added twice runs twice; use
  /// [addIfAbsent] for idempotent wiring.
  void add(RenderHook hook, {int order = 0}) {
    _hooks
      ..add((hook: hook, order: order))
      ..sort((a, b) => a.order.compareTo(b.order));
  }

  /// Adds [hook] unless it is already in the chain.
  void addIfAbsent(RenderHook hook, {int order = 0}) {
    if (!contains(hook)) add(hook, order: order);
  }

  /// Removes every occurrence of [hook].
  void remove(RenderHook hook) => _hooks.removeWhere((h) => h.hook == hook);

  /// Whether [hook] is in the chain.
  bool contains(RenderHook hook) => _hooks.any((h) => h.hook == hook);

  /// Whether nothing is registered.
  bool get isEmpty => _hooks.isEmpty;

  /// Number of hooks.
  int get length => _hooks.length;

  /// Runs every hook in order.
  void call(Canvas canvas, Size size) {
    // Copied so a hook that adds or removes hooks does not break iteration.
    for (final h in List.of(_hooks)) {
      h.hook(canvas, size);
    }
  }

  /// Drops every hook.
  void clear() => _hooks.clear();
}

/// Registry for custom dialogue commands invoked from Yarn source.
library;

/// Context passed to every [DialogueCommandHandler].
class DialogueCommandContext {
  const DialogueCommandContext({
    required this.name,
    required this.args,
    required this.rawArgs,
  });

  /// The command name exactly as registered (lowercased).
  final String name;

  /// Arguments split on whitespace.
  final List<String> args;

  /// The full raw argument string (before splitting).
  final String rawArgs;

  /// Convenience accessor — returns [args]\[[index]\] or `null`.
  String? arg(int index) => index < args.length ? args[index] : null;
}

/// Handler invoked when a `<<commandName args>>` statement is executed.
///
/// Handlers are `async` so you can `await` fade-outs, play sounds, etc.
///
/// ```dart
/// manager.commands.register('fade_out', (ctx) async {
///   final duration = double.tryParse(ctx.arg(0) ?? '0.5') ?? 0.5;
///   await camera.fadeOut(duration);
/// });
/// ```
typedef DialogueCommandHandler =
    Future<void> Function(DialogueCommandContext ctx);

/// Registry for named [DialogueCommandHandler]s.
///
/// Register custom commands from your game code; reference them in Yarn:
///
/// ```yarn
/// <<fade_out 0.5>>
/// <<give_item sword 1>>
/// <<unlock_achievement first_boss>>
/// ```
class DialogueCommandRegistry {
  final Map<String, DialogueCommandHandler> _handlers = {};

  /// Registers [handler] under [name] (case-insensitive).
  ///
  /// Overwrites any existing registration with the same name.
  void register(String name, DialogueCommandHandler handler) {
    _handlers[name.toLowerCase()] = handler;
  }

  /// Executes the handler registered for [name] with [rawArgs].
  ///
  /// No-op if [name] is not registered.
  Future<void> execute(String name, String rawArgs) async {
    final handler = _handlers[name.toLowerCase()];
    if (handler == null) return;

    final args = rawArgs.trim().isEmpty
        ? <String>[]
        : rawArgs.trim().split(RegExp(r'\s+'));

    await handler(
      DialogueCommandContext(
        name: name.toLowerCase(),
        args: args,
        rawArgs: rawArgs,
      ),
    );
  }

  /// Returns `true` if a handler for [name] is registered.
  bool has(String name) => _handlers.containsKey(name.toLowerCase());

  /// Removes the handler registered under [name].
  void unregister(String name) => _handlers.remove(name.toLowerCase());

  /// Removes all registered handlers.
  void clear() => _handlers.clear();
}

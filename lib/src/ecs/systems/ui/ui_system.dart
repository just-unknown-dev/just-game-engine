/// Keeps the interface in step with the game.
///
/// Text that reads the game is re-read here, text that types itself out is
/// advanced here, and the screen layer is told when any of it changed —
/// once a frame, in one place, so the widgets rebuild only when they must.
library;

import '../../../subsystems/ui/ui_bindings.dart';
import '../../components/components.dart';
import '../../ecs.dart';
import '../system_priorities.dart';

class UiSystem extends System {
  UiSystem({this.localise});

  /// How a `@key` becomes words; without it a key shows as written.
  final String Function(String key)? localise;

  /// Called when something about the interface changed — the screen layer's
  /// `sync`. Set by whoever mounts the layer.
  void Function()? onChanged;

  // What each text last resolved to, so a binding that reads the same is
  // not a change. Comparing strings beats rebuilding widgets.
  final Map<Entity, String> _lastText = {};

  // Just before rendering: what a system did this frame shows this frame.
  @override
  int get priority => SystemPriorities.render + 1;

  @override
  List<Type> get requiredComponents => [TextComponent];

  @override
  void update(double deltaTime) {
    final live = entities.toSet();
    _lastText.removeWhere((entity, _) => !live.contains(entity));

    var changed = false;
    forEach((entity) {
      final text = entity.getComponent<TextComponent>()!;
      text.elapsed += deltaTime;

      final resolved = text.resolve(self: entity, localise: localise).plain;
      if (_lastText[entity] != resolved) {
        _lastText[entity] = resolved;
        changed = true;
      }

      if (text.revealSpeed > 0) {
        final total = text.resolve(self: entity, localise: localise).length;
        if (text.revealed < total) {
          text.revealed += deltaTime * text.revealSpeed;
          if (text.revealed > total) text.revealed = total.toDouble();
          changed = true;
        }
      }

      // Anything that moves keeps the layer refreshing while it moves.
      if (text.resolve(self: entity, localise: localise).needsPainter) {
        changed = true;
      }
    });

    if (changed) onChanged?.call();
  }

  /// Reads every binding a text asks for, for the editor's Problems dock.
  static List<String> missingBindings(World world) {
    final missing = <String>{};
    for (final entity in world.query([TextComponent])) {
      final text = entity.getComponent<TextComponent>()!;
      for (final name in UiBindings.namesIn(text.text)) {
        if (!UiBindings.has(name)) missing.add(name);
      }
    }
    return missing.toList()..sort();
  }
}

/// Everything the interface needs to run.
library;

import '../../../subsystems/ui/ui_bindings.dart';
import '../../ecs.dart';
import 'ui_pointer_system.dart';
import 'ui_system.dart';

/// Adds what keeps the interface alive: bindings re-read, text typed out,
/// world buttons pressed. A game that shows any UI calls this once at boot.
/// Systems already in [world] are left alone.
void registerUiSystems(
  World world, {
  String Function(String key)? localise,
  void Function(String path)? onSound,
}) {
  bool has<T extends System>() => world.systems.any((s) => s is T);
  UiBindings.registerBuiltIns();
  if (!has<UiSystem>()) {
    world.addSystem(UiSystem(localise: localise));
  }
  if (!has<UiPointerSystem>()) {
    world.addSystem(UiPointerSystem(onSound: onSound));
  }
}

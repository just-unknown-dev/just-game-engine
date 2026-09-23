/// Which screens are open, and in what order.
///
/// A canvas marked `isScreen` is a page: opened over what is already
/// there, closed to go back. A canvas that is not one is a layer that
/// stays — a HUD under everything.
///
/// The scene stays the source of truth: opening a screen sets its
/// `visible`, so what the editor shows and what the game shows are the
/// same thing, and a scene saved with a menu open opens with it open.
library;

import '../../ecs/components/components.dart';
import '../../ecs/ecs.dart';
import 'ui_actions.dart';

class UiNavigator {
  UiNavigator(this.world);

  final World world;

  /// The names of the open screens, oldest first. Names rather than
  /// entities, so a scene reloading under it does not leave it holding
  /// entities that have gone.
  final List<String> _stack = [];

  /// The open screens, bottom first.
  List<Entity> get stack => [for (final name in _stack) ?_screen(name)];

  /// What is on top, or null when only the layers are showing.
  Entity? get top => stack.isEmpty ? null : stack.last;

  bool get isEmpty => stack.isEmpty;

  /// Opens [name] over whatever is already open.
  void push(String name) {
    final entity = _screen(name);
    if (entity == null) return;
    _stack.remove(name);
    _stack.add(name);
    entity.getComponent<UiCanvasComponent>()!
      ..visible = true
      ..markDirty();
  }

  /// Closes the screen on top. Does nothing when there is none — a back
  /// press with nothing to go back to is the game's business, not the
  /// interface's.
  void back() {
    if (_stack.isEmpty) return;
    final name = _stack.removeLast();
    _screen(name)?.getComponent<UiCanvasComponent>()
      ?..visible = false
      ..markDirty();
  }

  /// Closes every screen, leaving the layers.
  void popToRoot() {
    while (_stack.isNotEmpty) {
      back();
    }
  }

  /// Shows, hides or flips any UI entity by name: a screen goes through
  /// the stack, a layer simply appears.
  ///
  /// [visible] null flips it.
  void show(String name, bool? visible) {
    final entity = world.findEntityByName(name);
    if (entity == null) return;
    final canvas = entity.getComponent<UiCanvasComponent>();
    if (canvas == null) {
      // Not a canvas: a single element inside one.
      final slot = entity.getComponent<UiSlotComponent>();
      if (slot != null) slot.visible = visible ?? !slot.visible;
      return;
    }
    final wanted = visible ?? !canvas.visible;
    if (canvas.isScreen) {
      if (wanted) {
        push(name);
      } else if (_stack.contains(name)) {
        _stack.remove(name);
        canvas
          ..visible = false
          ..markDirty();
      }
      return;
    }
    canvas
      ..visible = wanted
      ..markDirty();
  }

  /// Picks up screens a scene was saved with open, so the stack and the
  /// scene agree from the first frame.
  void adopt() {
    for (final entity in world.query([UiCanvasComponent])) {
      final canvas = entity.getComponent<UiCanvasComponent>()!;
      final name = entity.name;
      if (!canvas.isScreen || !canvas.visible || name == null) continue;
      if (!_stack.contains(name)) _stack.add(name);
    }
    _stack.sort((a, b) {
      final left =
          _screen(a)?.getComponent<UiCanvasComponent>()?.sortOrder ?? 0;
      final right =
          _screen(b)?.getComponent<UiCanvasComponent>()?.sortOrder ?? 0;
      return left.compareTo(right);
    });
    // A screen that was closed from elsewhere leaves the stack.
    _stack.removeWhere((name) {
      final canvas = _screen(name)?.getComponent<UiCanvasComponent>();
      return canvas == null || !canvas.visible;
    });
  }

  /// What `ui.push`, `ui.back` and `ui.show` reach when the game has not
  /// offered its own. Whatever the game *did* set is left alone.
  UiActionHost fillingIn(UiActionHost host) => UiActionHost(
    loadScene: host.loadScene,
    pause: host.pause,
    resume: host.resume,
    quit: host.quit,
    playSound: host.playSound,
    showUi: host.showUi ?? show,
    pushScreen: host.pushScreen ?? push,
    back: host.back ?? back,
  );

  Entity? _screen(String name) {
    final entity = world.findEntityByName(name);
    if (entity == null || !entity.isActive) return null;
    return entity.getComponent<UiCanvasComponent>() == null ? null : entity;
  }

  @override
  String toString() => 'UiNavigator($_stack)';
}

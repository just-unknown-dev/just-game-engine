/// Parallax backgrounds on entities, drawn behind the world.
library;

import 'dart:ui';

import '../../ecs.dart';
import '../../components/components.dart';
import '../../../interfaces/game_camera.dart';
import '../../../subsystems/parallax/parallax_background.dart';
import '../../../subsystems/parallax/parallax_ownership.dart';
import '../../../subsystems/rendering/render_hook_chain.dart';
import '../../base/system_priorities.dart';

/// Scrolls and draws every entity's [ParallaxComponent].
///
/// Backgrounds are drawn in screen space before the camera transform —
/// through [backgroundHooks], the rendering engine's hooks between clearing
/// the frame and drawing the world — so they sit behind everything else.
/// Each update advances their auto-scroll ([ParallaxLayer.velocityX] /
/// [ParallaxLayer.velocityY]); each frame, just before drawing, each is
/// given [camera]'s position, so the layers follow the camera of the frame
/// being drawn.
///
/// Several backgrounds draw by the entity's [LayerComponent] (lowest
/// first, none counting as 0), then in the order the entities were made.
/// An entity switched off, or this system switched off ([System.isActive]),
/// draws nothing.
///
/// `registerDefaultSystems` adds one, with the engine's
/// `RenderingEngine.backgroundHooks` and main camera, as part of
/// `DefaultSystem.rendering`:
///
/// ```dart
/// world.createEntityWithComponents([
///   ParallaxComponent(
///     background: ParallaxBackground(layers: [
///       ParallaxLayer(image: sky, scrollFactorX: 0),
///       ParallaxLayer(image: hills, scrollFactorX: 0.3, scrollFactorY: 0.2),
///     ]),
///   ),
/// ]);
/// ```
///
/// A background drawn here is skipped by the deprecated `engine.parallax`
/// list, so one registered in both is not drawn twice.
class ParallaxRenderSystem extends System {
  /// A system drawing through [backgroundHooks], following [camera] (no
  /// camera: the backgrounds stay where a camera at the origin sees them).
  ParallaxRenderSystem({required this.backgroundHooks, this.camera});

  /// Where the backgrounds are drawn: normally the engine's
  /// `RenderingEngine.backgroundHooks`. Joined when the system is added to
  /// a world, left when it is removed.
  final RenderHookChain backgroundHooks;

  /// The camera whose position the layers scroll against.
  final GameCamera? camera;

  static const List<Type> _query = [ParallaxComponent];

  /// The backgrounds this system marked as its own, last update.
  Set<ParallaxBackground> _claimed = Set.identity();
  Set<ParallaxBackground> _seen = Set.identity();

  /// Reused to sort each frame's entities, and to draw a background shared
  /// by two of them once.
  final List<Entity> _order = [];
  final Set<ParallaxBackground> _drawn = Set.identity();

  @override
  int get priority => SystemPriorities.parallax;

  @override
  List<Type> get requiredComponents => _query;

  @override
  void onAddedToWorld() => backgroundHooks.addIfAbsent(_paint);

  @override
  void onRemovedFromWorld() => _detach();

  @override
  void dispose() => _detach();

  void _detach() {
    backgroundHooks.remove(_paint);
    for (final background in _claimed) {
      if (identical(parallaxDrawnBy[background], this)) {
        parallaxDrawnBy[background] = null;
      }
    }
    _claimed.clear();
  }

  @override
  void update(double deltaTime) {
    final seen = _seen..clear();
    for (final entity in world.query(_query)) {
      final background = entity.getComponent<ParallaxComponent>()!.background;
      if (!seen.add(background)) continue; // on two entities: one scroll
      parallaxDrawnBy[background] = this;
      background.update(deltaTime);
    }
    // Backgrounds whose entity went (or was switched off) are no longer
    // this system's: the deprecated list may draw them again.
    for (final background in _claimed) {
      if (!seen.contains(background) &&
          identical(parallaxDrawnBy[background], this)) {
        parallaxDrawnBy[background] = null;
      }
    }
    _seen = _claimed;
    _claimed = seen;
  }

  void _paint(Canvas canvas, Size size) {
    if (!isActive) return;
    final order = _order
      ..clear()
      ..addAll(world.query(_query));
    if (order.isEmpty) return;
    order.sort(_byLayer);
    final at = camera?.position ?? Offset.zero;
    final drawn = _drawn..clear();
    for (final entity in order) {
      final background = entity.getComponent<ParallaxComponent>()!.background;
      if (!drawn.add(background)) continue;
      background.cameraPosition = at;
      background.render(canvas, size);
    }
    order.clear();
    drawn.clear();
  }

  static int _byLayer(Entity a, Entity b) {
    final byLayer = (a.getComponent<LayerComponent>()?.layer ?? 0).compareTo(
      b.getComponent<LayerComponent>()?.layer ?? 0,
    );
    return byLayer != 0 ? byLayer : a.id.compareTo(b.id);
  }
}

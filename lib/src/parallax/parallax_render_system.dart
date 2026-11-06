/// Parallax backgrounds on entities, drawn behind the world.
library;

import 'dart:math' as math;
import 'dart:ui';

import 'package:just_dart/just_dart.dart' show Matrix4;

import '../ecs/ecs.dart';
import '../interfaces/game_camera.dart';
import 'parallax_background.dart';
import '../rendering/render_hook_chain.dart';
import '../rendering/layer_component.dart';
import 'parallax_component.dart';

/// Scrolls and draws every entity's [ParallaxComponent].
///
/// Backgrounds are drawn in screen space before the camera transform —
/// through [backgroundHooks], the rendering engine's hooks between clearing
/// the frame and drawing the world — so they sit behind everything else.
/// Each update advances their auto-scroll ([ParallaxLayer.velocityX] /
/// [ParallaxLayer.velocityY]); each frame, just before drawing, each is
/// given [camera]'s position and zoom, so the layers follow the camera of
/// the frame being drawn.
///
/// Several backgrounds draw by the entity's [LayerComponent] (lowest
/// first, none counting as 0), then in the order the entities were made.
/// A background on two entities scrolls and draws once. An entity switched
/// off, or this system switched off ([System.isActive]), draws nothing.
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
class ParallaxRenderSystem extends System {
  /// A system drawing through [backgroundHooks], following [camera] (no
  /// camera: the backgrounds stay where a camera at the origin sees them).
  ParallaxRenderSystem({required this.backgroundHooks, this.camera});

  /// Where the backgrounds are drawn: normally the engine's
  /// `RenderingEngine.backgroundHooks`. Joined when the system is added to
  /// a world, left when it is removed.
  final RenderHookChain backgroundHooks;

  /// The camera whose position (and zoom) the layers scroll against.
  final GameCamera? camera;

  static const List<Type> _query = [ParallaxComponent];

  /// Reused: the backgrounds scrolled this update, the entities sorted
  /// each frame, and the backgrounds drawn — each shared one once.
  final Set<ParallaxBackground> _scrolled = Set.identity();
  final List<Entity> _order = [];
  final Set<ParallaxBackground> _drawn = Set.identity();

  /// Reused to read [camera]'s zoom.
  final Matrix4 _matrix = Matrix4.zero();

  @override
  int get priority => SystemPriorities.parallax;

  @override
  List<Type> get requiredComponents => _query;

  @override
  void onAddedToWorld() => backgroundHooks.addIfAbsent(_paint);

  @override
  void onRemovedFromWorld() => backgroundHooks.remove(_paint);

  @override
  void dispose() => backgroundHooks.remove(_paint);

  @override
  void update(double deltaTime) {
    final scrolled = _scrolled..clear();
    for (final entity in world.query(_query)) {
      final background = entity.getComponent<ParallaxComponent>()!.background;
      if (!scrolled.add(background)) continue; // on two entities: one scroll
      background.update(deltaTime);
    }
    scrolled.clear();
  }

  void _paint(Canvas canvas, Size size) {
    if (!isActive) return;
    final order = _order
      ..clear()
      ..addAll(world.query(_query));
    if (order.isEmpty) return;
    order.sort(_byLayer);
    final cam = camera;
    final at = cam?.position ?? Offset.zero;
    final zoom = cam == null ? 1.0 : _zoomOf(cam);
    final drawn = _drawn..clear();
    for (final entity in order) {
      final background = entity.getComponent<ParallaxComponent>()!.background;
      if (!drawn.add(background)) continue;
      background
        ..cameraPosition = at
        ..cameraZoom = zoom;
      background.render(canvas, size);
    }
    order.clear();
    drawn.clear();
  }

  /// How many screen pixels a world unit covers under [camera] — its zoom —
  /// read from the matrix it draws the world with. A camera that is not
  /// planar (pitched, yawed or perspective) has no one such scale: 1.
  double _zoomOf(GameCamera camera) {
    if (!camera.isPlanar) return 1.0;
    camera.canvasMatrixInto(_matrix);
    final m = _matrix.storage;
    final zoom = math.sqrt(m[0] * m[0] + m[1] * m[1]);
    return zoom > 0 && zoom.isFinite ? zoom : 1.0;
  }

  static int _byLayer(Entity a, Entity b) {
    final byLayer = (a.getComponent<LayerComponent>()?.layer ?? 0).compareTo(
      b.getComponent<LayerComponent>()?.layer ?? 0,
    );
    return byLayer != 0 ? byLayer : a.id.compareTo(b.id);
  }
}

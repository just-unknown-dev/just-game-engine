library;

import 'dart:math' as math;
import 'dart:ui' show Rect;

import '../../ecs.dart';
import '../../components/components.dart';
import '../../../interfaces/interfaces.dart';
import '../../../subsystems/rendering/impl/renderable.dart' show Renderable;

/// Opt-in view culling — tracks which entities are near the camera and marks
/// them accordingly on their `CullStateComponent`.
///
/// Two separate radii are used rather than one shared threshold:
/// - [renderRadiusMultiplier] (default `1.2`) — a tight radius matching what's
///   actually on screen. An entity outside it is hidden: `ViewCullingSystem`
///   sets its `RenderableComponent.renderable.visible` to false, so
///   `RenderSystem` skips drawing it — no extra wiring needed.
/// - [activeRadiusMultiplier] (default `2.0`) — a larger radius used for
///   simulation. This engine's `MovementSystem`/`PhysicsSystem` skip any
///   entity whose `CullStateComponent.isActive` is `false`, and game-specific
///   systems (AI, etc.) should check the same flag. The gap between the two
///   radii means entities approaching the screen are already moving by the
///   time they scroll into view, instead of snapping to life at the edge.
///
/// ## Who owns `visible`
///
/// The game does; the culler only borrows it. It writes `visible` when an
/// entity crosses the render edge and at no other time: on the way out it
/// hides the entity — if it was showing — and remembers doing so
/// ([CullStateComponent.hidesRenderable]); on the way back in it shows
/// again only what it hid. So a game can hide a culled entity on screen
/// and it stays hidden however often it scrolls away and back.
///
/// One case cannot be told apart: while an entity is culled its `visible`
/// is already false, so the game setting it false then changes nothing,
/// and the culler shows the entity when it comes back into view. To hide an
/// entity that may be off screen, clear
/// [CullStateComponent.hidesRenderable] as well.
///
/// ## Bounds
///
/// An entity's extent is its renderable's bounds, scaled and turned with
/// its transform — the bounding box of the turned rectangle, so a turned
/// entity is never culled while a corner still shows. A negative scale
/// (a flipped sprite) is fine. Without bounds it is a 1×1 box at its
/// position.
///
/// Entities must explicitly carry a [CullStateComponent] to participate —
/// nothing else is affected. The [hysteresisMargin] avoids visibility
/// flicker for entities sitting right on the render boundary (e.g. during
/// camera spring micro-movement): once visible, an entity needs to cross
/// slightly further out before it's culled back out.
///
/// ```dart
/// world.addSystem(ViewCullingSystem(camera: engine.cameraSystem.mainCamera));
/// enemy.addComponent(CullStateComponent()); // opt in — the player shouldn't get one
/// ```
class ViewCullingSystem extends System {
  /// The camera whose visible bounds, read each update, everything is
  /// measured against.
  final GameCamera camera;

  /// Size of the render area as a multiple of the visible bounds' width and
  /// height, about their centre: `1` is exactly the view, `1.2` a tenth of
  /// it spare on each side.
  final double renderRadiusMultiplier;

  /// Size of the active (simulated) area, as a multiple of the visible
  /// bounds' width and height about their centre.
  final double activeRadiusMultiplier;

  /// World units added to every side of the render area for an entity
  /// that is already visible, before it is culled again.
  final double hysteresisMargin;

  /// A culler for [camera] with a render area 1.2× the view, an active
  /// area 2× it and a 24-unit hysteresis margin, unless told otherwise.
  /// `gridCellSize` is ignored.
  ViewCullingSystem({
    required this.camera,
    this.renderRadiusMultiplier = 1.2,
    this.activeRadiusMultiplier = 2.0,
    this.hysteresisMargin = 24.0,
    @Deprecated(
      'Unused: culling tests every opted-in entity directly, which is '
      'cheaper than keeping a grid in step. Will be removed in 3.0.',
    )
    double gridCellSize = 256.0,
  });

  @override
  int get priority => 91; // above PhysicsSystem(90)/MovementSystem(80) so they see this frame's fresh flags

  @override
  List<Type> get requiredComponents => [TransformComponent, CullStateComponent];

  // The entity being tested's extent, as plain numbers — no Rect per entity.
  double _left = 0.0, _top = 0.0, _right = 0.0, _bottom = 0.0;

  @override
  void update(double deltaTime) {
    final visible = camera.getVisibleBounds();
    final cx = visible.center.dx, cy = visible.center.dy;

    // The render rect, the same rect with the hysteresis margin, and the
    // active rect — as Rect.fromCenter and Rect.inflate would make them.
    final rw = visible.width * renderRadiusMultiplier;
    final rh = visible.height * renderRadiusMultiplier;
    final rl = cx - rw / 2, rt = cy - rh / 2;
    final rr = cx + rw / 2, rb = cy + rh / 2;
    final m = hysteresisMargin;
    final hl = rl - m, ht = rt - m, hr = rr + m, hb = rb + m;
    final aw = visible.width * activeRadiusMultiplier;
    final ah = visible.height * activeRadiusMultiplier;
    final al = cx - aw / 2, at = cy - ah / 2;
    final ar = cx + aw / 2, ab = cy + ah / 2;

    // One pass over the opted-in entities, the columns read directly.
    for (final archetype in world.queryArchetypes(requiredComponents)) {
      final transforms = archetype.getColumn(TransformComponent)!;
      final culls = archetype.getColumn(CullStateComponent)!;
      final renderables = archetype.getColumn(RenderableComponent);
      for (var i = 0; i < transforms.length; i++) {
        if (!archetype.entityAt(i).isActive) continue;
        final cull = culls[i] as CullStateComponent;
        final renderable =
            (renderables?[i] as RenderableComponent?)?.renderable;
        _boundsOf(transforms[i] as TransformComponent, renderable);

        final show = cull.isVisible
            ? _overlaps(hl, ht, hr, hb)
            : _overlaps(rl, rt, rr, rb);
        cull.isVisible = show;
        cull.isActive = _overlaps(al, at, ar, ab);

        if (renderable == null) continue;
        if (!show) {
          if (!cull.hidesRenderable && renderable.visible) {
            renderable.visible = false;
            cull.hidesRenderable = true;
          }
        } else if (cull.hidesRenderable) {
          renderable.visible = true;
          cull.hidesRenderable = false;
        }
      }
    }
  }

  /// Whether the entity's extent overlaps the rect — as [Rect.overlaps].
  bool _overlaps(double l, double t, double r, double b) =>
      !(r <= _left || _right <= l || b <= _top || _bottom <= t);

  /// Sets the entity's extent in the world from [transform] and
  /// [renderable].
  void _boundsOf(TransformComponent transform, Renderable? renderable) {
    final position = transform.position;
    final bounds = renderable?.getBounds();
    if (bounds == null) {
      _left = position.x - 0.5;
      _top = position.y - 0.5;
      _right = position.x + 0.5;
      _bottom = position.y + 0.5;
      return;
    }
    // Renderables like Sprite already center getBounds() on their own
    // (world-synced) position, and scale it — turning is all that is
    // left. Local, origin-centered bounds (CustomRenderable-based shapes)
    // need the transform's scale, turn and position. See
    // Renderable.boundsAreWorldSpace.
    if (renderable!.boundsAreWorldSpace) {
      _turned(bounds, renderable.rotation);
    } else {
      _placed(bounds, transform);
    }
  }

  /// World-space [bounds] turned by [angle] about their centre.
  void _turned(Rect bounds, double angle) {
    // A negative scale makes an inside-out rect: put it right way round.
    final l = math.min(bounds.left, bounds.right);
    final r = math.max(bounds.left, bounds.right);
    final t = math.min(bounds.top, bounds.bottom);
    final b = math.max(bounds.top, bounds.bottom);
    if (angle == 0.0) {
      _left = l;
      _top = t;
      _right = r;
      _bottom = b;
      return;
    }
    final c = math.cos(angle).abs(), s = math.sin(angle).abs();
    final hw = (r - l) / 2, hh = (b - t) / 2;
    final mx = (l + r) / 2, my = (t + b) / 2;
    final ex = c * hw + s * hh, ey = s * hw + c * hh;
    _left = mx - ex;
    _right = mx + ex;
    _top = my - ey;
    _bottom = my + ey;
  }

  /// Local [bounds] scaled, turned and moved by [transform].
  void _placed(Rect bounds, TransformComponent transform) {
    final p = transform.position;
    final sx = transform.scale.x, sy = transform.scale.y;
    final angle = transform.angle;
    if (angle == 0.0) {
      // Scale alone: each edge maps to an edge; order them.
      final x0 = p.x + bounds.left * sx, x1 = p.x + bounds.right * sx;
      final y0 = p.y + bounds.top * sy, y1 = p.y + bounds.bottom * sy;
      _left = math.min(x0, x1);
      _right = math.max(x0, x1);
      _top = math.min(y0, y1);
      _bottom = math.max(y0, y1);
      return;
    }
    final c = math.cos(angle), s = math.sin(angle);
    _left = double.infinity;
    _top = double.infinity;
    _right = double.negativeInfinity;
    _bottom = double.negativeInfinity;
    _corner(bounds.left * sx, bounds.top * sy, c, s, p.x, p.y);
    _corner(bounds.right * sx, bounds.top * sy, c, s, p.x, p.y);
    _corner(bounds.left * sx, bounds.bottom * sy, c, s, p.x, p.y);
    _corner(bounds.right * sx, bounds.bottom * sy, c, s, p.x, p.y);
  }

  void _corner(double x, double y, double c, double s, double px, double py) {
    final wx = px + c * x - s * y;
    final wy = py + s * x + c * y;
    if (wx < _left) _left = wx;
    if (wx > _right) _right = wx;
    if (wy < _top) _top = wy;
    if (wy > _bottom) _bottom = wy;
  }
}

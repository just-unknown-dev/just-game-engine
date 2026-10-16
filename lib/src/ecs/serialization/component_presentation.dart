/// How a component presents itself, apart from how it is saved: the size
/// it implies ([ComponentExtent]) and, for one that draws itself, its
/// painter ([ComponentPainter]) and what that is given per frame
/// ([RenderContext]). A `ComponentDefinition` carries both; the codec half
/// (`component_definition.dart`) knows nothing about drawing.
library;

import 'dart:ui';

import 'package:just_dart/just_dart.dart' show Aabb3;

import '../../interfaces/game_camera.dart';
import '../../subsystems/rendering/frame_view.dart';
import '../ecs.dart';

/// The size a component implies, and how to change it.
///
/// Unifies what used to be three separate type switches (selection bounds,
/// resize handles, gizmo bounds) into one answer per definition.
abstract class ComponentExtent {
  /// Const constructor so subclasses can be const.
  const ComponentExtent();

  /// The component's local, unrotated size, or null if it implies none.
  Size? sizeOf(Component component);

  /// Scales the component's own dimensions by ([sx], [sy]). Returns false when
  /// it has nothing to scale.
  bool scale(Component component, double sx, double sy) => false;

  /// Mirrors the component across its own centre, if that means anything
  /// for it — a sprite's flip flag, say.
  void flip(Component component, {required bool horizontal}) {}

  /// The component's local bounds in 3-D, centred on its origin, into
  /// [out]; false when it implies none. A flat thing's is its [sizeOf] with
  /// no depth — override for something with a depth of its own (a model).
  bool boundsInto(Component component, Aabb3 out) {
    final size = sizeOf(component);
    if (size == null) return false;
    out.setValues(
      -size.width / 2,
      -size.height / 2,
      0,
      size.width / 2,
      size.height / 2,
      0,
    );
    return true;
  }
}

/// What a [ComponentPainter] is given per frame.
class RenderContext {
  /// What the render system hands its painters for one frame;
  /// [interpolation] 1.0 means the latest physics state, unblended.
  const RenderContext({
    required this.world,
    required this.size,
    this.camera,
    this.interpolation = 1.0,
    this.view,
  });

  /// The world being drawn.
  final World world;

  /// The size of the viewport being drawn into, in logical pixels.
  final Size size;

  /// The camera the frame is drawn through; null when there is none.
  final GameCamera? camera;

  /// Sub-frame interpolation factor for physics-driven entities.
  final double interpolation;

  /// The frame's camera as matrices, when the renderer was given them —
  /// for a painter that draws something in 3-D.
  final FrameView? view;
}

/// Draws a component that is not a [RenderableComponent] — text, a button, a
/// progress bar, anything that renders itself from its own fields.
///
/// The canvas is already translated, rotated and scaled by the entity's
/// transform, so painters draw around the origin.
abstract class ComponentPainter<T extends Component> {
  /// Const constructor so subclasses can be const.
  const ComponentPainter();

  /// Draw order within the painter pass; lower first.
  int layerOf(T component) => 0;

  /// Whether to draw at all this frame.
  bool isVisible(T component) => true;

  /// Draws [component] of [entity] onto [canvas], around the origin, in
  /// the entity's local space. Called each frame the entity is active and
  /// [isVisible] is true.
  void paint(Canvas canvas, Entity entity, T component, RenderContext context);

  /// [paint] for a component typed only as [Component].
  void paintAny(Canvas canvas, Entity entity, Component c, RenderContext ctx) =>
      paint(canvas, entity, c as T, ctx);

  /// [layerOf] for a component typed only as [Component].
  int layerOfAny(Component c) => layerOf(c as T);

  /// [isVisible] for a component typed only as [Component].
  bool isVisibleAny(Component c) => isVisible(c as T);
}

/// Renderable Objects
///
/// Base classes and implementations for objects that can be rendered.
library;

import 'package:flutter/material.dart';

import 'package:just_dart/just_dart.dart';

/// Base class for all renderable objects
///
/// All objects that need to be rendered should extend this class.
abstract class Renderable {
  /// Position in world space (x, y used by 2-D Canvas; z reserved for 3-D).
  Vector3 position;

  /// Rotation in radians (Z-axis; standard 2-D rotation).
  double rotation;

  /// Scale factors (x, y used by 2-D Canvas; z reserved for 3-D).
  Vector3 scale;

  /// Layer index for rendering order (lower layers render first).
  ///
  /// In the ECS world an entity's `LayerComponent` takes its place; without
  /// one, `RenderSystem` sorts by this.
  int layer;

  /// Z-order within the layer; like [layer], a `LayerComponent` takes its
  /// place.
  int zOrder;

  /// When `true`, `RenderSystem` draws this renderable after the things on
  /// its layer and zOrder that do not y-sort, ordered among the ones that
  /// do by world-space [position].y — so entities visually "in front"
  /// (further down the screen) draw over ones behind them, regardless of
  /// type. It stays on its layer, keeps its `ShaderComponent`, and batches
  /// like any sprite. Opt-in per-renderable (default `false`) so unrelated
  /// entities (UI, ground decals) keep their existing behavior.
  bool ySort;

  /// Visibility flag
  bool visible;

  /// Opacity (0.0 to 1.0)
  double opacity;

  /// Tint color
  Color? tint;

  /// Whether [bounds] already returns world-space bounds (i.e. already
  /// centered on/incorporating [position]) rather than local bounds
  /// relative to the entity's own origin.
  ///
  /// Defaults to `false`, matching [CustomRenderable]-based shapes
  /// (`Rectangle2DComponent`, `Circle2DComponent`, `Line2DComponent`,
  /// `Polygon2DComponent`, `Capsule2DComponent`) — their `boundsOf`s
  /// return bounds centered on `Offset.zero`, so callers needing world-space
  /// bounds (e.g. `ViewCullingSystem`) must shift by the entity's
  /// [TransformComponent] position themselves. Every other built-in
  /// renderable — [Sprite], [TextRenderable], the nine-slice sprite, rays
  /// and particle emitters — overrides this to `true`: its [bounds] is
  /// already placed at its own [position] (synced to world space every
  /// render pass by `RenderSystem`), so shifting it again would double-count
  /// the position. (Only [Sprite] used to say so, and a culling system that
  /// shifted the others by their position again hid them once synced.)
  bool get boundsAreWorldSpace => false;

  /// Create a renderable object
  Renderable({
    Vector3? position,
    this.rotation = 0.0,
    Vector3? scale,
    this.layer = 0,
    this.zOrder = 0,
    this.ySort = false,
    this.visible = true,
    this.opacity = 1.0,
    this.tint,
  }) : position = position ?? Vector3.zero(),
       scale = scale ?? Vector3(1.0, 1.0, 1.0);

  /// Render this object
  ///
  /// [canvas] - Flutter canvas to render to
  /// [size] - Size of the rendering area
  void render(Canvas canvas, Size size);

  /// Get the bounding box of this renderable
  ///
  /// Returns null if no bounds are applicable. Never inside out: a
  /// renderable flipped by a negative scale still reports its left edge
  /// left of its right one.
  Rect? get bounds;

  /// Lets go of what it holds for drawing — a text layout, an image it was
  /// given to own. Called when its `RenderableComponent` leaves its entity
  /// (the component removed or the entity destroyed). What it made for
  /// itself it makes again if drawn after; what it was handed by someone
  /// else it leaves alone. Nothing by default.
  void dispose() {}

  /// Apply transform to canvas (projects 3-D position to 2-D XY plane).
  ///
  /// A rotation of 0 and a scale of (1, 1) change nothing, so they are not
  /// sent to the canvas: most things in a 2-D scene are neither turned nor
  /// scaled, and each canvas call crosses into the engine.
  void applyTransform(Canvas canvas) {
    canvas
      ..save()
      ..translate(position.x, position.y);
    if (rotation != 0.0) canvas.rotate(rotation);
    final sx = scale.x, sy = scale.y;
    if (sx != 1.0 || sy != 1.0) canvas.scale(sx, sy);
  }

  /// Restore canvas state
  void restoreTransform(Canvas canvas) {
    canvas.restore();
  }
}

/// A renderable text label
class TextRenderable extends Renderable {
  // bounds is already placed at [position].
  @override
  bool get boundsAreWorldSpace => true;

  /// Text to display
  String text;

  /// Text style
  TextStyle textStyle;

  /// Text alignment
  TextAlign textAlign;

  /// Create a text renderable
  TextRenderable({
    required this.text,
    TextStyle? textStyle,
    this.textAlign = TextAlign.center,
    super.position,
    super.rotation,
    super.scale,
    super.layer,
    super.zOrder,
    super.visible,
    super.opacity,
  }) : textStyle =
           textStyle ?? const TextStyle(color: Colors.white, fontSize: 16);

  /// Cached TextPainter — reused every frame, only re-laid-out when content
  /// changes; made when first needed, and let go by [dispose].
  TextPainter? _painter;
  String _lastText = '';
  TextStyle? _lastStyle;
  double _lastOpacity = -1;
  TextAlign _lastAlign = TextAlign.center;

  @override
  void render(Canvas canvas, Size canvasSize) {
    applyTransform(canvas);

    final painter = _layOut();
    final offset = Offset(-painter.width / 2, -painter.height / 2);
    painter.paint(canvas, offset);

    restoreTransform(canvas);
  }

  /// Lays the text out again when anything it depends on changed.
  ///
  /// One place for [render] and [bounds]: bounds used to lay the text out
  /// without the faded colour but still record it as current, so the next
  /// frame drew it at full opacity.
  TextPainter _layOut() {
    final effectiveOpacity = (textStyle.color?.a ?? 1.0) * opacity;
    final known = _painter;
    if (known != null &&
        text == _lastText &&
        textStyle == _lastStyle &&
        effectiveOpacity == _lastOpacity &&
        textAlign == _lastAlign) {
      return known;
    }
    _lastText = text;
    _lastStyle = textStyle;
    _lastOpacity = effectiveOpacity;
    _lastAlign = textAlign;
    return (_painter ??= TextPainter(textDirection: TextDirection.ltr))
      ..text = TextSpan(
        text: text,
        style: textStyle.copyWith(
          color: textStyle.color?.withValues(alpha: effectiveOpacity),
        ),
      )
      ..textAlign = textAlign
      ..layout();
  }

  /// The world-space box the text covers before it is turned: never inside
  /// out, whatever the sign of its scale.
  @override
  Rect? get bounds {
    final painter = _layOut();

    return Rect.fromCenter(
      center: position.toOffset(),
      width: (painter.width * scale.x).abs(),
      height: (painter.height * scale.y).abs(),
    );
  }

  /// Lets go of the laid-out text (a native paragraph); it is laid out
  /// again if drawn after.
  @override
  void dispose() {
    _painter?.dispose();
    _painter = null;
  }
}

/// A custom renderable that uses a callback for rendering
class CustomRenderable extends Renderable {
  /// Custom render callback
  final void Function(Canvas canvas, Size size) onRender;

  /// Optional bounds
  final Rect? Function()? boundsOf;

  /// Draws what [onRender] draws with [tint] and [opacity] already applied —
  /// a colour multiplied into each paint — and returns true; or returns
  /// false, drawing nothing, when it cannot.
  ///
  /// Without it, or when it returns false, a faded or tinted renderable is
  /// drawn through an offscreen layer that multiplies the colour in
  /// afterwards: exact for anything, but a layer per entity per frame. The
  /// built-in shapes supply one for the cases where the result is the same.
  final bool Function(Canvas canvas, Size size, Color? tint, double opacity)?
  onRenderFaded;

  /// Create a custom renderable
  CustomRenderable({
    required this.onRender,
    this.boundsOf,
    this.onRenderFaded,
    super.position,
    super.rotation,
    super.scale,
    super.layer,
    super.zOrder,
    super.visible,
    super.opacity,
  });

  @override
  void render(Canvas canvas, Size canvasSize) {
    applyTransform(canvas);

    final needsLayer = opacity < 1.0 || tint != null;
    if (!needsLayer) {
      onRender(canvas, canvasSize);
    } else if (onRenderFaded?.call(canvas, canvasSize, tint, opacity) != true) {
      canvas.saveLayer(null, _layerPaint());
      onRender(canvas, canvasSize);
      canvas.restore();
    }

    restoreTransform(canvas);
  }

  final Paint _fadePaint = Paint();
  Color? _fadeTint;
  double _fadeOpacity = -1;

  /// The paint of the layer that fades and tints what [onRender] draws.
  ///
  /// Kept, and given a new colour filter only when [tint] or [opacity]
  /// changed: a filter handed to a paint is converted for the engine every
  /// time, so a fading entity used to cost a paint and a filter a frame.
  Paint _layerPaint() {
    final t = tint;
    if (t != _fadeTint || opacity != _fadeOpacity) {
      _fadeTint = t;
      _fadeOpacity = opacity;
      _fadePaint.colorFilter = ColorFilter.mode(
        // Modulate blends both colour and alpha: multiply each channel of
        // the offscreen buffer by the tint colour (pre-multiplied with
        // opacity). Without a tint, white: only alpha is affected.
        t != null
            ? t.withValues(alpha: t.a * opacity)
            : Color.fromRGBO(255, 255, 255, opacity),
        BlendMode.modulate,
      );
    }
    return _fadePaint;
  }

  @override
  Rect? get bounds {
    return boundsOf?.call();
  }
}

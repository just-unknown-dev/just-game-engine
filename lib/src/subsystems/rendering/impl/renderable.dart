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

  /// Layer index for rendering order (lower layers render first)
  int layer;

  /// Z-order within the layer
  int zOrder;

  /// When `true`, `RenderSystem` draws this renderable in a separate pass
  /// sorted by world-space [position].y instead of by [zOrder] — so entities
  /// visually "in front" (further down the screen) draw over ones behind
  /// them, regardless of type. Opt-in per-renderable (default `false`) so
  /// unrelated entities (UI, ground decals) keep their existing behavior.
  bool ySort;

  /// Visibility flag
  bool visible;

  /// Opacity (0.0 to 1.0)
  double opacity;

  /// Tint color
  Color? tint;

  /// Whether [getBounds] already returns world-space bounds (i.e. already
  /// centered on/incorporating [position]) rather than local bounds
  /// relative to the entity's own origin.
  ///
  /// Defaults to `false`, matching [CustomRenderable]-based shapes
  /// (`RectangleComponent`, `CircleComponent`, `LineComponent`,
  /// `PolygonComponent`, `CapsuleComponent`) — their `getBoundsCallback`s
  /// return bounds centered on `Offset.zero`, so callers needing world-space
  /// bounds (e.g. `ViewCullingSystem`) must shift by the entity's
  /// [TransformComponent] position themselves. [Sprite] overrides this to
  /// `true`: its [getBounds] is already centered on its own [position]
  /// (synced to world space every render pass by `RenderSystem`), so
  /// shifting it again would double-count the position.
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
  /// Returns null if no bounds are applicable
  Rect? getBounds();

  /// Apply transform to canvas (projects 3-D position to 2-D XY plane).
  void applyTransform(Canvas canvas) {
    canvas.save();
    canvas.translate(position.x, position.y);
    canvas.rotate(rotation);
    canvas.scale(scale.x, scale.y);
  }

  /// Restore canvas state
  void restoreTransform(Canvas canvas) {
    canvas.restore();
  }
}

/// A renderable rectangle shape
class RectangleRenderable extends Renderable {
  /// Size of the rectangle
  Size size;

  /// Fill color
  Color fillColor;

  /// Stroke color (null for no stroke)
  Color? strokeColor;

  /// Stroke width
  double strokeWidth;

  // Cached paint objects
  final Paint _fillPaint = Paint()..style = PaintingStyle.fill;
  final Paint _strokePaint = Paint()..style = PaintingStyle.stroke;

  /// Create a rectangle renderable
  RectangleRenderable({
    required this.size,
    required this.fillColor,
    this.strokeColor,
    this.strokeWidth = 2.0,
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

    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: size.width,
      height: size.height,
    );

    // Draw fill
    _fillPaint.color = fillColor.withValues(alpha: fillColor.a * opacity);
    canvas.drawRect(rect, _fillPaint);

    // Draw stroke
    if (strokeColor != null) {
      _strokePaint
        ..color = strokeColor!.withValues(alpha: strokeColor!.a * opacity)
        ..strokeWidth = strokeWidth;
      canvas.drawRect(rect, _strokePaint);
    }

    restoreTransform(canvas);
  }

  @override
  Rect? getBounds() {
    return Rect.fromCenter(
      center: position.toOffset(),
      width: size.width * scale.x,
      height: size.height * scale.y,
    );
  }
}

class CircleRenderable extends Renderable {
  /// Radius of the circle
  double radius;

  /// Fill color
  Color fillColor;

  /// Stroke color (null for no stroke)
  Color? strokeColor;

  /// Stroke width
  double strokeWidth;

  // Cached paint objects
  final Paint _fillPaint = Paint()..style = PaintingStyle.fill;
  final Paint _strokePaint = Paint()..style = PaintingStyle.stroke;

  /// Create a circle renderable
  CircleRenderable({
    required this.radius,
    required this.fillColor,
    this.strokeColor,
    this.strokeWidth = 2.0,
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

    // Draw fill
    _fillPaint.color = fillColor.withValues(alpha: fillColor.a * opacity);
    canvas.drawCircle(Offset.zero, radius, _fillPaint);

    // Draw stroke
    if (strokeColor != null) {
      _strokePaint
        ..color = strokeColor!.withValues(alpha: strokeColor!.a * opacity)
        ..strokeWidth = strokeWidth;
      canvas.drawCircle(Offset.zero, radius, _strokePaint);
    }

    restoreTransform(canvas);
  }

  @override
  Rect? getBounds() {
    final scaledRadius = radius * (scale.x + scale.y) / 2;
    return Rect.fromCircle(center: position.toOffset(), radius: scaledRadius);
  }
}

/// A renderable line
class LineRenderable extends Renderable {
  /// End point relative to position
  Offset endPoint;

  /// Line color
  Color color;

  /// Line width
  double width;

  // Cached paint object
  final Paint _paint = Paint()..strokeCap = StrokeCap.round;

  /// Create a line renderable
  LineRenderable({
    required this.endPoint,
    required this.color,
    this.width = 2.0,
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

    _paint
      ..color = color.withValues(alpha: color.a * opacity)
      ..strokeWidth = width;

    canvas.drawLine(Offset.zero, endPoint, _paint);

    restoreTransform(canvas);
  }

  @override
  Rect? getBounds() {
    final origin = position.toOffset();
    return Rect.fromPoints(origin, origin + endPoint);
  }
}

/// A renderable text label
class TextRenderable extends Renderable {
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

  /// Cached TextPainter — reused every frame, only re-laid-out when content changes.
  final TextPainter _painter = TextPainter(textDirection: TextDirection.ltr);
  String _lastText = '';
  TextStyle? _lastStyle;
  double _lastOpacity = -1;
  TextAlign _lastAlign = TextAlign.center;

  @override
  void render(Canvas canvas, Size canvasSize) {
    applyTransform(canvas);

    final effectiveOpacity = (textStyle.color?.a ?? 1.0) * opacity;

    if (text != _lastText ||
        textStyle != _lastStyle ||
        effectiveOpacity != _lastOpacity ||
        textAlign != _lastAlign) {
      _lastText = text;
      _lastStyle = textStyle;
      _lastOpacity = effectiveOpacity;
      _lastAlign = textAlign;
      _painter
        ..text = TextSpan(
          text: text,
          style: textStyle.copyWith(
            color: textStyle.color?.withValues(alpha: effectiveOpacity),
          ),
        )
        ..textAlign = textAlign
        ..layout();
    }

    final offset = Offset(-_painter.width / 2, -_painter.height / 2);
    _painter.paint(canvas, offset);

    restoreTransform(canvas);
  }

  @override
  Rect? getBounds() {
    // Force layout if stale
    if (text != _lastText || textStyle != _lastStyle) {
      _painter
        ..text = TextSpan(text: text, style: textStyle)
        ..layout();
      _lastText = text;
      _lastStyle = textStyle;
    }

    return Rect.fromCenter(
      center: position.toOffset(),
      width: _painter.width * scale.x,
      height: _painter.height * scale.y,
    );
  }
}

/// A custom renderable that uses a callback for rendering
class CustomRenderable extends Renderable {
  /// Custom render callback
  final void Function(Canvas canvas, Size size) onRender;

  /// Optional bounds
  final Rect? Function()? getBoundsCallback;

  /// Create a custom renderable
  CustomRenderable({
    required this.onRender,
    this.getBoundsCallback,
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
    if (needsLayer) {
      if (tint != null) {
        // Modulate blends both colour and alpha: multiply each channel of the
        // offscreen buffer by the tint colour (pre-multiplied with opacity).
        canvas.saveLayer(
          null,
          Paint()
            ..colorFilter = ColorFilter.mode(
              tint!.withValues(alpha: tint!.a * opacity),
              BlendMode.modulate,
            ),
        );
      } else {
        // Opacity only — use a white modulate so only alpha is affected.
        canvas.saveLayer(
          null,
          Paint()
            ..colorFilter = ColorFilter.mode(
              Color.fromRGBO(255, 255, 255, opacity),
              BlendMode.modulate,
            ),
        );
      }
    }

    onRender(canvas, canvasSize);

    if (needsLayer) canvas.restore();
    restoreTransform(canvas);
  }

  @override
  Rect? getBounds() {
    return getBoundsCallback?.call();
  }
}

/// Renderable Objects
///
/// Base classes and implementations for objects that can be rendered.
library;

import 'package:flutter/material.dart';

/// Base class for all renderable objects
///
/// All objects that need to be rendered should extend this class.
abstract class Renderable {
  /// Position in world space
  Offset position;

  /// Rotation in radians
  double rotation;

  /// Scale factor
  double scale;

  /// Layer index for rendering order (lower layers render first)
  int layer;

  /// Z-order within the layer
  int zOrder;

  /// Visibility flag
  bool visible;

  /// Opacity (0.0 to 1.0)
  double opacity;

  /// Tint color
  Color? tint;

  /// Create a renderable object
  Renderable({
    this.position = Offset.zero,
    this.rotation = 0.0,
    this.scale = 1.0,
    this.layer = 0,
    this.zOrder = 0,
    this.visible = true,
    this.opacity = 1.0,
    this.tint,
  });

  /// Render this object
  ///
  /// [canvas] - Flutter canvas to render to
  /// [size] - Size of the rendering area
  void render(Canvas canvas, Size size);

  /// Get the bounding box of this renderable
  ///
  /// Returns null if no bounds are applicable
  Rect? getBounds();

  /// Apply transform to canvas
  void applyTransform(Canvas canvas) {
    canvas.save();
    canvas.translate(position.dx, position.dy);
    canvas.rotate(rotation);
    canvas.scale(scale, scale);
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
      center: position,
      width: size.width * scale,
      height: size.height * scale,
    );
  }
}

/// A renderable circle shape
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
    final scaledRadius = radius * scale;
    return Rect.fromCircle(center: position, radius: scaledRadius);
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
    return Rect.fromPoints(position, position + endPoint);
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
      center: position,
      width: _painter.width * scale,
      height: _painter.height * scale,
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

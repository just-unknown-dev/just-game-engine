library;

import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../../ecs.dart';
import '../../serialization/component_definition.dart';
import 'button_component.dart';
import 'elliptical_progress_component.dart';
import 'linear_progress_component.dart';
import 'text_component.dart';
import 'ui_component.dart';

/// Shared by the UI painters: draw order and visibility come from
/// [UIComponent].
mixin _UiLayering<T extends UIComponent> on ComponentPainter<T> {
  @override
  int layerOf(T component) => component.layer;

  @override
  bool isVisible(T component) => component.visible;
}

/// Draws a [TextComponent] centred on the origin.
class TextComponentPainter extends ComponentPainter<TextComponent>
    with _UiLayering<TextComponent> {
  const TextComponentPainter();

  static final _painter = TextPainter(textDirection: TextDirection.ltr);

  @override
  void paint(Canvas canvas, Entity e, TextComponent text, RenderContext ctx) {
    _painter
      ..text = TextSpan(text: text.text, style: text.textStyle)
      ..textAlign = text.textAlign
      ..layout();
    _painter.paint(canvas, Offset(-_painter.width / 2, -_painter.height / 2));
  }
}

/// Draws a [ButtonComponent]: rounded fill, optional border, centred label.
class ButtonComponentPainter extends ComponentPainter<ButtonComponent>
    with _UiLayering<ButtonComponent> {
  const ButtonComponentPainter();

  static final _fill = Paint();
  static final _border = Paint()..style = PaintingStyle.stroke;
  static final _painter = TextPainter(textDirection: TextDirection.ltr);

  @override
  void paint(Canvas canvas, Entity e, ButtonComponent b, RenderContext ctx) {
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset.zero,
        width: b.size.width,
        height: b.size.height,
      ),
      Radius.circular(b.borderRadius),
    );
    _fill.color = b.currentColor;
    canvas.drawRRect(rect, _fill);
    if (b.borderColor != null) {
      _border.color = b.borderColor!;
      canvas.drawRRect(rect, _border);
    }
    _painter
      ..text = TextSpan(text: b.text, style: b.textStyle)
      ..textAlign = TextAlign.center
      ..layout(maxWidth: b.size.width);
    _painter.paint(canvas, Offset(-_painter.width / 2, -_painter.height / 2));
  }
}

/// Draws a [LinearProgressComponent]: track, fill, optional border.
class LinearProgressPainter extends ComponentPainter<LinearProgressComponent>
    with _UiLayering<LinearProgressComponent> {
  const LinearProgressPainter();

  static final _track = Paint();
  static final _fill = Paint();
  static final _border = Paint()..style = PaintingStyle.stroke;

  @override
  void paint(
    Canvas canvas,
    Entity e,
    LinearProgressComponent p,
    RenderContext ctx,
  ) {
    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: p.size.width,
      height: p.size.height,
    );
    final track = RRect.fromRectAndRadius(
      rect,
      Radius.circular(p.borderRadius),
    );
    _track.color = p.trackColor;
    canvas.drawRRect(track, _track);

    final fillWidth = p.size.width * p.progress;
    if (fillWidth > 0) {
      _fill.color = p.progressColor;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(rect.left, rect.top, fillWidth, rect.height),
          Radius.circular(p.borderRadius),
        ),
        _fill,
      );
    }
    if (p.borderColor != null) {
      _border.color = p.borderColor!;
      canvas.drawRRect(track, _border);
    }
  }
}

/// Draws an [EllipticalProgressComponent]: an oval track and an arc.
class EllipticalProgressPainter
    extends ComponentPainter<EllipticalProgressComponent>
    with _UiLayering<EllipticalProgressComponent> {
  const EllipticalProgressPainter();

  static final _track = Paint()..style = PaintingStyle.stroke;
  static final _arc = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  @override
  void paint(
    Canvas canvas,
    Entity e,
    EllipticalProgressComponent p,
    RenderContext ctx,
  ) {
    // An oval inscribed in a square is a circle, so this is a strict superset
    // of a circular bar and also handles radiusY != radius.
    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: p.size.width,
      height: p.size.height,
    );
    _track
      ..color = p.trackColor
      ..strokeWidth = p.strokeWidth;
    canvas.drawOval(rect, _track);
    if (p.progress > 0) {
      final sweep = math.pi * 2 * p.progress;
      _arc
        ..color = p.progressColor
        ..strokeWidth = p.strokeWidth;
      canvas.drawArc(
        rect,
        p.startAngle,
        p.clockwise ? sweep : -sweep,
        false,
        _arc,
      );
    }
  }
}

library;

import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../../ecs.dart';
import '../../../subsystems/ui/ui_bindings.dart';
import '../../../subsystems/ui/ui_rich_text.dart';
import '../../../subsystems/ui/ui_text_painter.dart';
import '../../../subsystems/ui/ui_text_style.dart';
import '../../../subsystems/ui/ui_theme.dart';
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

/// Draws a [TextComponent]: its style, its tags, and whatever moves.
class TextComponentPainter extends ComponentPainter<TextComponent>
    with _UiLayering<TextComponent> {
  const TextComponentPainter();

  /// One painter per component, since laying text out is what costs and a
  /// component's text rarely changes between frames.
  static final Expando<UiTextPainter> _painters = Expando('uiTextPainter');

  /// How a key becomes words. The game sets this once; without it a key
  /// shows as written, which is what an editor wants.
  static String Function(String key)? localise;

  /// The theme world text is drawn with.
  static UiTheme theme = UiTheme.fallback;

  @override
  void paint(Canvas canvas, Entity e, TextComponent text, RenderContext ctx) {
    final resolved = text.resolve(self: e, localise: localise);
    if (resolved.isEmpty) return;
    final shown = text.revealSpeed > 0
        ? resolved.take(text.revealed.floor())
        : resolved;
    if (shown.isEmpty) return;

    final painter = _painters[text] ??= UiTextPainter();
    painter
      ..set(
        text: shown,
        style: text.styleUnder(theme),
        layout: text.layoutFor(),
      )
      ..paint(
        canvas,
        Offset.zero,
        animation: UiTextAnimation(seconds: text.elapsed),
      );
  }
}

/// Draws a [ButtonComponent]: its fill in the theme's colour and its
/// state's tint, an optional border, and its label.
class ButtonComponentPainter extends ComponentPainter<ButtonComponent>
    with _UiLayering<ButtonComponent> {
  const ButtonComponentPainter();

  static final _fill = Paint();
  static final _border = Paint()..style = PaintingStyle.stroke;
  static final Expando<UiTextPainter> _labels = Expando('uiButtonLabel');

  @override
  void paint(Canvas canvas, Entity e, ButtonComponent b, RenderContext ctx) {
    final theme = TextComponentPainter.theme;
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset.zero,
        width: b.size.width,
        height: b.size.height,
      ),
      Radius.circular(b.borderRadius),
    );
    final opacity = b.opacity;
    _fill.color = b.colorUnder(theme).withValues(alpha: opacity);
    canvas.drawRRect(rect, _fill);
    if (b.borderColor != null) {
      _border.color = b.borderColor!.withValues(alpha: opacity);
      canvas.drawRRect(rect, _border);
    }

    final label = UiRichText.parse(UiBindings.interpolate(b.label, self: e));
    if (label.isEmpty) return;
    final style = b.labelStyleUnder(theme);
    (_labels[b] ??= UiTextPainter())
      ..set(
        text: label,
        style: opacity < 1
            ? style.copyWith(
                color: (style.color ?? const Color(0xFFFFFFFF)).withValues(
                  alpha: opacity,
                ),
              )
            : style,
        layout: UiTextLayout(
          align: UiTextAlign.center,
          overflow: UiTextOverflow.ellipsis,
          maxWidth: b.size.width - 12,
          maxLines: 1,
        ),
      )
      ..paint(canvas, Offset.zero);
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

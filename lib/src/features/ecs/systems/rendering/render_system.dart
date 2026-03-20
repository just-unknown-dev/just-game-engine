library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../ecs.dart';
import '../../components/components.dart';
import '../../../rendering/camera.dart';

/// Render system - Renders ECS world-space renderables and UI components.
class RenderSystem extends System {
  /// Optional camera used to transform world-space entities.
  final Camera? camera;

  /// Create a render system.
  RenderSystem({this.camera});

  @override
  List<Type> get requiredComponents => [TransformComponent];

  @override
  void render(Canvas canvas, Size size) {
    if (camera != null) {
      camera!.viewportSize = size;
      canvas.save();
      camera!.applyTransform(canvas, size);
    }

    final renderableEntities = world
        .query([TransformComponent, RenderableComponent])
        .where((entity) => entity.isActive)
        .toList();

    for (final entity in renderableEntities) {
      final transform = entity.getComponent<TransformComponent>()!;
      final renderComp = entity.getComponent<RenderableComponent>()!;

      // Sync transform if enabled
      if (renderComp.syncTransform) {
        renderComp.renderable.position = transform.position;
        renderComp.renderable.rotation = transform.rotation;
        renderComp.renderable.scale = transform.scale;
      }

      // Render
      if (renderComp.renderable.visible) {
        renderComp.renderable.render(canvas, size);
      }
    }

    final uiEntities =
        world
            .query([TransformComponent])
            .where((entity) => entity.isActive)
            .where(
              (entity) =>
                  entity.hasComponent<TextComponent>() ||
                  entity.hasComponent<ButtonComponent>() ||
                  entity.hasComponent<LinearProgressComponent>() ||
                  entity.hasComponent<CircularProgressComponent>(),
            )
            .toList()
          ..sort((a, b) {
            final aLayer = _uiLayerFor(a);
            final bLayer = _uiLayerFor(b);
            return aLayer.compareTo(bLayer);
          });

    for (final entity in uiEntities) {
      final transform = entity.getComponent<TransformComponent>()!;
      canvas.save();
      canvas.translate(transform.position.dx, transform.position.dy);
      canvas.rotate(transform.rotation);
      canvas.scale(transform.scale);

      final text = entity.getComponent<TextComponent>();
      if (text != null && text.visible) {
        _paintText(canvas, text);
      }

      final button = entity.getComponent<ButtonComponent>();
      if (button != null && button.visible) {
        _paintButton(canvas, button);
      }

      final linearProgress = entity.getComponent<LinearProgressComponent>();
      if (linearProgress != null && linearProgress.visible) {
        _paintLinearProgress(canvas, linearProgress);
      }

      final circularProgress = entity.getComponent<CircularProgressComponent>();
      if (circularProgress != null && circularProgress.visible) {
        _paintCircularProgress(canvas, circularProgress);
      }

      canvas.restore();
    }

    if (camera != null) {
      canvas.restore();
    }
  }

  int _uiLayerFor(Entity entity) {
    if (entity.hasComponent<TextComponent>()) {
      return entity.getComponent<TextComponent>()!.layer;
    }
    if (entity.hasComponent<ButtonComponent>()) {
      return entity.getComponent<ButtonComponent>()!.layer;
    }
    if (entity.hasComponent<LinearProgressComponent>()) {
      return entity.getComponent<LinearProgressComponent>()!.layer;
    }
    if (entity.hasComponent<CircularProgressComponent>()) {
      return entity.getComponent<CircularProgressComponent>()!.layer;
    }
    return 0;
  }

  void _paintText(Canvas canvas, TextComponent text) {
    final textPainter = TextPainter(
      text: TextSpan(text: text.text, style: text.textStyle),
      textAlign: text.textAlign,
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      Offset(-textPainter.width / 2, -textPainter.height / 2),
    );
  }

  void _paintButton(Canvas canvas, ButtonComponent button) {
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset.zero,
        width: button.size.width,
        height: button.size.height,
      ),
      Radius.circular(button.borderRadius),
    );

    canvas.drawRRect(rect, Paint()..color = button.currentColor);

    if (button.borderColor != null) {
      canvas.drawRRect(
        rect,
        Paint()
          ..color = button.borderColor!
          ..style = PaintingStyle.stroke,
      );
    }

    final textPainter = TextPainter(
      text: TextSpan(text: button.text, style: button.textStyle),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: button.size.width);

    textPainter.paint(
      canvas,
      Offset(-textPainter.width / 2, -textPainter.height / 2),
    );
  }

  void _paintLinearProgress(Canvas canvas, LinearProgressComponent progress) {
    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: progress.size.width,
      height: progress.size.height,
    );
    final track = RRect.fromRectAndRadius(
      rect,
      Radius.circular(progress.borderRadius),
    );

    canvas.drawRRect(track, Paint()..color = progress.trackColor);

    final fillWidth = progress.size.width * progress.progress;
    if (fillWidth > 0) {
      final fillRect = Rect.fromLTWH(
        rect.left,
        rect.top,
        fillWidth,
        rect.height,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          fillRect,
          Radius.circular(progress.borderRadius),
        ),
        Paint()..color = progress.progressColor,
      );
    }

    if (progress.borderColor != null) {
      canvas.drawRRect(
        track,
        Paint()
          ..color = progress.borderColor!
          ..style = PaintingStyle.stroke,
      );
    }
  }

  void _paintCircularProgress(
    Canvas canvas,
    CircularProgressComponent progress,
  ) {
    final radius = progress.radius;
    final arcRect = Rect.fromCircle(center: Offset.zero, radius: radius);

    canvas.drawCircle(
      Offset.zero,
      radius,
      Paint()
        ..color = progress.trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = progress.strokeWidth,
    );

    if (progress.progress > 0) {
      final sweep = math.pi * 2 * progress.progress;
      canvas.drawArc(
        arcRect,
        progress.startAngle,
        progress.clockwise ? sweep : -sweep,
        false,
        Paint()
          ..color = progress.progressColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = progress.strokeWidth
          ..strokeCap = StrokeCap.round,
      );
    }
  }
}

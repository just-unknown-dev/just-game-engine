library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../ecs.dart';
import '../../components/components.dart';
import '../../../interfaces/interfaces.dart';
import '../../../subsystems/rendering/impl/sprite_batch.dart';
import '../system_priorities.dart';

/// Render system - Renders ECS world-space renderables and UI components.
class RenderSystem extends System {
  @override
  int get priority => SystemPriorities.render;

  /// Optional camera used to transform world-space entities.
  final GameCamera? camera;

  /// Factory for creating sprite-batch renderers from an atlas image.
  final SpriteBatchFactory _spriteBatchFactory;

  // ── Cached paint objects to avoid per-frame allocation ───────────────
  final Paint _buttonFillPaint = Paint();
  final Paint _buttonBorderPaint = Paint()..style = PaintingStyle.stroke;
  final Paint _trackPaint = Paint();
  final Paint _progressFillPaint = Paint();
  final Paint _progressBorderPaint = Paint()..style = PaintingStyle.stroke;
  final Paint _circleTrackPaint = Paint()..style = PaintingStyle.stroke;
  final Paint _circleProgressPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  /// Cached TextPainter — reused across _paintText and _paintButton.
  final TextPainter _textPainter = TextPainter(
    textDirection: TextDirection.ltr,
  );

  /// Reusable buffer for UI entity sorting — avoids per-frame list allocation.
  final List<Entity> _uiEntityBuffer = [];

  /// Cached [SpriteBatchRenderer] instances keyed by atlas image identity.
  /// Re-created only when the atlas image changes (e.g. hot-reload).
  final Map<int, SpriteBatchRenderer> _spriteBatches = {};

  /// Cached [Paint] for per-entity [ShaderComponent] saveLayer calls.
  /// Reused each frame to avoid allocation.
  final Paint _entityShaderPaint = Paint();

  /// Create a render system.
  RenderSystem({this.camera, SpriteBatchFactory? spriteBatchFactory})
    : _spriteBatchFactory =
          spriteBatchFactory ?? ((atlas) => SpriteBatch(atlas));

  @override
  List<Type> get requiredComponents => [TransformComponent];

  /// Whether the camera transform is already applied by an outer context
  /// (e.g. [RenderingEngine.onRenderOverlay]). When true, [render] skips
  /// its own save/transform/restore.
  bool cameraAppliedExternally = false;

  @override
  void render(Canvas canvas, Size size) {
    if (camera != null && !cameraAppliedExternally) {
      camera!.viewportSize = size;
      canvas.save();
      camera!.applyTransform(canvas, size);
    }

    final renderableEntities = world.query([
      TransformComponent,
      RenderableComponent,
    ]);

    // ── Batched sprite rendering ──────────────────────────────────────────
    // Sprites that share the same atlas image are collected into a SpriteBatch
    // and flushed in a single Canvas.drawAtlas() call per atlas.
    for (final entity in renderableEntities) {
      if (!entity.isActive) continue;
      final transform = entity.getComponent<TransformComponent>()!;
      final renderComp = entity.getComponent<RenderableComponent>()!;

      // Sync transform if enabled
      if (renderComp.syncTransform) {
        renderComp.renderable.position = transform.position;
        renderComp.renderable.rotation = transform.rotation;
        renderComp.renderable.scale = transform.scale;
      }

      if (!renderComp.renderable.visible) continue;

      // ── Per-entity shader detection ────────────────────────────────────
      final shaderComp = entity.getComponent<ShaderComponent>();
      final hasEntityShader =
          shaderComp != null && !shaderComp.isPostProcess && shaderComp.enabled;

      // Try to batch renderables that implement BatchableSprite.
      // Entities with a per-entity shader cannot be batched — they require an
      // isolated offscreen layer to composite the shader correctly.
      final renderable = renderComp.renderable;
      if (renderable is BatchableSprite &&
          (renderable as BatchableSprite).batchImage != null &&
          !hasEntityShader) {
        final batchable = renderable as BatchableSprite;
        final image = batchable.batchImage!;
        final key = identityHashCode(image);
        final batch = _spriteBatches.putIfAbsent(
          key,
          () => _spriteBatchFactory(image),
        );

        final srcRect =
            batchable.batchSourceRect ??
            Rect.fromLTWH(
              0,
              0,
              image.width.toDouble(),
              image.height.toDouble(),
            );

        final tintColor =
            renderable.tint?.withValues(alpha: renderable.opacity) ??
            Color.fromRGBO(255, 255, 255, renderable.opacity);

        batch.add(
          sourceRect: srcRect,
          position: renderable.position,
          rotation: renderable.rotation,
          scale: renderable.scale,
          color: tintColor,
        );
      } else {
        // Non-sprite, image-less sprite, or entity with a per-entity shader:
        // render individually, optionally wrapped in a shader saveLayer.
        if (hasEntityShader) {
          final bounds = renderable.getBounds();
          // Fall back to a generous world-space rect if bounds are unknown.
          final effectRect =
              bounds ??
              Rect.fromCenter(
                center: renderable.position,
                width: size.width,
                height: size.height,
              );
          shaderComp!.setUniforms?.call(
            shaderComp.shader,
            effectRect.width,
            effectRect.height,
            0.0, // per-entity mode: no time source in RenderSystem
          );
          _entityShaderPaint.imageFilter =
              ui.ImageFilter.shader(shaderComp.shader);
          canvas.saveLayer(effectRect, _entityShaderPaint);
        }

        renderable.render(canvas, size);

        if (hasEntityShader) canvas.restore();
      }
    }

    // Flush all sprite batches.
    for (final batch in _spriteBatches.values) {
      batch.flush(canvas);
    }

    _uiEntityBuffer.clear();
    for (final entity in world.query([TransformComponent])) {
      if (!entity.isActive) continue;
      if (entity.hasComponent<TextComponent>() ||
          entity.hasComponent<ButtonComponent>() ||
          entity.hasComponent<LinearProgressComponent>() ||
          entity.hasComponent<CircularProgressComponent>()) {
        _uiEntityBuffer.add(entity);
      }
    }
    _uiEntityBuffer.sort((a, b) {
      final aLayer = _uiLayerFor(a);
      final bLayer = _uiLayerFor(b);
      return aLayer.compareTo(bLayer);
    });

    for (final entity in _uiEntityBuffer) {
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

    if (camera != null && !cameraAppliedExternally) {
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
    _textPainter
      ..text = TextSpan(text: text.text, style: text.textStyle)
      ..textAlign = text.textAlign
      ..layout();

    _textPainter.paint(
      canvas,
      Offset(-_textPainter.width / 2, -_textPainter.height / 2),
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

    _buttonFillPaint.color = button.currentColor;
    canvas.drawRRect(rect, _buttonFillPaint);

    if (button.borderColor != null) {
      _buttonBorderPaint.color = button.borderColor!;
      canvas.drawRRect(rect, _buttonBorderPaint);
    }

    _textPainter
      ..text = TextSpan(text: button.text, style: button.textStyle)
      ..textAlign = TextAlign.center
      ..layout(maxWidth: button.size.width);

    _textPainter.paint(
      canvas,
      Offset(-_textPainter.width / 2, -_textPainter.height / 2),
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

    _trackPaint.color = progress.trackColor;
    canvas.drawRRect(track, _trackPaint);

    final fillWidth = progress.size.width * progress.progress;
    if (fillWidth > 0) {
      final fillRect = Rect.fromLTWH(
        rect.left,
        rect.top,
        fillWidth,
        rect.height,
      );
      _progressFillPaint.color = progress.progressColor;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          fillRect,
          Radius.circular(progress.borderRadius),
        ),
        _progressFillPaint,
      );
    }

    if (progress.borderColor != null) {
      _progressBorderPaint.color = progress.borderColor!;
      canvas.drawRRect(track, _progressBorderPaint);
    }
  }

  void _paintCircularProgress(
    Canvas canvas,
    CircularProgressComponent progress,
  ) {
    final radius = progress.radius;
    final arcRect = Rect.fromCircle(center: Offset.zero, radius: radius);

    _circleTrackPaint
      ..color = progress.trackColor
      ..strokeWidth = progress.strokeWidth;
    canvas.drawCircle(Offset.zero, radius, _circleTrackPaint);

    if (progress.progress > 0) {
      final sweep = math.pi * 2 * progress.progress;
      _circleProgressPaint
        ..color = progress.progressColor
        ..strokeWidth = progress.strokeWidth;
      canvas.drawArc(
        arcRect,
        progress.startAngle,
        progress.clockwise ? sweep : -sweep,
        false,
        _circleProgressPaint,
      );
    }
  }
}

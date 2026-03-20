/// Rendering abstract contracts shared between ECS and rendering subsystem.
library;

import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Marker interface for renderables that can be GPU-batched.
///
/// When a [Renderable] also implements [BatchableSprite], the render system
/// collects it into a [SpriteBatchRenderer] instead of issuing an individual
/// draw call.
abstract interface class BatchableSprite {
  /// The atlas / sprite-sheet image for batching.
  ui.Image? get batchImage;

  /// Source rectangle on the atlas (null = full image).
  Rect? get batchSourceRect;
}

/// Abstract contract for a sprite-batch renderer.
///
/// Implementations collect per-sprite data via [add] and issue a single GPU
/// draw call in [flush].
abstract interface class SpriteBatchRenderer {
  /// Queue a single sprite for batched rendering.
  void add({
    required Rect sourceRect,
    required Offset position,
    double rotation = 0.0,
    double scale = 1.0,
    double? anchorX,
    double? anchorY,
    Color color = const Color(0xFFFFFFFF),
  });

  /// Render all queued sprites and clear the batch.
  void flush(Canvas canvas);
}

/// Factory function type for creating [SpriteBatchRenderer] instances.
typedef SpriteBatchFactory = SpriteBatchRenderer Function(ui.Image atlas);

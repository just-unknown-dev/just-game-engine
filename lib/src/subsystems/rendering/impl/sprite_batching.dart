/// What the render systems share to batch sprites: deciding whether and how
/// a sprite goes into a batch, and keeping the batches.
library;

import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../interfaces/rendering_interfaces.dart';
import 'renderable.dart';
import 'sprite.dart';
import 'sprite_batch.dart';

/// How one sprite goes into a batch, worked out by [plan]. One instance is
/// reused for every sprite, so planning allocates nothing.
class SpriteBatchPlan {
  /// The atlas image.
  ui.Image? image;

  /// How the atlas is sampled; batches are kept per image *and* quality.
  FilterQuality quality = FilterQuality.none;

  /// The source rectangle on the atlas.
  double left = 0, top = 0, right = 0, bottom = 0;

  /// The centre of the sprite, its turn and its uniform scale.
  double x = 0, y = 0, rotation = 0, scale = 1;

  /// The colour the sprite is multiplied by, as 0xAARRGGBB.
  int argb = 0xFFFFFFFF;

  /// Works out how [renderable] — a [BatchableSprite] — is batched; false
  /// when it cannot be, and must be drawn by itself.
  ///
  /// A batch draws each sprite with one rotation, one uniform scale and a
  /// translation, so only a sprite scaled the same way on both axes, and not
  /// mirrored by a negative scale, is batched. (Averaging the two, as the
  /// render systems once did, drew a (3, 1) sprite at 2 and made a (−1, 1)
  /// one vanish.) A [Sprite]'s render size is honoured when it keeps the
  /// source's proportions; a stretched one draws by itself. A sprite that is
  /// not a [Sprite] is sampled with [FilterQuality.none], as batches always
  /// were.
  bool plan(Renderable renderable) {
    final batchable = renderable as BatchableSprite;
    final atlas = batchable.batchImage;
    if (atlas == null) return false;
    final sx = renderable.scale.x;
    if (!(sx > 0) || sx != renderable.scale.y) return false;

    final src = batchable.batchSourceRect;
    left = src?.left ?? 0.0;
    top = src?.top ?? 0.0;
    right = src?.right ?? atlas.width.toDouble();
    bottom = src?.bottom ?? atlas.height.toDouble();

    scale = sx;
    quality = FilterQuality.none;
    if (renderable is Sprite) {
      quality = renderable.filterQuality;
      final size = renderable.renderSize;
      if (size != null) {
        final fit = uniformFit(size, right - left, bottom - top);
        if (fit == null) return false;
        scale *= fit;
      }
    }
    image = atlas;
    x = renderable.position.x;
    y = renderable.position.y;
    rotation = renderable.rotation;
    argb = spriteColor(renderable.tint, renderable.opacity);
    return true;
  }

  /// Queues the planned sprite into [batch].
  void addTo(SpriteBatchRenderer batch) {
    if (batch is SpriteBatch) {
      batch.addRaw(
        left: left,
        top: top,
        right: right,
        bottom: bottom,
        x: x,
        y: y,
        rotation: rotation,
        scale: scale,
        argb: argb,
      );
    } else {
      batch.add(
        sourceRect: Rect.fromLTRB(left, top, right, bottom),
        position: Offset(x, y),
        rotation: rotation,
        scale: scale,
        color: Color(argb),
      );
    }
  }

  /// How much [size] scales a source [width] × [height] when it keeps its
  /// proportions; null when it stretches one way more than the other.
  static double? uniformFit(Size size, double width, double height) {
    if (!(width > 0) || !(height > 0)) return null;
    final fx = size.width / width, fy = size.height / height;
    if (!(fx > 0) || (fx - fy).abs() > 1e-9 * math.max(fx, fy)) return null;
    return fx;
  }

  /// The colour a batched sprite is multiplied by, as 0xAARRGGBB: its
  /// [tint] with [opacity] for alpha, or white at [opacity] — the colour it
  /// was given as an object, `tint.withValues(alpha: opacity)` or
  /// `Color.fromRGBO(255, 255, 255, opacity)`, without making one.
  static int spriteColor(Color? tint, double opacity) {
    // Both colours hold opacity as their alpha, and reached the canvas as
    // toARGB32(), which rounds it to 8 bits.
    final alpha = (opacity * 255.0).round().clamp(0, 255);
    return (alpha << 24) |
        (tint == null ? 0x00FFFFFF : tint.toARGB32() & 0x00FFFFFF);
  }
}

/// Sprite batches by atlas image — the image object itself, not a hash of
/// it, which two images can share — then by filter quality.
///
/// A frame is bracketed by [beginFrame] and [endFrame]; a batch the frame
/// did not use is dropped at its end, so an image the level no longer shows
/// is not held on to.
class SpriteBatchCache {
  /// An empty cache whose batches [factory] makes (plain [SpriteBatch]es
  /// when null).
  SpriteBatchCache([this.factory]);

  /// Makes a batch for an image; null makes a [SpriteBatch].
  SpriteBatchFactory? factory;

  final Map<ui.Image, _BatchSlot> _slots = LinkedHashMap.identity();
  int _frame = 0;

  /// How many batches are kept.
  int get length {
    var n = 0;
    for (final slot in _slots.values) {
      for (final batch in slot.batches) {
        if (batch != null) n++;
      }
    }
    return n;
  }

  /// Starts a frame.
  void beginFrame() => _frame++;

  /// The batch for [image] sampled with [quality], made on first use. A
  /// [SpriteBatch] from the [factory] is set to [quality].
  SpriteBatchRenderer batchFor(ui.Image image, FilterQuality quality) {
    final slot = _slots[image] ??= _BatchSlot();
    final index = quality.index;
    slot.used[index] = _frame;
    var batch = slot.batches[index];
    if (batch == null) {
      final make = factory;
      batch = make == null
          ? SpriteBatch(image, filterQuality: quality)
          : make(image);
      if (batch is SpriteBatch) batch.filterQuality = quality;
      slot.batches[index] = batch;
    }
    return batch;
  }

  /// Ends a frame: drops the batches it did not use.
  void endFrame() => _slots.removeWhere((_, slot) => !slot.keepOnly(_frame));

  /// Drops every batch.
  void clear() => _slots.clear();
}

/// One image's batches, one per filter quality, and the frame each was
/// last used in.
class _BatchSlot {
  final List<SpriteBatchRenderer?> batches = List.filled(
    FilterQuality.values.length,
    null,
  );
  final List<int> used = List.filled(FilterQuality.values.length, -1);

  /// Drops the batches not used in [frame]; false when none is left.
  bool keepOnly(int frame) {
    var any = false;
    for (var i = 0; i < batches.length; i++) {
      if (batches[i] == null) continue;
      if (used[i] == frame) {
        any = true;
      } else {
        batches[i] = null;
      }
    }
    return any;
  }
}

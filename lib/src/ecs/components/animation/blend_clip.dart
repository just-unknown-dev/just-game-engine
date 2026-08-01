/// Blend Clip & Frame Sources
///
/// Per-clip playback metadata (fps, frame count) plus where its pixels
/// come from. [GridBlendFrameSource] covers both this engine's real
/// sprite-sheet conventions with one class: a dedicated image per clip
/// (the common case — `originX`/`originY` stay 0) and a shared atlas sheet
/// (a fixed grid origin offset into one shared [BlendFrameSource.image]).
library;

import 'dart:ui' as ui;
import 'package:flutter/painting.dart' show Rect;

/// Where a [BlendClip]'s pixels live and how to find frame `n`'s rect.
abstract class BlendFrameSource {
  /// The decoded sheet image. `null` until loading completes — a state
  /// referencing a clip whose source has no image yet simply contributes
  /// no visible layer that frame (see `AnimationBlendTreeSystem`).
  ui.Image? image;

  /// The source rect for [frame] (0-based) at directional [row] (0 when
  /// the source has no directional rows).
  Rect frameRect(int frame, int row);
}

/// A fixed-size grid frame source — the common case for this engine's
/// sprite sheets (uniform frame size, N columns x M directional rows).
class GridBlendFrameSource extends BlendFrameSource {
  GridBlendFrameSource({
    ui.Image? image,
    required this.frameWidth,
    required this.frameHeight,
    required this.columns,
    required this.rows,
    this.originX = 0,
    this.originY = 0,
  }) {
    this.image = image;
  }

  final double frameWidth;
  final double frameHeight;
  final int columns;
  final int rows;

  /// Pixel offset of the grid's top-left cell within [image] — 0 for a
  /// dedicated per-clip image, non-zero when [image] is a shared atlas
  /// sheet and this clip occupies one region of it.
  final double originX;
  final double originY;

  @override
  Rect frameRect(int frame, int row) => Rect.fromLTWH(
    originX + frame.clamp(0, columns - 1) * frameWidth,
    originY + row.clamp(0, rows - 1) * frameHeight,
    frameWidth,
    frameHeight,
  );
}

/// Playback metadata for one named animation clip: how fast it plays, how
/// many frames it has, and where its pixels come from ([frameSource]).
class BlendClip {
  BlendClip({
    required this.name,
    required this.fps,
    required this.frameCount,
    this.assetPath,
    this.frameWidth,
    this.frameHeight,
    this.columns,
    this.rows,
    this.frameSource,
  });

  final String name;
  final double fps;
  final int frameCount;

  /// Optional asset path for a loader to resolve an image from and attach
  /// to [frameSource].
  final String? assetPath;
  final double? frameWidth;
  final double? frameHeight;
  final int? columns;
  final int? rows;

  /// Where this clip's frames come from. When constructed via [fromJson]
  /// with a complete grid description, this is already populated with a
  /// [GridBlendFrameSource] whose `image` is still `null` — a loader only
  /// needs to load [assetPath] and assign it to `frameSource!.image`.
  BlendFrameSource? frameSource;

  factory BlendClip.fromJson(Map<String, dynamic> json) {
    final frameWidth = (json['frameWidth'] as num?)?.toDouble();
    final frameHeight = (json['frameHeight'] as num?)?.toDouble();
    final columns = (json['columns'] as num?)?.toInt();
    final rows = (json['rows'] as num?)?.toInt();
    final hasGrid =
        frameWidth != null &&
        frameHeight != null &&
        columns != null &&
        rows != null;

    return BlendClip(
      name: json['name'] as String,
      fps: (json['fps'] as num).toDouble(),
      frameCount: (json['frameCount'] as num).toInt(),
      assetPath: json['assetPath'] as String?,
      frameWidth: frameWidth,
      frameHeight: frameHeight,
      columns: columns,
      rows: rows,
      frameSource: hasGrid
          ? GridBlendFrameSource(
              frameWidth: frameWidth,
              frameHeight: frameHeight,
              columns: columns,
              rows: rows,
            )
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'fps': fps,
    'frameCount': frameCount,
    if (assetPath != null) 'assetPath': assetPath,
    if (frameWidth != null) 'frameWidth': frameWidth,
    if (frameHeight != null) 'frameHeight': frameHeight,
    if (columns != null) 'columns': columns,
    if (rows != null) 'rows': rows,
  };
}

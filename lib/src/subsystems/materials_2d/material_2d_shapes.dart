/// Shapes drawn through a 2-D material: each drawn once into an image, which
/// the material then draws like a sprite's sheet.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:just_dart/just_dart.dart' show Vector3;

import '../../ecs/ecs.dart';
import '../rendering/impl/renderable.dart';

/// What a shape drawn through a 2-D material is drawn from: the shape drawn
/// into an image in its own space, its box ([bounds]) and how many image
/// pixels a unit of that space is ([resolution]).
final class ShapeSheet {
  ShapeSheet._(this.image, this.bounds, this.resolution, this._signature);

  final ui.Image image;
  final Rect bounds;
  final double resolution;
  final Object _signature;
  int _used = 0;

  /// The whole image, as a frame of the sheet.
  Rect get frame =>
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
}

/// Each entity's shape drawn into an image, kept while it looks the same.
///
/// A shape is drawn again only when what it is drawn from — [sheetOf]'s
/// `signature`, its box or the resolution it is drawn at — changes; one not
/// asked for in a frame is let go. Images are let go a frame after they are
/// last drawn with.
final class ShapeSheets {
  final Map<Entity, ShapeSheet> _sheets = Map.identity();
  final List<ui.Image> _gone = [];
  final List<ui.Image> _going = [];
  int _frame = 0;

  /// The largest side an image is drawn at.
  static const int maxSide = 2048;

  /// How many entities' shapes are held. For tests.
  int get length => _sheets.length;

  /// Starts a frame.
  void beginFrame() {
    for (final i in _gone) {
      i.dispose();
    }
    _gone
      ..clear()
      ..addAll(_going);
    _going.clear();
    _sheets.removeWhere((_, sheet) {
      if (sheet._used >= _frame) return false;
      _going.add(sheet.image);
      return true;
    });
    _frame++;
  }

  /// [renderable] — [entity]'s, drawing itself in its own space around its
  /// origin — as an image, drawn at [scale] (how big a unit of its space is
  /// on screen, so it stays sharp); null when it has no box. Drawn again
  /// only when [signature] (what it looks like) or its box changes.
  ShapeSheet? sheetOf(
    Entity entity,
    Renderable renderable,
    Object signature,
    double scale,
  ) {
    final bounds = renderable.getBounds();
    if (bounds == null ||
        renderable.boundsAreWorldSpace ||
        bounds.isEmpty ||
        !bounds.isFinite) {
      return null;
    }
    final resolution = resolutionFor(scale, bounds);
    final known = _sheets[entity];
    if (known != null &&
        known._signature == signature &&
        known.bounds == bounds &&
        known.resolution == resolution) {
      known._used = _frame;
      return known;
    }
    final width = math.max(1, (bounds.width * resolution).ceil());
    final height = math.max(1, (bounds.height * resolution).ceil());
    // Drawn where it stands, unturned, unscaled, untinted and opaque: the
    // material places, tints and fades it as it does a sprite.
    final position = Vector3.copy(renderable.position);
    final rotation = renderable.rotation;
    final rscale = Vector3.copy(renderable.scale);
    final opacity = renderable.opacity;
    final tint = renderable.tint;
    renderable.position.setValues(0, 0, 0);
    renderable.rotation = 0;
    renderable.scale.setValues(1, 1, 1);
    renderable.opacity = 1;
    renderable.tint = null;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..scale(resolution)
      ..translate(-bounds.left, -bounds.top);
    try {
      renderable.render(canvas, Size(width.toDouble(), height.toDouble()));
    } finally {
      renderable.position.setFrom(position);
      renderable.rotation = rotation;
      renderable.scale.setFrom(rscale);
      renderable.opacity = opacity;
      renderable.tint = tint;
    }
    final picture = recorder.endRecording();
    final image = picture.toImageSync(width, height);
    picture.dispose();
    if (known != null) _going.add(known.image);
    final sheet = _sheets[entity] = ShapeSheet._(
      image,
      bounds,
      resolution,
      signature,
    ).._used = _frame;
    return sheet;
  }

  /// How many image pixels a unit of a shape's space gets, drawn at [scale]
  /// on screen: the next power of two at least as big, from 1 to 4, and no
  /// more than fits [maxSide].
  static double resolutionFor(double scale, Rect bounds) {
    var r = 1.0;
    while (r < scale && r < 4) {
      r *= 2;
    }
    final longest = math.max(bounds.width, bounds.height);
    while (r > 1 && longest * r > maxSide) {
      r /= 2;
    }
    return r;
  }

  /// Lets go of every image.
  void clear() {
    beginFrame();
    beginFrame();
    for (final s in _sheets.values) {
      s.image.dispose();
    }
    _sheets.clear();
  }
}

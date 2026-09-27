/// Tilesets the engine draws itself: no image file and no tileset file, so
/// they are in every project and every build.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'tileset_data.dart';

/// The tilesets that come with the engine, by their `builtin:` path.
///
/// **Basic shapes** ([basicShapes]) is plain geometry for blocking out a
/// level before there is art: a full block, half and quarter blocks, a
/// one-way plank, 45° and 22.5° slopes floor and ceiling, rounded corners,
/// a circle, a triangle, a diamond. Every tile collides as it looks — its
/// picture is drawn from the very shapes its collision is made of — in a
/// light slate a layer's tint recolours.
///
/// Its tile ids never change, and new tiles only ever go after the last,
/// so a map painted with it keeps meaning the same tiles.
abstract final class BuiltInTilesets {
  /// What every built-in path starts with. Never a file: nothing may hand
  /// such a path to a file system.
  static const String prefix = 'builtin:';

  /// The basic shapes tileset, as a map names it.
  static const String basicShapes = 'builtin:basic_shapes.tileset.json';

  /// Its picture, as the tileset names it.
  static const String basicShapesImage = 'builtin:basic_shapes.png';

  /// The size of its tiles.
  static const int tileSize = 32;

  /// Its tiles per row.
  static const int columns = 8;

  /// Every built-in tileset's path.
  static const List<String> all = [basicShapes];

  /// Whether [path] names a built-in tileset or picture.
  static bool isBuiltIn(String path) => path.startsWith(prefix);

  /// The built-in tileset at [path]; null when there is none.
  static TilesetData? tileset(String path) =>
      path == basicShapes ? _basic ??= _basicShapes() : null;

  /// The built-in picture at [path], drawn the first time it is asked for;
  /// null when there is none.
  static ui.Image? image(String path) {
    if (path != basicShapesImage) return null;
    return _basicImage ??= _draw(tileset(basicShapes)!);
  }

  static TilesetData? _basic;
  static ui.Image? _basicImage;

  // ── The tiles ────────────────────────────────────────────────────────────

  static const double _s = 32;
  static const double _h = _s / 2;

  static List<ui.Offset> _poly(List<(double, double)> points) => [
    for (final (x, y) in points) ui.Offset(x, y),
  ];

  /// A quarter of a disc of radius [_s] about [c] — a block with its far
  /// corner rounded off.
  static List<ui.Offset> _quarterDisc(ui.Offset c, double from) => [
    c,
    for (var i = 0; i <= 8; i++)
      c +
          ui.Offset(
            math.cos(from + i * math.pi / 16) * _s,
            math.sin(from + i * math.pi / 16) * _s,
          ),
  ];

  /// Each tile's collision: its kind, and its one shape.
  static final List<(String, TileShape)> _shapes = [
    // Row 0: blocks.
    ('solid', const TileRectShape(ui.Rect.fromLTWH(0, 0, _s, _s))),
    ('solid', const TileRectShape(ui.Rect.fromLTWH(0, 0, _s, _h))),
    ('solid', const TileRectShape(ui.Rect.fromLTWH(0, _h, _s, _h))),
    ('solid', const TileRectShape(ui.Rect.fromLTWH(0, 0, _h, _s))),
    ('solid', const TileRectShape(ui.Rect.fromLTWH(_h, 0, _h, _s))),
    ('oneWay', const TileRectShape(ui.Rect.fromLTWH(0, 0, _s, 8))),
    ('solid', const TileRectShape(ui.Rect.fromLTWH(0, 0, _h, _h))),
    ('solid', const TileRectShape(ui.Rect.fromLTWH(_h, 0, _h, _h))),
    // Row 1: slopes, 45° floor and ceiling, then 22.5° floor pairs.
    ('solid', TilePolygonShape(_poly([(0, _s), (_s, 0), (_s, _s)]))),
    ('solid', TilePolygonShape(_poly([(0, 0), (_s, _s), (0, _s)]))),
    ('solid', TilePolygonShape(_poly([(0, 0), (_s, 0), (_s, _s)]))),
    ('solid', TilePolygonShape(_poly([(0, 0), (_s, 0), (0, _s)]))),
    ('solid', TilePolygonShape(_poly([(0, _s), (_s, _h), (_s, _s)]))),
    ('solid', TilePolygonShape(_poly([(0, _h), (_s, 0), (_s, _s), (0, _s)]))),
    ('solid', TilePolygonShape(_poly([(0, 0), (_s, _h), (_s, _s), (0, _s)]))),
    ('solid', TilePolygonShape(_poly([(0, _h), (_s, _s), (0, _s)]))),
    // Row 2: rounded corners — top-left, top-right, bottom-left,
    // bottom-right — then a circle, a triangle, a diamond, a small block.
    ('solid', TilePolygonShape(_quarterDisc(const ui.Offset(_s, _s), math.pi))),
    (
      'solid',
      TilePolygonShape(_quarterDisc(const ui.Offset(0, _s), 1.5 * math.pi)),
    ),
    (
      'solid',
      TilePolygonShape(_quarterDisc(const ui.Offset(_s, 0), 0.5 * math.pi)),
    ),
    ('solid', TilePolygonShape(_quarterDisc(ui.Offset.zero, 0))),
    ('solid', const TileEllipseShape(ui.Rect.fromLTWH(0, 0, _s, _s))),
    ('solid', TilePolygonShape(_poly([(0, _s), (_h, 0), (_s, _s)]))),
    ('solid', TilePolygonShape(_poly([(_h, 0), (_s, _h), (_h, _s), (0, _h)]))),
    ('solid', const TileRectShape(ui.Rect.fromLTWH(8, 8, _h, _h))),
  ];

  static TilesetData _basicShapes() {
    final rows = (_shapes.length / columns).ceil();
    final ts = TilesetData(
      name: 'Basic shapes',
      image: basicShapesImage,
      imageWidth: columns * tileSize,
      imageHeight: rows * tileSize,
      tileWidth: tileSize,
      tileHeight: tileSize,
      columns: columns,
      tileCount: _shapes.length,
    );
    for (var id = 0; id < _shapes.length; id++) {
      final (kind, shape) = _shapes[id];
      ts.tileOrNew(id).collision = TileCollision(kind: kind, shapes: [shape]);
    }
    return ts;
  }

  // ── The picture ──────────────────────────────────────────────────────────

  static const ui.Color _fill = ui.Color(0xFFCFD8DC);
  static const ui.Color _edge = ui.Color(0xFF607D8B);
  static const ui.Color _oneWay = ui.Color(0xFFFFE082);

  static ui.Image _draw(TilesetData ts) {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final fill = ui.Paint()..isAntiAlias = true;
    final edge = ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = _edge
      ..isAntiAlias = true;
    for (var id = 0; id < ts.tileCount; id++) {
      final collision = ts.tile(id)!.collision!;
      final at = ui.Offset(
        (id % columns) * tileSize.toDouble(),
        (id ~/ columns) * tileSize.toDouble(),
      );
      fill.color = collision.kind == 'oneWay' ? _oneWay : _fill;
      for (final shape in collision.shapes) {
        final path = switch (shape) {
          TileEllipseShape(:final bounds) =>
            ui.Path()..addOval(bounds.shift(at).deflate(0.75)),
          _ =>
            ui.Path()..addPolygon([
              for (final p in shape.outline()) _inset(p, at),
            ], true),
        };
        canvas
          ..drawPath(path, fill)
          ..drawPath(path, edge);
      }
    }
    return recorder.endRecording().toImageSync(ts.imageWidth, ts.imageHeight);
  }

  /// [p] of a tile placed at [at], pulled in from the tile's edges so its
  /// outline is not cut in half by the next tile.
  static ui.Offset _inset(ui.Offset p, ui.Offset at) =>
      at +
      ui.Offset(
        p.dx.clamp(0.75, _s - 0.75).toDouble(),
        p.dy.clamp(0.75, _s - 0.75).toDouble(),
      );
}

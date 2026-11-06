/// Sprites sharing a 2-D material and a sheet, drawn in one call.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:just_game_engine_formats/just_game_engine_formats.dart';
import 'package:meta/meta.dart' show internal;

import '../../../rendering/sprite.dart';
import 'material_2d_library.dart';
import 'material_2d_shader.dart';

/// Sprites drawn with one 2-D material from one sheet, queued to be drawn
/// together: one `drawVertices` call through the material's shader, each
/// sprite a quad, with what differs per sprite — its frame, tint, place and
/// overridden values — in a small params image made at [flush].
///
/// One batch draws at a time, so nothing is drawn out of order: whoever
/// queues sprites [flush]es before drawing anything else. Images and shaders
/// a frame made are let go at the next [beginFrame].
@internal
final class Material2DBatch {
  /// A batch drawing through [library]'s shader.
  Material2DBatch(this.library);

  /// Where the shaders come from: the engine's 2-D material library.
  final Material2DLibrary library;

  String _path = '';
  Material2DFile? _file;
  bool _normals = false;
  ui.Image? _image, _normalMap;
  FilterQuality _quality = FilterQuality.none;
  double _unitScale = 1;

  /// Each overrides map seen lately — by the map itself, as a component
  /// hands out the same one until it changes — with what it was worked out
  /// to be: worked out once, not for every sprite every frame.
  final Map<Map<String, Object>, _Overrides> _known = Map.identity();
  int _frame = 0;

  final List<_Slot> _slots = [];
  int _used = 0;
  double _maxWidth = 0, _maxHeight = 0, _reach = 0;
  double? _fileReach;
  final Set<String> _dynamic = {};

  // What the last frame drew with, let go once it is drawn.
  final List<ui.Image> _images = [];
  final List<ui.FragmentShader> _shaders = [];
  final List<ui.Image> _oldImages = [];
  final List<ui.FragmentShader> _oldShaders = [];
  ui.Image? _white;

  /// Whether nothing is queued.
  bool get isEmpty => _used == 0;

  /// How many sprites are queued.
  int get length => _used;

  /// The material path the queued sprites are drawn with.
  String get path => _path;

  /// Starts a frame: what the frame before made is let go.
  void beginFrame() {
    _frame++;
    // Overrides not used in the last frame are forgotten.
    _known.removeWhere((_, o) => o.used < _frame - 1);
    for (final i in _oldImages) {
      i.dispose();
    }
    for (final s in _oldShaders) {
      s.dispose();
    }
    _oldImages
      ..clear()
      ..addAll(_images);
    _oldShaders
      ..clear()
      ..addAll(_shaders);
    _images.clear();
    _shaders.clear();
  }

  /// Whether a sprite drawn with the material at [path] from [image] at
  /// [quality], [unitScale] pixels a unit (see [begin]), can join what is
  /// queued.
  bool accepts(
    String path,
    ui.Image image,
    FilterQuality quality, {
    double unitScale = 1,
  }) {
    final mine = _image;
    return path == _path &&
        quality == _quality &&
        unitScale == _unitScale &&
        mine != null &&
        (identical(mine, image) || mine.isCloneOf(image));
  }

  /// Starts queuing sprites drawn with [file] (resolved, from [path]) from
  /// [image] at [quality]. Only when [isEmpty].
  ///
  /// With [normals], what is drawn is their normals, for 2-D lighting
  /// (`material_2d_normals.frag`): their shape from [image], their normals
  /// from [normalMap] (repeated where it is smaller than [image]), flat
  /// without one.
  ///
  /// [unitScale] is how many of [image]'s pixels a unit of the world is
  /// where it is drawn at its own size: 1 for a sprite's sheet or a
  /// tileset, a shape's sheet's `ShapeSheet.resolution`. The material's
  /// lengths — an outline's width, a glow's radius, a wave, a scroll, a
  /// shadow's offset, the dissolve's grain — are in those pixels, so they
  /// are multiplied by it, and an effect stays the same size in the world
  /// whatever the sheet was drawn at.
  void begin(
    String path,
    Material2DFile file,
    ui.Image image,
    FilterQuality quality, {
    bool normals = false,
    ui.Image? normalMap,
    double unitScale = 1,
  }) {
    assert(isEmpty, 'Flush the batch before starting another');
    _path = path;
    _file = file;
    _image = image;
    _quality = quality;
    _normals = normals;
    _normalMap = normalMap;
    _unitScale = unitScale;
    _maxWidth = _maxHeight = _reach = 0;
    _fileReach = null;
    _dynamic.clear();
  }

  /// Queues [sprite] — of an entity [seed] stands for, with its own
  /// [overrides] — false when it cannot join: a frame packed turned on its
  /// sheet, or no room left in the batch (flush, begin and add again).
  bool addSprite(
    Sprite sprite, {
    required int seed,
    required Map<String, Object> overrides,
  }) {
    // Drawn where the sprite draws it: its frame over its box placed by its
    // pivot — a trimmed frame where the exporter cut it from.
    final src = sprite.drawnSourceRect;
    final dest = sprite.localRect;
    if (src == null || dest == null || sprite.batchTurned) return false;
    return addBox(
      src,
      dest,
      x: sprite.position.x,
      y: sprite.position.y,
      rotation: sprite.rotation,
      scaleX: sprite.scale.x,
      scaleY: sprite.scale.y,
      flipX: sprite.flipX,
      flipY: sprite.flipY,
      tint: sprite.tint,
      opacity: sprite.opacity,
      seed: seed,
      overrides: overrides,
    );
  }

  /// Queues [frame] of the sheet drawn over [dest] — a box in something's
  /// own space, centred on it — mirrored by [flipX] and [flipY], scaled,
  /// turned by [rotation] and moved to ([x], [y]) as a renderable is, and
  /// tinted by [tint] at [opacity]. False when there is no room left.
  bool addBox(
    Rect frame,
    Rect dest, {
    required double x,
    required double y,
    double rotation = 0,
    double scaleX = 1,
    double scaleY = 1,
    bool flipX = false,
    bool flipY = false,
    Color? tint,
    double opacity = 1,
    int seed = 0,
    Map<String, Object> overrides = const {},
  }) {
    if (!(frame.width > 0) || !(frame.height > 0)) return false;
    final kx = dest.width / frame.width, ky = dest.height / frame.height;
    final fx = flipX ? -1.0 : 1.0, fy = flipY ? -1.0 : 1.0;
    final cs = math.cos(rotation), sn = math.sin(rotation);
    // Frame pixels (u, v) to the world: the frame laid on its box, mirrored,
    // scaled, turned and moved.
    return addFrame(
      frame,
      a: cs * scaleX * fx * kx,
      b: sn * scaleX * fx * kx,
      c: -sn * scaleY * fy * ky,
      d: cs * scaleY * fy * ky,
      e: x + cs * scaleX * fx * dest.left - sn * scaleY * fy * dest.top,
      f: y + sn * scaleX * fx * dest.left + cs * scaleY * fy * dest.top,
      rgb: (tint?.toARGB32() ?? 0xFFFFFFFF) & 0x00FFFFFF,
      alpha: (Sprite.tintedAlpha(tint, opacity) * 255).round().clamp(0, 255),
      x: x,
      y: y,
      seed: seed,
      overrides: overrides,
    );
  }

  /// Queues [frame] of the sheet, each of its pixels (u, v) drawn at
  /// (a·u + c·v + e, b·u + d·v + f): coloured by [rgb] at [alpha] (0-255),
  /// at ([x], [y]) for what waves across the world, [seed] picking its own
  /// dissolve pattern, with its own [overrides]. False when there is no room
  /// left in the batch (flush, begin and add again).
  bool addFrame(
    Rect frame, {
    required double a,
    required double b,
    required double c,
    required double d,
    required double e,
    required double f,
    int rgb = 0xFFFFFF,
    int alpha = 255,
    double x = 0,
    double y = 0,
    int seed = 0,
    Map<String, Object> overrides = const {},
  }) {
    final file = _file;
    if (file == null || !(frame.width > 0) || !(frame.height > 0)) {
      return false;
    }
    // Room for it, with its effects' reach, in the grid.
    final own = overrides.isEmpty ? null : _overridesOf(overrides, file);
    final valid = own?.valid ?? const <String, Object>{};
    final reach =
        own?.reach ??
        (_fileReach ??= Material2DShader.reach(
          file,
          const {},
          unitScale: _unitScale,
        ));
    final width = math.max(_maxWidth, frame.width),
        height = math.max(_maxHeight, frame.height);
    final pad = (math.max(_reach, reach) + 1).ceilToDouble();
    final slotW = (width + pad * 2).ceilToDouble(),
        slotH = (height + pad * 2).ceilToDouble();
    final perRow = Material2DShader.maxGrid ~/ slotW;
    if (perRow < 1) return false;
    final rows = (_used + 1 + perRow - 1) ~/ perRow;
    if (rows * slotH > Material2DShader.maxGrid || (_used + 1) * 4 > 65535) {
      return false;
    }

    _maxWidth = width;
    _maxHeight = height;
    _reach = math.max(_reach, reach);
    if (own != null) _dynamic.addAll(own.columns);

    final slot = _used < _slots.length
        ? _slots[_used]
        : (_slots..add(_Slot())).last;
    _used++;
    slot
      ..frame = frame
      ..a = a
      ..b = b
      ..c = c
      ..d = d
      ..e = e
      ..f = f
      ..reach = reach
      ..rgb = rgb & 0x00FFFFFF
      ..alpha = alpha
      // Where it is, in the sheet's pixels, as the wave reads it.
      ..x = x * _unitScale
      ..y = y * _unitScale
      ..seed = seed & 0xFFFF
      ..overrides = valid;
    return true;
  }

  /// What [overrides] count as for [file] at this batch's scale: the
  /// values that may be overridden, how far they reach, and the shader's
  /// columns they need — worked out once while the same map, with the
  /// same values, keeps coming.
  _Overrides _overridesOf(Map<String, Object> overrides, Material2DFile file) {
    final known = _known[overrides];
    if (known != null &&
        identical(known.file, file) &&
        known.unitScale == _unitScale &&
        known.holds(overrides)) {
      known.used = _frame;
      return known;
    }
    final valid = <String, Object>{
      for (final e in overrides.entries)
        if (Material2DShader.overrides(e.key, e.value)) e.key: e.value,
    };
    final columns = <String>[];
    for (final key in valid.keys) {
      final effect = key.substring(0, key.indexOf('.'));
      if (!file.isOn(effect)) continue;
      if (Material2DShader.dynamicKeys.contains(key)) {
        columns.add(key);
      } else if (Material2DShader.dynamicKeys.contains('$key#0')) {
        columns
          ..add('$key#0')
          ..add('$key#1');
      }
    }
    final made = _known[overrides] = _Overrides(
      Map.of(overrides),
      valid,
      file,
      _unitScale,
      Material2DShader.reach(file, valid, unitScale: _unitScale),
      columns,
    )..used = _frame;
    return made;
  }

  /// Draws what is queued onto [canvas] — [time] seconds into the game, for
  /// what moves — and empties the batch. Draws nothing until the shader is
  /// loaded.
  void flush(Canvas canvas, double time) {
    final draw = take();
    if (draw == null) return;
    redraw(canvas, draw, time);
    release(draw);
  }

  /// Draws [draw] — made by [take], not yet [release]d — onto [canvas],
  /// [time] seconds into the game. Only the time is new: what was queued
  /// is drawn as it was, without being queued again.
  void redraw(Canvas canvas, Material2DDraw draw, double time) {
    assert(!draw._released, 'A released draw cannot be drawn');
    _shaders.add(draw._paint(canvas, time));
  }

  /// Hands [draw] back: what it holds is let go of — its params image at a
  /// later [beginFrame], as the batch's own are.
  void release(Material2DDraw draw) {
    if (draw._released) return;
    draw._released = true;
    draw._vertices.dispose();
    _images.add(draw._params);
  }

  /// What is queued, made into a [Material2DDraw] the caller keeps — to
  /// draw now and in later frames ([redraw]) for as long as nothing in it
  /// changes, then [release] — and the batch emptied. Null when nothing is
  /// queued or the shader is not loaded yet (the batch is emptied all the
  /// same).
  Material2DDraw? take() {
    if (_used == 0) return null;
    final program = _normals ? library.normalsProgram : library.program;
    final file = _file;
    final image = _image;
    if (program == null || file == null || image == null) {
      _used = 0;
      return null;
    }
    final pad = (_reach + 1).ceilToDouble();
    final slotW = (_maxWidth + pad * 2).ceilToDouble();
    final slotH = (_maxHeight + pad * 2).ceilToDouble();
    final perRow = math.max(1, Material2DShader.maxGrid ~/ slotW);

    // Where each overridden value is in a row; drawing normals, each
    // sprite's turn and mirroring instead.
    final columns = <String, int>{};
    var width = Material2DShader.fixedColumns;
    if (_normals) {
      width += 4;
    } else {
      for (final key in Material2DShader.dynamicKeys) {
        if (!_dynamic.contains(key)) continue;
        columns[key] = width;
        width += Material2DShader.columnsOf(key);
      }
    }
    final params = _params(file, columns, width);

    final positions = Float32List(_used * 8);
    final coords = Float32List(_used * 8);
    final indices = Uint16List(_used * 6);
    for (var i = 0; i < _used; i++) {
      final s = _slots[i];
      final ox = (i % perRow) * slotW + pad, oy = (i ~/ perRow) * slotH + pad;
      final r = s.reach;
      // The frame grown by its reach, corner by corner: (u0, v0), (u1, v0),
      // (u1, v1), (u0, v1) in frame pixels.
      final u0 = -r, v0 = -r;
      final u1 = s.frame.width + r, v1 = s.frame.height + r;
      final k = i * 8;
      positions
        ..[k] = s.a * u0 + s.c * v0 + s.e
        ..[k + 1] = s.b * u0 + s.d * v0 + s.f
        ..[k + 2] = s.a * u1 + s.c * v0 + s.e
        ..[k + 3] = s.b * u1 + s.d * v0 + s.f
        ..[k + 4] = s.a * u1 + s.c * v1 + s.e
        ..[k + 5] = s.b * u1 + s.d * v1 + s.f
        ..[k + 6] = s.a * u0 + s.c * v1 + s.e
        ..[k + 7] = s.b * u0 + s.d * v1 + s.f;
      coords
        ..[k] = ox + u0
        ..[k + 1] = oy + v0
        ..[k + 2] = ox + u1
        ..[k + 3] = oy + v0
        ..[k + 4] = ox + u1
        ..[k + 5] = oy + v1
        ..[k + 6] = ox + u0
        ..[k + 7] = oy + v1;
      final at = i * 4, j = i * 6;
      indices
        ..[j] = at
        ..[j + 1] = at + 1
        ..[j + 2] = at + 2
        ..[j + 3] = at
        ..[j + 4] = at + 2
        ..[j + 5] = at + 3;
    }

    final draw = Material2DDraw._(
      program: program,
      file: file,
      normals: _normals,
      image: image,
      normalMap: _normalMap,
      quality: _quality,
      slotWidth: slotW,
      slotHeight: slotH,
      perRow: perRow,
      pad: pad,
      paramsWidth: width,
      length: _used,
      columns: columns,
      vertices: ui.Vertices.raw(
        ui.VertexMode.triangles,
        positions,
        textureCoordinates: coords,
        indices: indices,
      ),
      params: params,
      unitScale: _unitScale,
    );
    _used = 0;
    return draw;
  }

  /// The params image: a row per sprite, [width] columns, each pixel opaque
  /// so nothing is premultiplied away.
  ui.Image _params(Material2DFile file, Map<String, int> columns, int width) {
    // ARGB by column and row; 0 where nothing is put (all put are opaque).
    final cells = Int32List(width * _used);
    void put(int column, int row, int argb) =>
        cells[row * width + column] = argb;

    int u16(double v) {
      final i = v.round().clamp(0, 65535);
      return 0xFF000000 | ((i >> 8) << 16) | ((i & 0xFF) << 8);
    }

    int wrapped(double v) => ((v.round() % 65536) + 65536) % 65536;

    for (var row = 0; row < _used; row++) {
      final s = _slots[row];
      put(0, row, u16(s.frame.left));
      put(1, row, u16(s.frame.top));
      put(2, row, u16(s.frame.width));
      put(3, row, u16(s.frame.height));
      put(4, row, 0xFF000000 | s.rgb);
      put(5, row, 0xFF000000 | (s.alpha << 16));
      put(6, row, u16(wrapped(s.x).toDouble()));
      put(7, row, u16(wrapped(s.y).toDouble()));
      put(8, row, u16(s.seed.toDouble()));
      if (_normals) {
        int half(double v) {
          final h = Material2DShader.halfOf(v);
          return 0xFF000000 | ((h >> 8) << 16) | ((h & 0xFF) << 8);
        }

        put(9, row, half(s.a));
        put(10, row, half(s.b));
        put(11, row, half(s.c));
        put(12, row, half(s.d));
      }
      for (final MapEntry(:key, value: column) in columns.entries) {
        if (Material2DShader.isColor(key)) {
          final c = Material2DShader.color(
            file,
            s.overrides,
            Material2DShader.paramOf(key),
          );
          put(column, row, 0xFF000000 | (c & 0x00FFFFFF));
          put(column + 1, row, 0xFF000000 | (((c >> 24) & 0xFF) << 16));
        } else {
          final v = Material2DShader.number(file, s.overrides, key);
          final h = Material2DShader.halfOf(
            Material2DShader.lengthKeys.contains(key) ? v * _unitScale : v,
          );
          put(column, row, 0xFF000000 | ((h >> 8) << 16) | ((h & 0xFF) << 8));
        }
      }
    }
    return _imageOf(cells, width, _used);
  }

  /// Whether images can be made from their pixels here (Impeller can; Skia
  /// and the web cannot): null until a batch has tried.
  bool? _uploads;

  /// [cells] (ARGB, row by row, [width] × [height]) as an image.
  ///
  /// Uploaded from its pixels where the renderer can. Drawn with
  /// `toImageSync` instead — a fresh image each flush, sampled inside other
  /// offscreen work (the shader's own texture of a `drawVertices`, the lit
  /// frame) — Impeller on Windows held on to GPU memory until the card was
  /// full: a lit cave of 180 sprites took 7 GB and ran at 4 fps.
  ui.Image _imageOf(Int32List cells, int width, int height) {
    if (_uploads ?? true) {
      final pixels = Uint8List(cells.length * 4);
      for (var i = 0; i < cells.length; i++) {
        final c = cells[i];
        if (c == 0) continue;
        final o = i * 4;
        pixels
          ..[o] = (c >> 16) & 0xFF
          ..[o + 1] = (c >> 8) & 0xFF
          ..[o + 2] = c & 0xFF
          ..[o + 3] = (c >> 24) & 0xFF;
      }
      try {
        final image = ui.decodeImageFromPixelsSync(
          pixels,
          width,
          height,
          ui.PixelFormat.rgba8888,
        );
        _uploads = true;
        return image;
      } on Object {
        // Not here (Skia, the web): drawn from now on.
        _uploads = false;
      }
    }
    final white = _white ??= _whitePixel();
    var count = 0;
    for (final c in cells) {
      if (c != 0) count++;
    }
    final transforms = Float32List(count * 4);
    final rects = Float32List(count * 4);
    final colors = Int32List(count);
    var n = 0;
    for (var i = 0; i < cells.length; i++) {
      final c = cells[i];
      if (c == 0) continue;
      final t = n * 4;
      transforms
        ..[t] = 1
        ..[t + 1] = 0
        ..[t + 2] = (i % width).toDouble()
        ..[t + 3] = (i ~/ width).toDouble();
      rects
        ..[t] = 0
        ..[t + 1] = 0
        ..[t + 2] = 1
        ..[t + 3] = 1;
      colors[n++] = c;
    }
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRawAtlas(
      white,
      transforms,
      rects,
      colors,
      BlendMode.modulate,
      null,
      Paint(),
    );
    final picture = recorder.endRecording();
    final image = picture.toImageSync(width, height);
    picture.dispose();
    return image;
  }

  static ui.Image _whitePixel() {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 1, 1),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    final picture = recorder.endRecording();
    final image = picture.toImageSync(1, 1);
    picture.dispose();
    return image;
  }

  /// Lets go of everything held.
  void dispose() {
    beginFrame();
    beginFrame();
    _white?.dispose();
    _white = null;
    _slots.clear();
    _known.clear();
    _used = 0;
  }
}

/// One overrides map worked out for a file at a scale; see
/// [Material2DBatch._overridesOf].
final class _Overrides {
  _Overrides(
    this.source,
    this.valid,
    this.file,
    this.unitScale,
    this.reach,
    this.columns,
  );

  /// The values it was worked out from, copied: a map changed in place is
  /// worked out again.
  final Map<String, Object> source;
  final Map<String, Object> valid;
  final Material2DFile file;
  final double unitScale;
  final double reach;

  /// The [Material2DShader.dynamicKeys] entries it needs columns for.
  final List<String> columns;
  int used = 0;

  /// Whether [overrides] still holds what it was worked out from.
  bool holds(Map<String, Object> overrides) {
    if (overrides.length != source.length) return false;
    for (final key in overrides.keys) {
      if (source[key] != overrides[key]) return false;
    }
    return true;
  }
}

final class _Slot {
  Rect frame = Rect.zero;
  double a = 1, b = 0, c = 0, d = 1, e = 0, f = 0;
  double reach = 0;
  int rgb = 0xFFFFFF;
  int alpha = 255;
  double x = 0, y = 0;
  int seed = 0;
  Map<String, Object> overrides = const {};
}

/// What a [Material2DBatch] had queued, made ready to draw — and to draw
/// again, frame after frame, while nothing in it changes: only the time the
/// material's moving effects run on is new each time. Made by
/// [Material2DBatch.take], drawn by [Material2DBatch.redraw], let go of by
/// [Material2DBatch.release].
@internal
final class Material2DDraw {
  Material2DDraw._({
    required ui.FragmentProgram program,
    required Material2DFile file,
    required bool normals,
    required ui.Image image,
    required ui.Image? normalMap,
    required FilterQuality quality,
    required double slotWidth,
    required double slotHeight,
    required int perRow,
    required double pad,
    required int paramsWidth,
    required this.length,
    required Map<String, int> columns,
    required ui.Vertices vertices,
    required ui.Image params,
    required double unitScale,
  }) : _program = program,
       _file = file,
       _normals = normals,
       _image = image,
       _normalMap = normalMap,
       _quality = quality,
       _slotWidth = slotWidth,
       _slotHeight = slotHeight,
       _perRow = perRow,
       _pad = pad,
       _paramsWidth = paramsWidth,
       _columns = columns,
       _vertices = vertices,
       _params = params,
       _unitScale = unitScale;

  final ui.FragmentProgram _program;
  final Material2DFile _file;
  final bool _normals;
  final ui.Image _image;
  final ui.Image? _normalMap;
  final FilterQuality _quality;
  final double _slotWidth, _slotHeight, _pad;
  final int _perRow, _paramsWidth;
  final Map<String, int> _columns;
  final ui.Vertices _vertices;
  final ui.Image _params;
  final double _unitScale;
  bool _released = false;

  /// How many sprites it draws.
  final int length;

  /// Draws it onto [canvas] through a new shader carrying [time]; returns
  /// the shader, to be let go of once the frame is drawn.
  ui.FragmentShader _paint(Canvas canvas, double time) {
    final shader = _program.fragmentShader();
    final image = _image;
    if (_normals) {
      Material2DShader.writeNormals(
        shader,
        _file,
        slotWidth: _slotWidth,
        slotHeight: _slotHeight,
        perRow: _perRow,
        pad: _pad,
        sheetWidth: image.width,
        sheetHeight: image.height,
        paramsWidth: _paramsWidth,
        paramsHeight: length,
        time: time,
        normalMap: _normalMap != null,
        mapWidth: (_normalMap ?? image).width,
        mapHeight: (_normalMap ?? image).height,
        unitScale: _unitScale,
      );
    } else {
      Material2DShader.write(
        shader,
        _file,
        slotWidth: _slotWidth,
        slotHeight: _slotHeight,
        perRow: _perRow,
        pad: _pad,
        sheetWidth: image.width,
        sheetHeight: image.height,
        paramsWidth: _paramsWidth,
        paramsHeight: length,
        time: time,
        dynamicColumns: _columns,
        unitScale: _unitScale,
      );
    }
    shader
      ..setImageSampler(0, image, filterQuality: _quality)
      ..setImageSampler(1, _params);
    if (_normals) {
      shader.setImageSampler(2, _normalMap ?? image, filterQuality: _quality);
    }
    canvas.drawVertices(_vertices, BlendMode.srcOver, Paint()..shader = shader);
    return shader;
  }
}

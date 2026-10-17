/// Sprites sharing a 2-D material and a sheet, drawn in one call.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:just_game_engine_formats/just_game_engine_formats.dart';

import '../rendering/impl/sprite.dart';
import '../sprite_atlas/sprite_atlas_subsystem.dart' show AtlasRegionSprite;
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
final class Material2DBatch {
  /// A batch drawing through [library]'s shader.
  Material2DBatch(this.library);

  final Material2DLibrary library;

  String _path = '';
  Material2DFile? _file;
  bool _normals = false, _normalMap = false;
  ui.Image? _image;
  FilterQuality _quality = FilterQuality.none;

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
  /// [quality] can join what is queued.
  bool accepts(String path, ui.Image image, FilterQuality quality) {
    final mine = _image;
    return path == _path &&
        quality == _quality &&
        mine != null &&
        (identical(mine, image) || mine.isCloneOf(image));
  }

  /// Starts queuing sprites drawn with [file] (resolved, from [path]) from
  /// [image] at [quality]. Only when [isEmpty].
  ///
  /// With [normals], what is drawn is their normals, for 2-D lighting
  /// (`material_2d_normals.frag`): [image] is then the sprites' normal map
  /// when [normalMap], else their sheet, whose shape is drawn flat.
  void begin(
    String path,
    Material2DFile file,
    ui.Image image,
    FilterQuality quality, {
    bool normals = false,
    bool normalMap = false,
  }) {
    assert(isEmpty, 'Flush the batch before starting another');
    _path = path;
    _file = file;
    _image = image;
    _quality = quality;
    _normals = normals;
    _normalMap = normalMap;
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
    final image = sprite.image;
    if (image == null) return false;
    final src =
        sprite.sourceRect ??
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    var dest = Rect.fromCenter(
      center: Offset.zero,
      width: (sprite.renderSize ?? src.size).width,
      height: (sprite.renderSize ?? src.size).height,
    );
    if (sprite is AtlasRegionSprite && sprite.region != null) {
      final region = sprite.region!;
      if (region.rotated) return false;
      if (AtlasRegionSprite.isTrimmedAway(region)) {
        // The untrimmed box is centred on the sprite; the frame sits in it
        // where the exporter cut it from.
        final box = region.sourceSize;
        dest = Rect.fromLTWH(
          -box.width / 2 + region.spriteSourceOffset.dx,
          -box.height / 2 + region.spriteSourceOffset.dy,
          region.frame.width,
          region.frame.height,
        );
      }
    }
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
    final valid = overrides.isEmpty
        ? const <String, Object>{}
        : <String, Object>{
            for (final e in overrides.entries)
              if (Material2DShader.overrides(e.key, e.value)) e.key: e.value,
          };
    final reach = valid.isEmpty
        ? (_fileReach ??= Material2DShader.reach(file, const {}))
        : Material2DShader.reach(file, valid);
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
    for (final key in valid.keys) {
      final effect = key.substring(0, key.indexOf('.'));
      if (!file.isOn(effect)) continue;
      if (Material2DShader.dynamicKeys.contains(key)) {
        _dynamic.add(key);
      } else if (Material2DShader.dynamicKeys.contains('$key#0')) {
        _dynamic
          ..add('$key#0')
          ..add('$key#1');
      }
    }

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
      ..x = x
      ..y = y
      ..seed = seed & 0xFFFF
      ..overrides = valid;
    return true;
  }

  /// Draws what is queued onto [canvas] — [time] seconds into the game, for
  /// what moves — and empties the batch. Draws nothing until the shader is
  /// loaded.
  void flush(Canvas canvas, double time) {
    if (_used == 0) return;
    final program = _normals ? library.normalsProgram : library.program;
    final file = _file;
    final image = _image;
    if (program == null || file == null || image == null) {
      _used = 0;
      return;
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
      final w = s.frame.width, h = s.frame.height;
      var k = i * 8;
      for (final (u, v) in [
        (-r, -r),
        (w + r, -r),
        (w + r, h + r),
        (-r, h + r),
      ]) {
        positions[k] = s.a * u + s.c * v + s.e;
        positions[k + 1] = s.b * u + s.d * v + s.f;
        coords[k] = ox + u;
        coords[k + 1] = oy + v;
        k += 2;
      }
      final v0 = i * 4;
      indices.setAll(i * 6, [v0, v0 + 1, v0 + 2, v0, v0 + 2, v0 + 3]);
    }

    final shader = program.fragmentShader();
    if (_normals) {
      Material2DShader.writeNormals(
        shader,
        file,
        slotWidth: slotW,
        slotHeight: slotH,
        perRow: perRow,
        pad: pad,
        sheetWidth: image.width,
        sheetHeight: image.height,
        paramsWidth: width,
        paramsHeight: _used,
        time: time,
        normalMap: _normalMap,
      );
    } else {
      Material2DShader.write(
        shader,
        file,
        slotWidth: slotW,
        slotHeight: slotH,
        perRow: perRow,
        pad: pad,
        sheetWidth: image.width,
        sheetHeight: image.height,
        paramsWidth: width,
        paramsHeight: _used,
        time: time,
        dynamicColumns: columns,
      );
    }
    shader
      ..setImageSampler(0, image, filterQuality: _quality)
      ..setImageSampler(1, params);
    final vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      positions,
      textureCoordinates: coords,
      indices: indices,
    );
    canvas.drawVertices(vertices, BlendMode.srcOver, Paint()..shader = shader);
    vertices.dispose();
    _images.add(params);
    _shaders.add(shader);
    _used = 0;
  }

  /// The params image: a row per sprite, [width] columns, each pixel opaque
  /// so nothing is premultiplied away.
  ui.Image _params(Material2DFile file, Map<String, int> columns, int width) {
    final white = _white ??= _whitePixel();
    final count = width * _used;
    final transforms = Float32List(count * 4);
    final rects = Float32List(count * 4);
    final colors = Int32List(count);
    var n = 0;
    void put(int column, int row, int argb) {
      final t = n * 4;
      transforms
        ..[t] = 1
        ..[t + 1] = 0
        ..[t + 2] = column.toDouble()
        ..[t + 3] = row.toDouble();
      rects
        ..[t] = 0
        ..[t + 1] = 0
        ..[t + 2] = 1
        ..[t + 3] = 1;
      colors[n++] = argb;
    }

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
        if (Material2DShader.isColour(key)) {
          final c = Material2DShader.colour(
            file,
            s.overrides,
            Material2DShader.paramOf(key),
          );
          put(column, row, 0xFF000000 | (c & 0x00FFFFFF));
          put(column + 1, row, 0xFF000000 | (((c >> 24) & 0xFF) << 16));
        } else {
          final h = Material2DShader.halfOf(
            Material2DShader.number(file, s.overrides, key),
          );
          put(column, row, 0xFF000000 | ((h >> 8) << 16) | ((h & 0xFF) << 8));
        }
      }
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
    final image = picture.toImageSync(width, _used);
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
    _used = 0;
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

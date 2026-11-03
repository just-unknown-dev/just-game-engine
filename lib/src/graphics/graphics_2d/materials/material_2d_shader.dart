/// How a 2-D material is handed to `shaders/material_2d.frag`: its uniforms,
/// the values an entity may override and where they go, and the numbers
/// packed into the params image.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:just_game_engine_formats/just_game_engine_formats.dart';

/// The layout `shaders/material_2d.frag` reads. Change one, change both.
abstract final class Material2DShader {
  /// The shader asset, as the engine's pubspec lists it.
  static const String asset = 'shaders/material_2d.frag';

  /// The screen materials' shader asset.
  static const String screenAsset = 'shaders/material_2d_screen.frag';

  /// The shader 2-D materials' normals are drawn through, for lighting.
  static const String normalsAsset = 'shaders/material_2d_normals.frag';

  /// The shader a lit frame is drawn through.
  static const String lightingAsset = 'shaders/lighting_2d.frag';

  /// The shader 2-D shadows are found with.
  static const String shadowsAsset = 'shaders/shadow_map_2d.frag';

  /// The columns every slot's row starts with: the frame's left, top, width
  /// and height; the sprite's tint (red, green, blue) and its alpha; where
  /// it is (x, y); a seed. Overridden values come after.
  static const int fixedColumns = 9;

  /// The most gradient stops and palette swaps drawn.
  static const int maxStops = 8, maxSwaps = 8;

  /// The widest and tallest the slot grid may be, in pixels.
  static const int maxGrid = 4096;

  /// Every value an entity can override, in the order `uDyn` keeps their
  /// columns. A pair's two numbers are `key#0` and `key#1`.
  static const List<String> dynamicKeys = [
    'wave.amplitude',
    'wave.wavelength',
    'wave.speed',
    'scroll.speed#0',
    'scroll.speed#1',
    'paletteSwap.tolerance',
    'gradientMap.amount',
    'greyscale.amount',
    'tint.colour',
    'flash.colour',
    'flash.amount',
    'dissolve.amount',
    'dissolve.edgeColour',
    'dissolve.edgeWidth',
    'dissolve.scale',
    'shine.colour',
    'shine.width',
    'shine.angle',
    'shine.duration',
    'shine.interval',
    'outline.colour',
    'outline.width',
    'glow.colour',
    'glow.radius',
    'glow.strength',
    'dropShadow.colour',
    'dropShadow.offset#0',
    'dropShadow.offset#1',
    'dropShadow.softness',
  ];

  /// How many params columns a dynamic key takes: two for a colour (its
  /// red, green and blue, then its alpha), one for a number.
  static int columnsOf(String key) => isColour(key) ? 2 : 1;

  /// Whether [key] (from [dynamicKeys]) is a colour.
  static bool isColour(String key) => key.endsWith('olour');

  /// The material key a dynamic key reads (`scroll.speed#0` reads
  /// `scroll.speed`).
  static String paramOf(String key) {
    final hash = key.indexOf('#');
    return hash < 0 ? key : key.substring(0, hash);
  }

  /// The number [key] (from [dynamicKeys]) has in [file], or in
  /// [overrides] when they give it.
  static double number(
    Material2DFile file,
    Map<String, Object> overrides,
    String key,
  ) {
    final hash = key.indexOf('#');
    final param = hash < 0 ? key : key.substring(0, hash);
    final own = overrides[param];
    if (hash < 0) {
      if (own is num) return own.toDouble();
      return file.number(param);
    }
    final i = int.parse(key.substring(hash + 1));
    // One number of the pair on its own (as a timeline keys it), or both.
    final part = overrides[key];
    if (part is num) return part.toDouble();
    if (own is List && own.length == 2 && own[i] is num) {
      return (own[i] as num).toDouble();
    }
    final (x, y) = file.pair(param);
    return i == 0 ? x : y;
  }

  /// The colour [key] has in [file], or in [overrides] when they give it.
  static int colour(
    Material2DFile file,
    Map<String, Object> overrides,
    String key,
  ) {
    final own = overrides[key];
    if (own is num) return own.toInt();
    return file.colour(key);
  }

  /// The overrides that can count: values a game may change, of the right
  /// type.
  static bool overrides(String key, Object value) {
    final hash = key.indexOf('#');
    if (hash >= 0) {
      // One number of a pair: `scroll.speed#0`.
      final pair = Material2DEffects.param(key.substring(0, hash));
      final i = key.substring(hash + 1);
      return pair != null &&
          pair.$2.type == Material2DValue.pair &&
          (i == '0' || i == '1') &&
          value is num;
    }
    final found = Material2DEffects.param(key);
    if (found == null || !found.$2.animatable) return false;
    return switch (found.$2.type) {
      Material2DValue.pair =>
        value is List && value.length == 2 && value.every((v) => v is num),
      _ => value is num,
    };
  }

  /// How far past its frame a sprite's effects reach, in frame pixels: the
  /// outline, glow and shadow around it and how far a wave moves it.
  static double reach(Material2DFile file, Map<String, Object> overrides) {
    double n(String key) => number(file, overrides, key).abs();
    var around = 0.0;
    if (file.isOn('outline')) around = math.max(around, n('outline.width'));
    if (file.isOn('glow')) around = math.max(around, n('glow.radius'));
    if (file.isOn('dropShadow')) {
      around = math.max(
        around,
        math.max(n('dropShadow.offset#0'), n('dropShadow.offset#1')) +
            n('dropShadow.softness'),
      );
    }
    final moved = file.isOn('wave') ? n('wave.amplitude') : 0.0;
    return around + moved;
  }

  // Uniform floats, by the vec4 they start.
  static const int _grid = 0,
      _sheet = 4,
      _time = 8,
      _on0 = 12,
      _on1 = 16,
      _on2 = 20;
  static const int _wave = 24,
      _scroll = 28,
      _amounts = 32,
      _tint = 36,
      _flash = 40;
  static const int _dissolveEdge = 44,
      _dissolveShine = 48,
      _shineColour = 52,
      _shine2 = 56;
  static const int _outlineColour = 60,
      _glowColour = 64,
      _shadow = 68,
      _shadowColour = 72;
  static const int _dyn = 76,
      _stopColours = 108,
      _stopAt = 140,
      _swapFrom = 172,
      _swapTo = 204;

  /// How many floats the shader's uniforms hold.
  static const int uniformFloats = 236;

  /// Writes [file]'s values — [file] resolved, with no parent — into
  /// [shader], for a batch whose slots are [slotWidth] × [slotHeight]
  /// pixels, [perRow] to a row, [pad] around each frame, over a sheet of
  /// [sheetWidth] × [sheetHeight] and a params image of [paramsWidth] ×
  /// [paramsHeight], at [time] seconds. [dynamicColumns] says where each
  /// overridden value is (by [dynamicKeys] entry); the rest are the file's.
  static void write(
    ui.FragmentShader shader,
    Material2DFile file, {
    required double slotWidth,
    required double slotHeight,
    required int perRow,
    required double pad,
    required int sheetWidth,
    required int sheetHeight,
    required int paramsWidth,
    required int paramsHeight,
    required double time,
    Map<String, int> dynamicColumns = const {},
  }) {
    final f = Float32List(uniformFloats);
    void vec4(int at, double x, double y, double z, double w) {
      f[at] = x;
      f[at + 1] = y;
      f[at + 2] = z;
      f[at + 3] = w;
    }

    void rgba(int at, int argb) => vec4(
      at,
      ((argb >> 16) & 0xFF) / 255,
      ((argb >> 8) & 0xFF) / 255,
      (argb & 0xFF) / 255,
      ((argb >> 24) & 0xFF) / 255,
    );
    double on(String id) => file.isOn(id) ? 1 : 0;
    double n(String key) => number(file, const {}, key);
    int c(String key) => file.colour(key);

    final stops = file.isOn('gradientMap')
        ? file.stops('gradientMap.stops').take(maxStops).toList()
        : <(double, int)>[];
    final swaps = file.isOn('paletteSwap')
        ? file.swaps('paletteSwap.swaps').take(maxSwaps).toList()
        : <(int, int)>[];
    vec4(_grid, slotWidth, slotHeight, perRow.toDouble(), pad);
    vec4(
      _sheet,
      sheetWidth.toDouble(),
      sheetHeight.toDouble(),
      paramsWidth.toDouble(),
      paramsHeight.toDouble(),
    );
    vec4(_time, time, swaps.length.toDouble(), stops.length.toDouble(), 0);
    vec4(_on0, on('wave'), on('scroll'), on('paletteSwap'), on('gradientMap'));
    vec4(_on1, on('greyscale'), on('tint'), on('flash'), on('dissolve'));
    vec4(_on2, on('shine'), on('outline'), on('glow'), on('dropShadow'));
    vec4(
      _wave,
      n('wave.amplitude'),
      n('wave.wavelength'),
      n('wave.speed'),
      file.text('wave.direction') == 'vertical' ? 1 : 0,
    );
    vec4(
      _scroll,
      n('scroll.speed#0'),
      n('scroll.speed#1'),
      n('paletteSwap.tolerance'),
      n('gradientMap.amount'),
    );
    vec4(
      _amounts,
      n('greyscale.amount'),
      n('flash.amount'),
      n('dissolve.amount'),
      n('dissolve.edgeWidth'),
    );
    rgba(_tint, c('tint.colour'));
    rgba(_flash, c('flash.colour'));
    rgba(_dissolveEdge, c('dissolve.edgeColour'));
    vec4(
      _dissolveShine,
      n('dissolve.scale'),
      n('shine.width'),
      n('shine.angle'),
      n('shine.duration'),
    );
    rgba(_shineColour, c('shine.colour'));
    vec4(
      _shine2,
      n('shine.interval'),
      n('outline.width'),
      n('glow.radius'),
      n('glow.strength'),
    );
    rgba(_outlineColour, c('outline.colour'));
    rgba(_glowColour, c('glow.colour'));
    vec4(
      _shadow,
      n('dropShadow.offset#0'),
      n('dropShadow.offset#1'),
      n('dropShadow.softness'),
      0,
    );
    rgba(_shadowColour, c('dropShadow.colour'));
    for (var i = 0; i < dynamicKeys.length; i++) {
      f[_dyn + i] = (dynamicColumns[dynamicKeys[i]] ?? -1).toDouble();
    }
    for (var i = dynamicKeys.length; i < 32; i++) {
      f[_dyn + i] = -1;
    }
    for (var i = 0; i < stops.length; i++) {
      rgba(_stopColours + i * 4, stops[i].$2);
      f[_stopAt + i * 4] = stops[i].$1;
    }
    for (var i = 0; i < swaps.length; i++) {
      rgba(_swapFrom + i * 4, swaps[i].$1);
      rgba(_swapTo + i * 4, swaps[i].$2);
    }
    for (var i = 0; i < uniformFloats; i++) {
      shader.setFloat(i, f[i]);
    }
  }

  /// Writes what `material_2d_normals.frag` reads for [file]'s normals:
  /// the same grid as [write], whether [normalMap] is the sheet, the map's
  /// strength, how emissive it is, and what moves it.
  static void writeNormals(
    ui.FragmentShader shader,
    Material2DFile file, {
    required double slotWidth,
    required double slotHeight,
    required int perRow,
    required double pad,
    required int sheetWidth,
    required int sheetHeight,
    required int paramsWidth,
    required int paramsHeight,
    required double time,
    required bool normalMap,
    required int mapWidth,
    required int mapHeight,
  }) {
    double n(String key) => number(file, const {}, key);
    final values = <double>[
      slotWidth,
      slotHeight,
      perRow.toDouble(),
      pad,
      sheetWidth.toDouble(),
      sheetHeight.toDouble(),
      paramsWidth.toDouble(),
      paramsHeight.toDouble(),
      normalMap ? 1 : 0,
      file.isOn('normalMap') ? n('normalMap.strength') : 1,
      file.isOn('emissive') ? n('emissive.amount') : 0,
      time,
      file.isOn('wave') ? 1 : 0,
      file.isOn('scroll') ? 1 : 0,
      file.isOn('normalMap') && file.toggle('normalMap.directX') ? 1 : 0,
      0,
      n('wave.amplitude'),
      n('wave.wavelength'),
      n('wave.speed'),
      file.text('wave.direction') == 'vertical' ? 1 : 0,
      n('scroll.speed#0'),
      n('scroll.speed#1'),
      0,
      0,
      mapWidth.toDouble(),
      mapHeight.toDouble(),
      0,
      0,
    ];
    for (var i = 0; i < values.length; i++) {
      shader.setFloat(i, values[i]);
    }
  }

  /// [v] as a half float's 16 bits: what the shader's `half16` reads back.
  /// Too big a number is the largest a half holds; too small, zero.
  static int halfOf(double v) {
    if (v.isNaN) return 0;
    final sign = v < 0 || (v == 0 && v.isNegative) ? 0x8000 : 0;
    var a = v.abs();
    if (a >= 65504) return sign | 0x7BFF;
    if (a < 5.960464477539063e-8) return sign;
    if (a < 6.103515625e-5) {
      // Subnormal: m × 2^-24.
      return sign | (a / 5.960464477539063e-8).round().clamp(0, 1023);
    }
    var e = (math.log(a) / math.ln2).floor();
    // Guard the log's rounding at a power of two.
    if (math.pow(2, e) > a) e--;
    if (math.pow(2, e + 1) <= a) e++;
    var m = ((a / math.pow(2, e) - 1) * 1024).round();
    if (m == 1024) {
      m = 0;
      e++;
    }
    if (e + 15 >= 31) return sign | 0x7BFF;
    return sign | ((e + 15) << 10) | m;
  }

  /// What the shader reads back from a half's 16 [bits].
  static double fromHalf(int bits) {
    final sign = bits & 0x8000 != 0 ? -1.0 : 1.0;
    final e = (bits >> 10) & 0x1F;
    final m = bits & 0x3FF;
    if (e == 0) return sign * m * 5.960464477539063e-8;
    return sign * (1 + m / 1024) * math.pow(2, e - 15);
  }
}

/// Screen materials: the whole view drawn through a 2-D material of the
/// `screen` kind.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:just_game_engine_formats/just_game_engine_formats.dart';

import '../../ecs/components/components.dart';
import '../../ecs/ecs.dart';
import '../rendering/screen_pass.dart';
import 'material_2d_library.dart';
import 'material_2d_shader.dart';

/// Draws the frame through the world's [ScreenMaterial]: of those enabled
/// on active entities, the one with the highest order. What the engine
/// installs as its `RenderingEngine.screenPass`.
///
/// The material's values are the file's (resolved, variants laid over their
/// parents) with the component's overrides on top, handed to the shader as
/// uniforms: one draw, nothing made per frame but the frame's image.
final class ScreenMaterialPass implements ScreenPass {
  /// A pass over the world [world] gives (null for none), moving effects
  /// timed by [clock].
  ScreenMaterialPass(this.world, {this.clock});

  /// The world whose screen material is drawn.
  final World? Function() world;

  /// Seconds into the game; null stands still.
  final double Function()? clock;

  ui.FragmentShader? _shader;
  ui.FragmentProgram? _shaderOf;
  Material2DFile? _file;
  Map<String, Object> _overrides = const {};

  /// The screen material drawn this frame, once [active] has been asked.
  ScreenMaterial? get current => _current;
  ScreenMaterial? _current;

  @override
  bool get active {
    _current = null;
    _file = null;
    final w = world();
    if (w == null) return false;
    ScreenMaterial? best;
    for (final entity in w.query(const [ScreenMaterial])) {
      if (!entity.isActiveInHierarchy) continue;
      final c = entity.getComponent<ScreenMaterial>();
      if (c == null || !c.enabled || c.material.isEmpty) continue;
      if (best == null || c.order >= best.order) best = c;
    }
    if (best == null) return false;
    final library = Material2DLibrary.of(w.context);
    final file = library.fileOf(best.material);
    final program = library.screenProgram;
    if (file == null || program == null || file.kind != Material2DKind.screen) {
      return false;
    }
    if (!identical(program, _shaderOf)) {
      _shader?.dispose();
      _shader = program.fragmentShader();
      _shaderOf = program;
    }
    _current = best;
    _file = file;
    _overrides = best.overrides;
    return true;
  }

  @override
  void paint(
    ui.Canvas canvas,
    ui.Image frame,
    ui.Size size,
    double pixelRatio,
  ) {
    final shader = _shader;
    final file = _file;
    if (shader == null || file == null) return;
    write(shader, file, _overrides, size: size, time: clock?.call() ?? 0);
    shader.setImageSampler(0, frame, filterQuality: FilterQuality.low);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  /// Writes [file]'s values, with [overrides] on top, into [shader] for a
  /// view of [size] at [time] seconds: the layout `material_2d_screen.frag`
  /// reads.
  static void write(
    ui.FragmentShader shader,
    Material2DFile file,
    Map<String, Object> overrides, {
    required ui.Size size,
    double time = 0,
  }) {
    final f = Float32List(uniformFloats);
    void vec4(int at, double x, double y, double z, double w) {
      f[at] = x;
      f[at + 1] = y;
      f[at + 2] = z;
      f[at + 3] = w;
    }

    double n(String key) {
      final own = overrides[key];
      if (own is num && Material2DShader.overrides(key, own)) {
        return own.toDouble();
      }
      return file.number(key);
    }

    int c(String key) {
      final own = overrides[key];
      if (own is num && Material2DShader.overrides(key, own)) {
        return own.toInt();
      }
      return file.colour(key);
    }

    void rgba(int at, int argb) => vec4(
      at,
      ((argb >> 16) & 0xFF) / 255,
      ((argb >> 8) & 0xFF) / 255,
      (argb & 0xFF) / 255,
      ((argb >> 24) & 0xFF) / 255,
    );
    double on(String id) => file.isOn(id) ? 1 : 0;

    final stops = file.isOn('gradientMap')
        ? file
              .stops('gradientMap.stops')
              .take(Material2DShader.maxStops)
              .toList()
        : <(double, int)>[];
    vec4(0, size.width, size.height, time, 0);
    vec4(4, on('pixelate'), on('crt'), on('grade'), on('gradientMap'));
    vec4(8, on('greyscale'), on('scanlines'), on('vignette'), 0);
    vec4(12, n('pixelate.size'), n('crt.curvature'), n('crt.aberration'), 0);
    vec4(
      16,
      n('grade.brightness'),
      n('grade.contrast'),
      n('grade.saturation'),
      n('grade.hue'),
    );
    rgba(20, c('grade.tint'));
    vec4(
      24,
      n('gradientMap.amount'),
      n('greyscale.amount'),
      n('scanlines.amount'),
      n('scanlines.size'),
    );
    vec4(
      28,
      n('vignette.amount'),
      n('vignette.softness'),
      stops.length.toDouble(),
      0,
    );
    rgba(32, c('vignette.colour'));
    for (var i = 0; i < stops.length; i++) {
      rgba(36 + i * 4, stops[i].$2);
      f[68 + i * 4] = stops[i].$1;
    }
    for (var i = 0; i < uniformFloats; i++) {
      shader.setFloat(i, f[i]);
    }
  }

  /// How many floats the screen shader's uniforms hold.
  static const int uniformFloats = 100;

  /// Lets go of the shader.
  void dispose() {
    _shader?.dispose();
    _shader = null;
    _shaderOf = null;
  }
}

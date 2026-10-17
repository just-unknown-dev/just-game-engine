/// 2-D lighting: the frame lit by the world's [Light2D]s, as a screen pass.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart' show Matrix4, Offset, Paint, Rect;

import '../../ecs/components/components.dart';
import '../../ecs/ecs.dart';
import '../../ecs/systems/rendering/render_system.dart';
import '../materials_2d/material_2d_library.dart';
import '../rendering/screen_pass.dart';

/// Lights the frame when the world has a [Lighting2D] on: the frame and its
/// normals (`RenderSystem.renderNormals`) drawn through
/// `shaders/lighting_2d.frag`, lit by up to [maxLights] [Light2D]s — those
/// reaching the view, the nearest its middle first — over the ambient
/// light. Lights that cast shadows are stopped by what casts them
/// ([ShadowCaster2D], Level Map layers that cast them): their shapes drawn
/// into a mask (`RenderSystem.renderOccluders`), how far each light reaches
/// every way found from it (`shaders/shadow_map_2d.frag`). What the engine
/// puts first in `RenderingEngine.screenPasses`.
final class Lighting2DPass implements ScreenPass {
  /// A pass over the world [world] gives (null for none).
  Lighting2DPass(this.world, {this.clock});

  /// The world that is lit.
  final World? Function() world;

  /// Seconds into the game; null stands still.
  final double Function()? clock;

  /// The most lights drawn at once.
  static const int maxLights = 16;

  /// Whether it lights at all: an editor turns it off to see the scene
  /// unlit while it is worked on.
  bool enabled = true;

  /// Directions round a light its shadows are found in.
  static const int shadowDirections = 512;

  /// How big the mask of what casts shadows is, to the view.
  static const double maskScale = 0.5;

  /// The most pixels the frame's normals are drawn at in full: past this
  /// (a big window), at half its size each way. Every buffer is a render
  /// target, which a GPU has only so much room for — Impeller on OpenGL ES
  /// aborts when one cannot be made — and light is smooth.
  static const int fullNormalsPixels = 1920 * 1080;

  Lighting2D? _lighting;
  RenderSystem? _render;
  ui.FragmentShader? _shader;
  ui.FragmentProgram? _shaderOf;
  ui.FragmentShader? _shadowShader;
  ui.FragmentProgram? _shadowShaderOf;
  ui.Image? _blank;
  final List<ui.Image> _images = [];
  final List<ui.Image> _oldImages = [];
  final Matrix4 _matrix = Matrix4.zero();

  /// The lights drawn in the last frame, nearest the view's middle first.
  /// For tests and an editor's overlay.
  List<Light2D> get lastLights => List.unmodifiable(_lastLights);
  final List<Light2D> _lastLights = [];

  /// Whether the last frame had shadows: a light casting them, and
  /// something they were cast by.
  bool get lastHadShadows => _lastHadShadows;
  bool _lastHadShadows = false;

  @override
  bool get active {
    _lighting = null;
    if (!enabled) return false;
    final w = world();
    if (w == null) return false;
    Lighting2D? on;
    for (final entity in w.query(const [Lighting2D])) {
      if (!entity.isActiveInHierarchy) continue;
      final c = entity.getComponent<Lighting2D>();
      if (c != null && c.enabled) {
        on = c;
        break;
      }
    }
    if (on == null) return false;
    RenderSystem? render;
    for (final s in w.systems) {
      if (s is RenderSystem && s.isAttached) {
        render = s;
        break;
      }
    }
    if (render == null) return false;
    final library = Material2DLibrary.of(w.context);
    library.normalsProgram;
    library.shadowsProgram;
    final program = library.lightingProgram;
    if (program == null) return false;
    if (!identical(program, _shaderOf)) {
      _shader?.dispose();
      _shader = program.fragmentShader();
      _shaderOf = program;
    }
    _lighting = on;
    _render = render;
    return true;
  }

  ui.Image _image(
    void Function(ui.Canvas canvas) draw,
    int width,
    int height,
  ) => _imageIf(
    (c) {
      draw(c);
      return true;
    },
    width,
    height,
  )!;

  // [draw] recorded, and made an image only when it says it drew anything:
  // every image is a render target, and a GPU has only so many — Impeller
  // on OpenGL ES aborts when one cannot be made.
  ui.Image? _imageIf(
    bool Function(ui.Canvas canvas) draw,
    int width,
    int height,
  ) {
    final recorder = ui.PictureRecorder();
    final drew = draw(ui.Canvas(recorder));
    final picture = recorder.endRecording();
    if (!drew) {
      picture.dispose();
      return null;
    }
    final image = picture.toImageSync(width, height);
    picture.dispose();
    _images.add(image);
    return image;
  }

  @override
  void paint(
    ui.Canvas canvas,
    ui.Image frame,
    ui.Size size,
    double pixelRatio,
  ) {
    final lighting = _lighting;
    final render = _render;
    final shader = _shader;
    final w = world();
    if (lighting == null || render == null || shader == null || w == null) {
      return;
    }
    for (final i in _oldImages) {
      i.dispose();
    }
    _oldImages
      ..clear()
      ..addAll(_images);
    _images.clear();
    final blank = _blank ??= _blankImage();

    // The frame's normals, drawn as the frame was — none when nothing in
    // it is shaded: flat everywhere.
    final normalsScale = frame.width * frame.height > fullNormalsPixels
        ? 0.5
        : 1.0;
    final normals =
        _imageIf(
          (c) =>
              render.renderNormals(c..scale(pixelRatio * normalsScale), size),
          math.max(1, (frame.width * normalsScale).ceil()),
          math.max(1, (frame.height * normalsScale).ceil()),
        ) ??
        blank;

    // World to view (the camera's matrix), and back.
    var ma = 1.0, mb = 0.0, mc = 0.0, md = 1.0, me = 0.0, mf = 0.0;
    final camera = render.camera;
    Rect view = Offset.zero & size;
    if (camera != null) {
      camera.canvasMatrixInto(_matrix);
      final m = _matrix.storage;
      ma = m[0];
      mb = m[1];
      mc = m[4];
      md = m[5];
      me = m[12];
      mf = m[13];
      view = camera.getVisibleBounds();
    }
    var a = 1.0, b = 0.0, c = 0.0, d = 1.0, e = 0.0, f = 0.0;
    final det = ma * md - mb * mc;
    if (det.abs() > 1e-12) {
      a = md / det;
      b = -mb / det;
      c = -mc / det;
      d = ma / det;
      e = -(a * me + c * mf);
      f = -(b * me + d * mf);
    }
    final zoom = math.sqrt(det.abs());

    // The lights that reach the view, nearest its middle first.
    final middle = view.center;
    final found = <(Light2D, TransformComponent, double)>[];
    for (final entity in w.query(const [Light2D, TransformComponent])) {
      if (!entity.isActiveInHierarchy) continue;
      final light = entity.getComponent<Light2D>()!;
      if (!light.enabled || light.radius <= 0 || light.intensity <= 0) continue;
      final t = entity.getComponent<TransformComponent>()!;
      final p = Offset(t.position.x, t.position.y);
      if (!view.inflate(light.radius).contains(p)) continue;
      found.add((light, t, (p - middle).distanceSquared));
    }
    found.sort((x, y) => x.$3.compareTo(y.$3));
    final count = math.min(found.length, maxLights);
    _lastLights
      ..clear()
      ..addAll(found.take(count).map((l) => l.$1));

    // Shadows: what casts them, then how far each light reaches each way.
    final rows = <int, int>{};
    for (var i = 0; i < count; i++) {
      if (found[i].$1.castsShadows) rows[i] = rows.length;
    }
    var mask = blank, shadowMap = blank;
    var shadows = false;
    final library = Material2DLibrary.of(w.context);
    final shadowProgram = library.shadowsProgram;
    final maskW = math.max(1, (size.width * maskScale).ceil());
    final maskH = math.max(1, (size.height * maskScale).ceil());
    if (rows.isNotEmpty && shadowProgram != null) {
      final drawn = _imageIf(
        (c) => render.renderOccluders(c..scale(maskScale), size),
        maskW,
        maskH,
      );
      if (drawn != null) {
        mask = drawn;
        if (!identical(shadowProgram, _shadowShaderOf)) {
          _shadowShader?.dispose();
          _shadowShader = shadowProgram.fragmentShader();
          _shadowShaderOf = shadowProgram;
        }
        final s = _shadowShader!;
        final su = Float32List(72)
          ..[0] = shadowDirections.toDouble()
          ..[1] = rows.length.toDouble()
          ..[2] = maskW.toDouble()
          ..[3] = maskH.toDouble()
          ..[4] = maskScale;
        for (final MapEntry(key: i, value: row) in rows.entries) {
          final t = found[i].$2;
          su
            ..[8 + row * 4] = ma * t.position.x + mc * t.position.y + me
            ..[9 + row * 4] = mb * t.position.x + md * t.position.y + mf
            ..[10 + row * 4] = found[i].$1.radius * zoom;
        }
        for (var i = 0; i < su.length; i++) {
          s.setFloat(i, su[i]);
        }
        s.setImageSampler(0, mask);
        shadowMap = _image(
          (c) => c.drawRect(
            Rect.fromLTWH(
              0,
              0,
              shadowDirections.toDouble(),
              rows.length.toDouble(),
            ),
            Paint()..shader = s,
          ),
          shadowDirections,
          rows.length,
        );
        shadows = true;
      }
    }
    _lastHadShadows = shadows;

    final u = Float32List(uniformFloats);
    final ambient = lighting.ambient;
    final ai = lighting.ambientIntensity;
    u
      ..[0] = size.width
      ..[1] = size.height
      ..[2] = count.toDouble()
      ..[4] = ambient.r * ai
      ..[5] = ambient.g * ai
      ..[6] = ambient.b * ai
      ..[8] = a
      ..[9] = b
      ..[10] = c
      ..[11] = d
      ..[12] = e
      ..[13] = f
      ..[208] = shadowDirections.toDouble()
      ..[209] = rows.length.toDouble()
      ..[210] = lighting.shadowSoftness.clamp(0.0, 1.0)
      ..[211] = zoom
      ..[212] = maskW.toDouble()
      ..[213] = maskH.toDouble()
      ..[214] = maskScale
      ..[215] = shadows ? 1 : 0;
    for (var i = 0; i < count; i++) {
      final (light, t, _) = found[i];
      final l = 16 + i * 4, col = 80 + i * 4, s = 144 + i * 4, sl = 216 + i * 4;
      u
        ..[l] = t.position.x
        ..[l + 1] = t.position.y
        ..[l + 2] = light.radius
        ..[l + 3] = math.max(light.height, 0.01)
        ..[col] = light.colour.r * light.intensity
        ..[col + 1] = light.colour.g * light.intensity
        ..[col + 2] = light.colour.b * light.intensity
        ..[col + 3] = math.max(light.falloff, 0.01)
        ..[sl] = ma * t.position.x + mc * t.position.y + me
        ..[sl + 1] = mb * t.position.x + md * t.position.y + mf
        ..[sl + 2] = light.radius * zoom
        ..[sl + 3] = (rows[i] ?? -1).toDouble();
      if (light.kind == Light2DKind.spot) {
        final half = light.coneAngle.clamp(0.0, 360.0) * math.pi / 360;
        final inner = half * (1 - light.coneSoftness.clamp(0.0, 1.0));
        final cosOuter = math.cos(half), cosInner = math.cos(inner);
        u
          ..[s] = math.cos(t.angle)
          ..[s + 1] = math.sin(t.angle)
          ..[s + 2] = cosOuter
          ..[s + 3] = 1 / math.max(cosInner - cosOuter, 1e-4);
      } else {
        u[s + 2] = -2;
      }
    }
    for (var i = count; i < maxLights; i++) {
      u[216 + i * 4 + 3] = -1;
    }
    for (var i = 0; i < uniformFloats; i++) {
      shader.setFloat(i, u[i]);
    }
    shader
      ..setImageSampler(0, frame)
      ..setImageSampler(1, normals)
      ..setImageSampler(2, mask)
      ..setImageSampler(3, shadowMap, filterQuality: ui.FilterQuality.low);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  static ui.Image _blankImage() {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(1, 1);
    picture.dispose();
    return image;
  }

  /// How many floats `lighting_2d.frag`'s uniforms hold.
  static const int uniformFloats = 280;

  /// Lets go of the shaders and images.
  void dispose() {
    _shader?.dispose();
    _shader = null;
    _shaderOf = null;
    _shadowShader?.dispose();
    _shadowShader = null;
    _shadowShaderOf = null;
    for (final i in [..._images, ..._oldImages]) {
      i.dispose();
    }
    _images.clear();
    _oldImages.clear();
    _blank?.dispose();
    _blank = null;
  }
}

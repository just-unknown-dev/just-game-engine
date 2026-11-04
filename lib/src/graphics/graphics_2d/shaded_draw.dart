/// A renderable drawn through its entity's own shader.
library;

import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:meta/meta.dart' show internal;

import '../../rendering/renderable.dart';
import '../../rendering/shader_component.dart';
import '../../rendering/shader_filter_support.dart';
import 'render_bounds.dart';

/// Draws a renderable through its entity's [ShaderComponent]: an offscreen
/// layer over its bounds, filtered by the shader.
@internal
final class ShadedDraw {
  /// The layer's paint, kept between draws.
  final Paint _paint = Paint();

  /// Draws [renderable] through [shaderComp], [time] seconds into the game.
  ///
  /// Where shaders cannot filter layers (the web, Skia) the renderable is
  /// drawn without the effect; see [ShaderFilterSupport].
  void draw(
    Canvas canvas,
    Size size,
    Renderable renderable,
    ShaderComponent shaderComp,
    double time,
  ) {
    if (!ShaderFilterSupport.check('A per-entity ShaderComponent')) {
      renderable.render(canvas, size);
      return;
    }
    final effectRect =
        RenderBounds.shaderBounds(renderable) ??
        // Fall back to a generous world-space rect if bounds are unknown.
        Rect.fromCenter(
          center: renderable.position.toOffset(),
          width: size.width,
          height: size.height,
        );
    shaderComp.setUniforms?.call(
      shaderComp.shader,
      effectRect.width,
      effectRect.height,
      time,
    );
    // Made every frame on purpose: a shader filter copies the uniforms when
    // it is made, so a kept one would freeze an animated effect.
    _paint.imageFilter = ui.ImageFilter.shader(shaderComp.shader);
    canvas.saveLayer(effectRect, _paint);
    renderable.render(canvas, size);
    canvas.restore();
  }
}

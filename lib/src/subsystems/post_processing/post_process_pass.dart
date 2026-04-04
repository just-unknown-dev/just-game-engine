/// Post-Process Pass
///
/// A single fullscreen shader pass registered with [RenderingEngine].
/// Each pass wraps the accumulated scene in an offscreen layer and
/// composites it back through a custom [FragmentShader].
library;

import 'dart:ui' as ui;

/// A single fullscreen post-process shader pass.
///
/// Register instances with [RenderingEngine.addPostProcessPass] to apply
/// a [ui.FragmentShader] as a screen-space effect over the entire rendered
/// scene each frame.
///
/// Multiple passes can be chained: they are ordered by [passOrder] (ascending)
/// so that the lowest-order pass is applied innermost (closest to the raw
/// scene) and the highest-order pass composites last (outermost / closest
/// to the viewer).
///
/// ### GLSL Shader Requirements
///
/// Post-process shaders must declare a `sampler2D` for the accumulated scene
/// texture. Flutter's `canvas.saveLayer` + `Paint.imageFilter` pipeline
/// automatically binds the layer content to sampler index 0.
///
/// Minimal screen-space pass skeleton:
/// ```glsl
/// #include <flutter/runtime_effect.glsl>
///
/// uniform vec2 uResolution;
/// uniform float uTime;
/// uniform sampler2D uTexture;
///
/// out vec4 fragColor;
///
/// void main() {
///   vec2 uv = FlutterFragCoord().xy / uResolution;
///   fragColor = texture(uTexture, uv);
/// }
/// ```
///
/// Set sampler index **last** in your [setUniforms] callback:
/// ```dart
/// setUniforms: (shader, w, h, t) {
///   shader.setFloat(0, w);    // uResolution.x
///   shader.setFloat(1, h);    // uResolution.y
///   shader.setFloat(2, t);    // uTime
///   // sampler bound automatically by saveLayer — do NOT setImageSampler here
/// },
/// ```
class PostProcessPass {
  /// The resolved [ui.FragmentShader] instance used to composite this pass.
  ///
  /// Uniforms are written via [setUniforms] before each [RenderingEngine]
  /// render call. Do **not** dispose this shader externally — dispose the
  /// owning [ShaderComponent] instead (which holds the [ui.FragmentProgram]).
  final ui.FragmentShader shader;

  /// Determines the layering order when multiple passes are active.
  ///
  /// Lower values are applied **innermost** (i.e. first, closest to scene).
  /// Higher values composite **outermost** (last, closest to viewer).
  int passOrder;

  /// Whether this pass is evaluated during the current frame.
  ///
  /// Toggle to temporarily disable a pass without removing it from the engine.
  bool enabled;

  /// Per-frame uniform setter.
  ///
  /// Called with the live shader instance, current viewport dimensions, and
  /// elapsed engine time immediately before the offscreen layer is saved.
  ///
  /// Use this callback to write float uniforms and configure the shader state
  /// for the current frame. The scene texture sampler (index 0 by convention)
  /// is bound automatically by Flutter's layer compositing — do **not** call
  /// [ui.FragmentShader.setImageSampler] inside this callback.
  void Function(
    ui.FragmentShader shader,
    double viewportWidth,
    double viewportHeight,
    double elapsedSeconds,
  )? setUniforms;

  /// Create a post-process pass.
  ///
  /// [shader]     — Resolved fragment shader (from [ui.FragmentProgram.fragmentShader]).
  /// [passOrder]  — Layering index, default 0 (innermost).
  /// [enabled]    — Whether this pass runs each frame, default `true`.
  /// [setUniforms]— Optional per-frame uniform configuration callback.
  PostProcessPass({
    required this.shader,
    this.passOrder = 0,
    this.enabled = true,
    this.setUniforms,
  });
}

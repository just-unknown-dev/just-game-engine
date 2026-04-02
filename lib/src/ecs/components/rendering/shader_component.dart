/// Shader Component
///
/// Attaches a custom GLSL [FragmentShader] to an ECS entity, enabling
/// per-entity visual effects or fullscreen post-process passes.
library;

import 'dart:ui' as ui;

import '../../ecs.dart';

/// Attaches a custom GLSL [ui.FragmentShader] to an ECS entity.
///
/// Two operating modes are supported:
///
/// ---
/// ### Per-entity effects  ([isPostProcess] = `false`, default)
///
/// The [RenderSystem] detects this component on an entity and wraps that
/// entity's renderable in a `canvas.saveLayer()` call backed by the shader
/// as a [ui.ImageFilter]. The effect is clipped to the entity's bounding
/// rectangle, keeping it computationally cheap.
///
/// This mode is suitable for effects such as:
/// - Per-sprite chromatic aberration or color grading
/// - Individual entity distortion (heat haze, water ripple)
/// - Entity-level dissolve or glitch patterns
///
/// ---
/// ### Fullscreen post-process  ([isPostProcess] = `true`)
///
/// The [PostProcessSystem] registers a corresponding [PostProcessPass] with
/// the [RenderingEngine]. The entire composed scene — subsystem renderables
/// and ECS overlay — is first rendered into an offscreen buffer, then
/// composited through this shader before being drawn to the screen.
///
/// Multiple passes are chained in ascending [passOrder] (lowest = innermost).
///
/// This mode is suitable for effects such as:
/// - Bloom / glow
/// - Chromatic aberration across the full viewport
/// - Vignette, scanlines, CRT filters
/// - Screen-space dynamic 2D lighting accumulation
///
/// ---
/// ### Loading a shader
///
/// Shaders must be declared in `pubspec.yaml` and compiled by Flutter's
/// shader bundler (SPIR-V cross-compilation):
///
/// ```yaml
/// flutter:
///   shaders:
///     - shaders/bloom.frag
/// ```
///
/// Load at runtime before creating the component:
///
/// ```dart
/// final program = await ui.FragmentProgram.fromAsset('shaders/bloom.frag');
/// world.addComponent(bloomEntity, ShaderComponent(
///   program: program,
///   isPostProcess: true,
///   passOrder: 0,
///   setUniforms: (shader, w, h, t) {
///     shader.setFloat(0, w);   // uResolution.x
///     shader.setFloat(1, h);   // uResolution.y
///     shader.setFloat(2, t);   // uTime
///   },
/// ));
/// ```
///
/// ---
/// ### GLSL skeleton for post-process shaders
///
/// ```glsl
/// #include <flutter/runtime_effect.glsl>
///
/// uniform vec2  uResolution;
/// uniform float uTime;
/// uniform sampler2D uTexture;  // index 0 — bound automatically
///
/// out vec4 fragColor;
///
/// void main() {
///   vec2 uv = FlutterFragCoord().xy / uResolution;
///   fragColor = texture(uTexture, uv);
/// }
/// ```
///
/// ---
/// ### GLSL skeleton for per-entity shaders
///
/// Per-entity shaders receive the entity's composited layer as the sampler.
/// The bounding rect of the renderable defines the UV extent:
///
/// ```glsl
/// #include <flutter/runtime_effect.glsl>
///
/// uniform vec2  uSize;   // entity width / height
/// uniform sampler2D uTexture;
///
/// out vec4 fragColor;
///
/// void main() {
///   vec2 uv = FlutterFragCoord().xy / uSize;
///   fragColor = texture(uTexture, uv);
/// }
/// ```
class ShaderComponent extends Component {
  /// The compiled fragment program.
  ///
  /// Shared and immutable — owned by the program asset loader, not this
  /// component. Do **not** dispose it here.
  final ui.FragmentProgram program;

  /// When `false` (default) the shader is applied to this entity only.
  /// When `true` the shader is applied as a fullscreen post-process pass
  /// managed by [PostProcessSystem].
  final bool isPostProcess;

  /// Execution order for post-process passes.
  ///
  /// Lower values are innermost (applied first to the raw scene).
  /// Ignored when [isPostProcess] is `false`.
  ///
  /// Mutable so [PostProcessSystem] can synchronise live changes from ECS.
  int passOrder;

  /// Toggle this shader on or off each frame without removing the component.
  bool enabled;

  /// Per-frame uniform setter.
  ///
  /// Called with the live shader instance, the viewport (or entity-bound)
  /// width and height, and the elapsed engine time in seconds.
  ///
  /// For per-entity effects ([isPostProcess] = `false`) the width/height
  /// reflect the entity's bounding rect; the `time` parameter is `0.0`
  /// unless the [RenderSystem] is provided a time source externally.
  /// Use a closure to capture any additional game-state you require:
  ///
  /// ```dart
  /// double _dissolveProgress = 0;
  /// setUniforms: (shader, w, h, t) => shader.setFloat(0, _dissolveProgress),
  /// ```
  void Function(
    ui.FragmentShader shader,
    double width,
    double height,
    double elapsedSeconds,
  )? setUniforms;

  // ── Internal state ──────────────────────────────────────────────────────

  /// Resolved [ui.FragmentShader] instance.
  ///
  /// One instance per component ensures isolated uniform state across
  /// multiple entities using the same program.
  late final ui.FragmentShader _shader;

  /// Create a shader component.
  ///
  /// [program] must already be loaded via [ui.FragmentProgram.fromAsset].
  ShaderComponent({
    required this.program,
    this.isPostProcess = false,
    this.passOrder = 0,
    this.enabled = true,
    this.setUniforms,
  }) {
    _shader = program.fragmentShader();
  }

  /// The resolved [ui.FragmentShader] instance for this component.
  ///
  /// Configure uniforms via [setUniforms] rather than mutating this directly.
  ui.FragmentShader get shader => _shader;

  @override
  void onDetach(EntityId entityId) {
    _shader.dispose();
  }

  @override
  String toString() =>
      'ShaderComponent(postProcess: $isPostProcess, order: $passOrder, '
      'enabled: $enabled)';
}

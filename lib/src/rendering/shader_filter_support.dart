/// Whether shaders can be used as image filters where the game is running.
library;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// Guards every `ImageFilter.shader` the engine makes.
///
/// A [ui.FragmentShader] can filter a layer only under Impeller. On the web
/// (both renderers) and on native platforms still drawing with Skia,
/// `ImageFilter.shader` throws — and the engine used to call it every frame,
/// so one post-process pass or one shaded entity broke the whole frame.
///
/// Where it is not supported the effect is skipped — the content still draws,
/// unshaded — and a line says so once per kind of effect. A fallback that
/// draws the content into an image and paints it through the shader is not
/// used: such a shader reads `FlutterFragCoord()` in the coordinates of the
/// layer it filters, and a painted rectangle would feed it the render
/// target's instead, so the effect would sample the wrong place.
abstract final class ShaderFilterSupport {
  /// Stands in for the platform's answer in tests; null asks the platform.
  @visibleForTesting
  static bool? debugSupportedOverride;

  static final Set<String> _warned = {};

  /// Whether `ImageFilter.shader` works here.
  static bool get isSupported =>
      debugSupportedOverride ?? ui.ImageFilter.isShaderFilterSupported;

  /// [isSupported]; when not, logs — once per [effect] — that the effect is
  /// being skipped.
  static bool check(String effect) {
    if (isSupported) return true;
    if (_warned.add(effect)) {
      debugPrint(
        '$effect skipped: shaders cannot filter layers on this renderer '
        '(ImageFilter.isShaderFilterSupported is false — the web, and Skia). '
        'The content is drawn without the effect.',
      );
    }
    return false;
  }

  /// Forgets which effects were reported, so the next [check] logs again.
  @visibleForTesting
  static void debugReset() {
    _warned.clear();
    debugSupportedOverride = null;
  }
}

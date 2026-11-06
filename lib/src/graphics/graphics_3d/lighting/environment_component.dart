import 'dart:ui' show Color;

import '../../../ecs/ecs.dart';

// Plain data with no GPU imports, so scenes that hold it load everywhere,
// the web included (where it simply draws nothing).

/// The sky and the ambient light of a 3-D scene. The first enabled one in
/// a scene is used.
class EnvironmentComponent extends Component {
  /// An environment; the defaults are a daylight sky.
  EnvironmentComponent({
    this.sky = true,
    this.zenith = const Color(0xFF8AB4F0),
    this.horizon = const Color(0xFFE0EAF5),
    this.ground = const Color(0xFF9E978F),
    this.ambientSky = const Color(0xFF9EAAC0),
    this.ambientGround = const Color(0xFF6B655F),
    this.exposure = 1.0,
    this.background = const Color(0xFF101014),
    this.fog = false,
    this.fogColor = const Color(0xFFC8D2DC),
    this.fogDensity = 0.02,
    this.fogStart = 10.0,
    this.reflections = true,
    this.reflectionStrength = 1.0,
    this.skybox = '',
    this.skyboxBlur = 0.0,
  });

  /// Whether the gradient sky is drawn; otherwise [background].
  bool sky;

  /// Straight up.
  Color zenith;

  /// At eye level.
  Color horizon;

  /// Below the horizon.
  Color ground;

  /// Ambient light from above.
  Color ambientSky;

  /// Ambient light from below.
  Color ambientGround;

  /// Exposure before tonemapping.
  double exposure;

  /// Background when there is no sky.
  Color background;

  /// Whether distance fog is on.
  bool fog;

  /// What things fade to in the distance (sRGB, as picked).
  Color fogColor;

  /// How thick the fog is, per metre: 0.02 hides things a hundred metres
  /// beyond [fogStart].
  double fogDensity;

  /// Metres from the camera where fog begins.
  double fogStart;

  /// Whether surfaces light and reflect what surrounds them — the
  /// [skybox], or else the gradient sky — rather than the two ambient
  /// colours.
  bool reflections;

  /// How strong the reflections are: 0 for none.
  double reflectionStrength;

  /// A panorama (an equirectangular Radiance `.hdr`) drawn as the sky and
  /// lighting the scene; empty for the gradient sky.
  String skybox;

  /// How blurred the skybox is drawn: 0 sharp, 1 its blurriest.
  double skyboxBlur;
}

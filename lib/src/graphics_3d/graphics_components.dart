import 'dart:ui' show Color;

import 'package:just_dart/just_dart.dart' show Aabb3;

import '../ecs/ecs.dart';

// The 3-D components. Plain data with no GPU imports, so scenes that hold
// them load everywhere, the web included (where they simply draw nothing).

/// Draws a 3-D model (glTF 2.0, `.glb` or `.gltf`) at its entity's
/// transform. The model's own +Y-up axes are turned into the engine's.
class ModelComponent extends Component {
  /// A model loaded from the asset at [model].
  ModelComponent({
    this.model = '',
    Map<String, String>? materials,
    this.castShadows = true,
    this.visible = true,
  }) : materials = materials ?? {};

  /// Asset path, for example `assets/models/crate.glb`. Empty draws nothing.
  String model;

  /// Material files (`*.material.json`) drawn instead of the model's own
  /// materials: by a material's name, by `#` and its index (`#0`), or `*`
  /// for every one. Empty draws the model as it is.
  Map<String, String> materials;

  /// Whether it casts shadows (where shadows are on).
  bool castShadows;

  /// Whether it is drawn.
  bool visible;

  /// The loaded model's bounds in the entity's own space (engine axes), or
  /// empty until it has loaded. Runtime only, never saved.
  final Aabb3 bounds = Aabb3();
}

/// The kind of a [LightComponent].
enum LightKind {
  /// Light from far away along the entity's forward (+Z) axis: the sun.
  directional,

  /// Light from the entity's position in every direction.
  point,

  /// A cone of light from the entity's position along its forward axis.
  spot,
}

/// A light at its entity's transform. Directional and spot lights shine
/// along the entity's forward (+Z) axis.
class LightComponent extends Component {
  /// A light of [kind].
  LightComponent({
    this.kind = LightKind.point,
    this.color = const Color(0xFFFFFFFF),
    this.intensity = 10.0,
    this.range = 0.0,
    this.innerConeAngle = 0.0,
    this.outerConeAngle = 0.7853981633974483,
  });

  /// Directional, point or spot.
  LightKind kind;

  /// Its colour (sRGB, as picked).
  Color color;

  /// Brightness: lux-like for a directional light, candela-like otherwise.
  double intensity;

  /// Where a point or spot light stops reaching, in metres; 0 for no limit.
  double range;

  /// Spot: full brightness inside this angle (radians).
  double innerConeAngle;

  /// Spot: no light outside this angle (radians).
  double outerConeAngle;
}

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

/// Plays the animations (glTF clips) of the entity's [ModelComponent].
///
/// Saved: which [clip] plays, how fast, whether it loops, and how long a
/// change of clip fades. The playback position is runtime state. Call
/// [play] to change clip, or [playBlend] for several clips at once (a blend
/// tree's motions, kept in step); the old one fades out over [crossfade]
/// seconds. An animator graph drives it through `SkeletalAnimationTarget`.
class AnimationPlayerComponent extends Component {
  /// A player starting [clip].
  AnimationPlayerComponent({
    this.clip = '',
    this.speed = 1.0,
    this.loop = true,
    this.playing = true,
    this.crossfade = 0.2,
  });

  /// The clip's name in the model; empty shows the rest pose. While a
  /// blend plays ([blendClips]), the first of them.
  String clip;

  /// Playback rate: 1 is as authored, negative plays backwards.
  double speed;

  /// Whether the clip starts again at its end (else it holds the last pose).
  bool loop;

  /// Whether time moves.
  bool playing;

  /// Seconds a change of clip blends over.
  double crossfade;

  /// Seconds into [clip] (runtime).
  double time = 0;

  /// [time] at the previous update, for drawing between updates (runtime).
  double previousTime = 0;

  /// How many times [clip] (or the blend) has looped since it started
  /// (runtime).
  int cycles = 0;

  /// [clip]'s length in seconds, once its model has loaded (runtime).
  double duration = 0;

  /// The clips of the blend playing, or empty for [clip] alone (runtime).
  List<String> blendClips = const [];

  /// Each of [blendClips]' weight; they sum to 1 (runtime).
  List<double> blendWeights = const [];

  /// Each of [blendClips]' own speed (runtime).
  List<double> blendSpeeds = const [];

  /// How far through one cycle the blend is, 0–1: every clip of a blend is
  /// played at the same point of its own length, so a walk and a run keep
  /// their feet in step (runtime).
  double phase = 0;

  /// [phase] at the previous update (runtime).
  double previousPhase = 0;

  /// The clip fading out, or empty (runtime).
  String fadingFrom = '';

  /// Seconds into [fadingFrom] (runtime).
  double fadingFromTime = 0;

  /// The blend fading out, when a blend was playing (runtime).
  List<String> fadingFromBlend = const [];

  /// Its weights (runtime).
  List<double> fadingFromWeights = const [];

  /// Its phase (runtime).
  double fadingFromPhase = 0;

  /// Its clips' own speeds (runtime).
  List<double> fadingFromSpeeds = const [];

  /// The rate what fades out plays at: [speed] as it began to fade, or 0
  /// when it was paused (runtime).
  double fadingFromSpeed = 1;

  /// Whether what fades out loops, as [loop] said when it began to fade;
  /// otherwise it holds at its end (runtime).
  bool fadingFromLoop = true;

  /// How far the fade has gone: 1 when only what plays now shows (runtime).
  double fade = 1;

  /// Whether a blend is playing.
  bool get isBlending => blendClips.isNotEmpty;

  /// Plays [name] from its start, fading from what played over [fade]
  /// seconds ([crossfade] when null; 0 cuts). Asking for the clip already
  /// playing does nothing unless [restart].
  ///
  /// What fades out goes on as it played — at its [speed], looping or
  /// holding at its end as [loop] said — so set those for the new clip
  /// after this call, not before.
  void play(String name, {double? fade, bool restart = false}) {
    if (name == clip && !isBlending && !restart) {
      playing = true;
      return;
    }
    _fadeFromNow(fade ?? crossfade);
    clip = name;
    blendClips = const [];
    blendWeights = const [];
    blendSpeeds = const [];
    time = 0;
    previousTime = 0;
    cycles = 0;
    playing = true;
  }

  /// Plays [clips] together, weighted by [weights] (see [setBlendWeights])
  /// and kept in step, fading from what played over [fade] seconds.
  void playBlend(
    List<String> clips,
    List<double> weights, {
    List<double>? speeds,
    double? fade,
  }) {
    assert(clips.length == weights.length, 'one weight per clip');
    _fadeFromNow(fade ?? crossfade);
    clip = clips.isEmpty ? '' : clips.first;
    blendClips = List.of(clips);
    blendWeights = List.of(weights);
    blendSpeeds = speeds == null
        ? List.filled(clips.length, 1.0)
        : List.of(speeds);
    phase = 0;
    previousPhase = 0;
    time = 0;
    previousTime = 0;
    cycles = 0;
    playing = true;
  }

  /// Changes the playing blend's weights, every update as its parameters
  /// move; ignored when no blend plays or the count differs.
  void setBlendWeights(List<double> weights) {
    if (weights.length != blendClips.length) return;
    blendWeights = List.of(weights);
  }

  void _fadeFromNow(double seconds) {
    final showing = isBlending || clip.isNotEmpty;
    if (showing && seconds > 0) {
      fadingFrom = isBlending ? '' : clip;
      fadingFromTime = time;
      fadingFromBlend = isBlending ? blendClips : const [];
      fadingFromWeights = isBlending ? blendWeights : const [];
      fadingFromSpeeds = isBlending ? blendSpeeds : const [];
      fadingFromPhase = phase;
      fadingFromSpeed = playing ? speed : 0;
      fadingFromLoop = loop;
      fade = 0;
    } else {
      fadingFrom = '';
      fadingFromBlend = const [];
      fade = 1;
    }
    _fadeSeconds = seconds;
  }

  double _fadeSeconds = 0.2;

  /// The length of the fade under way, seconds (runtime).
  double get fadeSeconds => _fadeSeconds;

  /// Whether something is fading out.
  bool get isFading =>
      fade < 1 && (fadingFrom.isNotEmpty || fadingFromBlend.isNotEmpty);
}

/// Pins its entity to a node of its parent's model — a joint, for a sword
/// in a hand or a hat on a head. The entity must be a child (it has a
/// `ParentComponent`) of an entity with a [ModelComponent]; each update it
/// is moved to that node, keeping its own scale.
class SocketComponent extends Component {
  /// A socket on the node called [node].
  SocketComponent({this.node = ''});

  /// The node's name in the parent's model.
  String node;
}

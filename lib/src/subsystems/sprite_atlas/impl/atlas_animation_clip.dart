part of '../sprite_atlas_subsystem.dart';

/// A single frame within an [AtlasAnimationClip], pairing a [SpriteRegion]
/// name with how long that frame is displayed.
class AtlasFrame {
  /// Name of the [SpriteRegion] to display for this frame.
  final String regionName;

  /// How long this frame is shown, in **seconds**.
  ///
  /// Aseprite exports durations in milliseconds; the [AsepriteAtlasParser]
  /// converts them to seconds automatically.
  final double duration;

  /// A frame showing the region named [regionName] for [duration] seconds.
  const AtlasFrame({required this.regionName, required this.duration});

  @override
  String toString() => 'AtlasFrame("$regionName", ${duration}s)';
}

/// A named, reusable sequence of [AtlasFrame]s that forms one animation
/// (e.g. `"run"`, `"idle"`, `"jump_rise"`).
///
/// ## Source
/// Clips are:
/// - **Embedded** in the atlas JSON when the format supports it (Aseprite
///   `frameTags`, or a custom `"clips"` object in a TexturePacker variant).
/// - **Registered at runtime** via [SpriteAtlas.registerClip] /
///   [SpriteAtlas.registerClips] — useful for overriding imported data or
///   defining clips that span regions from multiple sources.
///
/// ## Per-frame durations
/// Each [AtlasFrame] carries its own [AtlasFrame.duration]; the clip therefore
/// supports mixed-rate animations (e.g. a slow anticipation frame, fast action
/// frames, slow follow-through) with no extra configuration.
class AtlasAnimationClip {
  /// Logical name used to look up this clip in [SpriteAtlas] (e.g. `"run"`).
  final String name;

  /// Ordered playback frames.
  final List<AtlasFrame> frames;

  /// Whether the clip loops after the last frame.
  ///
  /// Defaults to `true`.  Aseprite does not encode a per-tag loop flag, so
  /// all Aseprite-derived clips default to looping; override as needed via
  /// [SpriteAtlas.registerClip].
  final bool loop;

  /// The clip [name], playing [frames] in order and looping unless [loop]
  /// is false. [frames] is kept, not copied: don't change it afterwards.
  const AtlasAnimationClip({
    required this.name,
    required this.frames,
    this.loop = true,
  });

  /// Total wall-clock duration of one full pass through all frames (seconds).
  ///
  /// Worked out once per clip, like [frameEnds]: a clip's [frames] are not
  /// changed once it is made (register a new clip instead).
  double get totalDuration => _timing.total;

  /// When each frame stops showing, in seconds from the start of a pass:
  /// frame `i` shows from `frameEnds[i - 1]` (0 for the first) until
  /// `frameEnds[i]`.
  List<double> get frameEnds => _timing.ends;

  /// The frame showing [time] seconds into a pass — found by halving, not
  /// by walking the frames. Before the start it is the first; at or past
  /// the end, the last. -1 for a clip with no frames.
  int frameIndexAt(double time) {
    final ends = _timing.ends;
    if (ends.isEmpty) return -1;
    var lo = 0, hi = ends.length - 1;
    // The first frame that ends after [time].
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (time < ends[mid]) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    return lo;
  }

  static final Expando<_ClipTiming> _timings = Expando('clip timing');

  _ClipTiming get _timing {
    final known = _timings[this];
    if (known != null && known.ends.length == frames.length) return known;
    return _timings[this] = _ClipTiming(frames);
  }

  @override
  String toString() =>
      'AtlasAnimationClip("$name", ${frames.length} frames, '
      '${totalDuration.toStringAsFixed(3)}s, loop: $loop)';
}

/// A clip's running totals: when each frame ends, and the whole length.
class _ClipTiming {
  _ClipTiming(List<AtlasFrame> frames) : ends = _endsOf(frames);

  final List<double> ends;

  double get total => ends.isEmpty ? 0.0 : ends.last;

  static List<double> _endsOf(List<AtlasFrame> frames) {
    var t = 0.0;
    return List<double>.unmodifiable([
      for (final frame in frames) t += frame.duration,
    ]);
  }
}

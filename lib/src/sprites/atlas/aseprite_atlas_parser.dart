part of 'atlas.dart';

/// Parses Aseprite's JSON export format (both array and hash `frames`).
///
/// Named animation clips are extracted from `meta.frameTags`.  Four
/// playback directions are supported:
///
/// | `direction` value | Frame order |
/// |---|---|
/// | `"forward"`  | `from → to` |
/// | `"reverse"`  | `to → from` |
/// | `"pingpong"` | `from → to → (to-1) → (from+1)` |
/// | `"pingpong_reverse"` | `to → from → (from+1) → (to-1)` |
///
/// A tag's `repeat` count (Aseprite 1.3) makes a clip that plays that many
/// passes and stops — it does not loop. Each pass is the tag's frames once;
/// a ping-pong's passes go there and back in turn, each one after the first
/// leaving out the frame it turns on.
///
/// Per-frame durations (in MS in Aseprite, converted to seconds) produce
/// [AtlasAnimationClip]s that play with exact
/// designer-specified timing.
///
/// ## Aseprite Hash-frames example
/// ```json
/// {
///   "frames": {
///     "player_run 0": {
///       "frame":            { "x": 0,  "y": 0,  "w": 32, "h": 32 },
///       "rotated":          false,
///       "trimmed":          false,
///       "spriteSourceSize": { "x": 0,  "y": 0,  "w": 32, "h": 32 },
///       "sourceSize":       { "w": 32, "h": 32 },
///       "duration":         150
///     },
///     "player_run 1": { ... }
///   },
///   "meta": {
///     "app":       "http://www.aseprite.org/",
///     "image":     "player.png",
///     "size":      { "w": 256, "h": 256 },
///     "frameTags": [
///       { "name": "run",  "from": 0, "to": 7,  "direction": "forward"  },
///       { "name": "idle", "from": 8, "to": 11, "direction": "pingpong" }
///     ]
///   }
/// }
/// ```
class AsepriteAtlasParser extends AtlasParser {
  @override
  SpriteAtlas parse(Map<String, dynamic> json, String basePath) {
    final meta = (json['meta'] as Map<String, dynamic>?) ?? {};
    final imageFile = (meta['image'] as String?) ?? 'atlas.png';
    final sizeMap = (meta['size'] as Map<String, dynamic>?) ?? {};

    final page = SpriteAtlasPage(
      index: 0,
      imagePath: '$basePath$imageFile',
      size: Size(_d(sizeMap['w']), _d(sizeMap['h'])),
    );

    // ── Parse frames ──────────────────────────────────────────────────────
    final rawFrames = json['frames'];

    // orderedRegions preserves insertion order for frameTag index mapping.
    final orderedRegions = <SpriteRegion>[];
    final regions = <String, SpriteRegion>{};

    if (rawFrames is List) {
      for (final entry in rawFrames.cast<Map<String, dynamic>>()) {
        final name = (entry['filename'] as String?) ?? '';
        final region = _buildRegion(name, entry);
        orderedRegions.add(region);
        regions[region.name] = region;
      }
    } else if (rawFrames is Map) {
      for (final entry in rawFrames.entries) {
        final region = _buildRegion(
          entry.key as String,
          entry.value as Map<String, dynamic>,
        );
        orderedRegions.add(region);
        regions[region.name] = region;
      }
    }

    // ── Build AtlasAnimationClips from frameTags ──────────────────────────
    final clips = <String, AtlasAnimationClip>{};
    final frameTags = (meta['frameTags'] as List<dynamic>?) ?? [];

    for (final tagRaw in frameTags) {
      if (tagRaw is! Map) continue;
      final tag = tagRaw.cast<String, dynamic>();
      final clipName = (tag['name'] as String?) ?? '';
      // Some writers put whole numbers down as 3.0.
      var from = _index(tag['from']);
      var to = _index(tag['to']);
      // A range written backwards is still the frames between its ends.
      if (to < from) (from, to) = (to, from);
      final direction = (tag['direction'] as String?) ?? 'forward';
      final repeat = _repeat(tag['repeat']);

      final indices = _resolveIndices(from, to, direction, repeat: repeat);
      final frames = <AtlasFrame>[];

      for (final i in indices) {
        if (i >= 0 && i < orderedRegions.length) {
          final region = orderedRegions[i];
          final durationMs = _frameDurationMs(rawFrames, region.name, i);
          frames.add(
            AtlasFrame(regionName: region.name, duration: durationMs / 1000.0),
          );
        }
      }

      if (frames.isNotEmpty) {
        clips[clipName] = AtlasAnimationClip(
          name: clipName,
          frames: frames,
          // Aseprite's export has no per-tag loop flag, so a clip loops
          // unless it repeats a set number of times, or the tool that wrote
          // the file says otherwise in `meta.just.clips.<name>.loop`.
          loop: _clipLoops(meta, clipName) ?? repeat == null,
        );
      }
    }

    final atlasName = AtlasParser.stripImageExtension(imageFile);
    return SpriteAtlas(
      name: atlasName,
      pages: [page],
      regions: regions,
      clips: clips,
      userData: (meta['just'] as Map?)?.cast<String, dynamic>(),
    );
  }

  /// Whether `meta.just.clips.<clip>.loop` says [clip] loops; null when it
  /// says nothing.
  static bool? _clipLoops(Map<String, dynamic> meta, String clip) {
    final just = meta['just'];
    final clips = just is Map ? just['clips'] : null;
    final entry = clips is Map ? clips[clip] : null;
    final loop = entry is Map ? entry['loop'] : null;
    return loop is bool ? loop : null;
  }

  /// A tag's `repeat` count — written as a string by Aseprite, a number by
  /// others — or null when it repeats for ever (absent, or 0).
  static int? _repeat(Object? value) {
    final count = switch (value) {
      num n when n.isFinite => n.toInt(),
      String s => int.tryParse(s.trim()),
      _ => null,
    };
    return count != null && count > 0 ? count : null;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  SpriteRegion _buildRegion(String name, Map<String, dynamic> data) {
    final frameMap = (data['frame'] as Map<String, dynamic>?) ?? {};
    final sssMap = (data['spriteSourceSize'] as Map<String, dynamic>?) ?? {};
    final ssMap = (data['sourceSize'] as Map<String, dynamic>?) ?? {};
    final frameW = _d(frameMap['w']), frameH = _d(frameMap['h']);

    return SpriteRegion(
      name: name, // Aseprite names kept as-is, e.g. "player_run 0"
      pageIndex: 0,
      frame: Rect.fromLTWH(
        _d(frameMap['x']),
        _d(frameMap['y']),
        frameW,
        frameH,
      ),
      rotated: (data['rotated'] as bool?) ?? false,
      trimmed: (data['trimmed'] as bool?) ?? false,
      spriteSourceOffset: Offset(_d(sssMap['x']), _d(sssMap['y'])),
      // A frame without its untrimmed size is as big as it is, as PixiJS
      // reads it — not zero, which drew nothing.
      sourceSize: Size(
        _d(ssMap['w'], fallback: frameW),
        _d(ssMap['h'], fallback: frameH),
      ),
    );
  }

  /// Convert a `from/to/direction` tag into an ordered list of frame
  /// indices, played [repeat] passes when it is given.
  List<int> _resolveIndices(int from, int to, String direction, {int? repeat}) {
    final forward = List<int>.generate(to - from + 1, (i) => from + i);
    final backward = forward.reversed.toList();
    final pingPong = direction == 'pingpong' || direction == 'pingpong_reverse';
    final first = direction == 'reverse' || direction == 'pingpong_reverse'
        ? backward
        : forward;
    if (repeat != null) {
      if (!pingPong || forward.length < 2) {
        return [for (var i = 0; i < repeat; i++) ...first];
      }
      // Passes there and back in turn; after the first, each leaves out
      // the frame it turns on, which the pass before ended with.
      final second = identical(first, forward) ? backward : forward;
      return [
        ...first,
        for (var i = 1; i < repeat; i++) ...(i.isOdd ? second : first).skip(1),
      ];
    }
    if (!pingPong) return first;
    // There and back, leaving out both ends of the way back: the turning
    // frame is not shown twice, and neither is the first when the clip
    // loops round to it.
    return [
      ...first,
      if (first.length > 2) ...first.reversed.skip(1).take(first.length - 2),
    ];
  }

  /// Look up the per-frame duration in milliseconds from the raw frames data.
  ///
  /// Falls back to 100 ms (10 fps) if the duration field is absent.
  double _frameDurationMs(dynamic rawFrames, String name, int fallbackIndex) {
    if (rawFrames is List) {
      if (fallbackIndex < rawFrames.length) {
        final entry = rawFrames[fallbackIndex] as Map<String, dynamic>;
        return _d(entry['duration'], fallback: 100.0);
      }
    } else if (rawFrames is Map) {
      final entry = rawFrames[name] as Map<String, dynamic>?;
      if (entry != null) return _d(entry['duration'], fallback: 100.0);
    }
    return 100.0;
  }

  // ── Micro-utilities ───────────────────────────────────────────────────────

  static double _d(dynamic v, {double fallback = 0.0}) =>
      v != null ? (v as num).toDouble() : fallback;

  /// A frame index as written: an int, or a whole double; 0 otherwise.
  static int _index(Object? v) => v is num && v.isFinite ? v.toInt() : 0;
}

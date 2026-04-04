part of '../sprite_atlas_subsystem.dart';

/// Parses Aseprite's JSON export format (both array and hash `frames`).
///
/// Named animation clips are extracted from `meta.frameTags`.  Three
/// playback directions are supported:
///
/// | `direction` value | Frame order |
/// |---|---|
/// | `"forward"`  | `from → to` |
/// | `"reverse"`  | `to → from` |
/// | `"pingpong"` | `from → to → (to-1) → from` |
///
/// Per-frame durations (in MS in Aseprite, converted to seconds) produce
/// [AtlasAnimationClip]s that drive [AtlasSpriteAnimation] with exact
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
  Future<SpriteAtlas> parse(Map<String, dynamic> json, String basePath) async {
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
      final tag = tagRaw as Map<String, dynamic>;
      final clipName = (tag['name'] as String?) ?? '';
      final from = (tag['from'] as int?) ?? 0;
      final to = (tag['to'] as int?) ?? 0;
      final direction = (tag['direction'] as String?) ?? 'forward';

      final indices = _resolveIndices(from, to, direction);
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
          // Aseprite does not encode a per-tag loop flag; default to true.
          loop: true,
        );
      }
    }

    final atlasName = _stripExtension(imageFile);
    return SpriteAtlas(
      name: atlasName,
      pages: [page],
      regions: regions,
      clips: clips,
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  SpriteRegion _buildRegion(String name, Map<String, dynamic> data) {
    final frameMap = (data['frame'] as Map<String, dynamic>?) ?? {};
    final sssMap = (data['spriteSourceSize'] as Map<String, dynamic>?) ?? {};
    final ssMap = (data['sourceSize'] as Map<String, dynamic>?) ?? {};

    return SpriteRegion(
      name: name, // Aseprite names kept as-is, e.g. "player_run 0"
      pageIndex: 0,
      frame: Rect.fromLTWH(
        _d(frameMap['x']),
        _d(frameMap['y']),
        _d(frameMap['w']),
        _d(frameMap['h']),
      ),
      rotated: (data['rotated'] as bool?) ?? false,
      trimmed: (data['trimmed'] as bool?) ?? false,
      spriteSourceOffset: Offset(_d(sssMap['x']), _d(sssMap['y'])),
      sourceSize: Size(_d(ssMap['w']), _d(ssMap['h'])),
    );
  }

  /// Convert a `from/to/direction` tag into an ordered list of frame indices.
  List<int> _resolveIndices(int from, int to, String direction) {
    final forward = List<int>.generate(to - from + 1, (i) => from + i);
    switch (direction) {
      case 'reverse':
        return forward.reversed.toList();
      case 'pingpong':
        // forward + backward excluding the shared endpoints to avoid duplicates.
        return [...forward, ...forward.reversed.skip(1)];
      default:
        return forward;
    }
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

  static String _stripExtension(String name) {
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }
}

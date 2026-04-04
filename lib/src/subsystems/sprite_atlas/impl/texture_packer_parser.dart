part of '../sprite_atlas_subsystem.dart';

/// Parses the three TexturePacker JSON export variants into a [SpriteAtlas].
///
/// ## Supported variants
///
/// ### JSON-Array (single texture)
/// ```json
/// {
///   "frames": [
///     {
///       "filename":          "player_run_0.png",
///       "frame":             { "x": 0,  "y": 0,  "w": 32, "h": 32 },
///       "rotated":           false,
///       "trimmed":           true,
///       "spriteSourceSize":  { "x": 2,  "y": 4,  "w": 28, "h": 24 },
///       "sourceSize":        { "w": 32, "h": 32 },
///       "pivot":             { "x": 0.5, "y": 0.5 }
///     }
///   ],
///   "meta": {
///     "app":   "https://www.codeandweb.com/texturepacker",
///     "image": "atlas.png",
///     "size":  { "w": 256, "h": 256 }
///   }
/// }
/// ```
///
/// ### JSON-Hash (single texture)
/// Same as Array but `"frames"` is a JSON object keyed by filename instead
/// of a list.
///
/// ### Multi-page
/// ```json
/// {
///   "textures": [
///     {
///       "image":  "atlas_0.png",
///       "size":   { "w": 2048, "h": 2048 },
///       "frames": [ ... ]
///     },
///     {
///       "image":  "atlas_1.png",
///       "size":   { "w": 2048, "h": 2048 },
///       "frames": [ ... ]
///     }
///   ],
///   "meta": { "app": "https://www.codeandweb.com/texturepacker", ... }
/// }
/// ```
///
/// The variant is detected automatically from the JSON structure — the caller
/// does not need to specify which variant is in use.
class TexturePackerAtlasParser extends AtlasParser {
  @override
  Future<SpriteAtlas> parse(Map<String, dynamic> json, String basePath) async {
    final meta = (json['meta'] as Map<String, dynamic>?) ?? {};
    final regions = <String, SpriteRegion>{};
    final pages = <SpriteAtlasPage>[];

    if (json.containsKey('textures')) {
      // ── Multi-page variant ────────────────────────────────────────────────
      final textureList = json['textures'] as List<dynamic>;
      for (int i = 0; i < textureList.length; i++) {
        final pageJson = textureList[i] as Map<String, dynamic>;
        _addPage(pageJson, i, basePath, pages);
        _parseFrames(pageJson, i, regions);
      }
    } else {
      // ── Single-page variant (JSON-Array or JSON-Hash) ─────────────────────
      final imageFile = (meta['image'] as String?) ?? 'atlas.png';
      final sizeMap = (meta['size'] as Map<String, dynamic>?) ?? {};
      pages.add(
        SpriteAtlasPage(
          index: 0,
          imagePath: '$basePath$imageFile',
          size: _sizeFromMap(sizeMap),
        ),
      );
      _parseFrames(json, 0, regions);
    }

    final atlasName = _stripExtension((meta['image'] as String?) ?? 'atlas');
    return SpriteAtlas(name: atlasName, pages: pages, regions: regions);
  }

  // ── Internal helpers ──────────────────────────────────────────────────────

  void _addPage(
    Map<String, dynamic> pageJson,
    int index,
    String basePath,
    List<SpriteAtlasPage> pages,
  ) {
    final imageFile = (pageJson['image'] as String?) ?? 'atlas_$index.png';
    final sizeMap = (pageJson['size'] as Map<String, dynamic>?) ?? {};
    pages.add(
      SpriteAtlasPage(
        index: index,
        imagePath: '$basePath$imageFile',
        size: _sizeFromMap(sizeMap),
      ),
    );
  }

  void _parseFrames(
    Map<String, dynamic> pageJson,
    int pageIndex,
    Map<String, SpriteRegion> regions,
  ) {
    final rawFrames = pageJson['frames'];

    if (rawFrames is List) {
      // JSON-Array variant
      for (final entry in rawFrames.cast<Map<String, dynamic>>()) {
        final filename = (entry['filename'] as String?) ?? '';
        final region = _buildRegion(filename, entry, pageIndex);
        regions[region.name] = region;
      }
    } else if (rawFrames is Map) {
      // JSON-Hash variant
      for (final entry in rawFrames.entries) {
        final region = _buildRegion(
          entry.key as String,
          entry.value as Map<String, dynamic>,
          pageIndex,
        );
        regions[region.name] = region;
      }
    }
  }

  SpriteRegion _buildRegion(
    String filename,
    Map<String, dynamic> data,
    int pageIndex,
  ) {
    final frameMap = (data['frame'] as Map<String, dynamic>?) ?? {};
    final sssMap = (data['spriteSourceSize'] as Map<String, dynamic>?) ?? {};
    final ssMap = (data['sourceSize'] as Map<String, dynamic>?) ?? {};
    final pivotMap = data['pivot'] as Map<String, dynamic>?;

    return SpriteRegion(
      name: _stripExtension(filename),
      pageIndex: pageIndex,
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
      pivot: pivotMap != null
          ? Offset(
              _d(pivotMap['x'], fallback: 0.5),
              _d(pivotMap['y'], fallback: 0.5),
            )
          : const Offset(0.5, 0.5),
    );
  }

  // ── Micro-utilities ───────────────────────────────────────────────────────

  static Size _sizeFromMap(Map<String, dynamic> m) =>
      Size(_d(m['w']), _d(m['h']));

  static double _d(dynamic v, {double fallback = 0.0}) =>
      v != null ? (v as num).toDouble() : fallback;

  static String _stripExtension(String name) {
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }
}

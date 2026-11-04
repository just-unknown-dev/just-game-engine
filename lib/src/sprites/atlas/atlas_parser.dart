part of 'atlas.dart';

/// Common interface for all sprite atlas parsers.
///
/// Parsers transform a decoded JSON map into a [SpriteAtlas] data model.
/// All image I/O (page loading) is handled by [SpriteAtlasPage.loadImage]
/// after parsing; parsers work purely on JSON structure and perform no async
/// operations themselves (except returning a Future for API consistency).
abstract class AtlasParser {
  /// Parse [json] into a [SpriteAtlas].
  ///
  /// [basePath] is the directory component of the atlas JSON file path
  /// (e.g. `"assets/sprites/"`) used to resolve relative texture paths.
  Future<SpriteAtlas> parse(Map<String, dynamic> json, String basePath);

  // ── Format detection ──────────────────────────────────────────────────────

  /// Inspect [json] and return the appropriate parser.
  ///
  /// Detection heuristics (evaluated in order):
  ///
  /// | Condition | Parser selected |
  /// |---|---|
  /// | `meta.app` contains `"aseprite"` | [AsepriteAtlasParser] |
  /// | Top-level `"textures"` list | [TexturePackerAtlasParser] (multi-page) |
  /// | `"frames"` is a JSON array | [TexturePackerAtlasParser] (JSON-Array) |
  /// | `"frames"` is a JSON object | [TexturePackerAtlasParser] (JSON-Hash) |
  /// | Fallback | [TexturePackerAtlasParser] |
  static AtlasParser detect(Map<String, dynamic> json, {String? jsonPath}) {
    if (GridSheetAtlasParser.matches(json)) {
      // That format never named its image; assume it sits beside the JSON.
      final file = (jsonPath ?? '').split('/').last;
      final dot = file.lastIndexOf('.');
      return GridSheetAtlasParser(
        imageFallback: dot > 0 ? '${file.substring(0, dot)}.png' : 'sheet.png',
      );
    }
    final meta = json['meta'] as Map<String, dynamic>?;
    final app = ((meta?['app'] as String?) ?? '').toLowerCase();
    if (app.contains('aseprite')) return AsepriteAtlasParser();
    return TexturePackerAtlasParser();
  }

  /// [name] without its image-file extension (`.png`, `.jpg`, … in any
  /// case), as packers name frames after the files they packed. Only an
  /// extension after the last `/` counts, and only an image one: frames
  /// named `coin.1` and `coin.2`, or a folder `ui.v2/button`, keep their
  /// dots.
  static String stripImageExtension(String name) {
    final slash = name.lastIndexOf('/');
    final dot = name.lastIndexOf('.');
    if (dot <= slash + 1) return name;
    final extension = name.substring(dot + 1).toLowerCase();
    return _imageExtensions.contains(extension) ? name.substring(0, dot) : name;
  }

  static const Set<String> _imageExtensions = {
    'png',
    'jpg',
    'jpeg',
    'gif',
    'webp',
    'bmp',
    'tga',
    'tif',
    'tiff',
    'psd',
    'ase',
    'aseprite',
    'svg',
    'avif',
    'ktx',
    'ktx2',
    'dds',
    'pvr',
  };
}

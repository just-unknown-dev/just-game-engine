part of '../sprite_atlas_subsystem.dart';

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
  static AtlasParser detect(Map<String, dynamic> json) {
    final meta = json['meta'] as Map<String, dynamic>?;
    final app = ((meta?['app'] as String?) ?? '').toLowerCase();
    if (app.contains('aseprite')) return AsepriteAtlasParser();
    return TexturePackerAtlasParser();
  }
}

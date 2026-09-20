part of '../sprite_atlas_subsystem.dart';

/// Parses the engine's older "grid sheet" animation JSON, so files written
/// for the retired `AnimatedSpriteComponent` still play:
///
/// ```json
/// {
///   "meta":  { "image": "hero.png", "frameWidth": 32, "frameHeight": 32,
///              "columns": 4, "rows": 2 },
///   "clips": { "run":  { "frames": [0, 1, 2, 3], "fps": 12, "loop": true },
///              "idle": { "row": 1, "start": 0, "end": 1 } }
/// }
/// ```
///
/// Every cell becomes a region named by its index (`"0"`, `"1"`, …), and a
/// clip's `fps` becomes the same duration on each of its frames. The file
/// never named its image — the component did — so without `meta.image` the
/// sheet is taken to sit beside the JSON with the same name and `.png`;
/// [imageFallback] supplies that name.
class GridSheetAtlasParser extends AtlasParser {
  GridSheetAtlasParser({this.imageFallback = 'sheet.png'});

  final String imageFallback;

  /// Whether [json] is a grid sheet: a frame size and no `frames`.
  static bool matches(Map<String, dynamic> json) {
    final meta = json['meta'];
    return json['frames'] == null &&
        meta is Map &&
        meta['frameWidth'] is num &&
        meta['frameHeight'] is num;
  }

  @override
  Future<SpriteAtlas> parse(Map<String, dynamic> json, String basePath) async {
    final meta = (json['meta'] as Map).cast<String, dynamic>();
    final width = (meta['frameWidth'] as num).toDouble();
    final height = (meta['frameHeight'] as num).toDouble();
    final columns = ((meta['columns'] as num?)?.toInt() ?? 1).clamp(1, 4096);
    final rows = ((meta['rows'] as num?)?.toInt() ?? 1).clamp(1, 4096);
    final imageFile = (meta['image'] as String?) ?? imageFallback;
    final defaultFps = (meta['fps'] as num?)?.toDouble() ?? 12.0;

    final regions = <String, SpriteRegion>{
      for (var i = 0; i < columns * rows; i++)
        '$i': SpriteRegion(
          name: '$i',
          pageIndex: 0,
          frame: Rect.fromLTWH(
            (i % columns) * width,
            (i ~/ columns) * height,
            width,
            height,
          ),
          sourceSize: Size(width, height),
        ),
    };

    final clips = <String, AtlasAnimationClip>{};
    final rawClips = json['clips'];
    if (rawClips is Map) {
      for (final entry in rawClips.entries) {
        final clip = entry.value;
        if (clip is! Map) continue;
        final List<int> frames;
        if (clip['frames'] is List) {
          frames = [for (final f in clip['frames'] as List) (f as num).toInt()];
        } else {
          final row = (clip['row'] as num?)?.toInt() ?? 0;
          final start = (clip['start'] as num?)?.toInt() ?? 0;
          final end = (clip['end'] as num?)?.toInt() ?? columns - 1;
          frames = [for (var c = start; c <= end; c++) row * columns + c];
        }
        final fps = (clip['fps'] as num?)?.toDouble() ?? defaultFps;
        final duration = fps > 0 ? 1 / fps : 0.1;
        clips['${entry.key}'] = AtlasAnimationClip(
          name: '${entry.key}',
          frames: [
            for (final f in frames)
              if (regions.containsKey('$f'))
                AtlasFrame(regionName: '$f', duration: duration),
          ],
          loop: clip['loop'] is bool ? clip['loop'] as bool : true,
        );
      }
    }

    return SpriteAtlas(
      name: imageFile.contains('.')
          ? imageFile.substring(0, imageFile.lastIndexOf('.'))
          : imageFile,
      pages: [
        SpriteAtlasPage(
          index: 0,
          imagePath: '$basePath$imageFile',
          size: Size(columns * width, rows * height),
        ),
      ],
      regions: regions,
      clips: clips,
    );
  }
}

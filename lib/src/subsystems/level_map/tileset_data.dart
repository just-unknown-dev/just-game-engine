/// A tileset: an image cut into tiles, and what each tile means.
library;

import 'dart:math' as math;
import 'dart:ui';

import 'tile_properties.dart';

// ── Collision ──────────────────────────────────────────────────────────────

/// One shape of a tile's collision, in the tile image's own pixels (0,0 is
/// the image's top-left).
sealed class TileShape {
  const TileShape();

  /// The shape as a closed outline. An ellipse becomes [segments] points.
  List<Offset> outline({int segments = 12});

  /// The shape with every point passed through [f].
  TileShape map(Offset Function(Offset p) f);

  Map<String, dynamic> toJson();

  static TileShape? fromJson(Object? json) {
    if (json is! Map) return null;
    double n(String key) => (json[key] as num?)?.toDouble() ?? 0;
    switch (json['type']) {
      case 'rect':
        return TileRectShape(Rect.fromLTWH(n('x'), n('y'), n('w'), n('h')));
      case 'ellipse':
        return TileEllipseShape(Rect.fromLTWH(n('x'), n('y'), n('w'), n('h')));
      case 'polygon':
        final points = json['points'];
        if (points is! List) return null;
        final out = <Offset>[];
        for (var i = 0; i + 1 < points.length; i += 2) {
          out.add(
            Offset(
              (points[i] as num).toDouble(),
              (points[i + 1] as num).toDouble(),
            ),
          );
        }
        return out.length < 3 ? null : TilePolygonShape(out);
      default:
        return null;
    }
  }
}

/// An axis-aligned box.
class TileRectShape extends TileShape {
  const TileRectShape(this.rect);
  final Rect rect;

  @override
  List<Offset> outline({int segments = 12}) => [
    rect.topLeft,
    rect.topRight,
    rect.bottomRight,
    rect.bottomLeft,
  ];

  @override
  TileShape map(Offset Function(Offset p) f) {
    final a = f(rect.topLeft);
    final b = f(rect.bottomRight);
    return TileRectShape(Rect.fromPoints(a, b));
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'rect',
    'x': rect.left,
    'y': rect.top,
    'w': rect.width,
    'h': rect.height,
  };

  @override
  bool operator ==(Object other) =>
      other is TileRectShape && other.rect == rect;

  @override
  int get hashCode => rect.hashCode;
}

/// An ellipse inscribed in [bounds].
class TileEllipseShape extends TileShape {
  const TileEllipseShape(this.bounds);
  final Rect bounds;

  @override
  List<Offset> outline({int segments = 12}) => [
    for (var i = 0; i < segments; i++)
      bounds.center +
          Offset(
            math.cos(2 * math.pi * i / segments) * bounds.width / 2,
            math.sin(2 * math.pi * i / segments) * bounds.height / 2,
          ),
  ];

  @override
  TileShape map(Offset Function(Offset p) f) => TileEllipseShape(
    Rect.fromPoints(f(bounds.topLeft), f(bounds.bottomRight)),
  );

  @override
  Map<String, dynamic> toJson() => {
    'type': 'ellipse',
    'x': bounds.left,
    'y': bounds.top,
    'w': bounds.width,
    'h': bounds.height,
  };

  @override
  bool operator ==(Object other) =>
      other is TileEllipseShape && other.bounds == bounds;

  @override
  int get hashCode => bounds.hashCode;
}

/// A polygon, convex or not; the collision builder splits it as needed.
class TilePolygonShape extends TileShape {
  const TilePolygonShape(this.points);
  final List<Offset> points;

  @override
  List<Offset> outline({int segments = 12}) => points;

  @override
  TileShape map(Offset Function(Offset p) f) =>
      TilePolygonShape([for (final p in points) f(p)]);

  @override
  Map<String, dynamic> toJson() => {
    'type': 'polygon',
    'points': [
      for (final p in points) ...[p.dx, p.dy],
    ],
  };

  @override
  bool operator ==(Object other) =>
      other is TilePolygonShape &&
      other.points.length == points.length &&
      Iterable.generate(
        points.length,
      ).every((i) => other.points[i] == points[i]);

  @override
  int get hashCode => Object.hashAll(points);
}

/// What a tile does when something runs into it.
class TileCollision {
  TileCollision({this.kind = 'solid', List<TileShape>? shapes})
    : shapes = shapes ?? [];

  /// The whole tile, [width] by [height].
  factory TileCollision.full(num width, num height, {String kind = 'solid'}) =>
      TileCollision(
        kind: kind,
        shapes: [
          TileRectShape(
            Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
          ),
        ],
      );

  /// What sort of collision: `solid`, `oneWay`, or one a game registers
  /// (`hazard`, say). See `MapCollisionKinds`.
  String kind;

  /// Where, in the tile image's pixels.
  List<TileShape> shapes;

  /// Whether this is one box covering the whole [width] × [height] tile —
  /// the case that merges with its neighbours into long boxes.
  bool isFullCell(num width, num height) =>
      shapes.length == 1 &&
      shapes.single is TileRectShape &&
      (shapes.single as TileRectShape).rect ==
          Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'shapes': [for (final s in shapes) s.toJson()],
  };

  static TileCollision? fromJson(Object? json) {
    if (json is! Map) return null;
    return TileCollision(
      kind: json['kind'] as String? ?? 'solid',
      shapes: [
        for (final s in json['shapes'] as List? ?? const [])
          ?TileShape.fromJson(s),
      ],
    );
  }

  TileCollision copy() => TileCollision(kind: kind, shapes: [...shapes]);
}

// ── Animation ──────────────────────────────────────────────────────────────

/// One frame of an animated tile: which tile of the same tileset to show,
/// and for how long.
class TileFrame {
  const TileFrame(this.tileId, this.durationMs);
  final int tileId;
  final int durationMs;

  @override
  bool operator ==(Object other) =>
      other is TileFrame &&
      other.tileId == tileId &&
      other.durationMs == durationMs;

  @override
  int get hashCode => Object.hash(tileId, durationMs);
}

// ── Per-tile data ──────────────────────────────────────────────────────────

/// What a tileset says about one of its tiles. Only tiles that say
/// something have one.
class TileDef {
  TileDef({
    this.className = '',
    this.probability = 1,
    TileProperties? properties,
    this.collision,
    List<TileFrame>? animation,
  }) : properties = properties ?? TileProperties(),
       animation = animation ?? [];

  /// A free-form class, as in Tiled.
  String className;

  /// How often a random brush or a terrain brush picks this tile, relative
  /// to the others it could pick.
  double probability;

  TileProperties properties;

  /// Null for a tile nothing collides with.
  TileCollision? collision;

  /// Two frames or more make an animated tile.
  List<TileFrame> animation;

  bool get isAnimated => animation.length > 1;

  /// Total length of one loop of the animation, in milliseconds.
  int get animationLengthMs =>
      animation.fold(0, (sum, f) => sum + math.max(1, f.durationMs));

  /// The tile shown [timeMs] into the animation, or [ownId] when there is
  /// none.
  int frameAt(int ownId, int timeMs) {
    if (!isAnimated) return ownId;
    var t = timeMs % animationLengthMs;
    for (final frame in animation) {
      final d = math.max(1, frame.durationMs);
      if (t < d) return frame.tileId;
      t -= d;
    }
    return animation.last.tileId;
  }

  /// Whether it says nothing a default tile does not.
  bool get isDefault =>
      className.isEmpty &&
      probability == 1 &&
      properties.isEmpty &&
      collision == null &&
      animation.isEmpty;

  Map<String, dynamic> toJson() => {
    if (className.isNotEmpty) 'class': className,
    if (probability != 1) 'probability': probability,
    if (properties.isNotEmpty) 'properties': properties.toJson(),
    if (collision != null) 'collision': collision!.toJson(),
    if (animation.isNotEmpty)
      'animation': [
        for (final f in animation) [f.tileId, f.durationMs],
      ],
  };

  static TileDef fromJson(Map<String, dynamic> json) => TileDef(
    className: json['class'] as String? ?? '',
    probability: (json['probability'] as num?)?.toDouble() ?? 1,
    properties: TileProperties.fromJson(json['properties']),
    collision: TileCollision.fromJson(json['collision']),
    animation: [
      for (final f in json['animation'] as List? ?? const [])
        if (f is List && f.length >= 2)
          TileFrame((f[0] as num).toInt(), (f[1] as num).toInt()),
    ],
  );

  TileDef copy() => TileDef(
    className: className,
    probability: probability,
    properties: properties.copy(),
    collision: collision?.copy(),
    animation: [...animation],
  );
}

// ── Terrain ────────────────────────────────────────────────────────────────

/// What a terrain set matches tiles by — Tiled's Wang set types.
enum WangType {
  /// The four corners of a tile.
  corner,

  /// The four edges of a tile.
  edge,

  /// Corners and edges together.
  mixed;

  static WangType fromName(String? name) =>
      values.firstWhere((t) => t.name == name, orElse: () => corner);
}

/// One terrain: grass, water, a road.
class WangColorData {
  WangColorData({
    this.name = '',
    this.color = 0xFFFF0000,
    this.tile = -1,
    this.probability = 1,
    this.className = '',
    TileProperties? properties,
  }) : properties = properties ?? TileProperties();

  String name;

  /// ARGB, how the editor shows it.
  int color;

  /// A tile that stands for it, or -1.
  int tile;

  /// How often the brush picks tiles of it, relative to the others.
  double probability;

  String className;
  TileProperties properties;

  Map<String, dynamic> toJson() => {
    'name': name,
    'color': color,
    if (tile >= 0) 'tile': tile,
    if (probability != 1) 'probability': probability,
    if (className.isNotEmpty) 'class': className,
    if (properties.isNotEmpty) 'properties': properties.toJson(),
  };

  static WangColorData fromJson(Map<String, dynamic> json) => WangColorData(
    name: json['name'] as String? ?? '',
    color: (json['color'] as num?)?.toInt() ?? 0xFFFF0000,
    tile: (json['tile'] as num?)?.toInt() ?? -1,
    probability: (json['probability'] as num?)?.toDouble() ?? 1,
    className: json['class'] as String? ?? '',
    properties: TileProperties.fromJson(json['properties']),
  );

  WangColorData copy() => WangColorData(
    name: name,
    color: color,
    tile: tile,
    probability: probability,
    className: className,
    properties: properties.copy(),
  );
}

/// A set of terrains, and which corners or edges of which tiles are which.
///
/// A Wang id is eight colour indices, clockwise from the top: top edge,
/// top-right corner, right edge, bottom-right corner, bottom edge,
/// bottom-left corner, left edge, top-left corner. Colours count from 1;
/// 0 means "none". A corner set only uses the corner slots and an edge set
/// only the edge slots.
class WangSetData {
  WangSetData({
    this.name = '',
    this.type = WangType.corner,
    this.tile = -1,
    List<WangColorData>? colors,
    Map<int, List<int>>? wangIds,
    this.className = '',
    TileProperties? properties,
  }) : colors = colors ?? [],
       wangIds = wangIds ?? {},
       properties = properties ?? TileProperties();

  /// Slot indices.
  static const int top = 0;
  static const int topRight = 1;
  static const int right = 2;
  static const int bottomRight = 3;
  static const int bottom = 4;
  static const int bottomLeft = 5;
  static const int left = 6;
  static const int topLeft = 7;
  static const List<int> cornerSlots = [
    topRight,
    bottomRight,
    bottomLeft,
    topLeft,
  ];
  static const List<int> edgeSlots = [top, right, bottom, left];

  String name;
  WangType type;

  /// A tile that stands for the set, or -1.
  int tile;

  /// The terrains; colour 1 is `colors[0]`.
  List<WangColorData> colors;

  /// Each tile's Wang id, by tile id.
  Map<int, List<int>> wangIds;

  String className;
  TileProperties properties;

  /// The slots this set's type uses.
  List<int> get slots => switch (type) {
    WangType.corner => cornerSlots,
    WangType.edge => edgeSlots,
    WangType.mixed => const [0, 1, 2, 3, 4, 5, 6, 7],
  };

  Map<String, dynamic> toJson() => {
    'name': name,
    'type': type.name,
    if (tile >= 0) 'tile': tile,
    'colors': [for (final c in colors) c.toJson()],
    'tiles': {
      // Copies: a saved form shares nothing with the set, so a snapshot
      // taken before an edit is not changed by it.
      for (final id in wangIds.keys.toList()..sort()) '$id': [...wangIds[id]!],
    },
    if (className.isNotEmpty) 'class': className,
    if (properties.isNotEmpty) 'properties': properties.toJson(),
  };

  static WangSetData fromJson(Map<String, dynamic> json) => WangSetData(
    name: json['name'] as String? ?? '',
    type: WangType.fromName(json['type'] as String?),
    tile: (json['tile'] as num?)?.toInt() ?? -1,
    colors: [
      for (final c in json['colors'] as List? ?? const [])
        if (c is Map) WangColorData.fromJson(c.cast<String, dynamic>()),
    ],
    wangIds: {
      for (final e in (json['tiles'] as Map? ?? const {}).entries)
        if (int.tryParse('${e.key}') != null && e.value is List)
          int.parse('${e.key}'): [
            for (var i = 0; i < 8; i++)
              i < (e.value as List).length
                  ? ((e.value as List)[i] as num).toInt()
                  : 0,
          ],
    },
    className: json['class'] as String? ?? '',
    properties: TileProperties.fromJson(json['properties']),
  );

  WangSetData copy() => WangSetData(
    name: name,
    type: type,
    tile: tile,
    colors: [for (final c in colors) c.copy()],
    wangIds: {
      for (final e in wangIds.entries) e.key: [...e.value],
    },
    className: className,
    properties: properties.copy(),
  );
}

/// Which ways a terrain brush may turn this tileset's tiles to find a
/// match — Tiled's tileset transformations.
class TileTransformations {
  const TileTransformations({
    this.hflip = false,
    this.vflip = false,
    this.rotate = false,
    this.preferUntransformed = false,
  });

  final bool hflip;
  final bool vflip;
  final bool rotate;
  final bool preferUntransformed;

  bool get any => hflip || vflip || rotate;

  Map<String, dynamic> toJson() => {
    if (hflip) 'hflip': true,
    if (vflip) 'vflip': true,
    if (rotate) 'rotate': true,
    if (preferUntransformed) 'preferUntransformed': true,
  };

  static TileTransformations fromJson(Object? json) => json is Map
      ? TileTransformations(
          hflip: json['hflip'] == true,
          vflip: json['vflip'] == true,
          rotate: json['rotate'] == true,
          preferUntransformed: json['preferUntransformed'] == true,
        )
      : const TileTransformations();
}

// ── The tileset ────────────────────────────────────────────────────────────

/// A `.tileset.json`: an image cut into a grid of tiles, and what the tiles
/// mean — collision, animation, terrain, properties.
///
/// Tile ids count across and then down the image, from 0. [columns] is kept
/// rather than worked out from the image, because a tileset whose image
/// grows wider would otherwise renumber every tile painted with it.
class TilesetData {
  TilesetData({
    this.name = '',
    this.image = '',
    this.imageWidth = 0,
    this.imageHeight = 0,
    this.tileWidth = 32,
    this.tileHeight = 32,
    this.margin = 0,
    this.spacing = 0,
    this.columns = 0,
    this.tileCount = 0,
    this.tileOffsetX = 0,
    this.tileOffsetY = 0,
    this.className = '',
    TileProperties? properties,
    Map<int, TileDef>? tiles,
    List<WangSetData>? wangSets,
    this.transformations = const TileTransformations(),
  }) : properties = properties ?? TileProperties(),
       tiles = tiles ?? {},
       wangSets = wangSets ?? [];

  /// A tileset cutting [imageWidth] × [imageHeight] into [tileWidth] ×
  /// [tileHeight] tiles, [margin] from the edge and [spacing] apart.
  factory TilesetData.fromImage({
    required String name,
    required String image,
    required int imageWidth,
    required int imageHeight,
    required int tileWidth,
    required int tileHeight,
    int margin = 0,
    int spacing = 0,
  }) {
    final columns = gridCount(imageWidth, tileWidth, margin, spacing);
    final rows = gridCount(imageHeight, tileHeight, margin, spacing);
    return TilesetData(
      name: name,
      image: image,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      tileWidth: tileWidth,
      tileHeight: tileHeight,
      margin: margin,
      spacing: spacing,
      columns: columns,
      tileCount: columns * rows,
    );
  }

  /// How many [tile]-sized cells fit along [length] of image — Tiled's
  /// count, which takes the margin off one side only: an image whose last
  /// tile runs into the far margin still has that tile.
  static int gridCount(int length, int tile, int margin, int spacing) {
    if (tile <= 0) return 0;
    return math.max(0, (length - margin + spacing) ~/ (tile + spacing));
  }

  /// Version of the saved form.
  static const int format = 1;

  String name;

  /// The image, project-relative.
  String image;

  /// The image's size, as last seen.
  int imageWidth;
  int imageHeight;

  int tileWidth;
  int tileHeight;
  int margin;
  int spacing;
  int columns;
  int tileCount;

  /// Where tiles draw relative to their cell, in pixels.
  double tileOffsetX;
  double tileOffsetY;

  String className;
  TileProperties properties;

  /// What each tile that says something says.
  Map<int, TileDef> tiles;

  List<WangSetData> wangSets;
  TileTransformations transformations;

  /// Bumped by whoever changes the tileset, so the maps drawing it know.
  int revision = 0;

  void touch() => revision++;

  /// Rows of tiles.
  int get rows => columns <= 0 ? 0 : (tileCount + columns - 1) ~/ columns;

  /// Where tile [localId] is in the image.
  Rect sourceRect(int localId) {
    if (columns <= 0) return Rect.zero;
    final col = localId % columns;
    final row = localId ~/ columns;
    return Rect.fromLTWH(
      (margin + col * (tileWidth + spacing)).toDouble(),
      (margin + row * (tileHeight + spacing)).toDouble(),
      tileWidth.toDouble(),
      tileHeight.toDouble(),
    );
  }

  /// Whether [localId] is one of its tiles.
  bool contains(int localId) => localId >= 0 && localId < tileCount;

  /// What tile [id] says, or null for a plain tile.
  TileDef? tile(int id) => tiles[id];

  /// What tile [id] says, made if it said nothing yet.
  TileDef tileOrNew(int id) => tiles.putIfAbsent(id, TileDef.new);

  /// Drops [id]'s entry if it no longer says anything.
  void prune(int id) {
    if (tiles[id]?.isDefault ?? false) tiles.remove(id);
  }

  Map<String, dynamic> toJson() => {
    'format': format,
    'name': name,
    'image': image,
    'imageWidth': imageWidth,
    'imageHeight': imageHeight,
    'tileWidth': tileWidth,
    'tileHeight': tileHeight,
    if (margin != 0) 'margin': margin,
    if (spacing != 0) 'spacing': spacing,
    'columns': columns,
    'tileCount': tileCount,
    if (tileOffsetX != 0 || tileOffsetY != 0)
      'tileOffset': [tileOffsetX, tileOffsetY],
    if (className.isNotEmpty) 'class': className,
    if (properties.isNotEmpty) 'properties': properties.toJson(),
    if (transformations.any || transformations.preferUntransformed)
      'transformations': transformations.toJson(),
    'tiles': {
      for (final id in tiles.keys.toList()..sort())
        if (!tiles[id]!.isDefault) '$id': tiles[id]!.toJson(),
    },
    if (wangSets.isNotEmpty) 'wangSets': [for (final w in wangSets) w.toJson()],
  };

  static TilesetData fromJson(Map<String, dynamic> json) {
    final offset = json['tileOffset'];
    return TilesetData(
      name: json['name'] as String? ?? '',
      image: json['image'] as String? ?? '',
      imageWidth: (json['imageWidth'] as num?)?.toInt() ?? 0,
      imageHeight: (json['imageHeight'] as num?)?.toInt() ?? 0,
      tileWidth: (json['tileWidth'] as num?)?.toInt() ?? 32,
      tileHeight: (json['tileHeight'] as num?)?.toInt() ?? 32,
      margin: (json['margin'] as num?)?.toInt() ?? 0,
      spacing: (json['spacing'] as num?)?.toInt() ?? 0,
      columns: (json['columns'] as num?)?.toInt() ?? 0,
      tileCount: (json['tileCount'] as num?)?.toInt() ?? 0,
      tileOffsetX: offset is List && offset.isNotEmpty
          ? (offset[0] as num).toDouble()
          : 0,
      tileOffsetY: offset is List && offset.length > 1
          ? (offset[1] as num).toDouble()
          : 0,
      className: json['class'] as String? ?? '',
      properties: TileProperties.fromJson(json['properties']),
      transformations: TileTransformations.fromJson(json['transformations']),
      tiles: {
        for (final e in (json['tiles'] as Map? ?? const {}).entries)
          if (int.tryParse('${e.key}') != null && e.value is Map)
            int.parse('${e.key}'): TileDef.fromJson(
              (e.value as Map).cast<String, dynamic>(),
            ),
      },
      wangSets: [
        for (final w in json['wangSets'] as List? ?? const [])
          if (w is Map) WangSetData.fromJson(w.cast<String, dynamic>()),
      ],
    );
  }

  TilesetData copy() => TilesetData.fromJson(toJson())..revision = revision;
}

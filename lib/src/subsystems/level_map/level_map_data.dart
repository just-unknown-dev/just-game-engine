/// A level map: its grid, the tilesets it paints with, and its layers of
/// tiles.
library;

import 'tile_cell.dart';
import 'tile_chunks.dart';
import 'tile_properties.dart';

/// The shape and layout of a map's cells — Tiled's four orientations.
enum MapOrientation {
  /// Square (or rectangular) cells in rows and columns.
  orthogonal,

  /// Diamonds, the grid turned 45° and squashed: x runs down-right, y runs
  /// down-left.
  isometric,

  /// Diamonds laid out in staggered rows (or columns), so the map is a
  /// rectangle on screen.
  staggered,

  /// Hexagons in staggered rows (or columns).
  hexagonal;

  static MapOrientation fromName(String? name) =>
      values.firstWhere((o) => o.name == name, orElse: () => orthogonal);
}

/// Which axis a staggered or hexagonal map staggers along.
enum TileStaggerAxis {
  /// Alternate columns shift down (flat-topped hexagons).
  x,

  /// Alternate rows shift right (pointy-topped hexagons).
  y;

  static TileStaggerAxis fromName(String? name) =>
      name == 'x' ? TileStaggerAxis.x : TileStaggerAxis.y;
}

/// Whether the odd or the even rows (or columns) are the shifted ones.
enum TileStaggerIndex {
  odd,
  even;

  static TileStaggerIndex fromName(String? name) =>
      name == 'even' ? TileStaggerIndex.even : TileStaggerIndex.odd;
}

/// The order Tiled draws an orthogonal layer's tiles in. Kept for export;
/// the engine draws every orientation back to front by screen position.
enum TileRenderOrder {
  rightDown('right-down'),
  rightUp('right-up'),
  leftDown('left-down'),
  leftUp('left-up');

  const TileRenderOrder(this.id);
  final String id;

  static TileRenderOrder fromId(String? id) =>
      values.firstWhere((o) => o.id == id, orElse: () => rightDown);
}

/// One layer of a map: its tiles. What else is on it — the entities placed
/// there — are children of the map's entity that name the layer.
///
/// A layer sorts among the rest of the level like an entity with a
/// `LayerComponent`: by [sortLayer] then [zOrder]. That is what puts a
/// background layer behind the player and a foreground layer in front,
/// though both belong to one map.
class MapLayerData {
  MapLayerData({
    required this.id,
    this.name = '',
    this.visible = true,
    this.locked = false,
    this.opacity = 1,
    this.tint,
    this.offsetX = 0,
    this.offsetY = 0,
    this.parallaxX = 1,
    this.parallaxY = 1,
    this.sortLayerId = 'main',
    this.sortLayer = 0,
    this.zOrder = 0,
    this.collides = false,
    this.className = '',
    TileProperties? properties,
    TileChunkStore? cells,
  }) : properties = properties ?? TileProperties(),
       cells = cells ?? TileChunkStore();

  /// Stable within its map; what an undo step or a timeline names it by.
  final int id;

  String name;

  /// Whether it draws at all. Saved, as Tiled saves it.
  bool visible;

  /// Whether the editor refuses to paint on it. Saved, as Tiled saves it.
  bool locked;

  /// 0 to 1.
  double opacity;

  /// ARGB multiplied into every tile, or null for none.
  int? tint;

  /// Where the layer sits relative to the map, in pixels.
  double offsetX;
  double offsetY;

  /// How fast the layer scrolls with the camera: 1 moves with the level,
  /// less than 1 lags behind it like a distant background.
  double parallaxX;
  double parallaxY;

  /// The named layer of the level it belongs to (`background`, `main`,
  /// `foreground` — see `LevelLayers`), and the number that sorts it.
  String sortLayerId;
  int sortLayer;

  /// Order within [sortLayer].
  int zOrder;

  /// Whether its tiles' collision shapes become physics bodies.
  bool collides;

  /// A free-form class, as in Tiled.
  String className;

  TileProperties properties;

  /// The tiles.
  TileChunkStore cells;

  /// The cell at ([x], [y]).
  int cellAt(int x, int y) => cells.cellAt(x, y);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (!visible) 'visible': false,
    if (locked) 'locked': true,
    if (opacity != 1) 'opacity': opacity,
    'tint': ?tint,
    if (offsetX != 0 || offsetY != 0) 'offset': [offsetX, offsetY],
    if (parallaxX != 1 || parallaxY != 1) 'parallax': [parallaxX, parallaxY],
    'layerId': sortLayerId,
    'layer': sortLayer,
    if (zOrder != 0) 'zOrder': zOrder,
    if (collides) 'collides': true,
    if (className.isNotEmpty) 'class': className,
    if (properties.isNotEmpty) 'properties': properties.toJson(),
    'cells': cells.toJson(),
  };

  static MapLayerData fromJson(Map<String, dynamic> json) {
    final offset = json['offset'];
    final parallax = json['parallax'];
    double at(Object? list, int i, double fallback) =>
        list is List && list.length > i && list[i] is num
        ? (list[i] as num).toDouble()
        : fallback;
    return MapLayerData(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? '',
      visible: json['visible'] != false,
      locked: json['locked'] == true,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1,
      tint: (json['tint'] as num?)?.toInt(),
      offsetX: at(offset, 0, 0),
      offsetY: at(offset, 1, 0),
      parallaxX: at(parallax, 0, 1),
      parallaxY: at(parallax, 1, 1),
      sortLayerId: json['layerId'] as String? ?? 'main',
      sortLayer: (json['layer'] as num?)?.toInt() ?? 0,
      zOrder: (json['zOrder'] as num?)?.toInt() ?? 0,
      collides: json['collides'] == true,
      className: json['class'] as String? ?? '',
      properties: TileProperties.fromJson(json['properties']),
      cells: TileChunkStore.fromJson(json['cells']),
    );
  }

  /// A separate layer with the same content and [id].
  MapLayerData copy({int? id, TileChunkStore? cells}) => MapLayerData(
    id: id ?? this.id,
    name: name,
    visible: visible,
    locked: locked,
    opacity: opacity,
    tint: tint,
    offsetX: offsetX,
    offsetY: offsetY,
    parallaxX: parallaxX,
    parallaxY: parallaxY,
    sortLayerId: sortLayerId,
    sortLayer: sortLayer,
    zOrder: zOrder,
    collides: collides,
    className: className,
    properties: properties.copy(),
    cells: cells ?? this.cells.copy(),
  );
}

/// A level map.
///
/// The same document whether it is kept in the scene (a `LevelMapComponent`'s
/// inline data) or in a `.map.json` file of its own. Paths in it are
/// project-relative, like every other asset path the engine saves, so the
/// editor can find them when a file is renamed.
class LevelMapData {
  LevelMapData({
    this.orientation = MapOrientation.orthogonal,
    this.tileWidth = 32,
    this.tileHeight = 32,
    this.staggerAxis = TileStaggerAxis.y,
    this.staggerIndex = TileStaggerIndex.odd,
    this.hexSideLength = 0,
    this.renderOrder = TileRenderOrder.rightDown,
    List<String?>? tilesets,
    List<MapLayerData>? layers,
    this.nextLayerId = 1,
    this.backgroundColor,
    this.className = '',
    TileProperties? properties,
  }) : tilesets = tilesets ?? [],
       layers = layers ?? [],
       properties = properties ?? TileProperties();

  /// Version of the saved form. Bumped only for a change old readers would
  /// misread. Every earlier form still reads — 2 kept shapes in layers,
  /// which maps no longer hold: they are passed over.
  static const int format = 1;

  MapOrientation orientation;

  /// The grid, in pixels (world units).
  int tileWidth;
  int tileHeight;

  /// Staggered and hexagonal maps only.
  TileStaggerAxis staggerAxis;
  TileStaggerIndex staggerIndex;

  /// Hexagonal maps only: the length of the flat sides, in pixels.
  int hexSideLength;

  TileRenderOrder renderOrder;

  /// Tileset paths by slot — what a cell's slot number means. A removed
  /// tileset leaves a null, so the slots after it keep their numbers.
  final List<String?> tilesets;

  /// Back to front.
  final List<MapLayerData> layers;

  /// The id the next new layer gets.
  int nextLayerId;

  /// ARGB, or null.
  int? backgroundColor;

  String className;
  TileProperties properties;

  /// Bumped by whoever changes the map outside its layers' cells — layer
  /// settings, the tileset list — so a renderer knows to look again.
  int revision = 0;

  /// Marks a change to anything but cells.
  void touch() => revision++;

  /// The slot of the tileset at [path], or -1.
  int slotOf(String path) => tilesets.indexOf(path);

  /// The slot [path] is in, adding it if needed.
  int addTileset(String path) {
    final existing = slotOf(path);
    if (existing >= 0) return existing;
    if (tilesets.length >= TileCell.maxTilesets) {
      throw StateError(
        'A map can use at most ${TileCell.maxTilesets} tilesets',
      );
    }
    tilesets.add(path);
    touch();
    return tilesets.length - 1;
  }

  /// Whether any cell of any layer draws from [slot].
  bool usesSlot(int slot) => layers.any(
    (l) => l.cells.cells.any((c) => TileCell.slotOf(c.$3) == slot),
  );

  /// The layer called [id], or null.
  MapLayerData? layerById(int id) {
    for (final layer in layers) {
      if (layer.id == id) return layer;
    }
    return null;
  }

  /// A new, empty layer, added in front of the rest.
  MapLayerData addLayer({String? name, int? index}) {
    final layer = MapLayerData(
      id: nextLayerId++,
      name: name ?? 'Layer ${layers.length + 1}',
    );
    if (index == null) {
      layers.add(layer);
    } else {
      layers.insert(index.clamp(0, layers.length), layer);
    }
    touch();
    return layer;
  }

  /// The saved form. Always a new map, so a snapshot of it can never
  /// change underneath whoever took it.
  Map<String, dynamic> toJson() => {
    'format': format,
    'orientation': orientation.name,
    'tileWidth': tileWidth,
    'tileHeight': tileHeight,
    if (orientation == MapOrientation.staggered ||
        orientation == MapOrientation.hexagonal) ...{
      'staggerAxis': staggerAxis.name,
      'staggerIndex': staggerIndex.name,
    },
    if (orientation == MapOrientation.hexagonal) 'hexSideLength': hexSideLength,
    if (renderOrder != TileRenderOrder.rightDown) 'renderOrder': renderOrder.id,
    'tilesets': [...tilesets],
    'nextLayerId': nextLayerId,
    'backgroundColor': ?backgroundColor,
    if (className.isNotEmpty) 'class': className,
    if (properties.isNotEmpty) 'properties': properties.toJson(),
    'layers': [for (final layer in layers) layer.toJson()],
  };

  /// Reads what [toJson] wrote into a new, separate map.
  static LevelMapData fromJson(Map<String, dynamic> json) {
    final layers = [
      for (final raw in json['layers'] as List? ?? const [])
        if (raw is Map) MapLayerData.fromJson(raw.cast<String, dynamic>()),
    ];
    var next = (json['nextLayerId'] as num?)?.toInt() ?? 1;
    for (final layer in layers) {
      if (layer.id >= next) next = layer.id + 1;
    }
    return LevelMapData(
      orientation: MapOrientation.fromName(json['orientation'] as String?),
      tileWidth: (json['tileWidth'] as num?)?.toInt() ?? 32,
      tileHeight: (json['tileHeight'] as num?)?.toInt() ?? 32,
      staggerAxis: TileStaggerAxis.fromName(json['staggerAxis'] as String?),
      staggerIndex: TileStaggerIndex.fromName(json['staggerIndex'] as String?),
      hexSideLength: (json['hexSideLength'] as num?)?.toInt() ?? 0,
      renderOrder: TileRenderOrder.fromId(json['renderOrder'] as String?),
      tilesets: [
        for (final t in json['tilesets'] as List? ?? const [])
          t is String ? t : null,
      ],
      layers: layers,
      nextLayerId: next,
      backgroundColor: (json['backgroundColor'] as num?)?.toInt(),
      className: json['class'] as String? ?? '',
      properties: TileProperties.fromJson(json['properties']),
    );
  }

  /// A separate map with the same content.
  LevelMapData copy() => LevelMapData(
    orientation: orientation,
    tileWidth: tileWidth,
    tileHeight: tileHeight,
    staggerAxis: staggerAxis,
    staggerIndex: staggerIndex,
    hexSideLength: hexSideLength,
    renderOrder: renderOrder,
    tilesets: [...tilesets],
    layers: [for (final layer in layers) layer.copy()],
    nextLayerId: nextLayerId,
    backgroundColor: backgroundColor,
    className: className,
    properties: properties.copy(),
  );
}

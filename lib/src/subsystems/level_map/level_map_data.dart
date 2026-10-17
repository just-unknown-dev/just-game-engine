/// A level map: its grid, the tilesets it paints with, and its layers of
/// tiles.
library;

import '../../foundation/unsupported_format_version.dart';
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

  /// The orientation Tiled and a saved map call [name] (`orthogonal`,
  /// `isometric`, `staggered`, `hexagonal`); [orthogonal] for null or a
  /// name it does not know.
  static MapOrientation fromName(String? name) =>
      values.firstWhere((o) => o.name == name, orElse: () => orthogonal);
}

/// Which axis a staggered or hexagonal map staggers along.
enum TileStaggerAxis {
  /// Alternate columns shift down (flat-topped hexagons).
  x,

  /// Alternate rows shift right (pointy-topped hexagons).
  y;

  /// [x] for `x`, as Tiled saves it; [y] for anything else, null included.
  static TileStaggerAxis fromName(String? name) =>
      name == 'x' ? TileStaggerAxis.x : TileStaggerAxis.y;
}

/// Whether the odd or the even rows (or columns) are the shifted ones.
enum TileStaggerIndex {
  /// Rows (or columns) 1, 3, 5… are shifted.
  odd,

  /// Rows (or columns) 0, 2, 4… are shifted.
  even;

  /// [even] for `even`, as Tiled saves it; [odd] for anything else, null
  /// included.
  static TileStaggerIndex fromName(String? name) =>
      name == 'even' ? TileStaggerIndex.even : TileStaggerIndex.odd;
}

/// The order Tiled draws an orthogonal layer's tiles in. Kept for export;
/// the engine draws every orientation back to front by screen position.
enum TileRenderOrder {
  /// Row by row from the top, each left to right. The default.
  rightDown('right-down'),

  /// Row by row from the bottom, each left to right.
  rightUp('right-up'),

  /// Row by row from the top, each right to left.
  leftDown('left-down'),

  /// Row by row from the bottom, each right to left.
  leftUp('left-up');

  const TileRenderOrder(this.id);

  /// The name Tiled saves it under (`right-down`), which a saved map's
  /// `renderOrder` holds too.
  final String id;

  /// The order saved as [id]; [rightDown] for null or an id it does not
  /// know.
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
  /// Layer [id], with no cells unless given: visible, unlocked, opaque,
  /// untinted, at the map's origin, moving with the level, on the `main`
  /// sort layer (0) and colliding with nothing.
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
    this.material = '',
    this.castsShadows = false,
    this.shadowDepth = 12,
    TileProperties? properties,
    TileChunkStore? cells,
  }) : properties = properties ?? TileProperties(),
       cells = cells ?? TileChunkStore();

  /// Stable within its map; what an undo step or a timeline names it by.
  final int id;

  /// What the editor shows it as, and a name a game can look it up by;
  /// where two layers share one, the first wins.
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

  /// How far below the map the layer sits, in pixels (negative is up); see
  /// [offsetX].
  double offsetY;

  /// How fast the layer scrolls with the camera: 1 moves with the level,
  /// less than 1 lags behind it like a distant background.
  double parallaxX;

  /// The same, vertically; [parallaxX] is the horizontal factor.
  double parallaxY;

  /// The named layer of the level it belongs to (`background`, `main`,
  /// `foreground` — see `LevelLayers`), and the number that sorts it.
  String sortLayerId;

  /// The number [sortLayerId] sorts by: higher draws in front (`main` is
  /// 0, `foreground` 100).
  int sortLayer;

  /// Order within [sortLayer].
  int zOrder;

  /// Whether its tiles' collision shapes become physics bodies.
  bool collides;

  /// A free-form class, as in Tiled.
  String className;

  /// A 2-D material file (`*.material2d.json`) its tiles are drawn
  /// through — water that scrolls and waves, lava that glows; empty for
  /// none.
  String material;

  /// Whether its tiles block 2-D lights (`Light2D`), casting shadows.
  bool castsShadows;

  /// How far into its tiles a light reaches before their own shadow, in
  /// pixels: the face of a wall catching the light.
  double shadowDepth;

  /// Custom properties a game reads — a layer's `ambient` sound, say.
  TileProperties properties;

  /// The tiles.
  TileChunkStore cells;

  /// The cell at ([x], [y]).
  int cellAt(int x, int y) => cells.cellAt(x, y);

  /// The saved form, a JSON map. Settings at their defaults are left out;
  /// `offset` and `parallax` are `[x, y]` pairs, `layerId` and `layer` the
  /// sort layer, `cells` as [TileChunkStore.toJson] writes them.
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
    if (material.isNotEmpty) 'material': material,
    if (castsShadows) 'castsShadows': true,
    if (shadowDepth != 12) 'shadowDepth': shadowDepth,
    if (properties.isNotEmpty) 'properties': properties.toJson(),
    'cells': cells.toJson(),
  };

  /// Reads what [toJson] wrote; missing keys take their defaults (a missing
  /// id is 0 — [LevelMapData.fromJson] gives such a layer a new one). A
  /// value of the wrong type, such as a string `opacity`, throws.
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
      material: json['material'] as String? ?? '',
      castsShadows: json['castsShadows'] == true,
      shadowDepth: (json['shadowDepth'] as num?)?.toDouble() ?? 12,
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
    material: material,
    castsShadows: castsShadows,
    shadowDepth: shadowDepth,
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
  /// A map with no tilesets and no layers, on an orthogonal grid of 32 × 32
  /// pixel cells unless said. [nextLayerId] is the id [addLayer] gives next.
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

  /// The newest saved form [fromJson] reads. Above [format] because form 2
  /// (shapes in layers) was written for a while and still reads — so the
  /// next change that needs a new number takes 3.
  static const int newestReadableFormat = 2;

  /// The shape and layout of its cells.
  MapOrientation orientation;

  /// The grid, in pixels (world units).
  int tileWidth;

  /// Height of the grid's cells, in pixels (world units); see [tileWidth].
  int tileHeight;

  /// Staggered and hexagonal maps only.
  TileStaggerAxis staggerAxis;

  /// Whether the odd or the even rows (or columns) are shifted; staggered
  /// and hexagonal maps only.
  TileStaggerIndex staggerIndex;

  /// Hexagonal maps only: the length of the flat sides, in pixels.
  int hexSideLength;

  /// The order Tiled draws the tiles in. Kept for export only; the engine
  /// does not use it.
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

  /// A free-form class, as in Tiled.
  String className;

  /// Custom properties a game reads, as in Tiled.
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
    final i = indexOfLayer(id);
    return i < 0 ? null : layers[i];
  }

  /// Where in [layers] the layer called [id] is, or -1.
  ///
  /// Looked up in an index kept with [revision] and the number of layers,
  /// and checked against the list, so a list changed without a [touch]
  /// still answers right — by a search, as without the index.
  int indexOfLayer(int id) {
    var index = _indexById;
    if (index == null ||
        _indexRevision != revision ||
        _indexLength != layers.length) {
      index = _indexById = {};
      for (var i = 0; i < layers.length; i++) {
        index[layers[i].id] ??= i;
      }
      _indexRevision = revision;
      _indexLength = layers.length;
    }
    final i = index[id];
    if (i != null && i < layers.length && layers[i].id == id) return i;
    for (var j = 0; j < layers.length; j++) {
      if (layers[j].id == id) {
        _indexById = null; // stale: rebuilt on the next look-up
        return j;
      }
    }
    return -1;
  }

  Map<int, int>? _indexById;
  int _indexRevision = -1;
  int _indexLength = -1;

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
  ///
  /// Throws an [UnsupportedFormatVersionException] for a map saved by a newer
  /// engine ([newestReadableFormat]) rather than misread it. A layer saved
  /// without an id, or with the id of a layer before it, is given a new one
  /// after the largest: layers are found by id, and two sharing one would
  /// draw, collide and change as one.
  static LevelMapData fromJson(Map<String, dynamic> json) {
    final version = json['format'];
    if (version is num && version > newestReadableFormat) {
      throw UnsupportedFormatVersionException(
        'level map',
        version.toInt(),
        newestReadableFormat,
      );
    }
    final layers = <MapLayerData>[];
    final noId = <int>{};
    for (final raw in json['layers'] as List? ?? const []) {
      if (raw is! Map) continue;
      if (raw['id'] is! num) noId.add(layers.length);
      layers.add(MapLayerData.fromJson(raw.cast<String, dynamic>()));
    }
    var next = (json['nextLayerId'] as num?)?.toInt() ?? 1;
    for (final layer in layers) {
      if (layer.id >= next) next = layer.id + 1;
    }
    final ids = <int>{};
    for (var i = 0; i < layers.length; i++) {
      final layer = layers[i];
      if (!noId.contains(i) && ids.add(layer.id)) continue;
      layers[i] = layer.copy(id: next, cells: layer.cells);
      ids.add(next++);
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

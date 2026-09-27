/// Converting between the Tiled editor's files and the engine's level maps.
library;

import 'dart:typed_data';
import 'dart:ui';

import 'package:just_tiled/just_tiled.dart' as tiled;

import '../collision/map_collision_kinds.dart';
import '../tile_cell.dart';
import '../tile_chunks.dart';
import '../level_map_data.dart';
import '../tile_properties.dart';
import '../tileset_data.dart';

/// An object from one of a Tiled map's object layers, with what the groups
/// it sat in did to it.
class TiledObjectRecord {
  const TiledObjectRecord({
    required this.object,
    required this.layerName,
    required this.position,
    required this.opacity,
    required this.visible,
    this.mapLayerId,
  });

  final tiled.TiledObject object;

  /// The object layer's name, groups included (`Group/Layer`).
  final String layerName;

  /// The layer of the imported map the object layer became: what the
  /// object belongs on.
  final int? mapLayerId;

  /// The object's top-left (a tile object's bottom-left, as in Tiled), in
  /// the engine's map-local pixels.
  final Offset position;

  final double opacity;
  final bool visible;
}

/// An image layer from a Tiled map, placed in map-local pixels.
class TiledImageRecord {
  const TiledImageRecord({
    required this.layer,
    required this.position,
    required this.opacity,
  });
  final tiled.ImageLayer layer;
  final Offset position;
  final double opacity;
}

/// What an import made of a Tiled map.
class TiledImport {
  TiledImport({
    required this.map,
    required this.tilesets,
    required this.objects,
    required this.images,
    required this.warnings,
  });

  /// The tile layers, and a layer for each object layer, as an engine map.
  /// Its tileset slots are the Tiled map's tilesets, in order; a slot the
  /// caller has no path for is null.
  final LevelMapData map;

  /// The converted tilesets, by slot; null for one that could not be (an
  /// image collection).
  final List<TilesetData?> tilesets;

  /// Every object, groups flattened, each naming the layer of [map] its
  /// object layer became.
  final List<TiledObjectRecord> objects;

  /// Every image layer, groups flattened.
  final List<TiledImageRecord> images;

  /// What did not come across, in words.
  final List<String> warnings;
}

/// Conversions between just_tiled's models of TMX/TSX (and TMJ/TSJ) files
/// and the engine's [LevelMapData] and [TilesetData].
///
/// Pure data: nothing here reads or writes files. Tiled numbers the tiles of
/// all a map's tilesets in one sequence (global ids); the engine names a
/// tile by its tileset's slot and its own id, so ids are converted on the
/// way in and worked out afresh on the way out.
abstract final class TiledInterop {
  // ── Properties and colours ─────────────────────────────────────────────

  static int? _argb(Color? c) => c?.toARGB32();
  static Color? _color(int? argb) => argb == null ? null : Color(argb);

  /// Tiled's properties as the engine's.
  static TileProperties importProperties(tiled.TiledProperties p) {
    final out = TileProperties();
    for (final name in p.keys) {
      final type = TilePropertyType.fromName(p.typeOf(name));
      final value = p[name];
      out.set(name, value is Color ? value.toARGB32() : value, type);
    }
    return out;
  }

  /// The engine's properties as Tiled's.
  static tiled.TiledProperties exportProperties(TileProperties p) {
    final values = <String, dynamic>{};
    final types = <String, String>{};
    for (final name in p.names) {
      final type = p.typeOf(name) ?? TilePropertyType.string;
      final value = p[name];
      values[name] = type == TilePropertyType.color && value is int
          ? Color(value)
          : value;
      types[name] = type.name;
    }
    return tiled.TiledProperties(values, types);
  }

  // ── Tilesets ───────────────────────────────────────────────────────────

  /// [ts] as an engine tileset whose image is [image] (project-relative).
  /// Null for an image-collection tileset, which the engine does not draw.
  static TilesetData? importTileset(
    tiled.Tileset ts, {
    required String image,
    String? name,
    void Function(String warning)? warn,
  }) {
    if (ts.isImageCollection) {
      warn?.call(
        'Tileset "${ts.name}" is a collection of separate images; '
        'the engine draws tiles cut from one image, so it was left out.',
      );
      return null;
    }
    if (ts.tileRenderSize == tiled.TileRenderSize.grid) {
      warn?.call(
        'Tileset "${ts.name}" draws its tiles at the grid size; '
        'they are drawn at their own size.',
      );
    }
    if (ts.transparentColor != null) {
      warn?.call(
        'Tileset "${ts.name}" keys out a colour; use an image with '
        'transparency instead.',
      );
    }
    final tiles = <int, TileDef>{};
    for (final entry in ts.tiles.entries) {
      final t = entry.value;
      final def = TileDef(
        className: t.type ?? '',
        probability: t.probability,
        properties: importProperties(t.properties),
        animation: [
          for (final f in t.animation) TileFrame(f.tileId, f.duration),
        ],
        collision: _importCollision(t, warn),
      );
      if (!def.isDefault) tiles[entry.key] = def;
    }
    return TilesetData(
      name: name ?? ts.name,
      image: image,
      imageWidth: ts.imageWidth ?? 0,
      imageHeight: ts.imageHeight ?? 0,
      tileWidth: ts.tileWidth,
      tileHeight: ts.tileHeight,
      margin: ts.margin,
      spacing: ts.spacing,
      columns: ts.columns,
      tileCount: ts.tileCount,
      tileOffsetX: ts.tileOffset.dx,
      tileOffsetY: ts.tileOffset.dy,
      className: ts.className,
      properties: importProperties(ts.properties),
      tiles: tiles,
      transformations: TileTransformations(
        hflip: ts.transformations.hflip,
        vflip: ts.transformations.vflip,
        rotate: ts.transformations.rotate,
        preferUntransformed: ts.transformations.preferUntransformed,
      ),
      wangSets: [
        for (final w in ts.wangSets)
          WangSetData(
            name: w.name,
            type: WangType.fromName(w.type.name),
            tile: w.tile,
            className: w.className,
            properties: importProperties(w.properties),
            colors: [
              for (final c in w.colors)
                WangColorData(
                  name: c.name,
                  color: c.color.toARGB32(),
                  tile: c.tile,
                  probability: c.probability,
                  className: c.className,
                  properties: importProperties(c.properties),
                ),
            ],
            wangIds: {
              for (final e in w.wangTiles.entries) e.key: [...e.value],
            },
          ),
      ],
    );
  }

  /// A tile's collision: its object group's shapes. The kind is the tile's
  /// `collision` property, or failing that the first shape's class when it
  /// names a registered kind, or `solid`.
  static TileCollision? _importCollision(
    tiled.Tile tile,
    void Function(String warning)? warn,
  ) {
    if (tile.objectGroup.isEmpty) return null;
    final shapes = <TileShape>[];
    String? kind = tile.properties.getString('collision');
    for (final o in tile.objectGroup) {
      if (kind == null && MapCollisionKinds.byId(o.type) != null) {
        kind = o.type;
      }
      if (o.polygon != null) {
        shapes.add(
          TilePolygonShape([
            for (final p in o.polygon!) Offset(o.x + p.dx, o.y + p.dy),
          ]),
        );
      } else if (o.isEllipse) {
        shapes.add(
          TileEllipseShape(Rect.fromLTWH(o.x, o.y, o.width, o.height)),
        );
      } else if (o.polyline != null || o.isPoint) {
        warn?.call(
          'A collision line or point on tile ${tile.id} was left '
          'out: only areas collide.',
        );
      } else if (o.width > 0 && o.height > 0) {
        shapes.add(TileRectShape(Rect.fromLTWH(o.x, o.y, o.width, o.height)));
      }
    }
    if (shapes.isEmpty) return null;
    return TileCollision(kind: kind ?? 'solid', shapes: shapes);
  }

  /// [ts] as a Tiled tileset, its image at [imageSource] (relative to the
  /// file that will refer to it), numbered from [firstGid]. With [source],
  /// a map refers to it as an external file.
  static tiled.Tileset exportTileset(
    TilesetData ts, {
    int firstGid = 1,
    required String imageSource,
    String? source,
  }) => tiled.Tileset(
    firstGid: firstGid,
    name: ts.name,
    className: ts.className,
    tileWidth: ts.tileWidth,
    tileHeight: ts.tileHeight,
    spacing: ts.spacing,
    margin: ts.margin,
    tileCount: ts.tileCount,
    columns: ts.columns,
    tileOffset: Offset(ts.tileOffsetX, ts.tileOffsetY),
    imageSource: imageSource,
    imageWidth: ts.imageWidth == 0 ? null : ts.imageWidth,
    imageHeight: ts.imageHeight == 0 ? null : ts.imageHeight,
    transformations: tiled.TilesetTransformations(
      hflip: ts.transformations.hflip,
      vflip: ts.transformations.vflip,
      rotate: ts.transformations.rotate,
      preferUntransformed: ts.transformations.preferUntransformed,
    ),
    tiles: {
      for (final e in ts.tiles.entries)
        e.key: tiled.Tile(
          id: e.key,
          type: e.value.className.isEmpty ? null : e.value.className,
          probability: e.value.probability,
          properties: exportProperties(e.value.properties),
          animation: [
            for (final f in e.value.animation)
              tiled.AnimationFrame(tileId: f.tileId, duration: f.durationMs),
          ],
          objectGroup: _exportCollision(e.value.collision),
        ),
    },
    wangSets: [
      for (final w in ts.wangSets)
        tiled.WangSet(
          name: w.name,
          className: w.className,
          type: tiled.WangSetType.fromString(w.type.name),
          tile: w.tile,
          properties: exportProperties(w.properties),
          colors: [
            for (final c in w.colors)
              tiled.WangColor(
                name: c.name,
                className: c.className,
                color: Color(c.color),
                tile: c.tile,
                probability: c.probability,
                properties: exportProperties(c.properties),
              ),
          ],
          wangTiles: {
            for (final e in w.wangIds.entries) e.key: [...e.value],
          },
        ),
    ],
    properties: exportProperties(ts.properties),
    source: source,
  );

  static List<tiled.TiledObject> _exportCollision(TileCollision? collision) {
    if (collision == null) return const [];
    var id = 1;
    return [
      for (final shape in collision.shapes)
        switch (shape) {
          TileRectShape(:final rect) => tiled.TiledObject(
            id: id++,
            type: collision.kind == 'solid' ? '' : collision.kind,
            x: rect.left,
            y: rect.top,
            width: rect.width,
            height: rect.height,
          ),
          TileEllipseShape(:final bounds) => tiled.TiledObject(
            id: id++,
            type: collision.kind == 'solid' ? '' : collision.kind,
            x: bounds.left,
            y: bounds.top,
            width: bounds.width,
            height: bounds.height,
            isEllipse: true,
          ),
          TilePolygonShape(:final points) => tiled.TiledObject(
            id: id++,
            type: collision.kind == 'solid' ? '' : collision.kind,
            x: points.first.dx,
            y: points.first.dy,
            polygon: [for (final p in points) p - points.first],
          ),
        },
    ];
  }

  // ── Maps ───────────────────────────────────────────────────────────────

  static MapOrientation _orientation(tiled.MapOrientation o) =>
      MapOrientation.fromName(o.name);

  /// [map] as an engine map. [tilesetPath] names the `.tileset.json` each
  /// of its tilesets becomes; [imagePath] where each one's image is, both
  /// project-relative.
  ///
  /// Each object layer becomes a layer of the map with no tiles, where it
  /// was among the others; its objects are returned in
  /// [TiledImport.objects], each naming that layer, for the caller to make
  /// something of — an entity on the layer, say.
  static TiledImport importMap(
    tiled.TiledMap map, {
    required String Function(int index, tiled.Tileset ts) tilesetPath,
    required String Function(tiled.Tileset ts) imagePath,
  }) {
    final warnings = <String>[];
    final tilesets = <TilesetData?>[
      for (final ts in map.tilesets)
        importTileset(ts, image: imagePath(ts), warn: warnings.add),
    ];
    final data = LevelMapData(
      orientation: _orientation(map.orientation),
      tileWidth: map.tileWidth,
      tileHeight: map.tileHeight,
      staggerAxis: TileStaggerAxis.fromName(map.staggerAxis?.name),
      staggerIndex: TileStaggerIndex.fromName(map.staggerIndex?.name),
      hexSideLength: map.hexSideLength ?? 0,
      renderOrder: TileRenderOrder.fromId(map.renderOrder.tmxValue),
      tilesets: [
        for (var i = 0; i < map.tilesets.length; i++)
          tilesets[i] == null ? null : tilesetPath(i, map.tilesets[i]),
      ],
      backgroundColor: _argb(map.backgroundColor),
      className: map.className,
      properties: importProperties(map.properties),
    );

    // Global ids to slots: the tileset with the largest first id at or
    // below it.
    final order = [for (var i = 0; i < map.tilesets.length; i++) i]
      ..sort(
        (a, b) => map.tilesets[a].firstGid.compareTo(map.tilesets[b].firstGid),
      );
    var warnedMissing = false;
    int toCell(int raw) {
      final gid = tiled.TiledGid.idOf(raw);
      if (gid == 0) return TileCell.empty;
      int? slot;
      for (final i in order) {
        if (map.tilesets[i].firstGid <= gid) slot = i;
      }
      if (slot == null || tilesets[slot] == null) {
        if (!warnedMissing) {
          warnings.add(
            'Some tiles belong to no tileset the engine can draw '
            'and were left empty.',
          );
          warnedMissing = true;
        }
        return TileCell.empty;
      }
      return TileCell.make(
        slot,
        gid - map.tilesets[slot].firstGid,
        tiled.TiledGid.flagsOf(raw),
      );
    }

    final objects = <TiledObjectRecord>[];
    final images = <TiledImageRecord>[];
    var zOrder = -1000;

    void walk(
      List<tiled.Layer> layers, {
      String prefix = '',
      Offset offset = Offset.zero,
      double opacity = 1,
      double parallaxX = 1,
      double parallaxY = 1,
      Color? tint,
      bool visible = true,
    }) {
      for (final layer in layers) {
        final name = '$prefix${layer.name}';
        final off = offset + Offset(layer.offsetX, layer.offsetY);
        final op = opacity * layer.opacity;
        final px = parallaxX * layer.parallaxX;
        final py = parallaxY * layer.parallaxY;
        final t = _multiply(tint, layer.tintColor);
        final vis = visible && layer.visible;
        switch (layer) {
          case tiled.TileLayer():
            final cells = TileChunkStore();
            if (layer.isChunked) {
              for (final chunk in layer.chunks) {
                for (var i = 0; i < chunk.data.length; i++) {
                  final c = toCell(chunk.data[i]);
                  if (c != TileCell.empty) {
                    cells.setCell(
                      chunk.x + i % chunk.width,
                      chunk.y + i ~/ chunk.width,
                      c,
                    );
                  }
                }
              }
            } else {
              final raw = layer.rawGids;
              for (var i = 0; i < raw.length; i++) {
                final c = toCell(raw[i]);
                if (c != TileCell.empty) {
                  cells.setCell(i % layer.width, i ~/ layer.width, c);
                }
              }
            }
            final foreground = layer.properties.getBool('foreground') ?? false;
            data.layers.add(
              MapLayerData(
                id: layer.id,
                name: name,
                visible: vis,
                locked: layer.locked,
                opacity: op,
                tint: _argb(t),
                offsetX: off.dx,
                offsetY: off.dy,
                parallaxX: px,
                parallaxY: py,
                sortLayerId: foreground ? 'foreground' : 'main',
                sortLayer: foreground ? 100 : 0,
                zOrder: zOrder++,
                collides: layer.properties.getBool('collides') ?? false,
                className: layer.className,
                properties: importProperties(layer.properties),
                cells: cells,
              ),
            );
          case tiled.ObjectGroup():
            final foreground = layer.properties.getBool('foreground') ?? false;
            data.layers.add(
              MapLayerData(
                id: layer.id,
                name: name,
                visible: vis,
                locked: layer.locked,
                opacity: op,
                tint: _argb(t),
                offsetX: off.dx,
                offsetY: off.dy,
                parallaxX: px,
                parallaxY: py,
                sortLayerId: foreground ? 'foreground' : 'main',
                sortLayer: foreground ? 100 : 0,
                zOrder: zOrder++,
                className: layer.className,
                properties: importProperties(layer.properties),
              ),
            );
            for (final o in layer.objects) {
              objects.add(
                TiledObjectRecord(
                  object: o,
                  layerName: name,
                  position: off + objectPosition(map, o),
                  opacity: op,
                  visible: vis && o.visible,
                  mapLayerId: layer.id,
                ),
              );
            }
          case tiled.ImageLayer():
            images.add(
              TiledImageRecord(layer: layer, position: off, opacity: op),
            );
          case tiled.GroupLayer():
            walk(
              layer.layers,
              prefix: '$name/',
              offset: off,
              opacity: op,
              parallaxX: px,
              parallaxY: py,
              tint: t,
              visible: vis,
            );
          default:
            break;
        }
      }
    }

    walk(map.layers);
    var next = map.nextLayerId ?? 1;
    for (final l in data.layers) {
      if (l.id >= next) next = l.id + 1;
    }
    data.nextLayerId = next;
    return TiledImport(
      map: data,
      tilesets: tilesets,
      objects: objects,
      images: images,
      warnings: warnings,
    );
  }

  /// Where [o] is in the engine's map-local pixels. An isometric map keeps
  /// its objects in Tiled's own "tile pixels" (both axes measured in tile
  /// heights along the diamond axes), turned here into screen positions —
  /// without Tiled's shift of a finite map to start at zero, which the
  /// engine does not make.
  static Offset objectPosition(tiled.TiledMap map, tiled.TiledObject o) {
    if (map.orientation != tiled.MapOrientation.isometric) {
      return Offset(o.x, o.y);
    }
    final tx = o.x / map.tileHeight;
    final ty = o.y / map.tileHeight;
    return Offset(
      (tx - ty) * map.tileWidth / 2,
      (tx + ty) * map.tileHeight / 2,
    );
  }

  static Color? _multiply(Color? a, Color? b) {
    if (a == null) return b;
    if (b == null) return a;
    return Color.from(
      alpha: a.a * b.a,
      red: a.r * b.r,
      green: a.g * b.g,
      blue: a.b * b.b,
    );
  }

  /// [map] as a Tiled map.
  ///
  /// [tilesets] are the map's tilesets by slot. Each is embedded, with its
  /// image at [imageSource]; or, where [tilesetSource] gives a path, written
  /// as a reference to that file (write it with [exportTileset]). [objects]
  /// are extra object layers to add in front.
  ///
  /// A map whose tiles all sit at zero or beyond becomes a finite map just
  /// big enough for them; tiles further up or left make an infinite one, so
  /// nothing moves.
  static tiled.TiledMap exportMap(
    LevelMapData map,
    List<TilesetData?> tilesets, {
    required String Function(int slot) imageSource,
    String? Function(int slot)? tilesetSource,
    List<tiled.ObjectGroup> objects = const [],
    int nextObjectId = 1,
  }) {
    // First ids, slot by slot.
    final firstGid = <int, int>{};
    var next = 1;
    for (var slot = 0; slot < tilesets.length; slot++) {
      final ts = tilesets[slot];
      if (ts == null) continue;
      firstGid[slot] = next;
      next += ts.tileCount;
    }
    int toRaw(int cell) {
      if (TileCell.isEmpty(cell)) return 0;
      final first = firstGid[TileCell.slotOf(cell)];
      if (first == null) return 0;
      return tiled.TiledGid.compose(
        first + TileCell.localIdOf(cell),
        TileCell.flagsOf(cell),
      );
    }

    // Size: what the tiles cover.
    var minX = 0, minY = 0, maxX = 0, maxY = 0;
    var any = false;
    for (final layer in map.layers) {
      final b = layer.cells.usedBounds;
      if (b == null) continue;
      if (!any) {
        minX = b.left.toInt();
        minY = b.top.toInt();
        maxX = b.right.toInt();
        maxY = b.bottom.toInt();
        any = true;
      } else {
        if (b.left < minX) minX = b.left.toInt();
        if (b.top < minY) minY = b.top.toInt();
        if (b.right > maxX) maxX = b.right.toInt();
        if (b.bottom > maxY) maxY = b.bottom.toInt();
      }
    }
    final infinite = any && (minX < 0 || minY < 0);
    final width = infinite ? maxX - minX : (any ? maxX : 1);
    final height = infinite ? maxY - minY : (any ? maxY : 1);

    final layers = <tiled.Layer>[];
    for (final layer in map.layers) {
      final props = exportProperties(layer.properties);
      final values = {...props.toMap()};
      final types = {for (final k in props.keys) k: props.typeOf(k)};
      if (layer.collides) {
        values['collides'] = true;
        types['collides'] = 'bool';
      }
      Uint32List? raw;
      final chunks = <tiled.TileChunk>[];
      if (infinite) {
        for (final c in layer.cells.chunks) {
          if (c.isEmpty) continue;
          chunks.add(
            tiled.TileChunk(
              x: c.cx * TileChunkStore.size,
              y: c.cy * TileChunkStore.size,
              width: TileChunkStore.size,
              height: TileChunkStore.size,
              data: Uint32List.fromList([
                for (final cell in c.cells) toRaw(cell),
              ]),
            ),
          );
        }
      } else {
        raw = Uint32List(width * height);
        for (final (x, y, cell) in layer.cells.cells) {
          if (x < width && y < height) raw[y * width + x] = toRaw(cell);
        }
      }
      layers.add(
        tiled.TileLayer(
          id: layer.id,
          name: layer.name,
          className: layer.className,
          visible: layer.visible,
          locked: layer.locked,
          opacity: layer.opacity,
          tintColor: _color(layer.tint),
          offsetX: layer.offsetX,
          offsetY: layer.offsetY,
          parallaxX: layer.parallaxX,
          parallaxY: layer.parallaxY,
          properties: tiled.TiledProperties(values, types),
          width: width,
          height: height,
          data: raw == null
              ? const []
              : [for (final g in raw) tiled.TiledGid.idOf(g)],
          flipHorizontal: raw == null
              ? const []
              : [for (final g in raw) tiled.TiledGid.isFlippedHorizontally(g)],
          flipVertical: raw == null
              ? const []
              : [for (final g in raw) tiled.TiledGid.isFlippedVertically(g)],
          flipDiagonal: raw == null
              ? const []
              : [for (final g in raw) tiled.TiledGid.isFlippedDiagonally(g)],
          rawData: raw,
          chunks: chunks,
        ),
      );
    }
    layers.addAll(objects);
    var nextLayerId = map.nextLayerId;
    for (final l in layers) {
      if (l.id >= nextLayerId) nextLayerId = l.id + 1;
    }

    return tiled.TiledMap(
      orientation: tiled.MapOrientation.fromString(map.orientation.name),
      renderOrder: tiled.RenderOrder.fromString(map.renderOrder.id),
      width: width,
      height: height,
      tileWidth: map.tileWidth,
      tileHeight: map.tileHeight,
      infinite: infinite,
      backgroundColor: _color(map.backgroundColor),
      nextLayerId: nextLayerId,
      nextObjectId: nextObjectId,
      staggerAxis:
          map.orientation == MapOrientation.staggered ||
              map.orientation == MapOrientation.hexagonal
          ? tiled.StaggerAxis.fromString(map.staggerAxis.name)
          : null,
      staggerIndex:
          map.orientation == MapOrientation.staggered ||
              map.orientation == MapOrientation.hexagonal
          ? tiled.StaggerIndex.fromString(map.staggerIndex.name)
          : null,
      hexSideLength: map.orientation == MapOrientation.hexagonal
          ? map.hexSideLength
          : null,
      className: map.className,
      properties: exportProperties(map.properties),
      tilesets: [
        for (var slot = 0; slot < tilesets.length; slot++)
          if (tilesets[slot] case final ts?)
            exportTileset(
              ts,
              firstGid: firstGid[slot]!,
              imageSource: imageSource(slot),
              source: tilesetSource?.call(slot),
            ),
      ],
      layers: layers,
    );
  }
}

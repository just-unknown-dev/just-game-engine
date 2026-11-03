# Level maps

_Gameplay_ · Draw tile maps from the scene, a .map.json file or a Tiled .tmx/.tmj with LevelMapComponent, give layers collision, and change tiles while the game runs.

A level map is layers of tiles. One `LevelMapComponent` puts a whole map in the level at its entity's position; the map is not rotated or scaled with the entity. Maps can be orthogonal, isometric, staggered or hexagonal (`MapOrientation`), and `MapGeometry` places cells exactly as Tiled does, so a map looks and collides the same here as in Tiled. Tiles can be animated, flipped and rotated.

Two default systems run maps: `LevelMapSystem` (priority 110) loads and draws them, and `MapCollisionSystem` (108) builds their collision. Both are in `DefaultSystems.all`; for a world of your own, call `registerLevelMapSystems(world)` and add a `RenderSystem` to draw the layers.

## Three ways to store a map

| Where the map lives | How you set it | Good for |
|---|---|---|
| In the scene | `LevelMapComponent(inline: LevelMapData(...))`, saved as the component's `inline` field | the editor's default: a level that is one file with one undo history |
| A `.map.json` file | `LevelMapComponent(mapPath: 'assets/maps/cave.map.json')` | one map shared by several scenes |
| A Tiled file | `LevelMapComponent(mapPath: 'assets/maps/cave.tmx')`, or `.tmj` | maps made in Tiled |

While `mapPath` is set the inline map is ignored. Tilesets are `.tileset.json` files, or Tiled's `.tsx`. Older `.tilemap.json` files are still read. List every folder the map, its tilesets and their images live in under `flutter: assets:`; a folder entry does not include its subfolders.

A scene's own map is usually the entity called `LevelMaps.primaryName` (`Level Map`), which is how `LevelMaps.primary(world)` finds it.

```dart lib/level.dart
Future<void> startLevel(World world) async {
  world.createEntityWithComponents([
    TransformComponent(),
    LevelMapComponent(mapPath: 'assets/maps/level_01.tmx'),
  ], name: LevelMaps.primaryName);

  // Load maps and tilesets before the first frame: otherwise the player
  // can fall through ground that is still loading.
  final failures = await LevelMaps.preload(world);
  for (final failure in failures) {
    debugPrint('Map ${failure.path} did not load: ${failure.error}');
  }
}
```

`LevelMaps.preload` loads every map in the world and its tilesets; images may still be arriving. A map that will not load does not stop the others: it is left without anything to draw or collide with, logged once, and returned in the list. When you move from level to level, call `LevelMaps.evictUnused(world)` after the next level has loaded to drop tilesets that no map uses any more. Loading scenes is covered in [Scenes](/docs/scenes).

## Tiled maps

`.tmx` and `.tmj` maps load directly, with their tilesets embedded or as `.tsx` files; image paths are read relative to the file that names them. A few Tiled settings carry meaning:

- A tile layer with the bool custom property `collides` set to true gets physics bodies, and one with `foreground` draws in front of the level.
- Tile collision comes from Tiled's tile collision editor: rectangles, ellipses and polygons. Lines and points are left out.
- A tile's collision kind is its `collision` string property; failing that, the first shape's class when it names a registered kind; otherwise `solid`.
- Object layers become empty map layers. Their objects are not turned into entities.

To read the objects, parse the file with the `just_tiled` package and call `TiledInterop.importMap`. It returns a `TiledImport` with the converted `map` and `tilesets`, every object as a `TiledObjectRecord` (`object`, `layerName`, `position`, `mapLayerId`), the image layers and any `warnings`. `TiledInterop.exportMap` and `exportTileset` go the other way. Their signatures use `just_tiled` models, so add that package to call them.

## Layers

Each layer is a `MapLayerData` with a `name`, `visible`, `opacity`, `tint`, `offsetX` and `offsetY`, `parallaxX` and `parallaxY` (less than 1 lags behind like a distant background), `collides`, `className` and custom `properties`. A layer sorts among the level's other drawing by `sortLayerId` (`background`, `main` or `foreground`), `sortLayer` and `zOrder`, so one map's background layer draws behind the player and its foreground layer in front.

An entity can sit on a layer: make it a child of the map's entity with `LayerComponent(mapLayer: layerId)`, and it draws just above that layer's tiles and below the next layer's.

## Tile collision

`MapCollisionSystem` gives every layer marked `collides` static bodies built from its tiles' collision shapes. The bodies are ordinary entities with a transform, a static `RigidBody2D`, a `Collider2D` and a `MapBodyComponent` that says which map, layer, kind, class and cells they came from. They are generated, never saved. Contacts with them are reported like any other, and standing on them grounds a character (see [2D physics](/docs/physics-2d)). A layer's bodies are rebuilt at most once a frame when its cells, settings or tilesets change, or the map moves.

The engine knows two collision kinds: `MapCollisionKinds.solid`, merged into as few boxes as possible, and `MapCollisionKinds.oneWay`, merged along rows and passed through from below. A kind nobody registered resolves to `solid`. Register your own in `engine.context.collisionKinds` before the maps load:

```dart lib/hazards.dart
void addHazards(Engine engine) {
  engine.context.collisionKinds.register(
    MapCollisionKind(
      id: 'hazard',
      label: 'Hazard',
      color: 0xFFE57373, // the editor's collision overlay
      merge: TileMergeMode.none, // one body per tile
      sensor: true,
      decorate: (body, spec, properties) => body.addTag('hazard'),
    ),
  );

  engine.world.events.on<SensorEnter2DEvent>((e) {
    final tile = e.sensor.getComponent<MapBodyComponent>();
    if (tile?.kind == 'hazard' && e.other.hasTag('player')) {
      debugPrint('${e.other.name} touched a hazard');
    }
  });
}
```

`decorate` runs once each body is built and receives its tile's properties, such as a spike's `damage`. `TileMergeMode` is `area`, `rows` or `none`.

## Change tiles at run time

`LevelMaps.primary(world)`, or `LevelMaps.of(world, entity)` for any map, returns a `LevelMapHandle` once the map has loaded. Changes are the running game's own: the map file and the scene's saved map are untouched. Collision follows within the frame, and each change fires a `TileChangedEvent` with the map entity, the layer id and the changed cells.

```dart lib/blocks.dart
/// Knocks out the tile under [point] on the "Ground" layer if its
/// tileset gives it the class "Breakable".
void hitBlock(World world, Offset point) {
  final map = LevelMaps.primary(world);
  final ground = map?.layer('Ground');
  if (map == null || ground == null) return;
  final cell = map.cellAt(ground, point);
  if (map.tileAt(ground, cell)?.className == 'Breakable') {
    map.setTile(ground, cell, TileCell.empty);
  }
}
```

`tileAt` returns a `TileInfo` with the tile's `className`, `properties`, `tileset` and `localId`, and `tileAtPoint` takes a world point. `setTiles` changes many cells with one event and one collision rebuild. `cellCenter` turns a cell back into a world point. `setCellsHidden` and `setBodyHidden` stop drawing cells without changing them, for a platform that crumbles and comes back. A cell value is made with `TileCell.make(slot, localId)`, where `slot` is the tileset's index in the map's `tilesets`.

## Terrain with Wang sets

`LevelMapHandle.setTerrain(layer, targets, color, slot: ..., wangSet: ...)` paints terrain from a tileset's Wang set, choosing tiles as the editor's terrain brush does. `WangFiller` does the work; targets are `WangTarget.corner`, `WangTarget.edge` or `WangTarget.cell`. It returns a `WangResult` with the cells it changed and any it could only match roughly. Hexagonal maps are not supported by the filler.

## Block out with built-in shapes

`BuiltInTilesets.basicShapes` is a tileset the engine draws itself, so it needs no image or tileset file. Its 32 × 32 tiles are plain geometry for blocking out a level before there is art: a full block, half and quarter blocks, a one-way plank, 45° and 22.5° slopes for floors and ceilings, rounded corners, a circle, a triangle and a diamond. Every tile collides as it looks, and tile ids never change.

```dart lib/blockout.dart
Entity addBlockout(World world) {
  final map = LevelMapData(tilesets: [BuiltInTilesets.basicShapes]);
  final ground = map.addLayer(name: 'Ground')..collides = true;
  for (var x = -10; x < 10; x++) {
    ground.cells.setCell(x, 4, TileCell.make(0, 0)); // a full block
  }
  ground.cells.setCell(2, 1, TileCell.make(0, 5)); // a one-way plank
  return world.createEntityWithComponents([
    TransformComponent(),
    LevelMapComponent(inline: map),
  ], name: LevelMaps.primaryName);
}
```

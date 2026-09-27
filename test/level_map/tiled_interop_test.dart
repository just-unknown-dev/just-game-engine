// Tiled maps in and out: global ids become tileset slots and back, groups
// flatten, collision and terrain come across, and a map exported and
// imported again is the map it was.

import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_tiled/just_tiled.dart' as tiled;

const _tmx = '''<?xml version="1.0" encoding="UTF-8"?>
<map version="1.10" tiledversion="1.10.2" orientation="orthogonal" renderorder="right-down" width="4" height="2" tilewidth="16" tileheight="16" infinite="0" nextlayerid="5" nextobjectid="3">
 <properties>
  <property name="music" type="file" value="music/a.ogg"/>
 </properties>
 <tileset firstgid="1" name="grass" tilewidth="16" tileheight="16" tilecount="4" columns="2">
  <image source="../images/grass.png" width="32" height="32"/>
  <tile id="1" type="Ledge">
   <properties>
    <property name="collision" value="oneWay"/>
   </properties>
   <objectgroup draworder="index">
    <object id="1" x="0" y="0" width="16" height="4"/>
   </objectgroup>
  </tile>
  <tile id="2">
   <objectgroup draworder="index">
    <object id="1" x="0" y="16">
     <polygon points="0,0 16,-16 16,0"/>
    </object>
   </objectgroup>
   <animation>
    <frame tileid="2" duration="100"/>
    <frame tileid="3" duration="200"/>
   </animation>
  </tile>
  <wangsets>
   <wangset name="Grass" type="corner" tile="0">
    <wangcolor name="grass" color="#00ff00" tile="0" probability="1"/>
    <wangtile tileid="0" wangid="0,1,0,1,0,1,0,1"/>
   </wangset>
  </wangsets>
 </tileset>
 <tileset firstgid="5" name="cave" tilewidth="16" tileheight="16" tilecount="4" columns="2">
  <image source="cave.png" width="32" height="32"/>
 </tileset>
 <layer id="1" name="Ground" width="4" height="2">
  <properties>
   <property name="collides" type="bool" value="true"/>
  </properties>
  <data encoding="csv">
1,2,5,2147483654,
0,3,1610612737,0
</data>
 </layer>
 <group id="2" name="Deco" offsetx="10" offsety="4" opacity="0.5" tintcolor="#ff808080" parallaxx="0.5">
  <layer id="3" name="Vines" width="4" height="2" opacity="0.5" offsetx="2">
   <data encoding="csv">
0,0,0,0,
0,0,0,8
</data>
  </layer>
  <objectgroup id="4" name="Things">
   <object id="1" name="Spawn" type="PlayerSpawn" x="20" y="30">
    <point/>
   </object>
   <object id="2" name="Hidden" x="0" y="0" width="8" height="8" visible="0"/>
  </objectgroup>
 </group>
</map>
''';

Future<TiledImport> _import([String text = _tmx]) async {
  final map = await tiled.TileMapParser.parse(text);
  return TiledInterop.importMap(
    map,
    tilesetPath: (i, ts) => 'assets/tilesets/${ts.name}.tileset.json',
    imagePath: (ts) => 'assets/images/${ts.name}.png',
  );
}

void main() {
  group('importing', () {
    late TiledImport result;
    setUpAll(() async => result = await _import());

    test('global ids become slots and tile ids, flags kept', () {
      final ground = result.map.layers.first;
      expect(ground.cells.cellAt(0, 0), TileCell.make(0, 0));
      expect(ground.cells.cellAt(1, 0), TileCell.make(0, 1));
      expect(
        ground.cells.cellAt(2, 0),
        TileCell.make(1, 0),
        reason: 'second tileset',
      );
      expect(ground.cells.cellAt(3, 0), TileCell.make(1, 1, TileCell.flipH));
      expect(
        ground.cells.cellAt(2, 1),
        TileCell.make(0, 0, TileCell.flipV | TileCell.flipD),
      );
      expect(ground.cells.cellAt(0, 1), TileCell.empty);
      expect(result.map.tilesets, [
        'assets/tilesets/grass.tileset.json',
        'assets/tilesets/cave.tileset.json',
      ]);
    });

    test(
      "a layer's collides property and the map's properties come across",
      () {
        expect(result.map.layers.first.collides, isTrue);
        expect(result.map.properties['music'], 'music/a.ogg');
        expect(result.map.properties.typeOf('music'), TilePropertyType.file);
      },
    );

    test('groups flatten into their layers', () {
      final vines = result.map.layers[1];
      expect(vines.name, 'Deco/Vines');
      expect(vines.offsetX, 12);
      expect(vines.offsetY, 4);
      expect(vines.opacity, 0.25);
      expect(vines.parallaxX, 0.5);
      expect(vines.tint, const Color(0xFF808080).toARGB32());
      expect(vines.cells.cellAt(3, 1), TileCell.make(1, 3));
    });

    test('every object comes out, with where it is and the layer it '
        'belongs on', () {
      final spawn = result.objects.firstWhere(
        (r) => r.object.type == 'PlayerSpawn',
      );
      expect(spawn.layerName, 'Deco/Things');
      expect(spawn.position, const Offset(30, 34));
      expect(spawn.mapLayerId, 4);
      final hidden = result.objects.firstWhere(
        (r) => r.object.name == 'Hidden',
      );
      expect(hidden.visible, isFalse);
      expect(hidden.mapLayerId, 4);
    });

    test('an object layer becomes a layer of the map, with no tiles', () {
      final things = result.map.layers.singleWhere(
        (l) => l.name == 'Deco/Things',
      );
      expect(things.id, 4);
      expect((things.offsetX, things.offsetY), (10, 4));
      expect(things.opacity, 0.5);
      expect(things.cells.usedBounds, isNull);
    });

    test('collision, animation and terrain come across', () {
      final grass = result.tilesets.first!;
      expect(grass.image, 'assets/images/grass.png');
      final ledge = grass.tile(1)!;
      expect(ledge.className, 'Ledge');
      expect(ledge.collision!.kind, 'oneWay');
      expect(
        (ledge.collision!.shapes.single as TileRectShape).rect,
        const Rect.fromLTWH(0, 0, 16, 4),
      );
      final slope = grass.tile(2)!;
      expect(
        (slope.collision!.shapes.single as TilePolygonShape).points,
        const [Offset(0, 16), Offset(16, 0), Offset(16, 16)],
        reason: 'object position added to its points',
      );
      expect(slope.animation, const [TileFrame(2, 100), TileFrame(3, 200)]);
      expect(grass.wangSets.single.wangIds[0], [0, 1, 0, 1, 0, 1, 0, 1]);
      expect(grass.wangSets.single.colors.single.color, 0xFF00FF00);
    });
  });

  test('exported and imported again, the map is the same', () async {
    final first = await _import();
    final exported = TiledInterop.exportMap(
      first.map,
      first.tilesets,
      imageSource: (slot) => '../images/${first.tilesets[slot]!.name}.png',
    );
    final xml = tiled.TmxWriter.write(exported);
    final again = await _import(xml);

    expect(
      jsonEncode([for (final l in again.map.layers) l.toJson()]),
      jsonEncode([for (final l in first.map.layers) l.toJson()]),
    );
    expect(
      jsonEncode([for (final t in again.tilesets) t!.toJson()]),
      jsonEncode([for (final t in first.tilesets) t!.toJson()]),
    );
    expect(again.map.properties.typeOf('music'), TilePropertyType.file);
  });

  test(
    'tiles left of or above the origin make an infinite map, nothing moved',
    () async {
      final map = LevelMapData(tileWidth: 16, tileHeight: 16);
      final slot = map.addTileset('assets/tilesets/a.tileset.json');
      map.addLayer(name: 'L').cells
        ..setCell(-3, -20, TileCell.make(slot, 1))
        ..setCell(5, 2, TileCell.make(slot, 2, TileCell.flipH));
      final ts = TilesetData(
        name: 'a',
        image: 'a.png',
        columns: 2,
        tileCount: 4,
      );

      final exported = TiledInterop.exportMap(map, [
        ts,
      ], imageSource: (_) => 'a.png');
      expect(exported.infinite, isTrue);

      final parsed = await tiled.TileMapParser.parse(
        tiled.TmxWriter.write(exported),
      );
      final back = TiledInterop.importMap(
        parsed,
        tilesetPath: (_, _) => 'assets/tilesets/a.tileset.json',
        imagePath: (_) => 'a.png',
      );
      expect(back.map.layers.single.cells.cellAt(-3, -20), TileCell.make(0, 1));
      expect(
        back.map.layers.single.cells.cellAt(5, 2),
        TileCell.make(0, 2, TileCell.flipH),
      );
    },
  );

  test('a map at zero or beyond is a finite map just big enough', () {
    final map = LevelMapData(tileWidth: 16, tileHeight: 16);
    map.addTileset('t');
    map.addLayer().cells.setCell(6, 3, TileCell.make(0, 0));
    final exported = TiledInterop.exportMap(map, [
      TilesetData(name: 't', image: 't.png', columns: 1, tileCount: 1),
    ], imageSource: (_) => 't.png');
    expect(exported.infinite, isFalse);
    expect((exported.width, exported.height), (7, 4));
    expect(exported.tileLayers.single.rawData![3 * 7 + 6], 1);
  });

  test('an image collection is left out, with a warning', () async {
    const text = '''<?xml version="1.0" encoding="UTF-8"?>
<map version="1.10" orientation="orthogonal" renderorder="right-down" width="1" height="1" tilewidth="16" tileheight="16" infinite="0">
 <tileset firstgid="1" name="bits" tilewidth="16" tileheight="16" tilecount="1" columns="0">
  <tile id="0"><image width="16" height="16" source="a.png"/></tile>
 </tileset>
 <layer id="1" name="L" width="1" height="1"><data encoding="csv">1</data></layer>
</map>''';
    final result = await _import(text);
    expect(result.tilesets.single, isNull);
    expect(result.map.layers.single.cells.isEmpty, isTrue);
    expect(result.warnings, isNotEmpty);
  });

  test("an isometric map's objects are placed on screen", () async {
    const text = '''<?xml version="1.0" encoding="UTF-8"?>
<map version="1.10" orientation="isometric" renderorder="right-down" width="4" height="4" tilewidth="64" tileheight="32" infinite="0">
 <objectgroup id="1" name="O">
  <object id="1" x="32" y="0"><point/></object>
 </objectgroup>
</map>''';
    final result = await _import(text);
    // One tile along x: half a tile right and half a tile down of the top.
    expect(result.objects.single.position, const Offset(32, 16));
  });
}

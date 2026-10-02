// Layer ids that are missing or repeated are made unique on import and on
// read; maps and tilesets saved by a newer engine are refused; and the
// template's own maps and tilesets still read and write exactly as before.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_tiled/just_tiled.dart' as tiled;

const _fixtures = 'test/fx_map_fixtures';

Map<String, dynamic> _fixture(String name) =>
    jsonDecode(File('$_fixtures/$name').readAsStringSync())
        as Map<String, dynamic>;

/// A map from before Tiled 1.2: no layer ids, no next layer id.
const _noIds = '''<?xml version="1.0" encoding="UTF-8"?>
<map version="1.0" orientation="orthogonal" renderorder="right-down" width="2" height="1" tilewidth="16" tileheight="16">
 <tileset firstgid="1" name="set" tilewidth="16" tileheight="16" tilecount="4" columns="2">
  <image source="set.png" width="32" height="32"/>
  <tile id="0"><objectgroup><object id="1" x="0" y="0" width="16" height="16"/></objectgroup></tile>
 </tileset>
 <layer name="A" width="2" height="1">
  <properties><property name="collides" type="bool" value="true"/></properties>
  <data encoding="csv">1,0</data>
 </layer>
 <layer name="B" width="2" height="1">
  <properties><property name="collides" type="bool" value="true"/></properties>
  <data encoding="csv">0,1</data>
 </layer>
 <objectgroup name="Things">
  <object id="1" name="coin" x="4" y="4" width="8" height="8"/>
 </objectgroup>
</map>''';

/// Two layers sharing an id, and a third with one of its own.
const _repeated = '''<?xml version="1.0" encoding="UTF-8"?>
<map version="1.10" orientation="orthogonal" renderorder="right-down" width="1" height="1" tilewidth="16" tileheight="16" nextlayerid="4">
 <layer id="2" name="A" width="1" height="1"><data encoding="csv">0</data></layer>
 <layer id="2" name="B" width="1" height="1"><data encoding="csv">0</data></layer>
 <layer id="3" name="C" width="1" height="1"><data encoding="csv">0</data></layer>
</map>''';

TiledImport _import(tiled.TiledMap map) => TiledInterop.importMap(
  map,
  tilesetPath: (i, _) => 'set#$i',
  imagePath: (_) => 'set.png',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('layer ids', () {
    test('a Tiled map without layer ids gets one per layer', () async {
      final result = _import(await tiled.TileMapParser.parse(_noIds));
      final ids = [for (final l in result.map.layers) l.id];
      expect(ids.toSet(), hasLength(3));
      expect(ids.every((id) => id > 0), isTrue);
      expect(
        result.map.nextLayerId,
        greaterThan(ids.reduce((a, b) => a > b ? a : b)),
      );
      final things = result.map.layers.firstWhere((l) => l.name == 'Things');
      expect(result.objects.single.mapLayerId, things.id);
      expect(result.map.layerById(ids[1])!.name, 'B');
    });

    test('a repeated Tiled layer id: the first keeps it, the next gets a new '
        'one', () async {
      final result = _import(await tiled.TileMapParser.parse(_repeated));
      expect(
        [for (final l in result.map.layers) (l.name, l.id)],
        [('A', 2), ('B', 4), ('C', 3)],
      );
      expect(result.map.nextLayerId, 5);
    });

    test('in a running game each such layer draws, collides and changes on '
        'its own', () async {
      final world = World()..initialize();
      final tiles = world.context.tiles;
      tiles.readText = (path) async =>
          path == 'maps/old.tmx' ? _noIds : throw StateError('no file $path');
      tiles.log = (_) {}; // its image is not there
      registerLevelMapSystems(world);
      addTearDown(world.dispose);
      final e = world.createEntityWithComponents([
        TransformComponent(),
        LevelMapComponent(mapPath: 'maps/old.tmx'),
      ]);
      expect(await LevelMaps.preload(world), isEmpty);
      world.update(0);

      final items = e.getComponent<RenderItemsComponent>()!.items;
      expect({
        for (final i in items) (i as MapLayerRenderItem).layerId,
      }, hasLength(3));
      final bodies = world.query([MapBodyComponent]);
      expect(
        {for (final b in bodies) b.getComponent<MapBodyComponent>()!.layerId},
        hasLength(2),
        reason: 'each colliding layer keeps its bodies',
      );

      final h = LevelMaps.of(world, e)!;
      final a = h.layer('A')!;
      final b = h.layer('B')!;
      h.setTile(b, const TileCoord(0, 0), TileCell.make(0, 3));
      expect(h.rawAt(a, const TileCoord(0, 0)), TileCell.make(0, 0));
      expect(h.rawAt(b, const TileCoord(0, 0)), TileCell.make(0, 3));
    });

    test('a saved map: a layer without an id, or repeating one, gets a new '
        'one after the largest', () {
      final map = LevelMapData.fromJson({
        'format': 1,
        'nextLayerId': 3,
        'layers': [
          {'id': 1, 'name': 'A'},
          {'name': 'B'},
          {'id': 1, 'name': 'C'},
          {'id': 2, 'name': 'D'},
        ],
      });
      expect(
        [for (final l in map.layers) (l.name, l.id)],
        [('A', 1), ('B', 3), ('C', 4), ('D', 2)],
      );
      expect(map.nextLayerId, 5);
      expect(map.addLayer().id, 5);
    });

    test('a saved layer whose id is 0 and its own keeps it', () {
      final map = LevelMapData.fromJson({
        'layers': [
          {'id': 0, 'name': 'A'},
          {'id': 1, 'name': 'B'},
        ],
      });
      expect([for (final l in map.layers) l.id], [0, 1]);
    });
  });

  group('formats', () {
    test('a map saved by a newer engine is refused', () {
      expect(
        () => LevelMapData.fromJson({'format': 3, 'layers': []}),
        throwsA(
          isA<UnsupportedFormatVersionException>()
              .having((e) => e.found, 'found', 3)
              .having((e) => e.supported, 'supported', 2),
        ),
      );
    });

    test('form 2 — shapes in layers — still reads, its shapes passed over', () {
      final map = LevelMapData.fromJson({
        'format': 2,
        'layers': [
          {
            'id': 1,
            'name': 'A',
            'shapes': [
              {'type': 'rect'},
            ],
          },
        ],
      });
      expect(map.layers.single.name, 'A');
      expect(map.toJson()['format'], LevelMapData.format);
    });

    test('a tileset saved by a newer engine is refused', () {
      expect(
        () => TilesetData.fromJson({'format': 2}),
        throwsA(isA<UnsupportedFormatVersionException>()),
      );
      expect(TilesetData.fromJson({'format': 1}).name, '');
    });

    test('a newer map file does not load: reported, and returned by '
        'preload', () async {
      final logged = <String>[];
      final world = World()..initialize();
      world.context.tiles
        ..log = logged.add
        ..readText = (path) async => jsonEncode({'format': 9});
      registerLevelMapSystems(world);
      addTearDown(world.dispose);
      world.createEntityWithComponents([
        TransformComponent(),
        LevelMapComponent(mapPath: 'maps/new.map.json'),
      ]);
      final failures = await LevelMaps.preload(world);
      expect(failures.single.error, isA<UnsupportedFormatVersionException>());
      expect(logged.single, contains('maps/new.map.json'));
    });
  });

  group("the template's maps and tilesets", () {
    for (final name in [
      'playground.map.json',
      'level_01_inline.map.json',
      'level_01_piece.map.json',
    ]) {
      test('$name reads and writes exactly as saved', () {
        final json = _fixture(name);
        final again = jsonDecode(
          jsonEncode(LevelMapData.fromJson(json).toJson()),
        );
        expect(again, json);
      });
    }

    test('grassland.tileset.json reads and writes exactly as saved', () {
      final json = _fixture('grassland.tileset.json');
      final again = jsonDecode(jsonEncode(TilesetData.fromJson(json).toJson()));
      expect(again, json);
    });

    test('the Tiled map and its .tsx import as they did before', () async {
      final tiles = EngineContext().tiles
        ..readText = (path) async =>
            File('$_fixtures/${path.split('/').last}').readAsString();
      addTearDown(tiles.dispose);
      final map = await tiles.map('maps/level_map_1.tmx');
      expect(
        jsonDecode(jsonEncode(map.toJson())),
        _fixture('level_map_1.expected.map.json'),
      );
      expect(
        jsonDecode(
          jsonEncode(tiles.loadedTileset('maps/level_map_1.tmx#0')!.toJson()),
        ),
        _fixture('level_map_1.expected.tileset.json'),
      );
    });
  });
}

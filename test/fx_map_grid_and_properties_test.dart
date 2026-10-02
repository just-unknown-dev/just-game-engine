// A grid with no size does not throw when a cell is looked up or drawn; a
// property keeps the type it was declared with; and a layer's collides and
// foreground settings leave for Tiled as the engine has them.

import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_tiled/just_tiled.dart' as tiled;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('a grid with no size', () {
    for (final orientation in MapOrientation.values) {
      for (final (w, h) in [(0, 0), (0, 16), (16, 0), (1, 1), (-4, 3)]) {
        test('${orientation.name} $w×$h: cells are still found', () {
          final g = MapGeometry(
            orientation: orientation,
            tileWidth: w,
            tileHeight: h,
            hexSideLength: -6,
          );
          final cell = g.cellAt(const Offset(37.5, -12.25));
          final range = g.cellRange(const Rect.fromLTWH(-50, -50, 300, 200));
          expect(range.isEmpty, isFalse);
          expect(g.cellsIn(const Rect.fromLTWH(0, 0, 40, 40)), isNotNull);
          final c = g.cellCenter(cell.x, cell.y);
          expect(c.dx.isFinite && c.dy.isFinite, isTrue);
          expect(g.tileWidth, greaterThanOrEqualTo(1));
          expect(g.tileHeight, greaterThanOrEqualTo(1));
        });
      }
    }

    test('a map of it draws without throwing', () async {
      final image = await createTestImage(width: 32, height: 32);
      final m = LevelMapData(
        orientation: MapOrientation.staggered,
        tileWidth: 0,
        tileHeight: 0,
      );
      m.addLayer().cells.setCell(0, 0, TileCell.make(0, 0));
      final world = World()..initialize();
      registerLevelMapSystems(world, collision: false);
      world.addSystem(
        RenderSystem(camera: Camera(viewportSize: const Size(100, 100))),
      );
      addTearDown(world.dispose);
      world.createEntityWithComponents([
        TransformComponent(),
        LevelMapComponent(inline: m),
      ]);
      world.update(0);
      final recorder = PictureRecorder();
      world.render(Canvas(recorder), const Size(100, 100));
      recorder.endRecording().dispose();
      image.dispose();
    });
  });

  group('a property', () {
    test('declared a float stays one when set to a whole number', () {
      final p = TileProperties()..set('speed', 1.5);
      expect(p.typeOf('speed'), TilePropertyType.float);
      p.set('speed', 2);
      expect(p.typeOf('speed'), TilePropertyType.float);
      expect(p['speed'], isA<double>());
      final again = TileProperties.fromJson(jsonDecode(jsonEncode(p.toJson())));
      expect(again.typeOf('speed'), TilePropertyType.float);
      expect(again['speed'], 2.0);
    });

    test('declared a file stays one when set to another path', () {
      final p = TileProperties()
        ..set('music', 'a.ogg', TilePropertyType.file)
        ..set('music', 'b.ogg');
      expect(p.typeOf('music'), TilePropertyType.file);
    });

    test('declared an int stays one for whole numbers, becomes a float for '
        'a fraction', () {
      final p = TileProperties()..set('hp', 3);
      p.set('hp', 4.0);
      expect(p.typeOf('hp'), TilePropertyType.int);
      expect(p['hp'], 4);
      p.set('hp', 4.5);
      expect(p.typeOf('hp'), TilePropertyType.float);
    });

    test('given a value of another kind is typed by it; a type given '
        'wins', () {
      final p = TileProperties()
        ..set('x', true)
        ..set('x', 'yes');
      expect(p.typeOf('x'), TilePropertyType.string);
      p.set('x', 2, TilePropertyType.float);
      expect(p.typeOf('x'), TilePropertyType.float);
      expect(p['x'], 2.0);
      p.set('id', 7, TilePropertyType.object);
      expect(p.typeOf('id'), TilePropertyType.object);
    });

    test('new, is typed by its value', () {
      final p = TileProperties()
        ..set('a', 2)
        ..set('b', 2.5)
        ..set('c', false)
        ..set('d', 'text')
        ..set('e', double.infinity);
      expect(
        [
          for (final n in ['a', 'b', 'c', 'd', 'e']) p.typeOf(n),
        ],
        [
          TilePropertyType.int,
          TilePropertyType.float,
          TilePropertyType.bool,
          TilePropertyType.string,
          TilePropertyType.float,
        ],
      );
    });
  });

  group('export to Tiled', () {
    const tmx = '''<?xml version="1.0" encoding="UTF-8"?>
<map version="1.10" orientation="orthogonal" renderorder="right-down" width="1" height="1" tilewidth="16" tileheight="16" nextlayerid="3">
 <layer id="1" name="Ground" width="1" height="1">
  <properties><property name="collides" type="bool" value="true"/><property name="foreground" type="bool" value="true"/><property name="damage" type="int" value="2"/></properties>
  <data encoding="csv">0</data>
 </layer>
 <layer id="2" name="Plain" width="1" height="1"><data encoding="csv">0</data></layer>
</map>''';

    Future<LevelMapData> roundTrip(LevelMapData map) async {
      final exported = TiledInterop.exportMap(
        map,
        const [],
        imageSource: (_) => '',
      );
      final parsed = await tiled.TileMapParser.parse(
        tiled.TmxWriter.write(exported),
      );
      return TiledInterop.importMap(
        parsed,
        tilesetPath: (i, _) => 't#$i',
        imagePath: (_) => '',
      ).map;
    }

    Future<LevelMapData> imported() async => TiledInterop.importMap(
      await tiled.TileMapParser.parse(tmx),
      tilesetPath: (i, _) => 't#$i',
      imagePath: (_) => '',
    ).map;

    test('writes the settings as they are now, not as they were '
        'imported', () async {
      final map = await imported();
      final ground = map.layers.first;
      expect(ground.collides, isTrue);
      expect(ground.sortLayerId, 'foreground');
      ground
        ..collides = false
        ..sortLayerId = 'main'
        ..sortLayer = 0;
      final plain = map.layers.last
        ..collides = true
        ..sortLayerId = 'foreground'
        ..sortLayer = 100;

      final again = await roundTrip(map);
      expect(again.layers.first.collides, isFalse);
      expect(again.layers.first.sortLayerId, 'main');
      expect(again.layers.first.properties['damage'], 2);
      expect(again.layers.last.name, plain.name);
      expect(again.layers.last.collides, isTrue);
      expect(again.layers.last.sortLayerId, 'foreground');
    });

    test('an unchanged import exports the same settings', () async {
      final again = await roundTrip(await imported());
      final ground = again.layers.first;
      expect(ground.collides, isTrue);
      expect(ground.sortLayerId, 'foreground');
      expect(again.layers.last.collides, isFalse);
      expect(again.layers.last.sortLayerId, 'main');
    });
  });
}

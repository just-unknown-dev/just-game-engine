// A tile map in a running world: loaded from the scene, a file or a Tiled
// map; drawn a layer at a time among the level's sprites; changed by the
// game without touching the map it was loaded from.

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// Records every draw call instead of drawing.
class _Recorder implements Canvas {
  final List<Invocation> calls = [];

  List<Invocation> get atlases =>
      calls.where((c) => c.memberName == #drawRawAtlas).toList();

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation);
    return null;
  }
}

class _Images extends SpriteAssetLoader {
  _Images(this.image);
  final ui.Image image;

  @override
  Future<ui.Image> loadImage(String path) async => image;

  @override
  Future<SpriteAtlas> loadAtlas(String path) => throw UnimplementedError();
}

TilesetData _tileset() =>
    TilesetData(
        name: 'grass',
        image: 'assets/t.png',
        imageWidth: 32,
        imageHeight: 32,
        tileWidth: 16,
        tileHeight: 16,
        columns: 2,
        tileCount: 4,
      )
      ..tileOrNew(1).className = 'Spike'
      ..tileOrNew(1).properties.set('damage', 2)
      ..tileOrNew(2).animation = [
        const TileFrame(2, 100),
        const TileFrame(3, 100),
      ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late World world;
  late ui.Image image;
  final files = <String, String>{};

  setUpAll(() async => image = await createTestImage(width: 32, height: 32));

  setUp(() {
    TileAssets.clear();
    TileAssets.readText = (path) async =>
        files[path] ?? (throw StateError('no file $path'));
    SpriteAssets.loader = _Images(image);
    files
      ..clear()
      ..['assets/t.tileset.json'] = jsonEncode(_tileset().toJson());
    world = World()..initialize();
    registerLevelMapSystems(world);
  });

  tearDown(() {
    world.dispose();
    TileAssets.useBundle();
    SpriteAssets.loader = BundleSpriteAssetLoader();
  });

  LevelMapData map() {
    final m = LevelMapData(tileWidth: 16, tileHeight: 16);
    m.addTileset('assets/t.tileset.json');
    m.addLayer(name: 'Back')
      ..sortLayer = LevelLayers.background
      ..cells.setCell(0, 0, TileCell.make(0, 0));
    m.addLayer(name: 'Front')
      ..sortLayer = LevelLayers.foreground
      ..cells.setCell(1, 0, TileCell.make(0, 1));
    return m;
  }

  group('in the scene', () {
    test('each layer is a render item of its own, kept in step', () {
      final m = map();
      final e = world.createEntityWithComponents([
        TransformComponent(),
        LevelMapComponent(inline: m),
      ]);
      world.update(0);
      final items = e.getComponent<RenderItemsComponent>()!.items;
      expect(
        [for (final i in items) (i as MapLayerRenderItem).layer],
        [LevelLayers.background, LevelLayers.foreground],
      );

      m.addLayer(name: 'More');
      m.touch();
      world.update(0);
      expect(e.getComponent<RenderItemsComponent>()!.items, hasLength(3));
    });

    test('its saved form is a copy, read back into a map of its own', () {
      final registry = ComponentDefinitionRegistry()
        ..registerAll(CoreDefinitions.all);
      final component = LevelMapComponent(inline: map());
      final json = registry.encode(component)!;
      final again =
          registry.decode(jsonDecode(jsonEncode(json)) as Map<String, dynamic>)
              as LevelMapComponent;
      expect(
        jsonEncode(again.inline!.toJson()),
        jsonEncode(component.inline!.toJson()),
      );
      // What was encoded does not change with the map afterwards.
      component.inline!.layers.first.cells.setCell(5, 5, TileCell.make(0, 3));
      expect(jsonEncode(json), isNot(contains('"5,5"')));
    });

    test('replacing the map (a play-test stopping) makes a new runtime', () {
      final c = LevelMapComponent(inline: map());
      world.createEntityWithComponents([TransformComponent(), c]);
      world.update(0);
      final first = c.runtime;
      c.inline = map();
      world.update(0);
      expect(c.runtime, isNot(same(first)));
      expect(c.runtime!.base, same(c.inline));
    });
  });

  group('from a file', () {
    test('loads with its tilesets; the game changes a copy', () async {
      files['assets/maps/a.tilemap.json'] = jsonEncode(map().toJson());
      final a = world.createEntityWithComponents([
        TransformComponent(position: Vector3(100, 0, 0)),
        LevelMapComponent(mapPath: 'assets/maps/a.tilemap.json'),
      ]);
      final b = world.createEntityWithComponents([
        TransformComponent(),
        LevelMapComponent(mapPath: 'assets/maps/a.tilemap.json'),
      ]);
      await LevelMaps.preload(world);

      final ha = LevelMaps.of(world, a)!;
      final front = ha.layer('Front')!;
      final spike = ha.tileAtPoint(front, const Offset(100 + 20, 5))!;
      expect(spike.className, 'Spike');
      expect(spike.properties['damage'], 2);
      expect(ha.cellCenter(front, const TileCoord(1, 0)), const Offset(124, 8));

      ha.setTile(front, const TileCoord(1, 0), TileCell.empty);
      expect(ha.tileAt(front, const TileCoord(1, 0)), isNull);
      final hb = LevelMaps.of(world, b)!;
      expect(
        hb.tileAt(hb.layer('Front')!, const TileCoord(1, 0))?.className,
        'Spike',
        reason: 'the other map made from the file is untouched',
      );
    });

    test('hiding a body hides the cells it was built from, and shows them '
        'again', () async {
      files['assets/maps/a.tilemap.json'] = jsonEncode(map().toJson());
      final e = world.createEntityWithComponents([
        TransformComponent(),
        LevelMapComponent(mapPath: 'assets/maps/a.tilemap.json'),
      ]);
      await LevelMaps.preload(world);
      final handle = LevelMaps.of(world, e)!;
      final front = handle.layer('Front')!;
      final body = MapBodyComponent(
        mapEntityId: e.id,
        layerId: front.id,
        kind: 'solid',
        cells: const [TileCoord(1, 0)],
      );
      handle.setBodyHidden(body, true);
      expect(handle.runtime.hiddenCells[front.id], {const TileCoord(1, 0)});
      handle.setBodyHidden(body, false);
      expect(handle.runtime.hiddenCells[front.id], isEmpty);
    });

    test('a Tiled map loads directly, tilesets and all', () async {
      files['assets/maps/b.tmx'] = '''<?xml version="1.0" encoding="UTF-8"?>
<map version="1.10" orientation="orthogonal" renderorder="right-down" width="2" height="1" tilewidth="16" tileheight="16" infinite="0" nextlayerid="2">
 <tileset firstgid="1" source="../tiles/set.tsx"/>
 <layer id="1" name="Ground" width="2" height="1">
  <properties><property name="collides" type="bool" value="true"/></properties>
  <data encoding="csv">1,2</data>
 </layer>
</map>''';
      files['assets/tiles/set.tsx'] = '''<?xml version="1.0" encoding="UTF-8"?>
<tileset version="1.10" name="set" tilewidth="16" tileheight="16" tilecount="4" columns="2">
 <image source="set.png" width="32" height="32"/>
 <tile id="0"><objectgroup><object id="1" x="0" y="0" width="16" height="16"/></objectgroup></tile>
</tileset>''';
      final e = world.createEntityWithComponents([
        TransformComponent(),
        LevelMapComponent(mapPath: 'assets/maps/b.tmx'),
      ]);
      await LevelMaps.preload(world);

      final h = LevelMaps.of(world, e)!;
      final ground = h.layer('Ground')!;
      expect(ground.collides, isTrue);
      expect(h.rawAt(ground, const TileCoord(1, 0)), TileCell.make(0, 1));
      final ts = TileAssets.loadedTileset('assets/maps/b.tmx#0')!;
      expect(ts.image, 'assets/tiles/set.png', reason: 'relative to the .tsx');

      world.update(0);
      expect(world.query([MapBodyComponent]), hasLength(1));
    });
  });

  group('drawing', () {
    late RenderSystem render;
    setUp(() {
      render = RenderSystem(camera: Camera(viewportSize: const Size(400, 300)));
      world.addSystem(render);
    });

    Future<Entity> ready(LevelMapData m) async {
      final e = world.createEntityWithComponents([
        TransformComponent(),
        LevelMapComponent(inline: m),
      ]);
      world.update(0);
      await e.getComponent<LevelMapComponent>()!.runtime!.syncAssets();
      return e;
    }

    test(
      'layers sort among sprites: background behind, foreground in front',
      () async {
        await ready(map());
        world.createEntityWithComponents([
          TransformComponent(),
          RenderableComponent(
            renderable: CustomRenderable(
              onRender: (canvas, _) =>
                  canvas.drawCircle(Offset.zero, 1, Paint()),
            ),
          ),
          LayerComponent(),
        ]);
        final canvas = _Recorder();
        world.render(canvas, const Size(400, 300));
        final order = [
          for (final c in canvas.calls)
            if (c.memberName == #drawRawAtlas)
              'tiles'
            else if (c.memberName == #drawCircle)
              'sprite',
        ];
        expect(order, ['tiles', 'sprite', 'tiles']);
      },
    );

    test('a mirrored tile is drawn from the mirrored image', () async {
      final m = LevelMapData(tileWidth: 16, tileHeight: 16)
        ..addTileset('assets/t.tileset.json');
      m.addLayer().cells
        ..setCell(0, 0, TileCell.make(0, 0))
        ..setCell(1, 0, TileCell.make(0, 1, TileCell.flipH));
      await ready(m);
      final canvas = _Recorder();
      world.render(canvas, const Size(400, 300));

      final atlases = canvas.atlases;
      expect(atlases, hasLength(2));
      final plain = atlases.firstWhere(
        (c) => identical(c.positionalArguments[0], image),
      );
      final mirrored = atlases.firstWhere(
        (c) => !identical(c.positionalArguments[0], image),
      );
      expect((plain.positionalArguments[2] as Float32List).toList(), [
        0,
        0,
        16,
        16,
      ]);
      // Tile 1 is at x 16..32; mirrored across the 32-wide image it is 0..16.
      expect((mirrored.positionalArguments[2] as Float32List).toList(), [
        0,
        0,
        16,
        16,
      ]);
    });

    test('an animated tile moves on with the clock', () async {
      final m = LevelMapData(tileWidth: 16, tileHeight: 16)
        ..addTileset('assets/t.tileset.json');
      m.addLayer().cells.setCell(0, 0, TileCell.make(0, 2));
      await ready(m);
      final system = world.systems.whereType<LevelMapSystem>().single
        ..advanceClock = false;

      Float32List rects() {
        final canvas = _Recorder();
        world.update(0);
        world.render(canvas, const Size(400, 300));
        return canvas.atlases.single.positionalArguments[2] as Float32List;
      }

      system.clockMs = 0;
      expect(rects().toList(), [0, 16, 16, 32], reason: 'tile 2');
      system.clockMs = 150;
      expect(rects().toList(), [16, 16, 32, 32], reason: 'tile 3');
    });

    test('chunks out of view are not drawn', () async {
      final m = LevelMapData(tileWidth: 16, tileHeight: 16)
        ..addTileset('assets/t.tileset.json');
      m.addLayer().cells
        ..setCell(0, 0, TileCell.make(0, 0))
        ..setCell(4000, 0, TileCell.make(0, 0));
      await ready(m);
      final canvas = _Recorder();
      world.render(canvas, const Size(400, 300));
      expect(canvas.atlases, hasLength(1));
    });

    test('an editor can fade a layer without changing it', () async {
      final e = await ready(map());
      final rt = e.getComponent<LevelMapComponent>()!.runtime!;
      rt.layerAlpha[rt.base.layers.first.id] = 0.25;
      final canvas = _Recorder();
      world.render(canvas, const Size(400, 300));
      final colors = canvas.atlases.first.positionalArguments[3] as Int32List;
      expect((colors.first >>> 24) & 0xFF, closeTo(64, 1));
      expect(rt.base.layers.first.opacity, 1);
    });
  });
}

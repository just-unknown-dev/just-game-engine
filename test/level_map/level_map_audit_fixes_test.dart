// Level map fixes from the 2.0.0 final pass: image layers keep their
// groups' visibility, parallax and tint (F10); chunk cell counts are
// checked (F11); a map body is a box or a polygon, never both (F12); hidden
// cells change only through the handle, which redraws (F13).

import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_tiled/just_tiled.dart' as tiled;

const _imageInHiddenGroup = '''<?xml version="1.0" encoding="UTF-8"?>
<map version="1.10" orientation="orthogonal" renderorder="right-down" width="1" height="1" tilewidth="16" tileheight="16" nextlayerid="4">
 <group id="1" name="G" visible="0" opacity="0.5" offsetx="10" parallaxx="0.5" parallaxy="2" tintcolor="#ff0000">
  <imagelayer id="2" name="Sky" offsetx="3" offsety="4" opacity="0.5" parallaxx="0.5">
   <image source="sky.png" width="8" height="8"/>
  </imagelayer>
 </group>
 <imagelayer id="3" name="Plain">
  <image source="plain.png" width="8" height="8"/>
 </imagelayer>
</map>''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('F10 an image layer carries its groups\' look', () async {
    final result = TiledInterop.importMap(
      await tiled.TileMapParser.parse(_imageInHiddenGroup),
      tilesetPath: (i, _) => 'set#$i',
      imagePath: (_) => 'set.png',
    );
    final sky = result.images.firstWhere((r) => r.layer.name == 'Sky');
    expect(sky.visible, isFalse, reason: 'its group is hidden');
    expect(sky.position, const Offset(13, 4));
    expect(sky.opacity, closeTo(0.25, 1e-9));
    expect(sky.parallaxX, closeTo(0.25, 1e-9));
    expect(sky.parallaxY, closeTo(2, 1e-9));
    expect(sky.tint, isNotNull);
    expect(sky.tint!.r, closeTo(1, 1e-9));
    expect(sky.tint!.g, closeTo(0, 1e-9));

    final plain = result.images.firstWhere((r) => r.layer.name == 'Plain');
    expect(plain.visible, isTrue);
    expect((plain.parallaxX, plain.parallaxY), (1.0, 1.0));
    expect(plain.tint, isNull);
  });

  test('F11 a chunk holds exactly one chunk of cells', () {
    expect(
      () => TileChunkData(0, 0, Uint32List(10)),
      throwsA(isA<ArgumentError>()),
    );
    final cells = Uint32List(TileChunkStore.cellsPerChunk);
    expect(TileChunkData(1, 2, cells).cells, same(cells));
    expect(TileChunkData(1, 2).cells, hasLength(TileChunkStore.cellsPerChunk));
  });

  test('F12 a map body is a box or a polygon — exactly one', () {
    expect(
      () => MapBodySpec(kind: 'solid', center: Offset.zero),
      throwsArgumentError,
    );
    expect(
      () => MapBodySpec(
        kind: 'solid',
        center: Offset.zero,
        size: const Size(4, 4),
        polygon: const [Offset.zero, Offset(1, 0), Offset(0, 1)],
      ),
      throwsArgumentError,
    );
    expect(
      MapBodySpec(
        kind: 'solid',
        center: Offset.zero,
        size: const Size(4, 4),
      ).isBox,
      isTrue,
    );
  });

  test(
    'F13 hidden cells change only through the handle, which redraws',
    () async {
      final world = World()..initialize();
      addTearDown(world.dispose);
      final data = LevelMapData();
      final layer = data.addLayer(name: 'Front');
      final entity = world.createEntityWithComponents([
        TransformComponent(),
        LevelMapComponent(inline: data),
      ]);
      await LevelMaps.preload(world);
      final handle = LevelMaps.of(world, entity)!;
      final runtime = handle.runtime;

      expect(
        () => runtime.hiddenCells[layer.id] = {const TileCoord(0, 0)},
        throwsUnsupportedError,
      );
      final before = runtime.hiddenRevision;
      handle.setCellsHidden(layer, const [TileCoord(1, 0)], true);
      expect(runtime.hiddenRevision, before + 1);
      expect(runtime.hiddenCellsOf(layer.id), {const TileCoord(1, 0)});
      expect(
        () => runtime.hiddenCellsOf(layer.id)!.add(const TileCoord(2, 0)),
        throwsUnsupportedError,
      );
      expect(
        () => runtime.hiddenCells[layer.id]!.clear(),
        throwsUnsupportedError,
      );
    },
  );
}

// The Level Map was a tile map: scenes and files saved under the old names
// still load, and are saved under the new ones.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  setUpAll(registerCoreCodecs);

  test('a map saved as a TileMapComponent loads, and is saved as a '
      'LevelMapComponent', () {
    final saved = ComponentCodecRegistry.instance.encode(
      LevelMapComponent(mapPath: 'assets/maps/cave.map.json'),
    )!;
    expect(saved['type'], 'LevelMapComponent');

    final old = {...saved, 'type': 'TileMapComponent'};
    final back = ComponentCodecRegistry.instance.decode(old);
    expect(back, isA<LevelMapComponent>());
    expect((back! as LevelMapComponent).mapPath, 'assets/maps/cave.map.json');
    expect(
      ComponentCodecRegistry.instance.encode(back)!['type'],
      'LevelMapComponent',
    );
  });

  test('a map file is a .map.json, and a .tilemap.json is still one', () {
    expect(LevelMapFiles.isMapFile('assets/maps/cave.map.json'), isTrue);
    expect(LevelMapFiles.isMapFile('assets/maps/cave.tilemap.json'), isTrue);
    expect(LevelMapFiles.isMapFile('assets/maps/CAVE.MAP.JSON'), isTrue);
    expect(LevelMapFiles.isMapFile('assets/maps/cave.tileset.json'), isFalse);
    expect(LevelMapFiles.isMapFile('assets/maps/cave.json'), isFalse);
    expect(LevelMapFiles.isMapFile('assets/maps/cave.tmx'), isFalse);
  });

  test('a map is named after its file, whichever ending it has', () {
    expect(LevelMapFiles.stem('assets/maps/cave.map.json'), 'cave');
    expect(LevelMapFiles.stem('assets/maps/cave.tilemap.json'), 'cave');
    expect(LevelMapFiles.stem(r'assets\maps\Cave.Map.Json'), 'Cave');
  });

  test('the level map is the one called Level Map, else the first', () {
    final world = World()..initialize();
    addTearDown(world.dispose);
    expect(LevelMaps.primaryEntity(world), isNull);
    final old = world.createEntityWithComponents([
      LevelMapComponent(),
    ], name: 'Tiles');
    expect(LevelMaps.primaryEntity(world), same(old));
    final level = world.createEntityWithComponents([
      LevelMapComponent(),
    ], name: LevelMaps.primaryName);
    expect(LevelMaps.primaryEntity(world), same(level));
  });
}

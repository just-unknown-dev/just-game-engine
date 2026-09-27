// A tile map's saved form, its sparse cells, and the copy-on-write overlay
// a running game writes to.

import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

LevelMapData _sample() {
  final map = LevelMapData(tileWidth: 16, tileHeight: 16);
  final slot = map.addTileset('assets/tilesets/grass.tileset.json');
  final ground = map.addLayer(name: 'Ground')
    ..collides = true
    ..opacity = 0.5
    ..tint = 0xFF808080
    ..parallaxX = 0.5
    ..sortLayerId = 'background'
    ..sortLayer = -200
    ..properties.set('ambient', 'wind');
  ground.cells
    ..setCell(0, 0, TileCell.make(slot, 1))
    ..setCell(-20, 3, TileCell.make(slot, 2, TileCell.flipH))
    ..setCell(40, -17, TileCell.make(slot, 3, TileCell.flipD));
  map.addLayer(name: 'Empty');
  map.properties.set('music', 'assets/a.ogg', TilePropertyType.file);
  return map;
}

void main() {
  group('the cells', () {
    test('live in chunks, anywhere, negative included', () {
      final store = TileChunkStore();
      expect(store.setCell(-1, -1, 5), isTrue);
      expect(store.setCell(17, 33, 6), isTrue);
      expect(store.cellAt(-1, -1), 5);
      expect(store.cellAt(17, 33), 6);
      expect(store.cellAt(0, 0), TileCell.empty);
      expect(store.chunks, hasLength(2));
      expect(store.usedBounds, const Rect.fromLTRB(-1, -1, 18, 34));
    });

    test('a write that changes nothing is not a change', () {
      final store = TileChunkStore()..setCell(2, 2, 9);
      final revision = store.revision;
      expect(store.setCell(2, 2, 9), isFalse);
      expect(store.setCell(90, 90, TileCell.empty), isFalse);
      expect(store.revision, revision);
    });

    test('an overlay writes its own copy and leaves the base alone', () {
      final base = TileChunkStore()..setCell(1, 1, 7);
      final overlay = TileChunkStore.over(base);
      expect(overlay.cellAt(1, 1), 7, reason: 'reads through');

      overlay.setCell(1, 1, TileCell.empty);
      overlay.setCell(2, 1, 8);

      expect(base.cellAt(1, 1), 7);
      expect(base.cellAt(2, 1), TileCell.empty);
      expect(overlay.cellAt(1, 1), TileCell.empty);
      expect(overlay.cellAt(2, 1), 8);
      expect(overlay.chunks, hasLength(1), reason: 'one chunk, now its own');
    });

    test('an untouched chunk of the base still shows through', () {
      final base = TileChunkStore()
        ..setCell(1, 1, 7)
        ..setCell(100, 100, 9);
      final overlay = TileChunkStore.over(base)..setCell(1, 1, 3);
      expect(overlay.cellAt(100, 100), 9);
      expect(overlay.chunks, hasLength(2));
    });
  });

  group('the saved form', () {
    test('round trips exactly', () {
      final map = _sample();
      final json = jsonEncode(map.toJson());
      final again = LevelMapData.fromJson(
        jsonDecode(json) as Map<String, dynamic>,
      );
      expect(jsonEncode(again.toJson()), json);
      expect(
        again.layers.first.cells.cellAt(-20, 3),
        map.layers.first.cells.cellAt(-20, 3),
      );
      expect(again.properties.typeOf('music'), TilePropertyType.file);
      expect(again.nextLayerId, 3);
    });

    test('leaves empty chunks out', () {
      final store = TileChunkStore()
        ..setCell(0, 0, 5)
        ..setCell(0, 0, TileCell.empty)
        ..setCell(40, 0, 6);
      expect(store.toJson().keys, ['2,0']);
    });

    test('is a new map every time, so a snapshot cannot change later', () {
      final map = _sample();
      final first = map.toJson();
      (first['layers'] as List).clear();
      expect(map.toJson()['layers'], hasLength(2));
    });

    test('reads into a map of its own, sharing nothing', () {
      final json = _sample().toJson();
      final a = LevelMapData.fromJson(json);
      final b = LevelMapData.fromJson(json);
      a.layers.first.cells.setCell(0, 0, TileCell.empty);
      expect(b.layers.first.cells.cellAt(0, 0), isNot(TileCell.empty));
    });

    test("a chunk's saved string is reused until the chunk changes", () {
      final store = TileChunkStore()..setCell(0, 0, 5);
      final before = store.toJson()['0,0'];
      expect(store.chunk(0, 0)!.encoded, before);
      store.setCell(1, 0, 6);
      expect(store.chunk(0, 0)!.encoded, isNull);
      expect(store.toJson()['0,0'], isNot(before));
    });

    test('an unreadable chunk is skipped, not fatal', () {
      final store = TileChunkStore.fromJson({'0,0': 'not base64!', 'x': 'y'});
      expect(store.isEmpty, isTrue);
    });

    test('a copy is separate', () {
      final map = _sample();
      final copy = map.copy();
      copy.layers.first.cells.setCell(0, 0, TileCell.empty);
      copy.layers.first.name = 'Changed';
      expect(map.layers.first.cells.cellAt(0, 0), isNot(TileCell.empty));
      expect(map.layers.first.name, 'Ground');
    });
  });

  test('tilesets keep their slots; one in use is known to be', () {
    final map = _sample();
    expect(map.addTileset('assets/tilesets/grass.tileset.json'), 0);
    expect(map.addTileset('assets/tilesets/cave.tileset.json'), 1);
    expect(map.usesSlot(0), isTrue);
    expect(map.usesSlot(1), isFalse);
  });

  group('a tileset', () {
    test('cuts its image into a grid', () {
      final ts = TilesetData.fromImage(
        name: 'grass',
        image: 'assets/tilesets/grass.png',
        imageWidth: 70,
        imageHeight: 36,
        tileWidth: 16,
        tileHeight: 16,
        margin: 2,
        spacing: 1,
      );
      expect(ts.columns, 4);
      expect(ts.rows, 2);
      expect(ts.sourceRect(5), const Rect.fromLTWH(19, 19, 16, 16));
    });

    test('round trips collision, animation, terrain and properties', () {
      final ts =
          TilesetData(name: 'x', image: 'a.png', columns: 4, tileCount: 8)
            ..tileOrNew(1).collision = TileCollision(
              kind: 'oneWay',
              shapes: [
                const TileRectShape(Rect.fromLTWH(0, 0, 32, 8)),
                const TilePolygonShape([
                  Offset(0, 32),
                  Offset(32, 0),
                  Offset(32, 32),
                ]),
                const TileEllipseShape(Rect.fromLTWH(4, 4, 8, 8)),
              ],
            )
            ..tileOrNew(2).animation = [
              const TileFrame(2, 100),
              const TileFrame(3, 150),
            ]
            ..tileOrNew(2).probability = 0.25
            ..tileOrNew(3).properties.set('damage', 2)
            ..wangSets.add(
              WangSetData(
                name: 'Grass',
                colors: [WangColorData(name: 'g')],
                wangIds: {
                  0: [0, 1, 0, 1, 0, 1, 0, 1],
                },
              ),
            );
      final again = TilesetData.fromJson(
        jsonDecode(jsonEncode(ts.toJson())) as Map<String, dynamic>,
      );
      expect(jsonEncode(again.toJson()), jsonEncode(ts.toJson()));
      expect(again.tile(1)!.collision!.shapes, hasLength(3));
      expect(again.tile(2)!.frameAt(2, 120), 3);
      expect(again.tile(2)!.frameAt(2, 260), 2, reason: 'loops');
    });

    test('a tile that says nothing is not saved', () {
      final ts = TilesetData()..tileOrNew(4);
      expect((ts.toJson()['tiles'] as Map), isEmpty);
    });

    test('its saved form shares nothing, so a snapshot is not changed by a '
        'later edit', () {
      final ts = TilesetData()
        ..wangSets.add(
          WangSetData(
            wangIds: {
              3: [0, 1, 0, 1, 0, 1, 0, 1],
            },
          ),
        );
      final json = ts.toJson();
      ts.wangSets.single.wangIds[3]![1] = 2;
      final saved = ((json['wangSets'] as List).single as Map)['tiles'] as Map;
      expect(saved['3'], [0, 1, 0, 1, 0, 1, 0, 1]);
    });
  });
}

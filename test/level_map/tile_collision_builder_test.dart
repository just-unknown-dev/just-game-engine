// A layer's collision as bodies: whole-cell ground merged into long boxes,
// ramps joined with the ground beneath and beyond them into one convex
// polygon each, everything else convex polygons small enough for Box2D.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

TilesetData _tileset() =>
    TilesetData(
        name: 't',
        image: 't.png',
        tileWidth: 16,
        tileHeight: 16,
        columns: 4,
        tileCount: 8,
      )
      // 0: solid, 1: one-way, 2: a slope rising to the right, 3: none,
      // 4: an L-shaped ledge, 5: a kind nobody registered.
      ..tileOrNew(0).collision = TileCollision.full(16, 16)
      ..tileOrNew(1).collision = TileCollision.full(16, 16, kind: 'oneWay')
      ..tileOrNew(2).collision = TileCollision(
        shapes: [
          const TilePolygonShape([
            Offset(0, 16),
            Offset(16, 0),
            Offset(16, 16),
          ]),
        ],
      )
      ..tileOrNew(4).collision = TileCollision(
        shapes: [
          const TilePolygonShape([
            Offset(0, 0),
            Offset(16, 0),
            Offset(16, 8),
            Offset(8, 8),
            Offset(8, 16),
            Offset(0, 16),
          ]),
        ],
      )
      ..tileOrNew(5).collision = TileCollision.full(16, 16, kind: 'lava')
      // 6: a half-height ledge at the bottom; 7: the top-left and top-right
      // quarters, as terrain draws a ceiling.
      ..tileOrNew(6).collision = TileCollision(
        shapes: [const TileRectShape(Rect.fromLTWH(0, 8, 16, 8))],
      )
      ..tileOrNew(7).collision = TileCollision(
        shapes: [
          const TileRectShape(Rect.fromLTWH(0, 0, 8, 8)),
          const TileRectShape(Rect.fromLTWH(8, 0, 8, 8)),
        ],
      );

List<MapBodySpec> _build(
  void Function(TileChunkStore s) paint, {
  MapGeometry? geometry,
  Offset offset = Offset.zero,
}) {
  final cells = TileChunkStore();
  paint(cells);
  final ts = _tileset();
  return TileCollisionBuilder.build(
    cells: cells,
    geometry: geometry ?? MapGeometry(tileWidth: 16, tileHeight: 16),
    tilesetAt: (slot) => slot == 0 ? ts : null,
    offset: offset,
  );
}

void main() {
  test('solid ground merges into one box per block', () {
    final bodies = _build((s) {
      for (var y = 0; y < 3; y++) {
        for (var x = 0; x < 10; x++) {
          s.setCell(x, y, TileCell.make(0, 0));
        }
      }
    });
    expect(bodies, hasLength(1));
    expect(bodies.single.bounds, const Rect.fromLTWH(0, 0, 160, 48));
    expect(bodies.single.cells, hasLength(30));
  });

  test('an L of ground is two boxes, rows first', () {
    final bodies = _build((s) {
      for (var x = 0; x < 5; x++) {
        s.setCell(x, 0, TileCell.make(0, 0));
      }
      s.setCell(0, 1, TileCell.make(0, 0));
    });
    expect(bodies.map((b) => b.bounds).toSet(), {
      const Rect.fromLTWH(0, 0, 80, 16),
      const Rect.fromLTWH(0, 16, 16, 16),
    });
  });

  test('one-way tiles join along rows only, and stay apart from solid', () {
    final bodies = _build((s) {
      for (var x = 0; x < 4; x++) {
        s.setCell(x, 0, TileCell.make(0, 1));
        s.setCell(x, 1, TileCell.make(0, 1));
        s.setCell(x, 2, TileCell.make(0, 0));
      }
    });
    final oneWay = bodies.where((b) => b.kind == 'oneWay').toList();
    expect(oneWay, hasLength(2));
    expect(bodies.where((b) => b.kind == 'solid'), hasLength(1));
  });

  test('a tile of an unknown kind still collides, and keeps its kind', () {
    final bodies = _build((s) => s.setCell(0, 0, TileCell.make(0, 5)));
    expect(bodies.single.kind, 'lava');
  });

  test('a slope is a triangle where the tile is', () {
    final body = _build((s) => s.setCell(2, 1, TileCell.make(0, 2))).single;
    expect(body.isBox, isFalse);
    expect(body.bounds, const Rect.fromLTWH(32, 16, 16, 16));
    expect(body.polygon, hasLength(3));
  });

  test('a mirrored slope rises the other way', () {
    final body = _build(
      (s) => s.setCell(0, 0, TileCell.make(0, 2, TileCell.flipH)),
    ).single;
    final points = [for (final p in body.polygon!) p + body.center];
    // The high corner is now on the left.
    expect(points, contains(const Offset(0, 0)));
    expect(points, isNot(contains(const Offset(16, 0))));
  });

  test('a concave shape becomes convex pieces covering the same area', () {
    final bodies = _build((s) => s.setCell(0, 0, TileCell.make(0, 4)));
    expect(bodies.length, greaterThanOrEqualTo(2));
    var area = 0.0;
    for (final b in bodies) {
      expect(
        PolygonDecompose.isConvex(PolygonDecompose.clean(b.polygon!)),
        isTrue,
      );
      expect(b.polygon!.length, lessThanOrEqualTo(8));
      area +=
          PolygonDecompose.signedArea2(
            PolygonDecompose.clean(b.polygon!),
          ).abs() /
          2;
    }
    expect(area, closeTo(16 * 16 - 8 * 8, 0.01));
  });

  test('half-tile ledges along a row are one box, with no seams', () {
    final bodies = _build((s) {
      for (var x = 0; x < 6; x++) {
        s.setCell(x, 2, TileCell.make(0, 6));
      }
    });
    expect(bodies, hasLength(1));
    expect(bodies.single.isBox, isTrue);
    expect(bodies.single.bounds, const Rect.fromLTWH(0, 40, 96, 8));
    expect(bodies.single.cells, hasLength(6));
  });

  test('quarters of a tile join each other and their neighbours', () {
    final bodies = _build((s) {
      s
        ..setCell(0, 0, TileCell.make(0, 7))
        ..setCell(1, 0, TileCell.make(0, 7));
    });
    expect(bodies.single.bounds, const Rect.fromLTWH(0, 0, 32, 8));
  });

  test('a ledge turned on its side is still a box, and stacks', () {
    final bodies = _build((s) {
      for (var y = 0; y < 3; y++) {
        s.setCell(0, y, TileCell.make(0, 6, TileCell.flipD));
      }
    });
    // Mirrored across the diagonal, the bottom half becomes the right half.
    expect(bodies.single.isBox, isTrue);
    expect(bodies.single.bounds, const Rect.fromLTWH(8, 0, 8, 48));
  });

  test('a layer offset moves every body', () {
    final body = _build(
      (s) => s.setCell(0, 0, TileCell.make(0, 0)),
      offset: const Offset(100, -20),
    ).single;
    expect(body.bounds, const Rect.fromLTWH(100, -20, 16, 16));
  });

  test('an isometric tile collides where its image is drawn', () {
    final g = MapGeometry(
      orientation: LevelMapOrientation.isometric,
      tileWidth: 32,
      tileHeight: 16,
    );
    // Tile 0 is a whole 16×16 box, which on an isometric map is not a
    // whole cell — but still an upright box, where the image is.
    final body = _build(
      (s) => s.setCell(0, 0, TileCell.make(0, 0)),
      geometry: g,
    ).single;
    expect(body.isBox, isTrue);
    expect(body.bounds, g.tileImageRect(0, 0, 16, 16));
  });

  group('convex pieces', () {
    test('a convex polygon over eight points is fanned', () {
      final twelve = [
        for (var i = 0; i < 12; i++)
          Offset(
            100 * (1 + 0.5 * (i.isEven ? 1 : 0.999)) * _cos(i * 30),
            100 * _sin(i * 30),
          ),
      ];
      final pieces = PolygonDecompose.convexPieces(twelve);
      expect(pieces.length, greaterThan(1));
      expect(pieces.every((p) => p.length <= 8), isTrue);
    });

    test('points in a straight line are dropped', () {
      final square = PolygonDecompose.clean(const [
        Offset(0, 0),
        Offset(5, 0),
        Offset(10, 0),
        Offset(10, 10),
        Offset(0, 10),
      ]);
      expect(square, hasLength(4));
    });

    test('a shape with no area gives nothing', () {
      expect(
        PolygonDecompose.convexPieces(const [
          Offset(0, 0),
          Offset(1, 1),
          Offset(2, 2),
        ]),
        isEmpty,
      );
    });
  });

  group('ramps', () {
    test('a ramp, the ground beneath it and the level ground at its top '
        'are one convex polygon', () {
      final bodies = _ramps([
        '.........',
        '...../###',
        '..../####',
        '.../#####',
        '#########',
        '#########',
      ]);
      expect(bodies, hasLength(2));
      final ramp = bodies.singleWhere((b) => !b.isBox);
      expect(_points(ramp), {
        const Offset(96, 128),
        const Offset(192, 32),
        const Offset(288, 32),
        const Offset(288, 128),
      });
      expect(
        ramp.cells.first,
        const TileCoord(3, 3),
        reason: 'its first slope',
      );
      expect(ramp.cells, hasLength(15));
      expect(ramp.cells.toSet(), hasLength(15));
      final floor = bodies.singleWhere((b) => b.isBox);
      expect(floor.bounds, const Rect.fromLTWH(0, 128, 288, 64));
      expect(floor.cells, hasLength(18));
      expect(_area(bodies), closeTo(32 * 32 * (15 + 18 - 1.5), 1e-6));
    });

    test(
      'a run ends at each foot: down to the floor, and up the next rise',
      () {
        final bodies = _ramps([
          r'##\......./#',
          r'###\...../##',
          '############',
        ]);
        final ramps = bodies.where((b) => !b.isBox).toList();
        expect(ramps.map(_points).toSet(), {
          {
            const Offset(0, 64),
            const Offset(0, 0),
            const Offset(64, 0),
            const Offset(128, 64),
          },
          {
            const Offset(288, 64),
            const Offset(352, 0),
            const Offset(384, 0),
            const Offset(384, 64),
          },
        });
        expect(bodies.where((b) => b.isBox).map((b) => b.bounds), [
          const Rect.fromLTWH(0, 64, 384, 32),
        ]);
        expect(
          _area(bodies),
          closeTo(32 * 32 * (2 + 3 + 0.5 + 0.5 + 12 + 4), 1e-6),
        );
      },
    );

    test('a ramp onto level ground a thousand tiles long is one polygon', () {
      final long = '#' * 1000;
      final bodies = _ramps(['./$long', '##$long']);
      expect(_points(bodies.singleWhere((b) => !b.isBox)), {
        const Offset(32, 32),
        const Offset(64, 0),
        const Offset(32064, 0),
        const Offset(32064, 32),
      });
      expect(bodies.where((b) => b.isBox), hasLength(1));
    });

    test('22.5° slopes in pairs are one straight line', () {
      final bodies = _ramps(['ab#', '###']);
      final ramp = bodies.singleWhere((b) => !b.isBox);
      expect(_points(ramp), {
        const Offset(0, 32),
        const Offset(64, 0),
        const Offset(96, 0),
        const Offset(96, 32),
      });
    });

    test(
      'a run stops at a wall, and where the ground beneath it gives out',
      () {
        final wall = _ramps(['..#', './#', '###']);
        expect(_points(wall.singleWhere((b) => !b.isBox)), {
          const Offset(32, 64),
          const Offset(64, 32),
          const Offset(64, 64),
        });
        expect(wall.where((b) => b.isBox).map((b) => b.bounds).toSet(), {
          const Rect.fromLTWH(64, 0, 32, 64),
          const Rect.fromLTWH(0, 64, 96, 32),
        });

        final ledge = _ramps(['../###', './##..', '######']);
        expect(_points(ledge.singleWhere((b) => !b.isBox)), {
          const Offset(32, 64),
          const Offset(96, 0),
          const Offset(128, 0),
          const Offset(128, 64),
        });
        expect(
          ledge.where((b) => b.isBox).map((b) => b.bounds),
          containsAll([const Rect.fromLTWH(128, 0, 64, 32)]),
        );
      },
    );

    test('ceiling slopes, and slopes of a kind merged by rows, stay apart', () {
      final ceiling = _ramps(['#v', '##']);
      expect(ceiling.where((b) => !b.isBox).single.polygon, hasLength(3));

      final oneWay = TilesetData(
        name: 'w',
        tileWidth: 16,
        tileHeight: 16,
        columns: 2,
        tileCount: 2,
      );
      oneWay.tileOrNew(0).collision = TileCollision.full(
        16,
        16,
        kind: 'oneWay',
      );
      oneWay.tileOrNew(1).collision = TileCollision(
        kind: 'oneWay',
        shapes: [
          const TilePolygonShape([
            Offset(0, 16),
            Offset(16, 0),
            Offset(16, 16),
          ]),
        ],
      );
      final cells = TileChunkStore()
        ..setCell(0, 1, TileCell.make(0, 1))
        ..setCell(1, 0, TileCell.make(0, 1))
        ..setCell(1, 1, TileCell.make(0, 0))
        ..setCell(2, 0, TileCell.make(0, 0))
        ..setCell(2, 1, TileCell.make(0, 0));
      final bodies = TileCollisionBuilder.build(
        cells: cells,
        geometry: MapGeometry(tileWidth: 16, tileHeight: 16),
        tilesetAt: (_) => oneWay,
      );
      final slopes = bodies.where((b) => !b.isBox).toList();
      expect(slopes, hasLength(2));
      for (final s in slopes) {
        expect(s.polygon, hasLength(3));
        expect(s.cells, hasLength(1));
      }
    });

    for (final (backend, make) in [
      ('native Box2D', PhysicsEngineFactory.create2D),
      ('pure Dart', Physics2DEngine.pureDart),
    ]) {
      group('on $backend, a sharp 32 × 48 box', () {
        test('runs down off the level ground over the crest, and on along '
            'the floor, without catching', () {
          final run = _slide(
            make,
            [
              r'######\.........',
              r'#######\........',
              r'########\.......',
              r'#########\......',
              '################',
            ],
            from: 3,
            toward: 14,
          );
          expect(run.past, isTrue, reason: '$run');
          expect(run.stalled, 0, reason: '$run');
        });

        test('and the same the other way', () {
          final run = _slide(
            make,
            [
              '........./######',
              '......../#######',
              '......./########',
              '....../#########',
              '################',
            ],
            from: 12,
            toward: 1,
          );
          expect(run.past, isTrue, reason: '$run');
          expect(run.stalled, 0, reason: '$run');
        });
      });
    }
  });

  test('merging cells: rows, then stacks of the same span', () {
    final cells = {
      for (var x = 0; x < 3; x++) ...[TileCoord(x, 0), TileCoord(x, 1)],
      const TileCoord(0, 2),
    };
    final area = TileCollisionBuilder.mergeCells(cells, TileMergeMode.area);
    expect(area, hasLength(2));
    final rows = TileCollisionBuilder.mergeCells(cells, TileMergeMode.rows);
    expect(rows, hasLength(3));
    expect(
      TileCollisionBuilder.mergeCells(cells, TileMergeMode.none),
      hasLength(7),
    );
  });
}

/// The basic shapes' tiles a ramp map is drawn with: a block, the 45° floor
/// slopes rising and falling to the right, a 45° ceiling slope, and the two
/// halves of a 22.5° rise.
const _rampTiles = {'#': 0, '/': 8, r'\': 9, 'v': 10, 'a': 12, 'b': 13};

TileChunkStore _rampCells(List<String> rows) {
  final cells = TileChunkStore();
  for (var y = 0; y < rows.length; y++) {
    for (var x = 0; x < rows[y].length; x++) {
      final id = _rampTiles[rows[y][x]];
      if (id != null) cells.setCell(x, y, TileCell.make(0, id));
    }
  }
  return cells;
}

/// [rows] drawn with the basic shapes (32 px tiles) as bodies.
List<MapBodySpec> _ramps(List<String> rows) {
  final ts = BuiltInTilesets.build(BuiltInTilesets.basicShapes)!;
  return TileCollisionBuilder.build(
    cells: _rampCells(rows),
    geometry: MapGeometry(tileWidth: 32, tileHeight: 32),
    tilesetAt: (slot) => slot == 0 ? ts : null,
  );
}

/// [body]'s polygon's points, map-local.
Set<Offset> _points(MapBodySpec body) => {
  for (final p in body.polygon!) p + body.center,
};

/// How much of the map [bodies] cover.
double _area(List<MapBodySpec> bodies) {
  var area = 0.0;
  for (final b in bodies) {
    area += b.isBox
        ? b.size!.width * b.size!.height
        : PolygonDecompose.signedArea2(
                PolygonDecompose.clean(b.polygon!),
              ).abs() /
              2;
  }
  return area;
}

/// A sharp 32 × 48 box on [rows] (the basic shapes, 32 px tiles) driven
/// from the top of column [from] toward column [toward] as a platformer
/// drives its player — 300 px/s along, held down at 300 px/s — under the
/// platformer template's gravity. Whether it gets past [toward]'s middle
/// within two seconds, and how many steps it moved less than half a pixel.
({bool past, int stalled}) _slide(
  Physics2DEngine Function() make,
  List<String> rows, {
  required int from,
  required int toward,
}) {
  final physics = make()
    ..initialize()
    ..setGravity(0, 2200);
  final world = World()..initialize();
  addTearDown(() {
    world.dispose();
    physics.dispose();
  });
  world.context.tiles.putTileset(
    'ramps.tileset.json',
    BuiltInTilesets.build(BuiltInTilesets.basicShapes)!,
  );
  world.addSystem(Physics2DSystem(physics));
  registerLevelMapSystems(world);
  final data = LevelMapData(tileWidth: 32, tileHeight: 32)
    ..addTileset('ramps.tileset.json');
  final layer = data.addLayer(name: 'Ground')..collides = true;
  for (final (x, y, cell) in _rampCells(rows).cells) {
    layer.cells.setCell(x, y, cell);
  }
  world.createEntityWithComponents([
    TransformComponent(),
    LevelMapComponent(inline: data),
  ]);
  var top = 0;
  while (rows[top][from] == '.') {
    top++;
  }
  final box = world.createEntityWithComponents([
    TransformComponent(position: Vector3(from * 32 + 16, top * 32 - 24.5, 0)),
    VelocityComponent(),
    RigidBody2DComponent(
      mass: 1,
      friction: 0.2,
      restitution: 0,
      lockRotation: true,
    ),
    Collider2DComponent(size: Vector2(32, 48)),
  ]);
  final velocity = box.getComponent<VelocityComponent>()!.velocity;
  final at = box.getComponent<TransformComponent>()!.position;
  for (var i = 0; i < 30; i++) {
    world.update(1 / 60);
  }
  final dir = toward > from ? 1.0 : -1.0;
  final goal = toward * 32 + 16.0;
  var stalled = 0;
  for (var i = 0; i < 120; i++) {
    if (dir > 0 ? at.x >= goal : at.x <= goal) {
      return (past: true, stalled: stalled);
    }
    final x = at.x;
    velocity.setValues(300 * dir, 300, 0);
    world.update(1 / 60);
    if ((at.x - x).abs() < 0.5) stalled++;
  }
  return (past: false, stalled: stalled);
}

double _cos(double degrees) => _trig(degrees, true);
double _sin(double degrees) => _trig(degrees, false);
double _trig(double degrees, bool cos) {
  final r = degrees * 3.141592653589793 / 180;
  // A few terms of the series is plenty for building a test polygon.
  double c = 1, s = r, term = 1;
  for (var n = 1; n < 12; n++) {
    term *= -r * r / ((2 * n - 1) * (2 * n));
    c += term;
  }
  term = r;
  for (var n = 1; n < 12; n++) {
    term *= -r * r / ((2 * n) * (2 * n + 1));
    s += term;
  }
  return cos ? c : s;
}

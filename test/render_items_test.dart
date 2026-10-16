// One sorted draw list: renderables, render items and sprite batches drawn in
// the order their layers say.
//
// A tile map draws a background layer behind the player and a foreground
// layer in front of it — two depths for one entity — through RenderItems.
// And batched sprites used to be drawn after *everything*, whatever their
// layer, so a background sprite covered the ground in front of it.

import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

class _Logged extends Renderable {
  _Logged(this.name, this.log);
  final String name;
  final List<String> log;

  @override
  void render(Canvas canvas, Size size) => log.add(name);

  @override
  Rect? getBounds() => null;
}

class _Batched extends _Logged implements BatchableSprite {
  _Batched(super.name, super.log, this.image);
  final ui.Image image;

  @override
  ui.Image? get batchImage => image;

  @override
  Rect? get batchSourceRect => null;
}

class _Item extends RenderItem {
  _Item(this.name, this.log, this.layer, {this.zOrder = 0});
  final String name;
  final List<String> log;
  @override
  final int layer;
  @override
  final int zOrder;
  bool shown = true;

  @override
  bool get visible => shown;

  @override
  void render(Canvas canvas, RenderContext context, Entity owner) =>
      log.add(name);
}

/// Records what it was given, and draws it — as one log line — on flush.
class _FakeBatch implements SpriteBatchRenderer {
  _FakeBatch(this.log);
  final List<String> log;
  int _queued = 0;

  @override
  void add({
    required Rect sourceRect,
    required Offset position,
    double rotation = 0.0,
    double scale = 1.0,
    double? anchorX,
    double? anchorY,
    Color color = const Color(0xFFFFFFFF),
  }) => _queued++;

  @override
  void flush(Canvas canvas) {
    if (_queued == 0) return;
    log.add('batch×$_queued');
    _queued = 0;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late World world;
  late List<String> log;

  setUp(() {
    log = [];
    world = World()..initialize();
    world.addSystem(RenderSystem(spriteBatchFactory: (_) => _FakeBatch(log)));
  });
  tearDown(() => world.dispose());

  void render() =>
      world.render(Canvas(ui.PictureRecorder()), const Size(800, 600));

  Entity drawn(Renderable renderable, {int layer = 0, int zOrder = 0}) =>
      world.createEntityWithComponents([
        TransformComponent(),
        RenderableComponent(renderable: renderable),
        LayerComponent(layer: layer, zOrder: zOrder),
      ]);

  test("an entity's items interleave with other entities by layer", () {
    drawn(_Logged('player', log));
    world.createEntityWithComponents([
      TransformComponent(),
      RenderItemsComponent([
        _Item('front', log, 100),
        _Item('back', log, -200),
      ]),
    ]);

    render();

    expect(log, ['back', 'player', 'front']);
  });

  test('zOrder orders within a layer, and ties keep a steady order', () {
    world.createEntityWithComponents([
      TransformComponent(),
      RenderItemsComponent([
        _Item('b', log, 0, zOrder: 2),
        _Item('a', log, 0, zOrder: 1),
        _Item('c1', log, 0, zOrder: 3),
        _Item('c2', log, 0, zOrder: 3),
      ]),
    ]);

    for (var frame = 0; frame < 3; frame++) {
      log.clear();
      render();
      expect(log, ['a', 'b', 'c1', 'c2']);
    }
  });

  test('an invisible item is skipped', () {
    final hidden = _Item('hidden', log, 0)..shown = false;
    world.createEntityWithComponents([
      TransformComponent(),
      RenderItemsComponent([hidden, _Item('shown', log, 0)]),
    ]);

    render();

    expect(log, ['shown']);
  });

  group('batched sprites keep their place in the order', () {
    late ui.Image image;
    setUpAll(() async => image = await createTestImage(width: 4, height: 4));

    test('a batch behind a plain renderable is drawn first', () {
      drawn(_Logged('ground', log));
      drawn(_Batched('far tree', log, image), layer: -200);

      render();

      expect(log, ['batch×1', 'ground']);
    });

    test('a batch is drawn before a render item in front of it', () {
      drawn(_Batched('far tree', log, image), layer: -200);
      world.createEntityWithComponents([
        TransformComponent(),
        RenderItemsComponent([_Item('tiles', log, -100)]),
      ]);
      drawn(_Batched('near bush', log, image), layer: 0);

      render();

      expect(log, ['batch×1', 'tiles', 'batch×1']);
    });

    test('sprites on one layer still share one batch', () {
      drawn(_Batched('a', log, image));
      drawn(_Batched('b', log, image));
      drawn(_Batched('c', log, image));

      render();

      expect(log, ['batch×3']);
    });

    test('a change of layer between two batched sprites splits the batch', () {
      drawn(_Batched('back', log, image), layer: -100);
      drawn(_Batched('front', log, image), layer: 100);

      render();

      expect(log, ['batch×1', 'batch×1']);
    });
  });
}

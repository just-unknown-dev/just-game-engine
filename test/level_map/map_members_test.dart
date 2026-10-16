// Entities on a map layer: children of a level map that draw with one of its
// layers — above its tiles, below the next layer's, hidden while it is — and
// follow it when it moves in depth.

import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

class _Logged extends Renderable {
  _Logged(this.name);
  final String name;

  @override
  void render(Canvas canvas, Size size) {}

  @override
  Rect? getBounds() => null;
}

/// Records which entities a pass is allowed to draw.
class _FilterLog extends RenderPass {
  _FilterLog(this.seen);
  final List<Entity> seen;

  @override
  void render(Canvas canvas, RenderContext context, RenderPassFilter filter) {
    for (final e in context.world.query([LayerComponent])) {
      if (filter(e)) seen.add(e);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late World world;
  late RenderSystem render;
  late List<Entity> passed;
  late Entity map;
  late LevelMapData data;
  late MapLayerData back, front;

  setUp(() {
    passed = [];
    world = World()..initialize();
    render = RenderSystem(passes: [_FilterLog(passed)]);
    world
      ..addSystem(LevelMapSystem())
      ..addSystem(render);
    data = LevelMapData();
    back = data.addLayer(name: 'Back');
    front = data.addLayer(name: 'Front');
    map = world.createEntityWithComponents([
      TransformComponent(),
      LevelMapComponent(inline: data),
      ChildrenComponent(),
    ], name: LevelMaps.primaryName);
  });
  tearDown(() => world.dispose());

  Entity member(String name, MapLayerData layer, {Entity? parent}) {
    final owner = parent ?? map;
    final e = world.createEntityWithComponents([
      TransformComponent(),
      RenderableComponent(renderable: _Logged(name)),
      LayerComponent(mapLayer: layer.id),
      ParentComponent(parentId: owner.id),
    ], name: name);
    owner.getComponent<ChildrenComponent>()!.addChild(e.id);
    return e;
  }

  /// What draws, in order: an entity's name, or `map:<layer name>`.
  List<String> order() {
    world.update(0);
    return [
      for (final (e, item) in render.debugDrawOrder())
        if (item is MapLayerRenderItem)
          '${e == map ? 'map' : e.name}:${item.data!.name}'
        else
          e.name!,
    ];
  }

  test('a member draws above its layer\'s tiles and below the next layer, '
      'in child order; others are as before', () {
    member('a', back);
    member('b', front);
    member('c', back);
    world.createEntityWithComponents([
      TransformComponent(),
      RenderableComponent(renderable: _Logged('plain')),
      LayerComponent(),
    ], name: 'plain');

    expect(order(), [
      'plain',
      'map:Back',
      'a',
      'c',
      'map:Front',
      'b',
    ], reason: 'an equal key still draws an entity under the map');
  });

  test('a member follows its layer\'s depth and order', () {
    final a = member('a', back);
    member('b', front);
    back
      ..sortLayer = 100
      ..sortLayerId = 'foreground'
      ..zOrder = 3;

    expect(order(), ['map:Front', 'b', 'map:Back', 'a']);
    final layer = a.getComponent<LayerComponent>()!;
    expect((layer.layer, layer.zOrder, layer.layerId), (100, 3, 'foreground'));
  });

  test('a hidden layer hides what is on it, in every pass', () {
    final a = member('a', back);
    final b = member('b', front);
    back.visible = false;

    expect(order(), isNot(contains('a')));
    passed.clear();
    world.render(Canvas(ui.PictureRecorder()), const Size(800, 600));
    expect(passed, [b], reason: 'the text pass is filtered too');

    // Leaving the layer, it is drawn as any entity is.
    a.getComponent<LayerComponent>()!.mapLayer = null;
    world.update(0);
    expect(a.getComponent<LayerComponent>()!.hiddenByMap, isFalse);
    expect(a.getComponent<LayerComponent>()!.subOrder, 0);
    expect(order(), contains('a'));
  });

  test('a member whose layer is gone, or of no map, is left as it is', () {
    final a = member('a', back);
    data.layers.remove(back);
    world.update(0);
    expect(a.getComponent<LayerComponent>()!.subOrder, 0);

    final loose = world.createEntityWithComponents([
      TransformComponent(),
      LayerComponent(mapLayer: front.id),
    ], name: 'loose');
    world.update(0);
    expect(loose.getComponent<LayerComponent>()!.subOrder, 0);
  });

  test('a piece of the map draws where its layer does', () {
    final pieceData = LevelMapData();
    pieceData.addLayer(name: 'Cut').sortLayer = 50;
    final piece = world.createEntityWithComponents([
      TransformComponent(),
      LevelMapComponent(inline: pieceData),
      LayerComponent(mapLayer: back.id),
      ParentComponent(parentId: map.id),
    ], name: 'Tiles');
    map.getComponent<ChildrenComponent>()!.addChild(piece.id);
    member('b', front);

    expect(order(), ['map:Back', 'Tiles:Cut', 'map:Front', 'b']);
    expect(LevelMaps.isPiece(world, piece), isTrue);
    expect(LevelMaps.isPiece(world, map), isFalse);
    expect(LevelMaps.memberLayer(world, piece), same(back));
    expect(LevelMaps.ownerOf(world, piece), same(map));
  });

  test('the level\'s map is never one of its pieces', () {
    world.destroyEntity(map);
    final other = LevelMapData()..addLayer(name: 'Ground');
    final piece = world.createEntityWithComponents([
      TransformComponent(),
      LevelMapComponent(inline: LevelMapData()),
      LayerComponent(mapLayer: 1),
      ParentComponent(),
    ], name: 'Tiles');
    final named = world.createEntityWithComponents([
      TransformComponent(),
      LevelMapComponent(inline: other),
      ChildrenComponent(),
    ], name: 'Ground map');
    piece.getComponent<ParentComponent>()!.parentId = named.id;
    named.getComponent<ChildrenComponent>()!.addChild(piece.id);

    expect(LevelMaps.primaryEntity(world), same(named));
  });

  test('the layer it is on is saved; an older scene has none', () {
    final schema = CoreComponentSchemas.layer;
    final json = schema.encode(LayerComponent(mapLayer: 7));
    expect(schema.decode(json).mapLayer, 7);
    final old = Map<String, dynamic>.of(json)
      ..['fields'] = (Map<String, dynamic>.of(
        (json['fields'] as Map).cast<String, dynamic>(),
      )..remove('mapLayer'));
    expect(schema.decode(old).mapLayer, isNull);
  });
}

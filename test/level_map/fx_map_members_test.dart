// What is on a map layer follows changes nothing announces — a child moved
// to another layer, children reordered, layers reordered in place — every
// update, as it did before the pass stopped allocating.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

class _Logged extends Renderable {
  @override
  void render(Canvas canvas, Size size) {}

  @override
  Rect? getBounds() => null;
}

class _Other extends RenderItem {
  @override
  int get layer => 0;

  @override
  void render(Canvas canvas, RenderContext context, Entity owner) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late World world;
  late RenderSystem render;
  late Entity map;
  late LevelMapData data;
  late MapLayerData back, front;

  setUp(() {
    world = World()..initialize();
    render = RenderSystem();
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

  Entity member(String name, MapLayerData layer) {
    final e = world.createEntityWithComponents([
      TransformComponent(),
      RenderableComponent(renderable: _Logged()),
      LayerComponent(mapLayer: layer.id),
      ParentComponent(parentId: map.id),
    ], name: name);
    map.getComponent<ChildrenComponent>()!.addChild(e.id);
    return e;
  }

  List<String> order() {
    world.update(0);
    return [
      for (final (e, item) in render.debugDrawOrder())
        if (item is MapLayerRenderItem)
          'map:${item.data!.name}'
        else if (item == null)
          e.name!,
    ];
  }

  test('a child moved to another layer in place follows it', () {
    final a = member('a', back);
    member('b', front);
    expect(order(), ['map:Back', 'a', 'map:Front', 'b']);
    a.getComponent<LayerComponent>()!.mapLayer = front.id;
    expect(order(), ['map:Back', 'map:Front', 'a', 'b']);
  });

  test('children reordered in place draw in their new order', () {
    final a = member('a', back);
    final b = member('b', back);
    expect(order(), ['map:Back', 'a', 'b', 'map:Front']);
    map.getComponent<ChildrenComponent>()!.childIds
      ..clear()
      ..addAll([b.id, a.id]);
    expect(order(), ['map:Back', 'b', 'a', 'map:Front']);
  });

  test('layers reordered in place, without a touch, keep their things with '
      'them', () {
    member('a', back);
    member('b', front);
    expect(order(), ['map:Back', 'a', 'map:Front', 'b']);
    data.layers
      ..clear()
      ..addAll([front, back]);
    expect(order(), ['map:Front', 'b', 'map:Back', 'a']);
  });

  test("a map keeps an entity's other render items beside its layers'", () {
    final e = world.createEntityWithComponents([
      TransformComponent(),
      LevelMapComponent(inline: LevelMapData()..addLayer()),
      RenderItemsComponent([_Other()]),
    ]);
    world.update(0);
    final items = e.getComponent<RenderItemsComponent>()!.items;
    expect(items.whereType<_Other>(), hasLength(1));
    expect(items.whereType<MapLayerRenderItem>(), hasLength(1));
    world.update(0);
    expect(e.getComponent<RenderItemsComponent>()!.items, hasLength(2));
  });

  test('several maps appearing in one update all get their layers', () {
    final maps = [
      for (var i = 0; i < 3; i++)
        world.createEntityWithComponents([
          TransformComponent(),
          LevelMapComponent(
            inline: LevelMapData()
              ..addLayer()
              ..addLayer(),
          ),
        ]),
    ];
    world.update(0);
    for (final e in maps) {
      expect(e.getComponent<RenderItemsComponent>()!.items, hasLength(2));
    }
  });
}

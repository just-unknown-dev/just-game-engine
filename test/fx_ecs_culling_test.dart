// View culling: the game keeps the say over `visible`, bounds follow the
// transform's scale and turn, and the spatial grid reuses what it can.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// Bounds centred on its own position, scaled — as a Sprite's are.
class _WorldBox extends Renderable {
  _WorldBox(this.w, this.h, {super.position, super.scale});
  final double w, h;

  @override
  bool get boundsAreWorldSpace => true;

  @override
  Rect? getBounds() => Rect.fromCenter(
    center: position.toOffset(),
    width: w * scale.x,
    height: h * scale.y,
  );

  @override
  void render(Canvas canvas, Size size) {}
}

void main() {
  late World world;
  late Camera camera;

  setUp(() {
    world = World();
    camera = Camera(position: Offset.zero, zoom: 1.0)
      ..viewportSize = const Size(800, 600);
    // Render rect x in (-480, 480); active rect x in (-800, 800).
    world.addSystem(ViewCullingSystem(camera: camera));
  });

  Entity spawn(
    double x,
    double y, {
    Renderable? renderable,
    Vector3? scale,
    double angle = 0,
  }) => world.createEntityWithComponents([
    TransformComponent(position: Vector3.fromXY(x, y), scale: scale)
      ..angle = angle,
    CullStateComponent(),
    RenderableComponent(
      // A built-in renderable's bounds are in world space, at its own
      // position — where RenderSystem puts it, synced to the transform.
      renderable:
          renderable ??
          CircleRenderable(
            radius: 5,
            fillColor: Colors.red,
            position: Vector3.fromXY(x, y),
          ),
    ),
  ]);

  bool visible(Entity e) =>
      e.getComponent<RenderableComponent>()!.renderable.visible;
  CullStateComponent cull(Entity e) => e.getComponent<CullStateComponent>()!;
  // Moves the entity, and its renderable as RenderSystem's sync would.
  void moveTo(Entity e, double x) {
    e.getComponent<TransformComponent>()!.position.x = x;
    e.getComponent<RenderableComponent>()!.renderable.position.x = x;
  }

  group('the game keeps the say over visible (C22)', () {
    test('an entity hidden on screen stays hidden', () {
      final e = spawn(0, 0);
      e.getComponent<RenderableComponent>()!.renderable.visible = false;
      world.update(0.016);
      expect(cull(e).isVisible, isTrue);
      expect(visible(e), isFalse);
    });

    test('what the culler hid it shows again, and nothing else', () {
      final shown = spawn(0, 0);
      final hidden = spawn(0, 0);
      hidden.getComponent<RenderableComponent>()!.renderable.visible = false;
      world.update(0.016);

      moveTo(shown, 2000);
      moveTo(hidden, 2000);
      world.update(0.016);
      expect(visible(shown), isFalse);
      expect(cull(shown).hidesRenderable, isTrue);
      expect(cull(hidden).hidesRenderable, isFalse);

      moveTo(shown, 0);
      moveTo(hidden, 0);
      world.update(0.016);
      expect(visible(shown), isTrue);
      expect(visible(hidden), isFalse);
    });

    test('a hide written on screen is not overwritten next frame', () {
      final e = spawn(0, 0);
      world.update(0.016);
      e.getComponent<RenderableComponent>()!.renderable.visible = false;
      world.update(0.016);
      world.update(0.016);
      expect(visible(e), isFalse);
    });
  });

  group('bounds follow the transform (C22)', () {
    // A bar 10 wide at x = 700: its right edge must pass 480 to be seen.

    test('scale', () {
      final e = spawn(
        700,
        0,
        renderable: _box(10, 10),
        scale: Vector3(60, 1, 1),
      );
      world.update(0.016);
      expect(cull(e).isVisible, isTrue); // 600 wide: 400..1000
    });

    test('a negative scale', () {
      final e = spawn(
        700,
        0,
        renderable: _box(10, 10),
        scale: Vector3(-60, 1, 1),
      );
      world.update(0.016);
      expect(cull(e).isVisible, isTrue);
    });

    test('a turn', () {
      // 10 wide and 600 tall, turned a quarter: 600 wide and 10 tall.
      final e = spawn(700, 0, renderable: _box(10, 600), angle: math.pi / 2);
      world.update(0.016);
      expect(cull(e).isVisible, isTrue);

      final upright = spawn(700, 0, renderable: _box(10, 600));
      world.update(0.016);
      expect(cull(upright).isVisible, isFalse);
    });

    test('world-space bounds flipped by a negative scale', () {
      final e = spawn(
        700,
        0,
        renderable: _WorldBox(
          10,
          10,
          position: Vector3(700, 0, 0),
          scale: Vector3(-60, 1, 1),
        ),
      );
      world.update(0.016);
      expect(cull(e).isVisible, isTrue);
    });

    test('world-space bounds turned', () {
      final box = _WorldBox(10, 600, position: Vector3(700, 0, 0))
        ..rotation = math.pi / 2;
      final e = spawn(700, 0, renderable: box);
      world.update(0.016);
      expect(cull(e).isVisible, isTrue);
    });

    test('a switched-off entity is left alone', () {
      final e = spawn(5000, 0)..isActive = false;
      world.update(0.016);
      expect(visible(e), isTrue);
      expect(cull(e).isActive, isTrue);
    });
  });

  group('the spatial grid (P12)', () {
    Rect at(double x, double y) =>
        Rect.fromCenter(center: Offset(x, y), width: 1, height: 1);

    test('fills a list the caller keeps, once per entity', () {
      final grid = EntitySpatialGrid(cellSize: 100);
      final a = world.createEntity();
      final wide = world.createEntity();
      grid.sync([a, wide], (e) {
        return identical(e, a)
            ? at(50, 50)
            : const Rect.fromLTWH(0, 0, 350, 10);
      });
      final out = <Entity>[];
      expect(grid.query(const Rect.fromLTWH(0, 0, 400, 400), out), same(out));
      expect(out, unorderedEquals([a, wide]));
      grid.query(const Rect.fromLTWH(0, 0, 400, 400), out);
      expect(out, hasLength(4)); // added to, not cleared
    });

    test('forgets an entity dropped from the set, keeps one that stays', () {
      final grid = EntitySpatialGrid(cellSize: 100);
      final a = world.createEntity();
      final b = world.createEntity();
      grid.sync([a, b], (e) => at(10, 10));
      grid.sync([b], (e) => at(10, 10));
      expect(grid.trackedEntityCount, 1);
      expect(grid.query(const Rect.fromLTWH(0, 0, 100, 100)), [b]);
      grid.sync([a, b], (e) => identical(e, a) ? at(510, 10) : at(10, 10));
      expect(grid.query(const Rect.fromLTWH(500, 0, 100, 100)), [a]);
    });
  });
}

/// Local bounds centred on the origin, as the shape components' are.
Renderable _box(double w, double h) => CustomRenderable(
  onRender: (canvas, size) {},
  getBoundsCallback: () =>
      Rect.fromCenter(center: Offset.zero, width: w, height: h),
);

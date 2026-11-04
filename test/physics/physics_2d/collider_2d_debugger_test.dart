// Collider2DDebuggerSystem, the one collider drawer (the game's debug view and
// the editor's): one outline per collider, coloured by its body; the
// characters too; a collider's own showDebugOutline and the outline filter
// are heeded; switched-off entities are not drawn; and outlines are listed
// into paths once, not every frame.

import 'dart:ui';

import 'package:flutter/material.dart' show Colors;
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// Counts what is drawn, and keeps the paths and paints.
class _Counter extends TestRecordingCanvas {
  int rects = 0, circles = 0, lines = 0;
  final List<Path> paths = [];
  final List<Color> colors = [];

  @override
  void drawRect(Rect rect, Paint paint) {
    rects++;
    colors.add(paint.color);
    super.drawRect(rect, paint);
  }

  @override
  void drawCircle(Offset c, double radius, Paint paint) {
    circles++;
    colors.add(paint.color);
    super.drawCircle(c, radius, paint);
  }

  @override
  void drawPath(Path path, Paint paint) {
    paths.add(path);
    colors.add(paint.color);
    super.drawPath(path, paint);
  }

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) {
    lines++;
    colors.add(paint.color);
    super.drawLine(p1, p2, paint);
  }

  int get outlines => rects + circles + lines + paths.length;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Physics2DEngine physics;
  late World world;
  late Collider2DDebuggerSystem debugger;

  setUp(() {
    physics = Physics2DEngine.pureDart()..initialize();
    world = World()..initialize();
    debugger = Collider2DDebuggerSystem();
    world
      ..addSystem(Physics2DSystem(physics))
      ..addSystem(debugger);
  });
  tearDown(() {
    world.dispose();
    physics.dispose();
  });

  _Counter draw() {
    final canvas = _Counter();
    debugger.render(canvas, const Size(100, 100));
    return canvas;
  }

  test('one outline per collider and character', () {
    world.createEntityWithComponents([
      TransformComponent(),
      Collider2DComponent(size: Vector2(10, 10)),
    ]);
    world.createEntityWithComponents([
      TransformComponent(),
      Collider2DComponent(shape: Collider2DShape.circle, radius: 4),
    ]);
    world.createEntityWithComponents([
      TransformComponent(),
      Collider2DComponent(shape: Collider2DShape.capsule),
    ]);
    world.createEntityWithComponents([
      TransformComponent(),
      Collider2DComponent(
        shape: Collider2DShape.chain,
        points: const [Offset(0, 0), Offset(10, 0), Offset(20, 5)],
      ),
    ]);
    world.createEntityWithComponents([
      TransformComponent(),
      CharacterBody2DComponent(),
    ]);

    // Drawn from their components before any step has made a body.
    final before = draw();
    expect(before.rects, 1, reason: 'the box');
    expect(before.circles, 1);
    expect(before.paths, hasLength(3), reason: 'capsule, chain, character');

    world.update(1 / 60);
    final after = draw();
    expect(after.outlines, before.outlines, reason: 'drawn from their bodies');
  });

  test('a body is coloured by its kind; a character too', () {
    world.createEntityWithComponents([
      TransformComponent(),
      RigidBody2DComponent(bodyType: Body2DType.kinematic),
      Collider2DComponent(size: Vector2(10, 10)),
    ]);
    world.update(1 / 60);
    expect(draw().colors.single.toARGB32(), Colors.orange.toARGB32());

    // A character in the air: its own colour, faded.
    world.createEntityWithComponents([
      TransformComponent(position: Vector3(100, 0, 0)),
      CharacterBody2DComponent(),
    ]);
    final colors = draw().colors;
    expect(colors, hasLength(2));
    expect(
      colors.last.toARGB32(),
      Colors.lightBlueAccent.withValues(alpha: 0.5).toARGB32(),
    );
  });

  test('its own switch, the filter and switched-off entities', () {
    final hidden = world.createEntityWithComponents([
      TransformComponent(),
      Collider2DComponent(size: Vector2(10, 10), showDebugOutline: false),
    ]);
    final filtered = world.createEntityWithComponents([
      TransformComponent(),
      Collider2DComponent(size: Vector2(10, 10)),
    ]);
    final off = world.createEntityWithComponents([
      TransformComponent(),
      CharacterBody2DComponent(),
    ]);
    world.createEntityWithComponents([
      TransformComponent(),
      Collider2DComponent(size: Vector2(10, 10)),
    ]);
    off.isActive = false;
    debugger.outlineFilter = (e) => !identical(e, filtered);
    world.update(1 / 60);
    expect(draw().outlines, 1);
    expect(hidden.isActive, isTrue);
    debugger.outlineFilter = null;
    expect(draw().outlines, 2);
  });

  test('static or moving bodies can be left out', () {
    final world = World()..initialize();
    addTearDown(world.dispose);
    final debugger = Collider2DDebuggerSystem(includeDynamicBodies: false);
    world.addSystem(debugger);
    world.createEntityWithComponents([
      TransformComponent(),
      RigidBody2DComponent(),
      Collider2DComponent(size: Vector2(10, 10)),
    ]);
    world.createEntityWithComponents([
      TransformComponent(),
      Collider2DComponent(size: Vector2(10, 10)),
    ]);
    final canvas = _Counter();
    debugger.render(canvas, const Size(100, 100));
    expect(canvas.rects, 1, reason: 'the static one');
  });

  test('outlines are listed into paths once', () {
    world.createEntityWithComponents([
      TransformComponent(),
      Collider2DComponent(
        shape: Collider2DShape.polygon,
        points: const [Offset(0, 0), Offset(10, 0), Offset(0, 10)],
      ),
    ]);
    world.update(1 / 60);
    final first = draw().paths.single;
    expect(draw().paths.single, same(first));
  });
}

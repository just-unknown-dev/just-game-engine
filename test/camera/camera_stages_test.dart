// The 2-D stages through the frames a game has: group framing holds its
// zoom while the group is empty for a moment; framing snaps to a target
// that spawns after the camera; noise holds while time is stopped; and the
// confiner keeps a rolled view inside its bounds.

import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

const _view = Size(800, 600);
const _dt = 1 / 60;

void main() {
  late World world;
  late CameraEngine cameras;

  OutputCamera output() => cameras.mainCamera;
  CameraBrain brain() => cameras.brain;

  setUp(() {
    world = World();
    cameras = CameraEngine()..initialize();
    cameras.mainCamera.viewportSize = _view;
    cameras.brain.defaultBlend = CameraBlend.cut;
    registerCameraSystems(world, cameras);
  });
  tearDown(() => world.dispose());

  Entity at(Offset position, List<Component> components, {String? name}) =>
      world.createEntityWithComponents([
        TransformComponent(position: Vector3(position.dx, position.dy, 0)),
        ...components,
      ], name: name);

  test('group framing holds its zoom while the group is empty a moment', () {
    final a = at(const Offset(-1000, 0), [TagComponent('player')]);
    final b = at(const Offset(1000, 0), [TagComponent('player')]);
    at(Offset.zero, [
      CameraTargetGroupComponent(
        members: [CameraGroupMember(target: const EntityTarget.tag('player'))],
      ),
    ], name: 'Party');
    at(Offset.zero, [
      VirtualCameraComponent(follow: const EntityTarget.name('Party')),
      CameraGroupFramingComponent(
        padding: 0,
        minZoom: 0.1,
        maxZoom: 2,
        zoomDamping: 0.5,
      ),
    ]);
    for (var i = 0; i < 5; i++) {
      world.update(_dt);
    }
    final fitted = output().zoom;
    expect(fitted, lessThan(0.5));

    // Both respawning: nobody to fit for a frame.
    world.destroyEntity(a);
    world.destroyEntity(b);
    world.update(_dt);
    expect(output().zoom, closeTo(fitted, 1e-9));
  });

  test('framing snaps to a target that spawns after the camera', () {
    at(Offset.zero, [
      VirtualCameraComponent(follow: const EntityTarget.name('Hero')),
      CameraFramingComponent(dampingX: 1, dampingY: 1),
    ]);
    for (var i = 0; i < 3; i++) {
      world.update(_dt);
    }
    expect(output().position, Offset.zero);
    at(const Offset(1000, 200), const [], name: 'Hero');
    world.update(_dt);
    expect(output().position.dx, closeTo(1000, 1e-9));
    expect(output().position.dy, closeTo(200, 1e-9));
  });

  test('noise holds where it is while time is stopped', () {
    at(Offset.zero, [VirtualCameraComponent(), CameraNoiseComponent()]);
    for (var i = 0; i < 20; i++) {
      brain().evaluate(world, _dt);
    }
    final shaken = output().position;
    expect(shaken, isNot(Offset.zero));
    brain().evaluate(world, 0); // a hit-stop
    expect(output().position, shaken);
    brain().evaluate(world, _dt);
    expect(output().position, isNot(shaken), reason: 'and moves on after');
  });

  test('the confiner keeps a rolled view inside its bounds', () {
    at(Offset.zero, [
      CameraBoundsComponent(width: 2000, height: 2000),
    ], name: 'Room');
    at(const Offset(900, 0), [
      VirtualCameraComponent(dutch: math.pi / 4),
      CameraConfinerComponent(boundsName: 'Room'),
    ]);
    world.update(_dt);
    final camera = output();
    expect(camera.rotation, closeTo(math.pi / 4, 1e-9));
    // Every corner of the turned screen is inside the room.
    for (final corner in const [
      Offset.zero,
      Offset(800, 0),
      Offset(0, 600),
      Offset(800, 600),
    ]) {
      final p = camera.screenToWorld(corner);
      expect(p.dx, inInclusiveRange(-1000 - 1e-6, 1000 + 1e-6));
      expect(p.dy, inInclusiveRange(-1000 - 1e-6, 1000 + 1e-6));
    }
    final reach = (800 * math.cos(math.pi / 4) + 600 * math.sin(math.pi / 4));
    expect(camera.position.dx, closeTo(1000 - reach / 2, 1e-6));
  });
}

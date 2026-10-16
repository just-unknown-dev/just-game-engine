// Cameras: a group framed from where the camera centres on it, a trigger's
// camera let go when the trigger goes, blends that overshoot, a pipeline
// kept between frames yet rebuilt when its components change, and the
// on-screen controls on a rolled camera.

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/widgets.dart';

const _view = Size(800, 600);
const _dt = 1 / 60;

void main() {
  late World world;
  late CameraSystem cameras;

  Camera output() => cameras.mainCamera;
  CameraBrain brain() => cameras.brain;

  setUp(() {
    world = World();
    cameras = CameraSystem()..initialize();
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

  void moveTo(Entity e, Offset to) => e.getComponent<TransformComponent>()!.setPositionXY(to.dx, to.dy);

  test('group framing keeps an outlier in shot, centred on the weighted centre', () {
    for (final (name, x) in [('A', 0.0), ('B', 10.0), ('C', 1000.0)]) {
      at(Offset(x, 0), const [], name: name);
    }
    at(Offset.zero, [
      CameraTargetGroupComponent(
        members: [
          for (final name in ['A', 'B', 'C']) CameraGroupMember(target: EntityTarget.name(name)),
        ],
      ),
    ], name: 'Party');
    at(Offset.zero, [
      VirtualCameraComponent(follow: const EntityTarget.name('Party')),
      CameraFramingComponent(deadZoneWidth: 0, deadZoneHeight: 0, dampingX: 0, dampingY: 0),
      CameraGroupFramingComponent(padding: 0.25, minZoom: 0.1, maxZoom: 4, zoomDamping: 0),
    ]);
    world.update(_dt);
    final camera = output();
    expect(camera.position.dx, closeTo(1010 / 3, 1e-6));
    final screenX = _view.width / 2 + (1000 - camera.position.dx) * camera.zoom;
    expect(screenX, lessThanOrEqualTo(_view.width));
    expect(camera.zoom, closeTo(800 / (2 * (1000 - 1010 / 3) * 1.25), 1e-9));
  });

  group('a trigger holding a camera on', () {
    late Entity player;
    late VirtualCameraComponent cave;
    late Entity trigger;
    setUp(() {
      player = at(const Offset(1000, 0), [TagComponent('player')]);
      at(Offset.zero, [VirtualCameraComponent(priority: 10)], name: 'Main');
      cave = VirtualCameraComponent(priority: 20, enabled: false);
      at(const Offset(1000, 0), [cave], name: 'Cave');
      trigger = at(const Offset(1000, 0), [CameraTriggerComponent(width: 400, height: 400, cameraName: 'Cave')]);
      world.update(_dt);
      expect(cave.enabled, isTrue);
      expect(brain().liveCamera?.name, 'Cave');
    });

    test('lets it go when the trigger is destroyed', () {
      world.destroyEntity(trigger);
      world.update(_dt);
      expect(cave.enabled, isFalse);
      expect(brain().liveCamera?.name, 'Main');
    });

    test('lets it go when the trigger is switched off', () {
      trigger.isActive = false;
      world.update(_dt);
      expect(cave.enabled, isFalse);
    });

    test('lets it go when the trigger names another camera', () {
      at(Offset.zero, [VirtualCameraComponent(priority: 1, enabled: false)], name: 'Other');
      trigger.getComponent<CameraTriggerComponent>()!.cameraName = 'Other';
      world.update(_dt);
      expect(cave.enabled, isFalse);
    });

    test('and still switches it as the player comes and goes', () {
      moveTo(player, const Offset(-5000, 0));
      world.update(_dt);
      expect(cave.enabled, isFalse);
      moveTo(player, const Offset(1000, 0));
      world.update(_dt);
      expect(cave.enabled, isTrue);
    });
  });

  test('a blend past its end carries on, for curves that overshoot', () {
    const a = CameraState(position: Offset.zero, zoom: 1);
    const b = CameraState(position: Offset(100, 0), zoom: 2);
    final past = CameraState.lerp(a, b, 1.1);
    expect(past.position.dx, closeTo(110, 1e-9));
    expect(past.zoom, closeTo(math.pow(2, 1.1), 1e-9));
    expect(CameraState.lerp(a, b, 1), same(b));
    expect(CameraState.lerp(a, b, -0.1).position.dx, closeTo(-10, 1e-9));
  });

  test('a camera\'s pipeline follows its components as they change', () {
    at(const Offset(-100, 0), const [], name: 'A');
    at(const Offset(100, 0), const [], name: 'B');
    at(Offset.zero, [
      CameraTargetGroupComponent(
        members: [
          for (final name in ['A', 'B']) CameraGroupMember(target: EntityTarget.name(name)),
        ],
      ),
    ], name: 'Party');
    final camera = at(Offset.zero, [VirtualCameraComponent(follow: const EntityTarget.name('Party'), zoom: 1.5)]);
    world.update(_dt);
    expect(output().zoom, 1.5);
    for (var i = 0; i < 3; i++) {
      world.update(_dt);
    }
    camera.addComponent(CameraGroupFramingComponent(padding: 0, minZoom: 0.25, maxZoom: 2, zoomDamping: 0));
    world.update(_dt);
    expect(output().zoom, 2);
    // Replaced by one of the same type: the new one is the one that runs.
    camera.addComponent(CameraGroupFramingComponent(padding: 0, minZoom: 0.25, maxZoom: 3, zoomDamping: 0));
    world.update(_dt);
    expect(output().zoom, 3);
    camera.removeComponent<CameraGroupFramingComponent>();
    world.update(_dt);
    expect(output().zoom, 1.5);
  });

  group('on-screen controls', () {
    Future<Camera> controls(WidgetTester tester, Camera camera) async {
      await tester.pumpWidget(
        MaterialApp(
          home: GameCameraControls(camera: camera, child: const ColoredBox(color: Colors.black)),
        ),
      );
      return camera;
    }

    testWidgets('a drag on a rolled camera moves the world with the pointer', (tester) async {
      final camera = await controls(tester, Camera(rotation: math.pi / 2, viewportSize: const Size(800, 600)));
      final grabbed = camera.screenToWorld(const Offset(300, 300));
      final gesture = await tester.startGesture(const Offset(300, 300), kind: PointerDeviceKind.mouse);
      await gesture.moveTo(const Offset(340, 300));
      await gesture.up();
      final under = camera.screenToWorld(const Offset(340, 300));
      expect(under.dx, closeTo(grabbed.dx, 1e-9));
      expect(under.dy, closeTo(grabbed.dy, 1e-9));
    });

    testWidgets('the buttons step from the camera\'s zoom as it is now', (tester) async {
      final camera = await controls(tester, Camera());
      camera.setZoom(3);
      await tester.tap(find.byTooltip('Zoom in'));
      expect(camera.zoom, closeTo(3.1, 1e-9));
    });
  });
}

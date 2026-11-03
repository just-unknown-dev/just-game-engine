// Camera regressions: blend lists that never end, lookahead thrown by a
// teleport, names shared with switched-off entities, triggers that fight,
// the brain losing where a cut came from, angles averaged the long way,
// lenses that cannot project, and fades that play only once.

import 'dart:math' as math;
import 'dart:ui' show Canvas, PictureRecorder;

import 'package:flutter/animation.dart' show Curves;
import 'package:flutter/material.dart' show Colors;
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

const _view = Size(800, 600);
const _dt = 1 / 60;

class _CountingEffect extends CameraEffect {
  int renders = 0;

  @override
  void render(Canvas canvas, Size size) => renders++;

  @override
  bool get isComplete => false;
}

void main() {
  late World world;
  late Camera output;
  late CameraBrain brain;

  setUp(() {
    world = World();
    output = Camera(viewportSize: _view);
    brain = CameraBrain(output)..defaultBlend = CameraBlend.cut;
  });
  tearDown(() => world.dispose());

  Entity at(Offset position, List<Component> components, {String? name}) =>
      world.createEntityWithComponents([
        TransformComponent(position: Vector3(position.dx, position.dy, 0)),
        ...components,
      ], name: name);

  Entity shot(
    String name,
    Offset position, {
    int priority = 10,
    double dutch = 0,
    List<Component> extra = const [],
  }) => at(position, [
    VirtualCameraComponent(priority: priority, dutch: dutch),
    ...extra,
  ], name: name);

  void adopt(Entity parent, List<Entity> children) {
    final list = ChildrenComponent();
    parent.addComponent(list);
    for (final child in children) {
      child.addComponent(ParentComponent(parentId: parent.id));
      list.addChild(child.id);
    }
  }

  void moveTo(Entity e, Offset to) =>
      e.getComponent<TransformComponent>()!.setPositionXY(to.dx, to.dy);

  VirtualCameraComponent vcamOf(Entity e) =>
      e.getComponent<VirtualCameraComponent>()!;

  CameraFramingComponent rigid({double lookahead = 0}) =>
      CameraFramingComponent(
        deadZoneWidth: 0,
        deadZoneHeight: 0,
        dampingX: 0,
        dampingY: 0,
        lookaheadTime: lookahead,
        lookaheadSmoothing: 0,
      );

  group('blend list (C6)', () {
    test('a looping list of instant steps does not hang', () {
      final rig = at(Offset.zero, [
        VirtualCameraComponent(),
        CameraBlendListComponent(
          loop: true,
          steps: [
            CameraBlendStep(child: 'A', hold: 0, blend: 0),
            CameraBlendStep(child: 'B', hold: 0, blend: 0),
          ],
        ),
      ], name: 'Rig');
      adopt(rig, [
        shot('A', const Offset(10, 0)),
        shot('B', const Offset(20, 0)),
      ]);
      for (var i = 0; i < 5; i++) {
        brain.evaluate(world, _dt);
      }
      expect(output.position.dx, anyOf(10, 20));
    });

    test('a list that loses steps mid-run carries on', () {
      final list = CameraBlendListComponent(
        steps: [
          CameraBlendStep(child: 'A', hold: 0.1, blend: 0),
          CameraBlendStep(child: 'B', hold: 0.1, blend: 0),
          CameraBlendStep(child: 'C', hold: 10, blend: 0),
        ],
      );
      final rig = at(Offset.zero, [VirtualCameraComponent(), list]);
      adopt(rig, [
        shot('A', const Offset(10, 0)),
        shot('B', const Offset(20, 0)),
        shot('C', const Offset(30, 0)),
      ]);
      for (var i = 0; i < 20; i++) {
        brain.evaluate(world, _dt);
      }
      expect(output.position.dx, 30);
      list.steps = [CameraBlendStep(child: 'A', hold: 1, blend: 0)];
      expect(() => brain.evaluate(world, _dt), returnsNormally);
      expect(output.position.dx, 10);
    });
  });

  group('framing lookahead (C15)', () {
    late Entity hero;

    setUp(() {
      hero = at(Offset.zero, [TagComponent('player')], name: 'Hero');
      at(Offset.zero, [
        VirtualCameraComponent(follow: const EntityTarget.tag('player')),
        rigid(lookahead: 0.25),
      ], name: 'Main');
      brain.evaluate(world, _dt);
    });

    test('a teleport longer than the view is not a speed', () {
      moveTo(hero, const Offset(3000, 0));
      brain.evaluate(world, _dt);
      expect(output.position.dx, closeTo(3000, 1));
    });

    test('a snap does not read the jump as a speed', () {
      moveTo(hero, const Offset(500, 0));
      brain.evaluate(world, _dt, snap: true);
      expect(output.position.dx, closeTo(500, 1));
    });

    test('a new target is not measured from the old one', () {
      world.destroyEntity(hero);
      at(const Offset(300, 0), [TagComponent('player')], name: 'Hero');
      brain.evaluate(world, _dt);
      expect(output.position.dx, closeTo(300, 1));
    });

    test('however fast the target, the lead stays inside the view', () {
      hero.addComponent(VelocityComponent(velocity: Vector3(1e6, 0, 0)));
      brain.evaluate(world, _dt);
      // Half of the 800-wide view at most.
      expect(output.position.dx, closeTo(400, 1));
    });
  });

  test('a name shared with a switched-off entity finds the active one '
      '(C20)', () {
    at(const Offset(-500, 0), const [], name: 'Hero').isActive = false;
    at(const Offset(300, 40), const [], name: 'Hero');
    at(Offset.zero, [
      VirtualCameraComponent(follow: const EntityTarget.name('Hero')),
      rigid(),
    ]);
    brain.evaluate(world, _dt);
    expect(output.position, const Offset(300, 40));
  });

  group('triggers (C29)', () {
    late CameraSystem cameras;
    late Entity player;

    setUp(() {
      cameras = CameraSystem()..initialize();
      cameras.mainCamera.viewportSize = _view;
      cameras.brain.defaultBlend = CameraBlend.cut;
      registerCameraSystems(world, cameras);
      player = at(Offset.zero, [TagComponent('player')], name: 'Player');
    });

    Entity trigger(
      Offset position, {
      required String camera,
      CameraTriggerMode mode = CameraTriggerMode.enableWhileInside,
      int amount = 10,
    }) => at(position, [
      CameraTriggerComponent(
        width: 100,
        height: 100,
        cameraName: camera,
        mode: mode,
        amount: amount,
      ),
    ]);

    test('two enable triggers on one camera: inside either is enough', () {
      final room = shot('Room', const Offset(1000, 0));
      vcamOf(room).enabled = false;
      trigger(Offset.zero, camera: 'Room');
      trigger(const Offset(5000, 0), camera: 'Room');
      world.update(_dt);
      expect(vcamOf(room).enabled, isTrue);
      moveTo(player, const Offset(5000, 0));
      world.update(_dt);
      expect(vcamOf(room).enabled, isTrue);
      moveTo(player, const Offset(2500, 0));
      world.update(_dt);
      expect(vcamOf(room).enabled, isFalse);
    });

    test('a boost is taken back when its trigger is switched off', () {
      final side = shot('Side', Offset.zero, priority: 5);
      final zone = trigger(
        Offset.zero,
        camera: 'Side',
        mode: CameraTriggerMode.boostPriority,
      );
      world.update(_dt);
      expect(vcamOf(side).priority, 15);
      zone.isActive = false;
      world.update(_dt);
      expect(vcamOf(side).priority, 5);
    });

    test('a boost is taken back when its trigger is destroyed', () {
      final side = shot('Side', Offset.zero, priority: 5);
      final zone = trigger(
        Offset.zero,
        camera: 'Side',
        mode: CameraTriggerMode.boostPriority,
      );
      world.update(_dt);
      world.destroyEntity(zone);
      world.update(_dt);
      expect(vcamOf(side).priority, 5);
    });

    test('editing the amount while boosted does not drift the priority', () {
      final side = shot('Side', Offset.zero, priority: 5);
      final zone = trigger(
        Offset.zero,
        camera: 'Side',
        mode: CameraTriggerMode.boostPriority,
      );
      world.update(_dt);
      zone.getComponent<CameraTriggerComponent>()!.amount = 3;
      world.update(_dt);
      expect(vcamOf(side).priority, 8);
      moveTo(player, const Offset(2500, 0));
      world.update(_dt);
      expect(vcamOf(side).priority, 5);
    });
  });

  group('brain (C30)', () {
    test('a rule naming the camera that was switched off still applies', () {
      brain
        ..defaultBlend = const CameraBlend(duration: 1)
        ..blendTable = CameraBlendTable(const [
          CameraBlendRule(from: 'Cutscene', blend: CameraBlend.cut),
        ]);
      final changes = <(String?, String?)>[];
      brain.onCameraActivated = (from, to) =>
          changes.add((from?.name, to.name));
      shot('Main', Offset.zero);
      final cutscene = shot('Cutscene', const Offset(1000, 0), priority: 50);
      brain.evaluate(world, _dt);
      vcamOf(cutscene).enabled = false;
      brain.evaluate(world, _dt);
      expect(output.position, Offset.zero, reason: 'the rule says cut');
      expect(changes.last, ('Cutscene', 'Main'));
    });

    test('a destroyed camera is still reported as where the cut came from', () {
      final changes = <String?>[];
      brain.onCameraActivated = (from, to) => changes.add(from?.name);
      shot('Main', Offset.zero);
      final cutscene = shot('Cutscene', const Offset(1000, 0), priority: 50);
      brain.evaluate(world, _dt);
      world.destroyEntity(cutscene);
      brain.evaluate(world, _dt);
      expect(changes, [null, 'Cutscene']);
    });

    test('an outgoing camera destroyed mid-blend does not jump the view', () {
      brain.defaultBlend = const CameraBlend(duration: 1, curve: Curves.linear);
      final a = shot('A', Offset.zero, priority: 10);
      final b = shot('B', const Offset(1000, 0), priority: 5);
      brain.evaluate(world, _dt);
      vcamOf(b).priority = 20;
      for (var i = 0; i < 10; i++) {
        moveTo(a, Offset(-100.0 * (i + 1), 0));
        brain.evaluate(world, _dt);
      }
      final before = output.position.dx;
      world.destroyEntity(a);
      brain.evaluate(world, _dt);
      // One frame of a one-second blend over ~2000 units is ~35.
      expect((output.position.dx - before).abs(), lessThan(60));
    });

    test('a manager that comes back live does not start its children from '
        'stale damping', () {
      final player = at(Offset.zero, [TagComponent('player')]);
      final main = shot('Main', const Offset(-5000, 0), priority: 10);
      final rig = at(Offset.zero, [
        VirtualCameraComponent(priority: 20),
        CameraBlendListComponent(
          steps: [CameraBlendStep(child: 'Follow', hold: 100)],
        ),
      ], name: 'Rig');
      final follow = at(Offset.zero, [
        VirtualCameraComponent(follow: const EntityTarget.tag('player')),
        CameraFramingComponent(
          deadZoneWidth: 0,
          deadZoneHeight: 0,
          dampingX: 1,
          dampingY: 1,
        ),
      ], name: 'Follow');
      adopt(rig, [follow]);
      brain.evaluate(world, _dt);
      expect(brain.liveCamera, rig);
      vcamOf(rig).priority = 1;
      brain.evaluate(world, _dt);
      expect(brain.liveCamera, main);
      moveTo(player, const Offset(600, 0));
      for (var i = 0; i < 5; i++) {
        brain.evaluate(world, _dt);
      }
      vcamOf(rig).priority = 20;
      brain.evaluate(world, _dt);
      expect(brain.liveCamera, rig);
      expect(output.position.dx, closeTo(600, 1e-6));
    });
  });

  group('angles and loops (C31)', () {
    test('a mixer averages +170° and −170° to 180°, not 0°', () {
      final rig = at(Offset.zero, [
        VirtualCameraComponent(),
        CameraMixerComponent(weights: {'L': 1, 'R': 1}),
      ]);
      adopt(rig, [
        shot('L', Offset.zero, dutch: 170 * math.pi / 180),
        shot('R', Offset.zero, dutch: -170 * math.pi / 180),
      ]);
      brain.evaluate(world, _dt);
      expect(math.cos(output.rotation), closeTo(-1, 1e-9));
    });

    test('a mixer of one shot keeps its angle exactly', () {
      final rig = at(Offset.zero, [
        VirtualCameraComponent(),
        CameraMixerComponent(weights: {'L': 1}),
      ]);
      adopt(rig, [shot('L', Offset.zero, dutch: 7.0)]);
      brain.evaluate(world, _dt);
      expect(output.rotation, 7.0);
    });

    test('a dolly on a closed track damps across the seam', () {
      final dolly = CameraDollyComponent(
        waypoints: const [
          Offset(0, 0),
          Offset(100, 0),
          Offset(100, 100),
          Offset(0, 100),
        ],
        closed: true,
        pathPosition: 0.95,
        damping: 0.4,
      );
      at(Offset.zero, [VirtualCameraComponent(), dolly]);
      brain.evaluate(world, _dt);
      expect(output.position.dx, closeTo(0, 1e-9));
      expect(output.position.dy, closeTo(20, 1e-9));
      dolly.pathPosition = 0.05;
      brain.evaluate(world, _dt);
      // Forward toward the seam at (0, 0), not back along the whole track.
      expect(output.position.dx, closeTo(0, 1e-9));
      expect(output.position.dy, lessThan(20));
      for (var i = 0; i < 300; i++) {
        brain.evaluate(world, _dt);
      }
      expect(output.position.dx, closeTo(20, 1e-3));
      expect(output.position.dy, closeTo(0, 1e-3));
    });
  });

  group('lenses and zoom (C37)', () {
    bool finite(Matrix4 m) => m.storage.every((v) => v.isFinite);

    test('a perspective lens made without a near plane sees ahead', () {
      const lens = CameraLens(projection: CameraProjection.perspective);
      expect(lens.near, greaterThan(0));
      expect(lens.far, greaterThan(lens.near));
      expect(const CameraLens().near, -10000);
    });

    test('lenses that cannot project still give finite matrices', () {
      final camera = Camera(viewportSize: _view);
      final m = Matrix4.zero();
      for (final lens in const [
        CameraLens.orthographic(near: 5, far: 5),
        CameraLens.perspective(fieldOfView: 0),
        CameraLens.perspective(near: 0),
        CameraLens.perspective(near: -10, far: -20),
        CameraLens.perspective(near: 10, far: 10),
      ]) {
        camera.lens = lens;
        camera.projectionMatrixInto(m);
        expect(finite(m), isTrue, reason: '$lens');
      }
    });

    test('a zoom of zero does not divide the world by zero', () {
      final camera = Camera(zoom: 0, viewportSize: _view);
      expect(camera.zoom, greaterThan(0));
      final bounds = camera.getVisibleBounds();
      expect(bounds.width.isFinite && bounds.height.isFinite, isTrue);
      camera.zoom = double.nan;
      expect(camera.zoom, greaterThan(0));
      camera.zoom = -3;
      expect(camera.zoom, greaterThan(0));
      final world = camera.screenToWorld(const Offset(10, 10));
      expect(world.dx.isFinite && world.dy.isFinite, isTrue);
    });
  });

  group('camera effects (C40)', () {
    test('a fade that finished plays again', () {
      final manager = Camera().effectManager;
      final fade = ScreenFadeEffect();
      manager.addEffect(fade);
      fade.flash(Colors.white, holdDuration: 0.05, fadeDuration: 0.05);
      for (var i = 0; i < 20; i++) {
        manager.update(_dt);
      }
      expect(manager.hasEffects, isFalse);
      fade.fadeIn(0.2);
      expect(manager.hasEffects, isTrue);
    });

    test('a letterbox that was hidden shows again', () {
      final manager = Camera().effectManager;
      final bars = LetterboxEffect();
      manager.addEffect(bars);
      bars.show(0.05);
      for (var i = 0; i < 10; i++) {
        manager.update(_dt);
      }
      bars.hide(0.05);
      for (var i = 0; i < 10; i++) {
        manager.update(_dt);
      }
      expect(manager.hasEffects, isFalse);
      bars.show(0.05);
      expect(manager.hasEffects, isTrue);
    });

    test('an effect taken out stays out, and adding one twice draws it '
        'once', () {
      final manager = Camera().effectManager;
      final fade = ScreenFadeEffect();
      manager
        ..addEffect(fade)
        ..removeEffect(fade);
      fade.fadeIn(0.2);
      expect(manager.hasEffects, isFalse);

      final counting = _CountingEffect();
      manager
        ..addEffect(counting)
        ..addEffect(counting)
        ..render(Canvas(PictureRecorder()), const Size(10, 10));
      expect(counting.renders, 1);
    });
  });
}

// Framing a party, and changing shots by where the player stands.

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

const _view = Size(800, 600);
const _dt = 1 / 60;

T _roundTrip<T extends Component>(T component) =>
    ComponentCodecRegistry.instance.decode(
          ComponentCodecRegistry.instance.encode(component)!,
        )
        as T;

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

  void moveTo(Entity e, Offset to) =>
      e.getComponent<TransformComponent>()!.setPositionXY(to.dx, to.dy);

  Offset where(Entity e) =>
      e.getComponent<TransformComponent>()!.position.toOffset();

  test('registerCameraSystems runs groups, then triggers, then the brain', () {
    final order = world.systems
        .where((s) => s.runtimeType.toString().startsWith('Camera'))
        .map((s) => s.runtimeType)
        .toList();
    expect(order, [
      CameraTargetGroupSystem,
      CameraTriggerSystem,
      CameraBrainSystem,
    ]);
  });

  group('target group', () {
    test('sits at the weighted centre of the members it finds', () {
      at(const Offset(0, 0), const [], name: 'A');
      at(const Offset(300, 0), const [], name: 'B');
      final party = at(Offset.zero, [
        CameraTargetGroupComponent(
          members: [
            CameraGroupMember(name: 'A', weight: 1),
            CameraGroupMember(name: 'B', weight: 2),
            CameraGroupMember(name: 'Nobody'),
          ],
        ),
      ], name: 'Party');
      world.update(_dt);
      expect(where(party), const Offset(200, 0));
      final group = party.getComponent<CameraTargetGroupComponent>()!;
      expect(group.resolved, 2);
      expect(group.bounds, const Rect.fromLTRB(0, 0, 300, 0));
    });

    test('radii make room, and a weightless member is kept in shot', () {
      at(const Offset(0, 0), const [], name: 'A');
      at(const Offset(100, 0), const [], name: 'B');
      final party = at(Offset.zero, [
        CameraTargetGroupComponent(
          members: [
            CameraGroupMember(name: 'A', radius: 50),
            CameraGroupMember(name: 'B', weight: 0, radius: 10),
          ],
        ),
      ]);
      world.update(_dt);
      expect(where(party), Offset.zero, reason: 'only A pulls the centre');
      expect(
        party.getComponent<CameraTargetGroupComponent>()!.bounds,
        const Rect.fromLTRB(-50, -50, 110, 50),
      );
    });

    test('a camera frames the party by following the group by name', () {
      final a = at(const Offset(-100, 0), [TagComponent('hero')]);
      at(const Offset(100, 40), const [], name: 'Friend');
      at(Offset.zero, [
        CameraTargetGroupComponent(
          members: [
            CameraGroupMember(tag: 'hero'),
            CameraGroupMember(name: 'Friend'),
          ],
        ),
      ], name: 'Party');
      at(Offset.zero, [
        VirtualCameraComponent(followName: 'Party'),
        CameraFramingComponent(
          deadZoneWidth: 0,
          deadZoneHeight: 0,
          dampingX: 0,
          dampingY: 0,
        ),
      ]);
      world.update(_dt);
      expect(output().position, const Offset(0, 20));
      moveTo(a, const Offset(-300, 0));
      world.update(_dt);
      expect(output().position, const Offset(-100, 20));
    });

    test('group framing pulls the lens back as the party spreads', () {
      final a = at(const Offset(-100, 0), const [], name: 'A');
      at(const Offset(100, 0), const [], name: 'B');
      at(Offset.zero, [
        CameraTargetGroupComponent(
          members: [
            CameraGroupMember(name: 'A'),
            CameraGroupMember(name: 'B'),
          ],
        ),
      ], name: 'Party');
      at(Offset.zero, [
        VirtualCameraComponent(followName: 'Party'),
        CameraGroupFramingComponent(
          padding: 0,
          minZoom: 0.25,
          maxZoom: 2,
          zoomDamping: 0,
        ),
      ]);
      world.update(_dt);
      // 200 wide in an 800 view would be 4×; the shot allows 2×.
      expect(output().zoom, 2);

      moveTo(a, const Offset(-1500, 0));
      world.update(_dt);
      expect(output().zoom, closeTo(0.5, 1e-9), reason: '800 / 1600');

      moveTo(a, const Offset(-9000, 0));
      world.update(_dt);
      expect(output().zoom, 0.25, reason: 'never wider than minZoom');
    });

    test('the lens eases rather than jumps', () {
      final a = at(const Offset(-100, 0), const [], name: 'A');
      at(const Offset(100, 0), const [], name: 'B');
      at(Offset.zero, [
        CameraTargetGroupComponent(
          members: [
            CameraGroupMember(name: 'A'),
            CameraGroupMember(name: 'B'),
          ],
        ),
      ], name: 'Party');
      at(Offset.zero, [
        VirtualCameraComponent(followName: 'Party'),
        CameraGroupFramingComponent(padding: 0, minZoom: 0.25, maxZoom: 2),
      ]);
      world.update(_dt);
      moveTo(a, const Offset(-1500, 0));
      world.update(_dt);
      expect(output().zoom, lessThan(2));
      expect(output().zoom, greaterThan(0.5));
    });
  });

  group('trigger', () {
    late Entity player;
    setUp(() {
      player = at(const Offset(-5000, 0), [TagComponent('player')]);
      at(Offset.zero, [VirtualCameraComponent(priority: 10)], name: 'Main');
    });

    test('a zone camera is live only while the player is inside', () {
      final zone = at(const Offset(1000, 0), [
        VirtualCameraComponent(priority: 20, enabled: false, zoom: 2),
        CameraTriggerComponent(width: 400, height: 400),
      ], name: 'Cave');
      world.update(_dt);
      expect(brain().liveCamera?.name, 'Main');

      moveTo(player, const Offset(1100, 50));
      world.update(_dt);
      expect(brain().liveCamera?.name, 'Cave');
      expect(output().zoom, 2);
      expect(zone.getComponent<CameraTriggerComponent>()!.isInside, isTrue);

      moveTo(player, const Offset(1201, 0));
      world.update(_dt);
      expect(brain().liveCamera?.name, 'Main');
    });

    test('a boost is applied once and handed back', () {
      final side = at(Offset.zero, [
        VirtualCameraComponent(priority: 5),
      ], name: 'Side');
      at(const Offset(1000, 0), [
        CameraTriggerComponent(
          width: 200,
          height: 200,
          cameraName: 'Side',
          mode: CameraTriggerMode.boostPriority,
          amount: 50,
        ),
      ]);
      int priority() => side.getComponent<VirtualCameraComponent>()!.priority;

      moveTo(player, const Offset(1000, 0));
      world.update(_dt);
      world.update(_dt);
      expect(priority(), 55, reason: 'not added again each frame');
      expect(brain().liveCamera?.name, 'Side');

      moveTo(player, const Offset(0, 0));
      world.update(_dt);
      expect(priority(), 5);
      expect(brain().liveCamera?.name, 'Main');
    });

    test('a one-shot trigger stays switched', () {
      at(const Offset(1000, 0), [
        VirtualCameraComponent(priority: 20, enabled: false),
        CameraTriggerComponent(width: 200, height: 200, oneShot: true),
      ], name: 'Finale');
      moveTo(player, const Offset(1000, 0));
      world.update(_dt);
      moveTo(player, const Offset(-5000, 0));
      world.update(_dt);
      expect(brain().liveCamera?.name, 'Finale');
    });

    test('nothing happens until the target exists', () {
      world.destroyEntity(player);
      at(const Offset(1000, 0), [
        VirtualCameraComponent(priority: 20, enabled: false),
        CameraTriggerComponent(width: 99999, height: 99999),
      ], name: 'Zone');
      world.update(_dt);
      expect(brain().liveCamera?.name, 'Main');
    });

    test('the switch blends like any other', () {
      brain().defaultBlend = const CameraBlend(duration: 1);
      at(const Offset(1000, 0), [
        VirtualCameraComponent(priority: 20, enabled: false),
        CameraTriggerComponent(width: 400, height: 400),
      ], name: 'Cave');
      world.update(_dt);
      moveTo(player, const Offset(1000, 0));
      world.update(_dt);
      expect(brain().activeBlend, isNotNull);
      expect(output().position.dx, inExclusiveRange(0, 1000));
    });
  });

  test('group, group framing and trigger are saved and restored', () {
    ComponentCodecRegistry.instance.clear();
    registerCoreCodecs();

    final group = _roundTrip(
      CameraTargetGroupComponent(
        members: [
          CameraGroupMember(name: 'A', weight: 2, radius: 30),
          CameraGroupMember(tag: 'enemy', weight: 0.5),
        ],
      ),
    );
    expect(group.members.map((m) => m.toJson()), [
      {'name': 'A', 'tag': '', 'weight': 2.0, 'radius': 30.0},
      {'name': '', 'tag': 'enemy', 'weight': 0.5, 'radius': 0.0},
    ]);

    final framing = _roundTrip(
      CameraGroupFramingComponent(
        padding: 0.1,
        minZoom: 0.3,
        maxZoom: 3,
        zoomDamping: 1.5,
      ),
    );
    expect(
      (framing.padding, framing.minZoom, framing.maxZoom, framing.zoomDamping),
      (0.1, 0.3, 3, 1.5),
    );

    final trigger = _roundTrip(
      CameraTriggerComponent(
        width: 100,
        height: 50,
        targetName: 'Hero',
        targetTag: '',
        cameraName: 'Boss',
        mode: CameraTriggerMode.boostPriority,
        amount: 7,
        oneShot: true,
      ),
    );
    expect((trigger.width, trigger.height), (100, 50));
    expect((trigger.targetName, trigger.targetTag), ('Hero', ''));
    expect(trigger.cameraName, 'Boss');
    expect(trigger.mode, CameraTriggerMode.boostPriority);
    expect((trigger.amount, trigger.oneShot), (7, true));
    expect(trigger.isInside, isFalse, reason: 'runtime state is not saved');
  });

  test('a trigger is sized and resized like a shape', () {
    final extent = CameraDefinitions.trigger.extent!;
    final trigger = CameraTriggerComponent(width: 400, height: 200);
    expect(extent.sizeOf(trigger), const Size(400, 200));
    expect(extent.scale(trigger, 0.5, 2), isTrue);
    expect((trigger.width, trigger.height), (200, 400));
  });
}

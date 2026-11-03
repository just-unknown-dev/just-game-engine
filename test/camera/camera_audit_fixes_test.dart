// Camera fixes from the 2.0.0 final pass: blend lists restart on standby
// cameras, registerAll override, closed dolly tracks, re-emitted impulses,
// a full rig-memory reset.

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

const _view = Size(800, 600);
const _dt = 1 / 60;

class _Marker extends Component {}

class _MarkerManager extends CameraManager<_Marker> {
  const _MarkerManager(this.id);

  final int id;

  @override
  CameraState? evaluate(CameraManagerContext context, _Marker component) =>
      null;
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

  Entity shot(String name, Offset position, {int priority = 10}) =>
      at(position, [VirtualCameraComponent(priority: priority)], name: name);

  void adopt(Entity parent, List<Entity> children) {
    final list = ChildrenComponent();
    parent.addComponent(list);
    for (final child in children) {
      child.addComponent(ParentComponent(parentId: parent.id));
      list.addChild(child.id);
    }
  }

  void run(double seconds) {
    for (var t = 0.0; t < seconds - 1e-9; t += _dt) {
      brain.evaluate(world, _dt);
    }
  }

  group('F1 blend list', () {
    test('starts over on going live even when it runs on standby', () {
      final rig = at(Offset.zero, [
        VirtualCameraComponent(
          priority: 20,
          standbyUpdate: CameraStandbyUpdate.always,
        ),
        CameraBlendListComponent(
          steps: [
            CameraBlendStep(child: 'Wide', hold: 1, blend: 0),
            CameraBlendStep(child: 'Close', hold: 1, blend: 0),
          ],
        ),
      ], name: 'Cutscene');
      adopt(rig, [
        shot('Wide', const Offset(0, 0)),
        shot('Close', const Offset(200, 0)),
      ]);
      final main = shot('Main', const Offset(-500, 0), priority: 1);

      run(1.5);
      expect(brain.liveCamera?.name, 'Cutscene');
      expect(output.position.dx, 200, reason: 'on the second shot');

      // Main takes over; the list keeps running on standby.
      main.getComponent<VirtualCameraComponent>()!.priority = 99;
      run(0.5);
      expect(brain.liveCamera?.name, 'Main');

      main.getComponent<VirtualCameraComponent>()!.priority = 1;
      brain.evaluate(world, _dt);
      expect(brain.liveCamera?.name, 'Cutscene');
      expect(output.position.dx, 0, reason: 'back on the first shot');
    });
  });

  test('F4 CameraManagerRegistry.registerAll takes override', () {
    final registry = CameraManagerRegistry()
      ..registerAll([const _MarkerManager(1)]);
    expect(
      () => registry.registerAll([const _MarkerManager(2)]),
      throwsStateError,
    );
    registry.registerAll([const _MarkerManager(3)], override: true);
    final entity = world.createEntityWithComponents([_Marker()]);
    final (manager, _) = registry.managerOf(entity)!;
    expect((manager as _MarkerManager).id, 3);
  });

  group('F5 DollyPath.closed', () {
    test('is false when too few points make the track open', () {
      final two = DollyPath(const [Offset.zero, Offset(10, 0)], closed: true);
      expect(two.closed, isFalse);
      expect(two.points, hasLength(2));

      final three = DollyPath(const [
        Offset.zero,
        Offset(10, 0),
        Offset(10, 10),
      ], closed: true);
      expect(three.closed, isTrue);
      expect(three.points, hasLength(4));

      expect(
        DollyPath(const [Offset.zero, Offset(1, 0), Offset(1, 1)]).closed,
        isFalse,
      );
    });
  });

  group('F6 impulses', () {
    test('emitting the same impulse twice is felt once, restarted', () {
      final bus = CameraImpulseBus();
      final impulse = CameraImpulse(position: Offset.zero, duration: 1);
      bus.emit(impulse);
      bus.update(0.5);
      bus.emit(impulse);
      expect(bus.activeCount, 1);
      // Restarted: still felt after the first emit's second would be up.
      bus.update(0.75);
      expect(bus.activeCount, 1);
      bus.update(0.5);
      expect(bus.activeCount, 0);
    });

    test('a spent impulse emitted again is felt again', () {
      final bus = CameraImpulseBus();
      final impulse = CameraImpulse(position: Offset.zero, duration: 0.2);
      bus.emit(impulse);
      bus.update(0.5);
      expect(bus.activeCount, 0);
      bus.emit(impulse);
      expect(impulse.isSpent, isFalse);
      bus.update(0.1);
      expect(bus.activeCount, 1);
    });
  });

  test('F7 CameraRigMemory.reset forgets the position too', () {
    final memory = CameraRigMemory()
      ..initialized = true
      ..position = const Offset(5, 6)
      ..lookaheadVelocity = const Offset(1, 1)
      ..noiseTime = 3;
    memory.extra['x'] = 1;
    memory.reset();
    expect(memory.initialized, isFalse);
    expect(memory.position, Offset.zero);
    expect(memory.lookaheadVelocity, Offset.zero);
    expect(memory.noiseTime, 0);
    expect(memory.extra, isEmpty);
  });
}

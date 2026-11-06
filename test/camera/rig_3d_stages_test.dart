// The 3-D rigs: orbit follow and first person read the target without
// changing it, so the stages after them see where the target is; a lowest
// pitch above the highest does not throw; and a target that goes missing
// is waited for where the camera was, then snapped to when it first
// appears.

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/src/camera/stages/rig_3d_stages.dart'
    show cameraAnglesOf;

const _dt = 1 / 60;

/// Notes the target position the last stage of the pipeline is given.
class _Probe extends Component {
  Vector3? seen;
}

class _ProbeStage extends CameraStage<_Probe> {
  const _ProbeStage();

  @override
  CameraStagePhase get phase => CameraStagePhase.finalize;

  @override
  CameraState apply(
    CameraStageContext context,
    _Probe probe,
    CameraState state,
    double dt,
  ) {
    final at = context.targetPosition3;
    probe.seen = at == null ? null : Vector3.copy(at);
    return state;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late World world;
  late CameraBrain brain;

  setUp(() {
    world = World()..initialize();
    brain =
        CameraBrain(
            OutputCamera(
              position: Offset.zero,
              viewportSize: const Size(800, 600),
            ),
          )
          ..defaultBlend = CameraBlend.cut
          ..stages.register(const _ProbeStage());
  });
  tearDown(() => world.dispose());

  Entity player([Vector3? at]) => world.createEntityWithComponents([
    TransformComponent(position: at ?? Vector3(2, 0, 3)),
  ], name: 'Player');

  Entity camera(List<Component> stages) => world.createEntityWithComponents([
    TransformComponent(position: Vector3(0, -3, -8)),
    VirtualCameraComponent(
      follow: const EntityTarget.name('Player'),
      projection: CameraProjection.perspective,
    ),
    ...stages,
  ], name: 'Cam');

  (double, double, double) where() {
    final s = brain.liveState!;
    return (s.position.dx, s.position.dy, s.z);
  }

  group('the target is read, never changed', () {
    test('orbit: a look-at after it aims at the target, not the pivot', () {
      player();
      final probe = _Probe();
      camera([
        OrbitFollowComponent(damping: 0, pivot: Vector3(0, -1.4, 0)),
        LookAtComponent(),
        probe,
      ]);
      brain.evaluate(world, _dt);
      expect((probe.seen!.x, probe.seen!.y, probe.seen!.z), (2.0, 0.0, 3.0));
      final (x, y, z) = where();
      final (pitch, yaw) = cameraAnglesOf(Vector3(2 - x, 0 - y, 3 - z));
      expect(brain.liveState!.pitch, closeTo(pitch, 1e-9));
      expect(brain.liveState!.yaw, closeTo(yaw, 1e-9));
    });

    test('first person: the target stays where it is', () {
      player();
      final probe = _Probe();
      camera([FirstPersonComponent(eye: Vector3(0, -1.6, 0)), probe]);
      brain.evaluate(world, _dt);
      expect((probe.seen!.x, probe.seen!.y, probe.seen!.z), (2.0, 0.0, 3.0));
      expect(where(), (2.0, -1.6, 3.0));
    });
  });

  test('a lowest pitch above the highest does not throw', () {
    player();
    camera([OrbitFollowComponent(pitch: 0.5, minPitch: 0.7, maxPitch: 0.6)]);
    expect(() => brain.evaluate(world, _dt), returnsNormally);
    expect(brain.liveState!.pitch, inInclusiveRange(0.6, 0.7));

    world.destroyEntity(world.findEntityByName('Cam')!);
    camera([FirstPersonComponent(pitch: -1, minPitch: 0.2, maxPitch: -0.2)]);
    expect(() => brain.evaluate(world, _dt), returnsNormally);
    expect(brain.liveState!.pitch, -0.2);
  });

  group('a missing target', () {
    test('orbit: the camera holds where it was', () {
      final hero = player();
      camera([OrbitFollowComponent(damping: 0.5)]);
      for (var i = 0; i < 10; i++) {
        brain.evaluate(world, _dt);
      }
      final before = where();
      world.destroyEntity(hero);
      for (var i = 0; i < 10; i++) {
        brain.evaluate(world, _dt);
      }
      expect(where(), before);
    });

    test('orbit: a target that appears late is snapped to', () {
      camera([OrbitFollowComponent(damping: 0.5)]);
      for (var i = 0; i < 5; i++) {
        brain.evaluate(world, _dt);
      }
      player(Vector3(100, 0, 50));
      brain.evaluate(world, _dt);
      final late = where();

      // The same rig framing the same target from its first frame.
      world.destroyEntity(world.findEntityByName('Cam')!);
      brain.reset();
      camera([OrbitFollowComponent(damping: 0.5)]);
      brain.evaluate(world, _dt);
      final (x, y, z) = where();
      expect(late.$1, closeTo(x, 1e-9));
      expect(late.$2, closeTo(y, 1e-9));
      expect(late.$3, closeTo(z, 1e-9));
    });

    test('first person: the camera stays at the last eyes', () {
      final hero = player();
      camera([FirstPersonComponent(eye: Vector3(0, -1.6, 0))]);
      brain.evaluate(world, _dt);
      world.destroyEntity(hero);
      brain.evaluate(world, _dt);
      expect(where(), (2.0, -1.6, 3.0));
    });
  });
}

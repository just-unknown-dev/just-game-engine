// The 3-D camera rigs in a brain: orbit follow, first person and look at;
// stage registries shared by an engine's brains; the rigs' definitions.

import 'dart:math' as math;
import 'dart:ui' show Offset, Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// A world with a 3-D virtual camera following an entity called `Player`.
(World, CameraBrain, Entity camera, Entity player) _rig(
  List<Component> stages, {
  Vector3? at,
}) {
  final world = World()..initialize();
  final player = world.createEntityWithComponents([
    TransformComponent(position: at),
  ], name: 'Player');
  final camera = world.createEntityWithComponents([
    TransformComponent(position: Vector3(0, -3, -8)),
    VirtualCameraComponent(
      follow: const EntityTarget.name('Player'),
      projection: CameraProjection.perspective,
    ),
    ...stages,
  ], name: 'Cam');
  final output = OutputCamera(
    position: Offset.zero,
    viewportSize: const Size(800, 600),
  );
  return (world, CameraBrain(output), camera, player);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('3-D rigs', () {
    test(
      'orbit follow: behind and above the pivot, looking where it is turned',
      () {
        final orbit = OrbitFollowComponent(
          distance: 4,
          pitch: -0.3,
          damping: 0,
        );
        final (world, brain, _, _) = _rig([orbit]);
        brain.evaluate(world, 1 / 60);
        final s = brain.liveState!;
        // Pivot (0, -1.5, 0); forward (0, sin 0.3, cos 0.3) looks down.
        expect(s.position.dx, closeTo(0, 1e-9));
        expect(s.position.dy, closeTo(-1.5 - 4 * math.sin(0.3), 1e-9));
        expect(s.z, closeTo(-4 * math.cos(0.3), 1e-9));
        expect((s.pitch, s.yaw), (-0.3, 0.0));
        // Turned a quarter: the camera swings to -X, looking along +X.
        orbit.yaw = math.pi / 2;
        brain.evaluate(world, 1 / 60);
        expect(brain.liveState!.position.dx, closeTo(-4 * math.cos(0.3), 1e-9));
        expect(brain.liveState!.z, closeTo(0, 1e-9));
      },
    );

    test(
      'orbit follow keeps its pitch and distance in bounds, and eases after the target',
      () {
        final orbit = OrbitFollowComponent(
          distance: 40,
          pitch: -3,
          damping: 0.5,
        );
        final (world, brain, _, player) = _rig([orbit]);
        brain.evaluate(world, 1 / 60);
        expect(brain.liveState!.pitch, orbit.minPitch);
        final first = brain.liveState!;
        final reach = math.sqrt(
          math.pow(first.position.dx, 2) +
              math.pow(first.position.dy + 1.5, 2) +
              math.pow(first.z, 2),
        );
        expect(reach, closeTo(orbit.maxDistance, 1e-9));
        // The target jumps 10 m: the camera follows part of the way.
        player.getComponent<TransformComponent>()!.position.x = 10;
        brain.evaluate(world, 1 / 60);
        final dx = brain.liveState!.position.dx - first.position.dx;
        expect(dx, greaterThan(0));
        expect(dx, lessThan(10));
      },
    );

    test('first person: at the eyes, with its own angles', () {
      final (world, brain, _, _) = _rig([
        FirstPersonComponent(yaw: 1, pitch: 0.2),
      ], at: Vector3(5, 0, 2));
      brain.evaluate(world, 1 / 60);
      final s = brain.liveState!;
      expect((s.position.dx, s.position.dy, s.z), (5.0, -1.7, 2.0));
      expect((s.pitch, s.yaw), (0.2, 1.0));
    });

    test('look at: aims from wherever the camera is', () {
      final (world, brain, _, _) = _rig([LookAtComponent()]);
      brain.evaluate(world, 1 / 60);
      final s = brain.liveState!;
      // From (0, -3, -8) to the origin: down and ahead.
      expect(s.pitch, closeTo(-math.atan2(3, 8), 1e-9));
      expect(s.yaw, closeTo(0, 1e-9));
      final forward = s.forward;
      expect(forward.y, greaterThan(0), reason: '+Y is down');
    });

    test('per frame, the brain follows its target between fixed updates', () {
      final orbit = OrbitFollowComponent(damping: 0);
      final (world, brain, _, player) = _rig([orbit]);
      brain.updateMode = CameraUpdateMode.frame;
      final transform = player.getComponent<TransformComponent>()!;
      brain.sampleTargets(world);
      transform.position.x = 1;
      brain.sampleTargets(world);
      brain.evaluate(world, 1 / 120, alpha: 0.5);
      expect(brain.liveState!.position.dx, closeTo(0.5, 1e-9));
      brain.evaluate(world, 1 / 120, alpha: 1);
      expect(brain.liveState!.position.dx, closeTo(1, 1e-9));
    });
  });

  test('every brain of an engine runs the stages its context holds', () async {
    final engine = Engine();
    await engine.initialize();
    addTearDown(engine.dispose);
    final registries = engine.context.cameraRegistries;
    expect(engine.camera.brain.registries, same(registries));
    // One set per context, made once.
    final other = EngineContext();
    addTearDown(other.dispose);
    expect(other.cameraRegistries, same(other.cameraRegistries));
    expect(other.cameraRegistries, isNot(same(registries)));
    expect(
      registries.stages.stageFor(OrbitFollowComponent()),
      isA<OrbitFollowStage>(),
    );
    // A brain on its own keeps a set of its own.
    final alone = CameraBrain(OutputCamera(position: Offset.zero));
    expect(alone.registries, isNot(same(registries)));
    expect(alone.stages.stageFor(LookAtComponent()), isA<LookAtStage>());
  });

  test('the rigs round-trip through their definitions', () {
    final registry = BuiltInComponents.registry();
    T trip<T extends Component>(T c) =>
        registry.decode(registry.encode(c)!)! as T;
    final orbit = trip(
      OrbitFollowComponent(
        distance: 6,
        yaw: 0.5,
        pitch: -0.2,
        pivot: Vector3(0, -2, 0),
        shoulder: 0.4,
      ),
    );
    expect(
      (orbit.distance, orbit.yaw, orbit.pitch, orbit.pivot.y, orbit.shoulder),
      (6.0, 0.5, -0.2, -2.0, 0.4),
    );
    expect(trip(FirstPersonComponent(eye: Vector3(0, -1.6, 0.1))).eye.z, 0.1);
    expect(trip(LookAtComponent(damping: 0.3)).damping, 0.3);
  });
}

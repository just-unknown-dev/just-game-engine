// What is laid over a framed shot: the level's edges, handheld noise, and
// the things that go bang.

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

const _view = Size(800, 600);
const _dt = 1 / 60;

/// What a kit's own level-bounds component looks like to the camera.
class _KitBounds extends Component implements CameraBoundsSource {
  @override
  Rect cameraBoundsAt(Offset entityPosition) =>
      const Rect.fromLTRB(-1000, -1000, 1000, 1000);
}

T _roundTrip<T extends Component>(T component) =>
    ComponentCodecRegistry.instance.decode(
          ComponentCodecRegistry.instance.encode(component)!,
        )
        as T;

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

  Entity bounds(double width, double height, {Offset centre = Offset.zero}) =>
      at(centre, [
        CameraBoundsComponent(width: width, height: height),
      ], name: 'Level');

  Entity camera(Offset position, List<Component> stages, {double zoom = 1}) =>
      at(position, [
        VirtualCameraComponent(zoom: zoom),
        ...stages,
      ], name: 'Cam');

  group('confiner', () {
    test('keeps the view, not just the centre, inside the bounds', () {
      bounds(2000, 1000);
      camera(const Offset(5000, -5000), [
        CameraConfinerComponent(boundsName: 'Level'),
      ]);
      brain.evaluate(world, _dt);
      // Half the level less half the view, on each axis.
      expect(output.position, const Offset(600, -200));
    });

    test('a closer lens may go nearer the edge', () {
      bounds(2000, 1000);
      camera(const Offset(5000, 0), [
        CameraConfinerComponent(boundsName: 'Level'),
      ], zoom: 2);
      brain.evaluate(world, _dt);
      expect(output.position.dx, 800);
    });

    test('a level smaller than the view is centred, not fought over', () {
      bounds(400, 300, centre: const Offset(50, 60));
      camera(const Offset(999, 999), [
        CameraConfinerComponent(boundsName: 'Level'),
      ]);
      brain.evaluate(world, _dt);
      expect(output.position, const Offset(50, 60));
    });

    test('a camera inside is left alone, as is one naming nothing', () {
      bounds(4000, 4000);
      final cam = camera(const Offset(123, -45), [
        CameraConfinerComponent(boundsName: 'Level'),
      ]);
      brain.evaluate(world, _dt);
      expect(output.position, const Offset(123, -45));

      cam.getComponent<CameraConfinerComponent>()!.boundsName = 'Nowhere';
      cam.getComponent<TransformComponent>()!.position.setValues(9e5, 0, 0);
      brain.evaluate(world, _dt);
      expect(output.position.dx, 9e5);
    });

    test("any component that is a bounds source will do — a kit's, say", () {
      at(Offset.zero, [_KitBounds()], name: 'KitLevel');
      camera(const Offset(5000, 0), [
        CameraConfinerComponent(boundsName: 'KitLevel'),
      ]);
      brain.evaluate(world, _dt);
      expect(output.position.dx, 600);
    });

    test('damping eases into the wall and lets go at once', () {
      bounds(2000, 1000);
      final cam = camera(Offset.zero, [
        CameraConfinerComponent(boundsName: 'Level', damping: 1),
      ]);
      brain.evaluate(world, _dt);
      final transform = cam.getComponent<TransformComponent>()!;
      transform.position.setValues(1000, 0, 0);
      brain.evaluate(world, _dt);
      expect(output.position.dx, greaterThan(600));
      expect(output.position.dx, lessThan(1000));
      for (var i = 0; i < 120; i++) {
        brain.evaluate(world, _dt);
      }
      expect(output.position.dx, closeTo(600, 0.5));

      transform.position.setValues(0, 0, 0);
      brain.evaluate(world, _dt);
      expect(output.position.dx, 0);
    });
  });

  group('noise', () {
    test('moves the shot, the same way every run', () {
      List<Offset> record() {
        final w = World();
        final out = Camera(viewportSize: _view);
        final b = CameraBrain(out);
        w.createEntityWithComponents([
          TransformComponent(),
          VirtualCameraComponent(),
          CameraNoiseComponent(preset: CameraNoisePreset.handheldStrong),
        ]);
        final seen = <Offset>[];
        for (var i = 0; i < 30; i++) {
          b.evaluate(w, _dt);
          seen.add(out.position);
        }
        w.dispose();
        return seen;
      }

      final first = record();
      expect(first.toSet().length, greaterThan(20), reason: 'it moves');
      expect(record(), first, reason: 'and repeats exactly');
    });

    test('is off at zero gain, and still while the game is frozen', () {
      final cam = camera(Offset.zero, [CameraNoiseComponent(amplitudeGain: 0)]);
      brain.evaluate(world, _dt);
      expect(output.position, Offset.zero);

      cam.getComponent<CameraNoiseComponent>()!.amplitudeGain = 1;
      brain.evaluate(world, 0, snap: true);
      expect(output.position, Offset.zero);
      brain.evaluate(world, _dt);
      expect(output.position, isNot(Offset.zero));
    });

    test('is measured in pixels, so a closer lens moves less of the world', () {
      double travel(double zoom) {
        final w = World();
        final out = Camera(viewportSize: _view);
        final b = CameraBrain(out);
        w.createEntityWithComponents([
          TransformComponent(),
          VirtualCameraComponent(zoom: zoom),
          CameraNoiseComponent(),
        ]);
        for (var i = 0; i < 40; i++) {
          b.evaluate(w, _dt);
        }
        w.dispose();
        return out.position.distance;
      }

      expect(travel(2), closeTo(travel(1) / 2, 1e-9));
    });
  });

  group('impulse', () {
    test('a listening camera feels it, and it dies away', () {
      camera(Offset.zero, [CameraImpulseListenerComponent()]);
      brain.evaluate(world, _dt);
      brain.emitImpulse(
        CameraImpulse(position: Offset.zero, amplitude: 20, duration: 0.5),
      );
      brain.evaluate(world, _dt);
      expect(output.position, isNot(Offset.zero));
      expect(output.position.distance, lessThanOrEqualTo(20 * 1.5));

      for (var i = 0; i < 40; i++) {
        brain.evaluate(world, _dt);
      }
      expect(output.position, Offset.zero);
      expect(brain.impulses.activeCount, 0);
    });

    test('a camera without a listener does not', () {
      camera(Offset.zero, const []);
      brain.emitImpulse(CameraImpulse(position: Offset.zero, amplitude: 50));
      brain.evaluate(world, _dt);
      expect(output.position, Offset.zero);
    });

    test('falls off with distance and stops at the radius', () {
      final bus = CameraImpulseBus()
        ..emit(CameraImpulse(position: Offset.zero, amplitude: 10, radius: 100))
        ..update(0.05);
      final near = bus.feltAt(Offset.zero).distance;
      final half = bus.feltAt(const Offset(50, 0)).distance;
      expect(near, greaterThan(0));
      expect(half, closeTo(near / 2, 1e-9));
      expect(bus.feltAt(const Offset(100, 0)), Offset.zero);
    });

    test('is only heard on a channel the listener has', () {
      final bus = CameraImpulseBus()
        ..emit(CameraImpulse(position: Offset.zero, channel: 2))
        ..update(0.05);
      expect(bus.feltAt(Offset.zero, channels: 1), Offset.zero);
      expect(bus.feltAt(Offset.zero, channels: 3), isNot(Offset.zero));
    });

    test('an authored source emits from where its entity is', () {
      final crate = at(const Offset(40, 0), [
        CameraImpulseSourceComponent(amplitude: 30, duration: 1, radius: 200),
      ]);
      expect(brain.emitImpulseFrom(crate), isTrue);
      expect(brain.impulses.activeCount, 1);
      expect(brain.emitImpulseFrom(at(Offset.zero, const [])), isFalse);
    });
  });

  test('every extension component is saved and restored', () {
    ComponentCodecRegistry.instance.clear();
    registerCoreCodecs();

    final confiner = _roundTrip(
      CameraConfinerComponent(boundsName: 'Level', damping: 0.4),
    );
    expect(confiner.boundsName, 'Level');
    expect(confiner.damping, 0.4);

    final level = _roundTrip(CameraBoundsComponent(width: 640, height: 360));
    expect((level.width, level.height), (640, 360));

    final noise = _roundTrip(
      CameraNoiseComponent(
        preset: CameraNoisePreset.shake,
        amplitudeGain: 0.5,
        frequencyGain: 2,
      ),
    );
    expect(noise.preset, CameraNoisePreset.shake);
    expect((noise.amplitudeGain, noise.frequencyGain), (0.5, 2));

    final listener = _roundTrip(
      CameraImpulseListenerComponent(gain: 0.7, channels: 5),
    );
    expect((listener.gain, listener.channels), (0.7, 5));

    final source = _roundTrip(
      CameraImpulseSourceComponent(
        amplitude: 9,
        duration: 0.2,
        radius: 300,
        channel: 4,
      ),
    );
    expect(
      (source.amplitude, source.duration, source.radius, source.channel),
      (9, 0.2, 300, 4),
    );
  });

  test('camera bounds are sized and resized like a shape', () {
    final extent = CameraDefinitions.bounds.extent!;
    final level = CameraBoundsComponent(width: 400, height: 200);
    expect(extent.sizeOf(level), const Size(400, 200));
    expect(extent.scale(level, 2, 0.5), isTrue);
    expect((level.width, level.height), (800, 100));
  });
}

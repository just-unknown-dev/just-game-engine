// Timing record for the transform hot path (3D-readiness work).
//
// The engine's transform gained 3-D rotation, a live hierarchy and camera
// matrices, with the promise that a 2-D game pays nothing for them. These
// benchmarks print ms/frame for the paths that touch every transform every
// frame, so a run before and after a change can be compared. They assert
// only generous ceilings: timing on a shared machine is too noisy for more.

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

double _frameMs(Stopwatch sw, int frames) =>
    sw.elapsedMicroseconds / 1000.0 / frames;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('10k moving shapes: update + render', () {
    final world = World()..initialize();
    addTearDown(world.dispose);
    world
      ..addSystem(MovementSystem())
      ..addSystem(RenderSystem());
    for (var i = 0; i < 10000; i++) {
      world.createEntityWithComponents([
        TransformComponent(
          position: Vector3((i % 100) * 12.0, (i ~/ 100) * 12.0, 0),
        ),
        VelocityComponent(velocity: Vector3(1, 0.5, 0)),
        RectangleComponent(width: 8, height: 8),
      ]);
    }

    const frames = 60;
    const size = ui.Size(1280, 720);
    // Warm up so the JIT settles before timing.
    for (var i = 0; i < 10; i++) {
      world.update(1 / 60);
      final recorder = ui.PictureRecorder();
      world.render(ui.Canvas(recorder), size);
      recorder.endRecording().dispose();
    }
    final sw = Stopwatch()..start();
    for (var i = 0; i < frames; i++) {
      world.update(1 / 60);
      final recorder = ui.PictureRecorder();
      world.render(ui.Canvas(recorder), size);
      recorder.endRecording().dispose();
    }
    sw.stop();
    debugPrint('PERF shapes10k: ${_frameMs(sw, frames).toStringAsFixed(3)} '
        'ms/frame');
    expect(_frameMs(sw, frames), lessThan(1000));
  });

  test('2k physics bodies: step + transform sync', () {
    final physics = PhysicsEngine.pureDart()..initialize();
    addTearDown(physics.dispose);
    physics.setGravity(0, 0);
    final world = World()..initialize();
    addTearDown(world.dispose);
    world.addSystem(PhysicsSystem(physics));
    for (var i = 0; i < 2000; i++) {
      world.createEntityWithComponents([
        TransformComponent(
          position: Vector3((i % 50) * 40.0, (i ~/ 50) * 40.0, 0),
        ),
        PhysicsBodyComponent(shape: CircleShape(4), showDebugOutline: false),
      ]);
    }

    const frames = 60;
    for (var i = 0; i < 10; i++) {
      world.update(1 / 60);
    }
    final sw = Stopwatch()..start();
    for (var i = 0; i < frames; i++) {
      world.update(1 / 60);
    }
    sw.stop();
    debugPrint('PERF physics2k: ${_frameMs(sw, frames).toStringAsFixed(3)} '
        'ms/frame');
    expect(_frameMs(sw, frames), lessThan(2000));
  });
}

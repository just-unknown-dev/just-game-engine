// Animated models in the engine: the player component saved and loaded,
// time moving on (looping or holding), crossfades, skinned drawing from
// an entity, and a socket following a joint.
@Tags(['graphics3d'])
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/graphics_3d.dart';
import 'package:just_graphics_engine/testing.dart';

import 'fixtures.dart';

const _barPath = 'assets/models/bar.glb';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the player and the socket survive a save and a load', () {
    final context = EngineContext(extensions: [Graphics3D()]);
    addTearDown(context.dispose);
    T roundTrip<T extends Component>(T c) =>
        context.definitions.decode(
              jsonDecode(jsonEncode(context.definitions.encode(c))) as Map<String, dynamic>,
            )!
            as T;
    final player = roundTrip(
      AnimationPlayerComponent(clip: 'walk', speed: 1.5, loop: false, playing: false, crossfade: 0.4),
    );
    expect((player.clip, player.speed, player.loop, player.playing, player.crossfade), ('walk', 1.5, false, false, 0.4));
    expect(roundTrip(SocketComponent(node: 'hand.R')).node, 'hand.R');
    for (final c in [AnimationPlayerComponent(), SocketComponent()]) {
      expect(context.definitions.definitionFor(c)!.hints.dimensions, Dimensions.threeD);
    }
  });

  group('in an engine', () {
    late Engine engine;
    late Graphics3D service;
    late NullGpuDevice device;

    setUp(() async {
      device = NullGpuDevice(shaders: rendererNullShaders);
      service = Graphics3D(device: device);
      engine = Engine(
        config: EngineConfig(graphics3D: service),
        context: EngineContext(bundle: TestBundle({_barPath: skinnedBarGlb()})),
      );
      await engine.initialize();
      await service.models.load(_barPath);
    });
    tearDown(() => engine.dispose());

    AnimationSystem3D system() => engine.world.systems.whereType<AnimationSystem3D>().single;

    Entity character(AnimationPlayerComponent player) => engine.world.createEntityWithComponents([
      TransformComponent(),
      ModelComponent(model: _barPath),
      player,
    ], name: 'Bar');

    test('time moves at the speed asked; loops wrap, others hold', () {
      final looping = AnimationPlayerComponent(clip: 'bend', speed: 0.5);
      final once = AnimationPlayerComponent(clip: 'bend', loop: false);
      character(looping);
      character(once);
      for (var i = 0; i < 9; i++) {
        system().update(0.25);
      }
      expect(looping.time, closeTo((9 * 0.25 * 0.5) % 1, 1e-9));
      expect(once.time, 1, reason: 'held at the end');
      expect(looping.previousTime, closeTo((8 * 0.25 * 0.5) % 1, 1e-9));
    });

    test('a new clip fades in over the crossfade, then plays alone', () {
      final player = AnimationPlayerComponent(clip: 'bend', crossfade: 0.5);
      character(player);
      system().update(0.3);
      player.play('hop');
      expect((player.playingClip, player.fadingFrom, player.fade), ('hop', 'bend', 0.0));
      expect(player.clip, 'bend', reason: 'what was authored stays');
      system().update(0.25);
      expect(player.fade, closeTo(0.5, 1e-9));
      system().update(0.25);
      expect(player.fade, 1);
      expect(player.fadingFrom, isEmpty);
      // Asking again for what plays changes nothing; a cut skips the fade.
      player.play('hop');
      expect(player.fade, 1);
      player.play('grow', fade: 0);
      expect((player.fadingFrom, player.fade), ('', 1.0));
    });

    test('an animated entity is drawn skinned, in its pose', () async {
      final player = AnimationPlayerComponent(clip: 'bend', loop: false);
      character(player);
      for (var i = 0; i < 4; i++) {
        system().update(0.25);
      }
      final view = frameView(eye: Vector3(0, -1, -5), target: Vector3(0, -1, 0));
      final renderer = service.sceneRenderer
        ..renderWithoutGpu = true
        ..pixelRatio = 1;
      renderer.render(ui.Canvas(ui.PictureRecorder()), view);
      expect(service.renderer.stats.skinnedInstances, 1);
      final palette = renderer.scene.instances.single.skin!;
      // The tip's joint matrix turns +Y into -X (90° about +Z, glTF axes).
      expect(palette.rows[12 + 1], closeTo(-1, 1e-5));
      // The bounds follow the bent tip (engine -X is left).
      expect(renderer.scene.instances.single.bounds.min.x, lessThan(-0.9));
    });

    test('a socket rides its joint', () async {
      final player = AnimationPlayerComponent(clip: 'hop');
      final bar = character(player);
      final hat = engine.world.createEntityWithComponents([
        TransformComponent(),
        ParentComponent(parentId: bar.id),
        SocketComponent(node: 'tip'),
      ], name: 'Hat');
      bar.getComponent<TransformComponent>()!.position.setValues(3, 0, 0);
      system().update(0.1);
      final at = hat.getComponent<TransformComponent>()!.position;
      // tip is 1 m up the bar (glTF +Y), which is -Y in the engine.
      expect(at.x, closeTo(3, 1e-6));
      expect(at.y, closeTo(-1, 1e-6));
      expect(at.z, closeTo(0, 1e-6));
      // hop lifts the root 0.5 m from half a second in.
      system().update(0.5);
      expect(hat.getComponent<TransformComponent>()!.position.y, closeTo(-1.5, 1e-6));
      // A socket on a turned joint turns with it.
      player.play('bend', fade: 0);
      for (var i = 0; i < 10; i++) {
        system().update(0.1);
      }
      final q = Quaternion.identity();
      hat.getComponent<TransformComponent>()!.rotationInto(q);
      final angle = 2 * math.acos(q.w.abs().clamp(0.0, 1.0));
      expect(angle, closeTo(math.pi / 2, 1e-3));
    });
  });
}

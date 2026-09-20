// The camera brain: which shot is live, how it frames its target, and how
// one shot becomes another. One test per promise the camera makes.

import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

const _view = Size(800, 600);
const _dt = 1 / 60;

class _NudgeComponent extends Component {
  _NudgeComponent(this.by);
  final Offset by;
}

/// What a kit would write: a stage of its own for a component of its own.
class _NudgeStage extends CameraStage<_NudgeComponent> {
  const _NudgeStage();
  @override
  CameraStagePhase get phase => CameraStagePhase.finalize;
  @override
  CameraState apply(
    CameraStageContext context,
    _NudgeComponent component,
    CameraState state,
    double dt,
  ) => state.copyWith(position: state.position + component.by);
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

  Entity camera(
    String name, {
    Offset at = Offset.zero,
    int priority = 10,
    String followTag = '',
    String followName = '',
    double zoom = 1,
    CameraFramingComponent? framing,
    CameraStandbyUpdate standby = CameraStandbyUpdate.never,
    List<Component> extra = const [],
  }) => world.createEntityWithComponents([
    TransformComponent(position: Vector3(at.dx, at.dy, 0)),
    VirtualCameraComponent(
      priority: priority,
      followTag: followTag,
      followName: followName,
      zoom: zoom,
      standbyUpdate: standby,
    ),
    ?framing,
    ...extra,
  ], name: name);

  Entity player({Offset at = Offset.zero, Offset? velocity}) =>
      world.createEntityWithComponents([
        TransformComponent(position: Vector3(at.dx, at.dy, 0)),
        TagComponent('player'),
        if (velocity != null)
          VelocityComponent(velocity: Vector3(velocity.dx, velocity.dy, 0)),
      ], name: 'Player');

  void moveTo(Entity e, Offset to) =>
      e.getComponent<TransformComponent>()!.position.setValues(to.dx, to.dy, 0);

  /// Rigid framing: no damping, so the rules can be read off directly.
  CameraFramingComponent rigid({
    double dead = 0,
    double soft = 2,
    double screenX = 0,
    double screenY = 0,
  }) => CameraFramingComponent(
    screenX: screenX,
    screenY: screenY,
    deadZoneWidth: dead,
    deadZoneHeight: dead,
    softZoneWidth: soft,
    softZoneHeight: soft,
    dampingX: 0,
    dampingY: 0,
  );

  void run(double seconds, {double step = _dt}) {
    for (var t = 0.0; t < seconds - 1e-9; t += step) {
      brain.evaluate(world, step);
    }
  }

  group('which camera is live', () {
    test('with no virtual camera the output is left alone', () {
      output.setPosition(const Offset(12, 34));
      brain.evaluate(world, _dt);
      expect(brain.liveCamera, isNull);
      expect(brain.liveState, isNull);
      expect(output.position, const Offset(12, 34));
    });

    test('the highest priority wins, and a disabled camera never does', () {
      camera('Low', at: const Offset(1, 0), priority: 5);
      final high = camera('High', at: const Offset(2, 0), priority: 50);
      brain.evaluate(world, _dt);
      expect(brain.liveCamera?.name, 'High');
      expect(output.position, const Offset(2, 0));

      high.getComponent<VirtualCameraComponent>()!.enabled = false;
      brain.evaluate(world, _dt);
      expect(brain.liveCamera?.name, 'Low');
    });

    test('between equals, the one activated most recently', () {
      final a = camera('A');
      camera('B');
      brain.evaluate(world, _dt);
      expect(brain.liveCamera?.name, 'B', reason: 'seen last');
      brain.activate(a);
      brain.evaluate(world, _dt);
      expect(brain.liveCamera?.name, 'A');
    });

    test('solo goes live whatever its priority, until it is gone', () {
      final low = camera('Low', priority: 1);
      camera('High', priority: 99);
      brain.soloEntity = low.id;
      brain.evaluate(world, _dt);
      expect(brain.liveCamera?.name, 'Low');

      world.destroyEntity(low);
      brain.evaluate(world, _dt);
      expect(brain.liveCamera?.name, 'High');
      expect(brain.soloEntity, isNull);
    });

    test('driveOutput false thinks without acting', () {
      camera('Main', at: const Offset(300, 0));
      output.setPosition(const Offset(-5, -5));
      brain.driveOutput = false;
      brain.evaluate(world, _dt);
      expect(brain.liveState?.position, const Offset(300, 0));
      expect(output.position, const Offset(-5, -5));
    });

    test('the lens is clamped to what the output allows', () {
      camera('Main', zoom: 500);
      brain.evaluate(world, _dt);
      expect(output.zoom, output.maxZoom);
    });

    test('onCameraActivated reports each change of shot', () {
      final seen = <String>[];
      brain.onCameraActivated = (from, to) =>
          seen.add('${from?.name}->${to.name}');
      camera('A', priority: 1);
      brain.evaluate(world, _dt);
      camera('B', priority: 2);
      brain.evaluate(world, _dt);
      expect(seen, ['null->A', 'A->B']);
    });
  });

  group('framing', () {
    test('the first frame puts the target on its screen spot', () {
      player(at: const Offset(1000, 500));
      camera(
        'Main',
        followTag: 'player',
        framing: rigid(screenX: 0.25, screenY: -0.1),
      );
      brain.evaluate(world, _dt);
      // A quarter of the view right of centre, a tenth above.
      expect(
        output.worldToScreen(const Offset(1000, 500)).dx,
        closeTo(600, 1e-6),
      );
      expect(
        output.worldToScreen(const Offset(1000, 500)).dy,
        closeTo(240, 1e-6),
      );
    });

    test('a target inside the dead zone does not move the camera', () {
      final p = player();
      camera('Main', followTag: 'player', framing: rigid(dead: 0.2));
      brain.evaluate(world, _dt);
      // Dead zone is 0.2 × 800 = 160 wide: 80 either side.
      moveTo(p, const Offset(79, -59));
      brain.evaluate(world, _dt);
      expect(output.position, Offset.zero);

      moveTo(p, const Offset(100, 0));
      brain.evaluate(world, _dt);
      expect(output.position.dx, closeTo(20, 1e-6), reason: 'only the excess');
    });

    test(
      'the target never leaves the soft zone, however heavy the damping',
      () {
        final p = player();
        camera(
          'Main',
          followTag: 'player',
          framing: CameraFramingComponent(
            deadZoneWidth: 0,
            deadZoneHeight: 0,
            softZoneWidth: 0.5,
            softZoneHeight: 0.5,
            dampingX: 30,
            dampingY: 30,
          ),
        );
        brain.evaluate(world, _dt);
        moveTo(p, const Offset(1000, 0));
        brain.evaluate(world, _dt);
        expect(1000 - output.position.dx, closeTo(200, 1), reason: '0.5×800/2');
      },
    );

    test('damping closes 99% of the gap in its time, at any frame rate', () {
      double settle(double step) {
        world.dispose();
        world = World();
        output = Camera(viewportSize: _view);
        brain = CameraBrain(output)..defaultBlend = CameraBlend.cut;
        final p = player();
        camera(
          'Main',
          followTag: 'player',
          framing: CameraFramingComponent(
            deadZoneWidth: 0,
            deadZoneHeight: 0,
            softZoneWidth: 2,
            softZoneHeight: 2,
            dampingX: 0.5,
            dampingY: 0.5,
          ),
        );
        brain.evaluate(world, step);
        moveTo(p, const Offset(100, 0));
        run(0.5, step: step);
        return output.position.dx;
      }

      final at30 = settle(1 / 30);
      final at120 = settle(1 / 120);
      expect(at30, closeTo(99, 0.5));
      expect(at120, closeTo(at30, 0.5));
    });

    test('lookahead leads along the velocity', () {
      player(velocity: const Offset(200, 0));
      camera(
        'Main',
        followTag: 'player',
        framing: CameraFramingComponent(
          deadZoneWidth: 0,
          deadZoneHeight: 0,
          dampingX: 0,
          dampingY: 0,
          lookaheadTime: 0.5,
          lookaheadSmoothing: 0,
        ),
      );
      brain.evaluate(world, _dt);
      expect(output.position.dx, closeTo(100, 1e-6));
    });

    test('an axis that does not follow stays where the camera sits', () {
      player(at: const Offset(500, 500));
      camera(
        'Room',
        at: const Offset(0, 120),
        followTag: 'player',
        framing: rigid()..followY = false,
      );
      brain.evaluate(world, _dt);
      expect(output.position, const Offset(500, 120));
    });

    test(
      'a target that does not exist yet is picked up when it is spawned',
      () {
        camera(
          'Main',
          at: const Offset(7, 7),
          followTag: 'player',
          framing: rigid(),
        );
        brain.evaluate(world, _dt);
        expect(output.position, const Offset(7, 7));
        player(at: const Offset(900, 0));
        brain.evaluate(world, _dt);
        expect(output.position.dx, closeTo(900, 1e-6));
      },
    );

    test('a name is tried before a tag', () {
      player(at: const Offset(10, 0));
      world.createEntityWithComponents([
        TransformComponent(position: Vector3(-400, 0, 0)),
      ], name: 'Boss');
      camera('Main', followName: 'Boss', followTag: 'player', framing: rigid());
      brain.evaluate(world, _dt);
      expect(output.position.dx, -400);
    });
  });

  group('blends', () {
    setUp(
      () => brain.defaultBlend = const CameraBlend(
        duration: 1,
        curve: Curves.linear,
      ),
    );

    test('a blend passes through the middle and ends on the new shot', () {
      camera('A', priority: 1);
      brain.evaluate(world, _dt);
      camera('B', at: const Offset(100, 0), priority: 2, zoom: 4);
      brain.evaluate(world, 0);
      expect(brain.activeBlend, isNotNull);
      brain.evaluate(world, 0.5);
      expect(output.position.dx, closeTo(50, 1e-6));
      expect(
        output.zoom,
        closeTo(2, 1e-6),
        reason: 'zoom blends geometrically',
      );
      brain.evaluate(world, 0.5);
      expect(output.position.dx, 100);
      expect(brain.activeBlend, isNull);
    });

    test('a cut is on screen the same frame', () {
      brain.defaultBlend = CameraBlend.cut;
      camera('A', priority: 1);
      brain.evaluate(world, _dt);
      camera('B', at: const Offset(100, 0), priority: 2);
      brain.evaluate(world, _dt);
      expect(output.position.dx, 100);
    });

    test(
      'the blend table beats the default, the named pair beats a wildcard',
      () {
        brain.blendTable = CameraBlendTable(const [
          CameraBlendRule(to: 'B', blend: CameraBlend(duration: 4)),
          CameraBlendRule(from: 'A', to: 'B', blend: CameraBlend.cut),
        ]);
        camera('A', priority: 1);
        brain.evaluate(world, _dt);
        camera('B', at: const Offset(100, 0), priority: 2);
        brain.evaluate(world, _dt);
        expect(output.position.dx, 100, reason: 'A → B is a cut');
      },
    );

    test('interrupting a blend leaves from what is on screen', () {
      camera('A', priority: 1);
      brain.evaluate(world, _dt);
      camera('B', at: const Offset(100, 0), priority: 2);
      brain.evaluate(world, 0);
      brain.evaluate(world, 0.5);
      final onScreen = output.position;
      camera('C', at: const Offset(0, 300), priority: 3);
      brain.evaluate(world, 0);
      expect(output.position, onScreen, reason: 'no jump');
      brain.evaluate(world, 1);
      expect(output.position, const Offset(0, 300));
    });

    test('losing the live camera blends from the shot it left', () {
      camera('A', priority: 1);
      final b = camera('B', at: const Offset(100, 0), priority: 2);
      brain.evaluate(world, _dt);
      world.destroyEntity(b);
      brain.evaluate(world, 0);
      expect(output.position.dx, 100);
      brain.evaluate(world, 0.5);
      expect(output.position.dx, closeTo(50, 1e-6));
    });

    test('snap skips the blend', () {
      camera('A', priority: 1);
      brain.evaluate(world, _dt);
      camera('B', at: const Offset(100, 0), priority: 2);
      brain.evaluate(world, 0, snap: true);
      expect(output.position.dx, 100);
      expect(brain.activeBlend, isNull);
    });
  });

  group('standby', () {
    test('a camera that was not running starts on its target', () {
      final p = player();
      final far = camera(
        'Far',
        priority: 1,
        followTag: 'player',
        framing: CameraFramingComponent(dampingX: 5, dampingY: 5),
      );
      camera('Main', priority: 2);
      brain.evaluate(world, _dt);
      moveTo(p, const Offset(2000, 0));
      run(0.2);
      brain.soloEntity = far.id;
      brain.evaluate(world, _dt);
      expect(brain.stateOf(far)!.position.dx, closeTo(2000, 1e-6));
    });

    test('an always-on camera is already settled when it goes live', () {
      final p = player();
      final other = camera(
        'Other',
        priority: 1,
        followTag: 'player',
        standby: CameraStandbyUpdate.always,
        framing: rigid(),
      );
      camera('Main', priority: 2);
      brain.evaluate(world, _dt);
      moveTo(p, const Offset(640, 0));
      brain.evaluate(world, _dt);
      expect(brain.stateOf(other)!.position.dx, closeTo(640, 1e-6));
    });
  });

  group('stages', () {
    test("a kit's stage runs for a kit's component", () {
      brain.stages.register(const _NudgeStage());
      camera('Main', extra: [_NudgeComponent(const Offset(0, -40))]);
      brain.evaluate(world, _dt);
      expect(output.position, const Offset(0, -40));
    });

    test('a second stage for one component must say override', () {
      expect(
        () => brain.stages.register(const FramingStage()),
        throwsStateError,
      );
      brain.stages.register(const FramingStage(), override: true);
    });
  });
}

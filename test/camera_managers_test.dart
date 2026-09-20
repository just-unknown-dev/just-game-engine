// Cameras made of cameras, and a camera on rails.

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
    double zoom = 1,
    int priority = 10,
  }) => at(position, [
    VirtualCameraComponent(zoom: zoom, priority: priority),
  ], name: name);

  /// Makes [children] the hierarchy children of [parent].
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

  test("a manager's children are not candidates on their own", () {
    shot('Main', const Offset(-1, 0), priority: 50);
    final rig = at(Offset.zero, [
      VirtualCameraComponent(priority: 5),
      CameraMixerComponent(weights: {'Loud': 1}),
    ], name: 'Rig');
    adopt(rig, [shot('Loud', const Offset(999, 0), priority: 9999)]);

    brain.evaluate(world, _dt);
    expect(brain.liveCamera?.name, 'Main');

    rig.getComponent<VirtualCameraComponent>()!.priority = 60;
    brain.evaluate(world, _dt);
    expect(brain.liveCamera?.name, 'Rig');
    expect(output.position.dx, 999);
  });

  group('state-driven', () {
    late Entity hero;
    late CameraStateDrivenComponent driven;

    setUp(() {
      hero = at(Offset.zero, [
        TagComponent('player'),
        CameraStateComponent(state: 'grounded'),
      ]);
      driven = CameraStateDrivenComponent(
        states: {'grounded': 'Ground', 'falling': 'Fall'},
        defaultChild: 'Ground',
        blend: 1,
      );
      final rig = at(Offset.zero, [
        VirtualCameraComponent(),
        driven,
      ], name: 'Rig');
      adopt(rig, [
        shot('Ground', const Offset(0, 0)),
        shot('Fall', const Offset(0, 400), zoom: 0.5),
      ]);
    });

    void setState(String state) =>
        hero.getComponent<CameraStateComponent>()!.state = state;

    test('shows the child for the state, and blends to the next', () {
      brain.evaluate(world, _dt);
      expect(output.position, Offset.zero);

      setState('falling');
      brain.evaluate(world, 0);
      expect(output.position, Offset.zero, reason: 'the blend starts here');
      run(0.5);
      expect(output.position.dy, inExclusiveRange(100, 300));
      run(0.6);
      expect(output.position.dy, 400);
      expect(output.zoom, 0.5);
    });

    test('an unmapped state, or a missing source, shows the default', () {
      driven.blend = 0;
      setState('falling');
      brain.evaluate(world, _dt);
      expect(output.position.dy, 400);

      setState('swimming');
      brain.evaluate(world, _dt);
      expect(output.position.dy, 0);

      setState('falling');
      world.destroyEntity(hero);
      brain.evaluate(world, _dt);
      expect(output.position.dy, 0);
    });
  });

  group('blend list', () {
    late Entity rig;

    setUp(() {
      rig = at(Offset.zero, [
        VirtualCameraComponent(priority: 20),
        CameraBlendListComponent(
          steps: [
            CameraBlendStep(child: 'Wide', hold: 1, blend: 0),
            CameraBlendStep(child: 'Close', hold: 1, blend: 1),
          ],
        ),
      ], name: 'Cutscene');
      adopt(rig, [
        shot('Wide', const Offset(0, 0)),
        shot('Close', const Offset(200, 0)),
      ]);
    });

    test('holds each shot, blends to the next, and holds the last', () {
      brain.evaluate(world, _dt);
      expect(output.position.dx, 0);
      run(0.9);
      expect(output.position.dx, 0, reason: 'still holding the first');
      run(0.6);
      expect(output.position.dx, inExclusiveRange(0, 200));
      run(1);
      expect(output.position.dx, 200);
      run(5);
      expect(output.position.dx, 200, reason: 'not looping');
    });

    test('loops when asked', () {
      rig.getComponent<CameraBlendListComponent>()!
        ..loop = true
        ..steps[1].blend = 0;
      run(1.5);
      expect(output.position.dx, 200);
      run(1);
      expect(output.position.dx, 0);
    });

    test('starts over each time it goes live', () {
      final main = shot('Main', const Offset(-500, 0), priority: 1);
      run(1.5);
      expect(output.position.dx, greaterThan(0));

      main.getComponent<VirtualCameraComponent>()!.priority = 99;
      brain.evaluate(world, _dt);
      expect(brain.liveCamera?.name, 'Main');

      main.getComponent<VirtualCameraComponent>()!.priority = 1;
      brain.evaluate(world, _dt);
      expect(brain.liveCamera?.name, 'Cutscene');
      expect(output.position.dx, 0, reason: 'back on the first shot');
    });

    test('time stands still while the game is frozen', () {
      brain.evaluate(world, _dt);
      for (var i = 0; i < 200; i++) {
        brain.evaluate(world, 0, snap: true);
      }
      expect(output.position.dx, 0);
    });
  });

  test('a mixer shows every weighted child at once', () {
    final rig = at(Offset.zero, [
      VirtualCameraComponent(),
      CameraMixerComponent(weights: {'A': 1, 'B': 3, 'Off': 0}),
    ]);
    adopt(rig, [
      shot('A', const Offset(0, 0), zoom: 1),
      shot('B', const Offset(400, 0), zoom: 16),
      shot('Off', const Offset(-9999, 0)),
    ]);
    brain.evaluate(world, _dt);
    expect(output.position.dx, closeTo(300, 1e-9));
    // Lenses mix geometrically: 1^(1/4) × 16^(3/4) = 8, clamped to the output.
    expect(brain.liveState!.zoom, closeTo(8, 1e-9));
  });

  test("a manager's own stages apply to whichever child shows", () {
    at(Offset.zero, [
      CameraBoundsComponent(width: 1000, height: 800),
    ], name: 'Level');
    final rig = at(Offset.zero, [
      VirtualCameraComponent(),
      CameraMixerComponent(weights: {'Far': 1}),
      CameraConfinerComponent(boundsName: 'Level'),
    ]);
    adopt(rig, [shot('Far', const Offset(5000, 0))]);
    brain.evaluate(world, _dt);
    expect(output.position.dx, 100, reason: '500 − half the 800 view');
  });

  test("a kit's manager runs for a kit's component", () {
    brain.managers.register(const _FirstChildManager());
    final rig = at(Offset.zero, [VirtualCameraComponent(), _KitRig()]);
    adopt(rig, [shot('Only', const Offset(77, 0))]);
    brain.evaluate(world, _dt);
    expect(output.position.dx, 77);
    expect(
      () => brain.managers.register(const MixerManager()),
      throwsStateError,
    );
  });

  group('dolly', () {
    const track = [Offset(0, 0), Offset(400, 0), Offset(400, 400)];

    test('a fixed position is measured along the length', () {
      at(const Offset(-50, -50), [
        VirtualCameraComponent(),
        CameraDollyComponent(
          waypoints: track,
          autoDolly: false,
          pathPosition: 0.75,
        ),
      ]);
      brain.evaluate(world, _dt);
      expect(output.position, const Offset(400, 200));
    });

    test('auto dolly rides to the point nearest the target', () {
      final hero = at(const Offset(100, -300), [TagComponent('player')]);
      at(Offset.zero, [
        VirtualCameraComponent(followTag: 'player'),
        CameraDollyComponent(waypoints: track, damping: 0),
      ]);
      brain.evaluate(world, _dt);
      expect(output.position, const Offset(100, 0));

      hero.getComponent<TransformComponent>()!.setPositionXY(900, 250);
      brain.evaluate(world, _dt);
      expect(output.position, const Offset(400, 250));
    });

    test('damping eases along the track', () {
      final hero = at(Offset.zero, [TagComponent('player')]);
      at(Offset.zero, [
        VirtualCameraComponent(followTag: 'player'),
        CameraDollyComponent(waypoints: track, damping: 1),
      ]);
      brain.evaluate(world, _dt);
      hero.getComponent<TransformComponent>()!.setPositionXY(400, 0);
      brain.evaluate(world, _dt);
      expect(output.position.dx, inExclusiveRange(0, 400));
      expect(output.position.dy, 0, reason: 'it stays on the rails');
    });

    test('a closed track joins its ends; a short one is ignored', () {
      const square = [
        Offset(0, 0),
        Offset(100, 0),
        Offset(100, 100),
        Offset(0, 100),
      ];
      final path = DollyPath(square, closed: true);
      expect(path.length, 400);
      expect(path.pointAt(0.875), const Offset(0, 50));
      expect(path.nearestTo(const Offset(-40, 50)), closeTo(0.875, 1e-9));

      at(const Offset(5, 6), [
        VirtualCameraComponent(),
        CameraDollyComponent(waypoints: const [Offset(1, 1)]),
      ]);
      brain.evaluate(world, _dt);
      expect(output.position, const Offset(5, 6));
    });
  });

  test('managers, state and dolly are saved and restored', () {
    ComponentCodecRegistry.instance.clear();
    registerCoreCodecs();

    final driven = _roundTrip(
      CameraStateDrivenComponent(
        sourceName: 'Hero',
        sourceTag: '',
        states: {'a': 'A', 'b': 'B'},
        defaultChild: 'A',
        blend: 0.25,
      ),
    );
    expect((driven.sourceName, driven.sourceTag), ('Hero', ''));
    expect(driven.states, {'a': 'A', 'b': 'B'});
    expect((driven.defaultChild, driven.blend), ('A', 0.25));

    expect(_roundTrip(CameraStateComponent(state: 'boss')).state, 'boss');

    final list = _roundTrip(
      CameraBlendListComponent(
        steps: [CameraBlendStep(child: 'Wide', hold: 2, blend: 0.75)],
        loop: true,
      ),
    );
    expect(list.loop, isTrue);
    expect(list.steps.single.toJson(), {
      'child': 'Wide',
      'hold': 2.0,
      'blend': 0.75,
    });

    expect(_roundTrip(CameraMixerComponent(weights: {'A': 0.5})).weights, {
      'A': 0.5,
    });

    final dolly = _roundTrip(
      CameraDollyComponent(
        waypoints: const [Offset(1, 2), Offset(3, 4)],
        closed: true,
        autoDolly: false,
        pathPosition: 0.4,
        damping: 2,
      ),
    );
    expect(dolly.waypoints, const [Offset(1, 2), Offset(3, 4)]);
    expect((dolly.closed, dolly.autoDolly), (true, false));
    expect((dolly.pathPosition, dolly.damping), (0.4, 2));
  });
}

class _KitRig extends Component {}

class _FirstChildManager extends CameraManager<_KitRig> {
  const _FirstChildManager();
  @override
  CameraState? evaluate(CameraManagerContext context, _KitRig component) =>
      context.children.isEmpty ? null : context.stateOf(context.children.first);
}

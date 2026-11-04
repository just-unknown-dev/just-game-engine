// RenderSystem's draw list (RenderQueue): ties drawn in the order entities
// were made in, whatever happens to the archetype rows; kept up to date as
// things come and go, always the same list one built from scratch would
// be. Also: painters interpolated and ordered the same way, flipped sprites
// batched, a per-entity shader given the clock, and a post-process pass
// switched off with its component.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// Draws nothing; sorts by its own layer when the entity has no
/// LayerComponent.
class _Blank extends Renderable {
  _Blank({super.layer});

  @override
  void render(Canvas canvas, Size size) {}

  @override
  Rect? get bounds => null;
}

class _Item extends RenderItem {
  _Item(this.layer);

  @override
  final int layer;

  @override
  void render(Canvas canvas, RenderContext context, Entity owner) {}
}

/// Captures the previous pose of the transforms in [next] in the coming
/// update, as a fixed step does.
class _Captures extends System {
  final Set<TransformComponent> next = {};

  @override
  List<Type> get requiredComponents => const [];

  @override
  void update(double deltaTime) {
    for (final t in next) {
      t.capturePrevious();
    }
    next.clear();
  }
}

/// A component painted by [_LabelPainter].
class _Label extends Component {
  _Label(this.name);
  final String name;
  int layer = 0;
}

/// Logs each label painted, with where the canvas put its origin.
class _LabelPainter extends ComponentPainter<_Label> {
  final List<(String, Offset)> painted = [];

  @override
  int layerOf(_Label c) => c.layer;

  @override
  void paint(Canvas canvas, Entity e, _Label c, RenderContext ctx) {
    final m = canvas.getTransform();
    painted.add((c.name, Offset(m[12], m[13])));
  }
}

Future<ui.Image> _image(int w, int h) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    Paint()..color = const Color(0xFFFF0000),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(w, h);
  picture.dispose();
  return image;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ties', () {
    late World world;
    late RenderSystem render;

    setUp(() {
      world = World()..initialize();
      render = RenderSystem(passes: const []);
      world.addSystem(render);
    });
    tearDown(() => world.dispose());

    List<int> order() => [for (final (e, _) in render.debugDrawOrder()) e.id];

    test('keep their order when an unrelated entity is destroyed', () {
      final a = world.createEntityWithComponents([
        TransformComponent(),
        RenderableComponent(renderable: _Blank()),
      ]);
      final b = world.createEntityWithComponents([
        TransformComponent(),
        RenderableComponent(renderable: _Blank()),
      ]);
      final c = world.createEntityWithComponents([
        TransformComponent(),
        RenderableComponent(renderable: _Blank()),
      ]);
      expect(order(), [a.id, b.id, c.id]);
      // c moves into a's row of the archetype.
      world.destroyEntity(a);
      expect(order(), [
        b.id,
        c.id,
      ], reason: 'the last one used to jump in front of the others');
    });

    test('draw in the order entities were made, whatever their archetype', () {
      final first = world.createEntityWithComponents([
        TransformComponent(),
        RenderableComponent(renderable: _Blank()),
        VelocityComponent(),
      ]);
      final second = world.createEntityWithComponents([
        TransformComponent(),
        RenderableComponent(renderable: _Blank()),
      ]);
      final third = world.createEntityWithComponents([
        TransformComponent(),
        RenderableComponent(renderable: _Blank()),
        VelocityComponent(),
      ]);
      expect(order(), [first.id, second.id, third.id]);
      // A component added moves `second` to another archetype: its place
      // holds.
      second.addComponent(VelocityComponent());
      expect(order(), [first.id, second.id, third.id]);
    });

    test("an entity's renderable comes before its items, in list order", () {
      final items = [_Item(0), _Item(0)];
      final e = world.createEntityWithComponents([
        TransformComponent(),
        RenderableComponent(renderable: _Blank()),
        RenderItemsComponent(items),
      ]);
      expect(render.debugDrawOrder(), [
        (e, null),
        (e, items[0]),
        (e, items[1]),
      ]);
    });
  });

  test('kept up to date, the list is the one built from scratch', () {
    final world = World()..initialize();
    addTearDown(world.dispose);
    final render = RenderSystem(passes: const []);
    world.addSystem(render);
    final random = math.Random(7);
    final live = <Entity>[];
    for (var step = 0; step < 300; step++) {
      final roll = random.nextInt(10);
      if (roll < 4 || live.isEmpty) {
        live.add(
          world.createEntityWithComponents([
            TransformComponent(),
            RenderableComponent(renderable: _Blank(layer: random.nextInt(3))),
            if (random.nextBool()) LayerComponent(layer: random.nextInt(3)),
            if (random.nextBool()) VelocityComponent(),
            if (random.nextInt(4) == 0)
              RenderItemsComponent([
                for (var i = random.nextInt(3); i > 0; i--)
                  _Item(random.nextInt(3)),
              ]),
          ]),
        );
      } else if (roll < 7) {
        world.destroyEntity(live.removeAt(random.nextInt(live.length)));
      } else if (roll < 8) {
        final e = live[random.nextInt(live.length)];
        e.isActive = !e.isActive;
      } else {
        final e = live[random.nextInt(live.length)];
        if (e.hasComponent<VelocityComponent>()) {
          e.removeComponent<VelocityComponent>();
        } else {
          e.addComponent(VelocityComponent());
        }
      }
      if (step % 3 == 0) {
        final kept = render.debugDrawOrder();
        final fresh = RenderSystem(passes: const []);
        world.addSystem(fresh);
        expect(kept, fresh.debugDrawOrder(), reason: 'step $step');
        world.removeSystem(fresh);
      }
    }
  });

  group('painters', () {
    late World world;
    late _LabelPainter painter;
    late RenderSystem render;

    setUp(() {
      painter = _LabelPainter();
      world = World()..initialize();
      final registry = ComponentDefinitionRegistry()
        ..register(
          ComponentDefinition<_Label>(
            type: 'Label',
            create: () => _Label('x'),
            fields: const [],
            painter: painter,
          ),
        );
      render = RenderSystem(
        passes: [ComponentPainterPass(definitions: registry)],
      );
      world.addSystem(render);
    });
    tearDown(() => world.dispose());

    void frame() => world.render(Canvas(ui.PictureRecorder()), Size.zero);

    test('keep their order when an unrelated entity is destroyed', () {
      final a = world.createEntityWithComponents([
        TransformComponent(),
        _Label('a'),
      ]);
      world.createEntityWithComponents([TransformComponent(), _Label('b')]);
      world.createEntityWithComponents([TransformComponent(), _Label('c')]);
      frame();
      expect(painter.painted.map((p) => p.$1), ['a', 'b', 'c']);
      world.destroyEntity(a);
      painter.painted.clear();
      frame();
      expect(painter.painted.map((p) => p.$1), ['b', 'c']);
    });

    test('are painted between two poses a fixed step captured', () {
      final e = world.createEntityWithComponents([
        TransformComponent(position: Vector3(10, 0, 0)),
        _Label('a'),
      ]);
      frame();
      e.getComponent<TransformComponent>()!
        ..capturePrevious()
        ..position.setValues(30, 0, 0);
      world.update(1 / 60);
      render.interpolation = 0.5;
      painter.painted.clear();
      frame();
      expect(
        painter.painted.single.$2,
        const Offset(20, 0),
        reason: 'a label on a moving body used to jitter against it',
      );
      world.update(1 / 60);
      painter.painted.clear();
      frame();
      expect(painter.painted.single.$2, const Offset(30, 0));
    });
  });

  test('seen first, a transform is drawn between its poses only when the '
      'latest update captured it', () {
    final world = World()..initialize();
    addTearDown(world.dispose);
    // No physics: a transform a system captured in the latest update, one
    // captured an update before, and one never captured.
    final now = TransformComponent(position: Vector3(30, 0, 0));
    final before = TransformComponent(position: Vector3(30, 0, 0));
    final never = TransformComponent(position: Vector3(30, 0, 0));
    final entities = [
      for (final t in [now, before, never])
        world.createEntityWithComponents([
          t,
          RenderableComponent(renderable: _Blank()),
        ]),
    ];
    final steps = _Captures();
    world.addSystem(steps);
    steps.next.add(before);
    world.update(1 / 60);
    steps.next.add(now);
    world.update(1 / 60);
    for (final t in [now, before, never]) {
      t.prevPosition.setValues(10, 0, 0);
    }
    expect(now.capturedInUpdate, world.updateCount);

    final render = RenderSystem(passes: const [])..interpolation = 0.5;
    world.addSystem(render);
    world.render(Canvas(ui.PictureRecorder()), const Size(100, 100));
    double drawnAt(Entity e) =>
        e.getComponent<RenderableComponent>()!.renderable.position.x;
    expect(drawnAt(entities[0]), 20);
    expect(drawnAt(entities[1]), 30);
    expect(drawnAt(entities[2]), 30);
  });

  test('flipped sprites batch with the others', () async {
    final image = await _image(4, 4);
    addTearDown(image.dispose);
    final world = World()..initialize();
    addTearDown(world.dispose);
    final render = RenderSystem(passes: const []);
    world.addSystem(render);
    for (var i = 0; i < 10; i++) {
      world.createEntityWithComponents([
        TransformComponent(position: Vector3(i * 5.0, 0, 0)),
        RenderableComponent(
          renderable: Sprite(image: image, flipX: i.isOdd),
        ),
      ]);
    }
    world.render(Canvas(ui.PictureRecorder()), const Size(100, 100));
    expect(render.stats['batchedSprites'], 10);
    expect(
      render.stats['drawCalls'],
      1,
      reason: 'each flipped sprite used to be drawn by itself, between batches',
    );
  });

  group('shaders', () {
    late ui.FragmentProgram program;
    setUpAll(() async {
      program = await ui.FragmentProgram.fromAsset('shaders/ink_sparkle.frag');
    });
    tearDown(ShaderFilterSupport.debugReset);

    test("a per-entity shader is given the render system's clock", () {
      // Claimed supported, so the shader path runs; the test renderer cannot
      // filter with a shader, and throws once the uniforms are set.
      ShaderFilterSupport.debugSupportedOverride = true;
      final world = World()..initialize();
      addTearDown(world.dispose);
      world.addSystem(RenderSystem(passes: const [], clock: () => 12.5));
      double? time;
      world.createEntityWithComponents([
        TransformComponent(),
        RenderableComponent(renderable: _Blank()),
        ShaderComponent(
          program: program,
          setUniforms: (shader, w, h, t) => time = t,
        ),
      ]);
      try {
        world.render(Canvas(ui.PictureRecorder()), const Size(10, 10));
      } on Object {
        // The filter itself: not what is tested.
      }
      expect(time, 12.5, reason: 'it was always given 0');
    });

    test('a removed post-process component switches its pass off at once', () {
      final rendering = RenderingEngine()
        ..camera = OutputCamera(viewportSize: const Size(10, 10));
      rendering.initialize();
      final world = World()..initialize();
      addTearDown(world.dispose);
      world.addSystem(PostProcessSystem(rendering));
      final entity = world.createEntityWithComponents([
        ShaderComponent(program: program, isPostProcess: true),
      ]);
      world.update(1 / 60);
      final pass = rendering.postProcessPasses.single;
      expect(pass.enabled, isTrue);

      // No update before the next frame: paused, say.
      entity.removeComponent<ShaderComponent>();
      expect(
        pass.enabled,
        isFalse,
        reason: 'it used to draw with the disposed shader until an update',
      );
      world.update(1 / 60);
      expect(rendering.postProcessPasses, isEmpty);
    });
  });
}

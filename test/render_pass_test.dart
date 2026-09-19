import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

class Blob extends Component {
  int layer = 0;
}

class BlobPainter extends ComponentPainter<Blob> {
  final calls = <(Entity, Offset)>[];
  @override
  int layerOf(Blob c) => c.layer;
  @override
  void paint(Canvas canvas, Entity e, Blob c, RenderContext ctx) {
    final m = canvas.getTransform();
    calls.add((e, Offset(m[12], m[13])));
  }
}

class _Plugin extends EnginePlugin {
  _Plugin(this.id);
  @override
  final String id;
  final updates = <double>[];
  bool detached = false;
  @override
  void update(double dt) => updates.add(dt);
  @override
  void detach() => detached = true;
}

void main() {
  test(
    'a component with a painter is drawn at its transform, in layer order',
    () {
      final painter = BlobPainter();
      final registry = ComponentDefinitionRegistry()
        ..register(
          ComponentDefinition<Blob>(
            type: 'Blob',
            create: Blob.new,
            fields: const [],
            painter: painter,
          ),
        );
      final world = World()..initialize();
      addTearDown(world.dispose);
      world
        ..createEntityWithComponents([
          TransformComponent(position: Vector3(10, 20, 0)),
          Blob()..layer = 5,
        ], name: 'back')
        ..createEntityWithComponents([
          TransformComponent(position: Vector3(30, 40, 0)),
          Blob()..layer = 1,
        ], name: 'front')
        ..addSystem(
          RenderSystem(passes: [ComponentPainterPass(definitions: registry)]),
        );

      world.render(Canvas(PictureRecorder()), const Size(800, 600));

      expect(painter.calls.map((c) => c.$1.name), [
        'front',
        'back',
      ], reason: 'lower layer draws first');
      expect(painter.calls[0].$2, const Offset(30, 40));
      expect(painter.calls[1].$2, const Offset(10, 20));
    },
  );

  test('render hooks run in order and can be removed', () {
    final chain = RenderHookChain();
    final log = <String>[];
    void a(Canvas c, Size s) => log.add('a');
    void b(Canvas c, Size s) => log.add('b');
    chain
      ..add(b, order: 10)
      ..add(a)
      ..addIfAbsent(a);
    chain(Canvas(PictureRecorder()), Size.zero);
    expect(log, ['a', 'b']);
    chain.remove(a);
    expect(chain.contains(a), isFalse);
    expect(chain.length, 1);
  });

  test('the plugin host forwards updates and replaces by id', () async {
    Engine.resetInstance();
    final host = PluginHost(Engine());
    final first = _Plugin('p');
    final second = _Plugin('p');
    await host.register(first);
    await host.register(second);
    expect(first.detached, isTrue, reason: 'replaced by id');
    host.update(0.5);
    expect(second.updates, [0.5]);
    expect(first.updates, isEmpty);
    host.unregister('p');
    expect(second.detached, isTrue);
    expect(host.all, isEmpty);
    Engine.resetInstance();
  });
}

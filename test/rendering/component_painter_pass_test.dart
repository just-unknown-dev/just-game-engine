// ComponentPainterPass: components that draw themselves.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

class Blob extends Component {
  int layer = 0;
}

class _BlobPainter extends ComponentPainter<Blob> {
  final List<String> names = [];
  @override
  int layerOf(Blob c) => c.layer;
  @override
  void paint(Canvas canvas, Entity e, Blob c, RenderContext ctx) =>
      names.add(e.name!);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ComponentPainterPass', () {
    late World world;
    late _BlobPainter painter;
    late ComponentDefinitionRegistry registry;

    setUp(() {
      painter = _BlobPainter();
      registry = ComponentDefinitionRegistry()
        ..register(
          ComponentDefinition<Blob>(
            type: 'Blob',
            create: Blob.new,
            fields: const [],
            painter: painter,
          ),
        );
      world = World()..initialize();
      world.addSystem(
        RenderSystem(passes: [ComponentPainterPass(definitions: registry)]),
      );
    });
    tearDown(() => world.dispose());

    List<String> frame() {
      painter.names.clear();
      world.render(Canvas(ui.PictureRecorder()), const Size(100, 100));
      return List.of(painter.names);
    }

    Entity blob(String name, int layer) => world.createEntityWithComponents([
      TransformComponent(),
      Blob()..layer = layer,
    ], name: name);

    test('keeps its order between frames, and follows changes', () {
      final a = blob('a', 1);
      blob('b', 2);
      expect(frame(), ['a', 'b']);
      a.getComponent<Blob>()!.layer = 3;
      expect(frame(), ['b', 'a']);
      final c = blob('c', 0);
      expect(frame(), ['c', 'b', 'a']);
      c.isActive = false;
      expect(frame(), ['b', 'a']);
    });

    test('equal layers paint in the order found, every frame', () {
      for (var i = 0; i < 40; i++) {
        blob('e$i', i % 2);
      }
      final first = frame();
      expect(first.take(20), [for (var i = 0; i < 40; i += 2) 'e$i']);
      expect(frame(), first);
    });

    test('an unturned, unscaled entity gets only a translation', () {
      blob('a', 0);
      final canvas = TestRecordingCanvas();
      world.render(canvas, const Size(100, 100));
      expect(
        [for (final i in canvas.invocations) i.invocation.memberName],
        [#save, #translate, #restore],
      );
    });
  });
}

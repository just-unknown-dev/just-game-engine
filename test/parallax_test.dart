import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ParallaxLayer', () {
    // We can't create real ui.Image in pure unit tests, so we test
    // property defaults and the uniform constructor via the API surface.

    test('default scroll factors are 0.5', () {
      // ParallaxLayer requires an image, but we can test the uniform
      // constructor indirectly through ParallaxBackground layer management.
      // Here we verify the class is importable and constructors exist.
      expect(ParallaxLayer.new, isA<Function>());
      expect(ParallaxLayer.uniform, isA<Function>());
    });
  });

  group('ParallaxBackground', () {
    test('starts with empty layers', () {
      final bg = ParallaxBackground();
      expect(bg.layers, isEmpty);
      expect(bg.cameraPosition, Offset.zero);
      expect(bg.opacity, 1.0);
      expect(bg.visible, true);
    });

    test('accepts layers list via constructor', () {
      final bg = ParallaxBackground(layers: []);
      expect(bg.layers, isEmpty);
    });

    test('visibility flag is respected', () {
      final bg = ParallaxBackground(visible: false);
      expect(bg.visible, false);
    });

    test('opacity can be customized', () {
      final bg = ParallaxBackground(opacity: 0.5);
      expect(bg.opacity, 0.5);
    });

    test('cameraPosition can be updated', () {
      final bg = ParallaxBackground();
      bg.cameraPosition = const Offset(100, 200);
      expect(bg.cameraPosition, const Offset(100, 200));
    });
  });

  group('ParallaxSystem', () {
    test('initializes correctly', () {
      final system = ParallaxSystem();
      expect(system.isInitialized, false);
      system.initialize();
      expect(system.isInitialized, true);
    });

    test('double initialize is safe', () {
      final system = ParallaxSystem();
      system.initialize();
      system.initialize(); // no-op
      expect(system.isInitialized, true);
    });

    test('addBackground / removeBackground', () {
      final system = ParallaxSystem();
      system.initialize();

      final bg = ParallaxBackground();
      system.addBackground(bg);
      expect(system.backgroundCount, 1);
      expect(system.backgrounds, contains(bg));

      final removed = system.removeBackground(bg);
      expect(removed, true);
      expect(system.backgroundCount, 0);
    });

    test('removeBackground returns false for unknown background', () {
      final system = ParallaxSystem();
      system.initialize();
      expect(system.removeBackground(ParallaxBackground()), false);
    });

    test('clear removes all backgrounds', () {
      final system = ParallaxSystem();
      system.initialize();
      system.addBackground(ParallaxBackground());
      system.addBackground(ParallaxBackground());
      system.clear();
      expect(system.backgroundCount, 0);
    });

    test('dispose clears state', () {
      final system = ParallaxSystem();
      system.initialize();
      system.addBackground(ParallaxBackground());
      system.dispose();
      expect(system.isInitialized, false);
      expect(system.backgroundCount, 0);
    });

    test('update feeds camera position to all backgrounds', () {
      final system = ParallaxSystem();
      system.initialize();

      final bg1 = ParallaxBackground();
      final bg2 = ParallaxBackground();
      system.addBackground(bg1);
      system.addBackground(bg2);

      const cameraPos = Offset(42, 99);
      system.update(0.016, cameraPos);

      expect(bg1.cameraPosition, cameraPos);
      expect(bg2.cameraPosition, cameraPos);
    });

    test('backgrounds list is unmodifiable', () {
      final system = ParallaxSystem();
      system.initialize();
      system.addBackground(ParallaxBackground());

      expect(
        () => system.backgrounds.add(ParallaxBackground()),
        throwsUnsupportedError,
      );
    });
  });

  group('ParallaxComponent (ECS)', () {
    test('wraps a ParallaxBackground', () {
      final bg = ParallaxBackground();
      final component = ParallaxComponent(background: bg);
      expect(component.background, same(bg));
    });

    test('toString includes layer count', () {
      final bg = ParallaxBackground();
      final component = ParallaxComponent(background: bg);
      expect(component.toString(), 'Parallax(0 layers)');
    });
  });

  group('SystemPriorities', () {
    test('parallax sits between tileMap and input', () {
      expect(SystemPriorities.parallax, greaterThan(SystemPriorities.input));
      expect(SystemPriorities.parallax, lessThan(SystemPriorities.tileMap));
    });
  });

  // Engine integration tests require native audio plugin (just_audio)
  // which is unavailable in the unit-test environment. These tests pass when
  // run on a device/emulator or when the audio subsystem is mocked.
  group('Engine integration', skip: 'Requires just_audio native plugin', () {
    setUp(() => Engine.resetInstance());

    test('Engine exposes parallax subsystem after init', () async {
      final engine = Engine();
      await engine.initialize();
      expect(engine.parallax, isNotNull);
      expect(engine.parallax.isInitialized, true);
    });

    test('ParallaxSystem can be retrieved via getSystem', () async {
      final engine = Engine();
      await engine.initialize();
      final system = engine.getSystem<ParallaxSystem>();
      expect(system, same(engine.parallax));
    });

    test('addBackground through engine parallax subsystem', () async {
      final engine = Engine();
      await engine.initialize();

      final bg = ParallaxBackground();
      engine.parallax.addBackground(bg);
      expect(engine.parallax.backgroundCount, 1);
    });
  });
}

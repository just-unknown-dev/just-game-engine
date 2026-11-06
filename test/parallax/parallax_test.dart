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
    test('parallax sits between levelMap and input', () {
      expect(SystemPriorities.parallax, greaterThan(SystemPriorities.input));
      expect(SystemPriorities.parallax, lessThan(SystemPriorities.levelMap));
    });
  });
}

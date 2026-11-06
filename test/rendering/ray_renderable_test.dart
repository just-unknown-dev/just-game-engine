// RayRenderable: a permanent ray never expires.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  group('RayRenderable', () {
    test('a permanent beam never expires', () {
      final ray = RayRenderable(
        start: Offset.zero,
        end: const Offset(10, 0),
        lifetime: 0,
      );
      expect(ray.isExpired, isFalse, reason: 'it expired at once');
      ray.update(100);
      expect(ray.isExpired, isFalse);
      expect(ray.opacity, 1.0);
    });

    test('a fading one expires after its lifetime', () {
      final ray = RayRenderable(start: Offset.zero, end: const Offset(1, 0));
      expect(ray.isExpired, isFalse);
      ray.update(0.3);
      expect(ray.isExpired, isTrue);
    });
  });
}

// Nothing one camera brain does leaks into another: impulses.

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  group('camera impulses', () {
    Offset shakeOf(CameraBrain brain) {
      brain.emitImpulse(
        CameraImpulse(position: Offset.zero, amplitude: 20, duration: 1),
      );
      brain.impulses.update(0.1);
      return brain.impulses.feltAt(Offset.zero);
    }

    test('after brain.reset() impulses replay identically', () {
      final brain = CameraBrain(Camera(viewportSize: const Size(800, 600)));
      final first = shakeOf(brain);
      final second = shakeOf(brain); // A second impulse on top: different.
      expect(second, isNot(first));

      brain.reset();
      expect(shakeOf(brain), first);
    });

    test('two brains shake the same way for the same impulses', () {
      final a = CameraBrain(Camera(viewportSize: const Size(800, 600)));
      final b = CameraBrain(Camera(viewportSize: const Size(800, 600)));
      shakeOf(a);
      shakeOf(a);
      // b has seen nothing yet; its first impulse is a's first, not its third.
      final fresh = CameraBrain(Camera(viewportSize: const Size(800, 600)));
      expect(shakeOf(b), shakeOf(fresh));
    });
  });
}

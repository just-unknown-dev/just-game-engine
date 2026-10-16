// Dynamic resolution: fewer pixels while frames run slow, more when fast.
@Tags(['graphics3d'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/graphics_3d.dart';

void main() {
  test('slow seconds step the scale down, fast ones back up, within bounds', () {
    final d = DynamicResolution(enabled: true, minScale: 0.6);
    void second(double frameSeconds) {
      for (var t = 0.0; t < 1.0; t += frameSeconds) {
        d.frame(frameSeconds);
      }
    }

    expect(d.scale, 1.0);
    second(1 / 40);
    expect(d.scale, closeTo(0.9, 1e-9));
    for (var i = 0; i < 10; i++) {
      second(1 / 40);
    }
    expect(d.scale, closeTo(0.6, 1e-9), reason: 'held at its minimum');
    second(1 / 60);
    expect(d.scale, closeTo(0.6, 1e-9), reason: 'on target: no change');
    second(1 / 120);
    expect(d.scale, closeTo(0.7, 1e-9));
    d.enabled = false;
    expect(d.scale, 1.0);
  });
}

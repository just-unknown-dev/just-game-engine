// The 2-D joints' definitions offer only what the physics backends take:
// the anchors a distance, fixed or slider joint cannot use are hidden — but
// still saved — and a wheel shows its axle.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  test('distance, fixed and slider joints hide the anchors', () {
    for (final definition in [
      Physics2DDefinitions.distanceJoint,
      Physics2DDefinitions.fixedJoint,
      Physics2DDefinitions.sliderJoint,
    ]) {
      final hints = definition.hints.fields;
      for (final name in ['anchor', 'connectedAnchor']) {
        expect(
          hints[name]?.visible,
          isFalse,
          reason: '${definition.type}.$name',
        );
      }
      expect(hints['collideConnected']?.visible, isTrue);
    }
  });

  test('a wheel shows its axle, not the other anchor', () {
    final hints = Physics2DDefinitions.wheelJoint.hints.fields;
    expect(hints['connectedAnchor']?.visible, isTrue);
    expect(hints['connectedAnchor']?.label, 'Axle');
    expect(hints['anchor']?.visible, isFalse);
  });

  test('a hidden anchor is still saved and loaded', () {
    final definition = Physics2DDefinitions.fixedJoint;
    final json = definition.encode(
      FixedJoint2DComponent(
        anchor: const Offset(3, 4),
        connectedAnchor: const Offset(-1, 2),
      ),
    );
    final back = definition.decode(json);
    expect(back.anchor, const Offset(3, 4));
    expect(back.connectedAnchor, const Offset(-1, 2));
  });
}

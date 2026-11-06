// The 2-D joints' definitions offer the anchors each joint takes — a
// distance joint both, a fixed joint its own, a slider and a wheel the
// other body's (a wheel's is its axle) — and hide the rest, still saved.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  test('each joint shows the anchors it takes', () {
    for (final (definition, anchor, connected) in [
      (Physics2DDefinitions.distanceJoint, true, true),
      (Physics2DDefinitions.fixedJoint, true, false),
      (Physics2DDefinitions.sliderJoint, false, true),
      (Physics2DDefinitions.wheelJoint, false, true),
    ]) {
      final hints = definition.hints.fields;
      expect(
        hints['anchor']?.visible,
        anchor,
        reason: '${definition.type}.anchor',
      );
      expect(
        hints['connectedAnchor']?.visible,
        connected,
        reason: '${definition.type}.connectedAnchor',
      );
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

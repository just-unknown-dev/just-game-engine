// A field a codec does not write is lost on every save, silently: the level
// reloads with the constructor default and nothing errors. That is how
// kinematic moving platforms came back as dynamic bodies and fell.
//
// So every value here is deliberately NOT the default.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

T roundTrip<T extends Component>(T component) {
  final json = ComponentCodecRegistry.instance.encode(component);
  expect(json, isNotNull, reason: '$T has no codec');
  final back = ComponentCodecRegistry.instance.decode(json!);
  expect(back, isA<T>());
  return back! as T;
}

void main() {
  setUpAll(registerCoreCodecs);

  test('PhysicsBodyComponent keeps its body type and rotation lock', () {
    final back = roundTrip(
      PhysicsBodyComponent(
        shape: RectangleShape(40, 12),
        bodyType: BodyType.kinematic,
        fixedRotation: true,
        gravityScale: 0.25,
        oneWayDirection: OneWayDirection.fromBelow,
        isOneWay: true,
        restitution: 0.1,
      ),
    );
    expect(back.bodyType, BodyType.kinematic);
    expect(back.fixedRotation, isTrue);
    expect(back.gravityScale, 0.25);
    expect(back.oneWayDirection, OneWayDirection.fromBelow);
    expect(back.isOneWay, isTrue);
  });

  test('CameraFollowComponent keeps its dead zone and priority', () {
    final back = roundTrip(
      CameraFollowComponent(
        enabled: false,
        lookaheadDistance: 140,
        deadZoneWidth: 60,
        deadZoneHeight: 40,
        priority: 3,
      ),
    );
    expect(back.enabled, isFalse);
    expect(back.lookaheadDistance, 140);
    expect(back.deadZoneWidth, 60);
    expect(back.deadZoneHeight, 40);
    expect(back.priority, 3);
  });

  test('SpriteComponent keeps its tint', () {
    final back = roundTrip(
      SpriteComponent(spritePath: 'a.png')..tint = const Color(0x80FF0000),
    );
    expect(back.tint, const Color(0x80FF0000));
  });

  test('TransformComponent keeps 3D rotation, and 2D saves stay unchanged', () {
    final tilted = roundTrip(
      TransformComponent(rotationX: 0.3, rotationY: -0.2),
    );
    expect(tilted.rotationX, closeTo(0.3, 1e-9));
    expect(tilted.rotationY, closeTo(-0.2, 1e-9));

    final flat = ComponentCodecRegistry.instance.encode(TransformComponent())!;
    expect(flat.keys, isNot(contains('rotationX')));
  });

  test('PolygonComponent keeps its shape', () {
    const triangle = [Offset(0, -20), Offset(18, 12), Offset(-18, 12)];
    final back = roundTrip(PolygonComponent(vertices: triangle));
    expect(back.vertices, triangle);
  });

  test('a save from before these fields existed loads as it always did', () {
    final old =
        ComponentCodecRegistry.instance.decode({
              'type': 'PhysicsBodyComponent',
              'shape': {'kind': 'rectangle', 'width': 32.0, 'height': 48.0},
              'mass': 1.0,
              'isStatic': false,
            })!
            as PhysicsBodyComponent;
    expect(old.bodyType, BodyType.dynamic);
    expect(old.fixedRotation, isFalse);
    expect(old.gravityScale, 1.0);
    expect(old.oneWayDirection, OneWayDirection.fromAbove);
  });

  test('every core component type has a codec', () {
    // The engine's own components must all be saveable without an editor.
    const expected = {
      'TransformComponent',
      'VelocityComponent',
      'RectangleComponent',
      'CircleComponent',
      'CapsuleComponent',
      'PhysicsBodyComponent',
      'SpriteComponent',
      'TextComponent',
      'LineComponent',
      'PolygonComponent',
      'CameraComponent',
      'CameraFollowComponent',
      'LayerComponent',
      'SpawnComponent',
      'CheckpointComponent',
      'HealthComponent',
      'TagComponent',
      'ParentComponent',
      'ChildrenComponent',
      'DistanceJointComponent',
      'PrismaticJointComponent',
      'WeldJointComponent',
      'WheelJointComponent',
      'SimpleMovementComponent',
    };
    expect(
      ComponentCodecRegistry.instance.types.toSet(),
      containsAll(expected),
    );
  });
}

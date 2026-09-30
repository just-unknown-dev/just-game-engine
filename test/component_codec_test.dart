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

  test('a virtual camera keeps its target, lens and standby mode', () {
    final back = roundTrip(
      VirtualCameraComponent(
        priority: 20,
        enabled: false,
        followName: 'Player',
        followTag: 'player',
        zoom: 1.5,
        dutch: 0.25,
        standbyUpdate: CameraStandbyUpdate.always,
      ),
    );
    expect(back.priority, 20);
    expect(back.enabled, isFalse);
    expect(back.followName, 'Player');
    expect(back.followTag, 'player');
    expect(back.zoom, 1.5);
    expect(back.dutch, 0.25);
    expect(back.standbyUpdate, CameraStandbyUpdate.always);
  });

  test('camera framing keeps its zones, damping and axes', () {
    final back = roundTrip(
      CameraFramingComponent(
        screenX: -0.1,
        screenY: 0.15,
        deadZoneWidth: 0.2,
        deadZoneHeight: 0.3,
        softZoneWidth: 0.7,
        softZoneHeight: 0.6,
        dampingX: 0.4,
        dampingY: 1.2,
        lookaheadTime: 0.25,
        lookaheadSmoothing: 0.5,
        followX: true,
        followY: false,
      ),
    );
    expect(back.screenX, -0.1);
    expect(back.screenY, 0.15);
    expect(back.deadZoneWidth, 0.2);
    expect(back.deadZoneHeight, 0.3);
    expect(back.softZoneWidth, 0.7);
    expect(back.softZoneHeight, 0.6);
    expect(back.dampingX, 0.4);
    expect(back.dampingY, 1.2);
    expect(back.lookaheadTime, 0.25);
    expect(back.lookaheadSmoothing, 0.5);
    expect(back.followY, isFalse);
  });

  test('SpriteComponent keeps its tint', () {
    final back = roundTrip(
      SpriteComponent(spritePath: 'a.png')..tint = const Color(0x80FF0000),
    );
    expect(back.tint, const Color(0x80FF0000));
  });

  test('TransformComponent keeps 3D rotation, and 2D saves stay unchanged', () {
    final tilted = roundTrip(
      TransformComponent(euler: Vector3(0.3, -0.2, 0)),
    );
    expect(tilted.eulerX, closeTo(0.3, 1e-9));
    expect(tilted.eulerY, closeTo(-0.2, 1e-9));

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
      // Text and buttons are just_ui_editor's.
      'LineComponent',
      'PolygonComponent',
      'VirtualCameraComponent',
      'CameraFramingComponent',
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

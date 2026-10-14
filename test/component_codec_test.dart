// A field a codec does not write is lost on every save, silently: the level
// reloads with the constructor default and nothing errors. That is how
// kinematic moving platforms came back as dynamic bodies and fell.
//
// So every value here is deliberately NOT the default.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// The engine's own definitions, fresh for this file.
final _coreDefinitions = ComponentDefinitionRegistry.core();
T roundTrip<T extends Component>(T component) {
  final json = _coreDefinitions.encode(component);
  expect(json, isNotNull, reason: '$T has no codec');
  final back = _coreDefinitions.decode(json!);
  expect(back, isA<T>());
  return back! as T;
}

void main() {
  test('RigidBody2D keeps its body type and rotation lock', () {
    final back = roundTrip(
      RigidBody2D(
        bodyType: BodyType.kinematic,
        lockRotation: true,
        gravityScale: 0.25,
        restitution: 0.1,
        linearDamping: 0.5,
        continuousCollision: true,
        collidesWith: 6,
      ),
    );
    expect(back.bodyType, BodyType.kinematic);
    expect(back.lockRotation, isTrue);
    expect(back.gravityScale, 0.25);
    expect(back.restitution, 0.1);
    expect(back.linearDamping, 0.5);
    expect(back.continuousCollision, isTrue);
    expect(back.collidesWith, 6);
  });

  test('Collider2D keeps its shape, placement and one-way side', () {
    final back = roundTrip(
      Collider2D(
        shape: ColliderShape2D.capsule,
        radius: 6,
        height: 30,
        offset: const Offset(2, 3),
        rotation: 0.5,
        scale: Vector2(2, 1),
        oneWay: true,
        oneWayDirection: OneWayDirection.fromBelow,
        points: const [Offset(1, 2), Offset(3, 4)],
      ),
    );
    expect(back.shape, ColliderShape2D.capsule);
    expect((back.radius, back.height), (6.0, 30.0));
    expect(back.offset, const Offset(2, 3));
    expect(back.rotation, 0.5);
    expect((back.scale.x, back.scale.y), (2.0, 1.0));
    expect(back.oneWay, isTrue);
    expect(back.oneWayDirection, OneWayDirection.fromBelow);
    expect(back.points, const [Offset(1, 2), Offset(3, 4)]);
  });

  test('a virtual camera keeps its target, lens and standby mode', () {
    final back = roundTrip(
      VirtualCameraComponent(
        priority: 20,
        enabled: false,
        follow: const EntityTarget.tag('player'),
        zoom: 1.5,
        dutch: 0.25,
        standbyUpdate: CameraStandbyUpdate.always,
      ),
    );
    expect(back.priority, 20);
    expect(back.enabled, isFalse);
    expect(back.follow, const EntityTarget.tag('player'));
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
    final tilted = roundTrip(TransformComponent(euler: Vector3(0.3, -0.2, 0)));
    expect(tilted.eulerX, closeTo(0.3, 1e-9));
    expect(tilted.eulerY, closeTo(-0.2, 1e-9));

    final flat = _coreDefinitions.encode(TransformComponent())!;
    expect(flat.keys, isNot(contains('rotationX')));
  });

  test('PolygonComponent keeps its shape', () {
    const triangle = [Offset(0, -20), Offset(18, 12), Offset(-18, 12)];
    final back = roundTrip(PolygonComponent(vertices: triangle));
    expect(back.vertices, triangle);
  });

  test('a body saved before 2-D and 3-D physics matched loads as both parts', () {
    final scene = SceneFormat.migrate({
      'version': 8,
      'entities': [
        {
          'name': 'Box',
          'components': [
            {
              'type': 'PhysicsBodyComponent',
              'fields': {
                'shape': {'kind': 'rectangle', 'width': 32.0, 'height': 48.0},
                'bodyType': 'kinematic',
                'fixedRotation': true,
                'drag': 0.5,
                'isOneWay': true,
              },
            },
          ],
        },
      ],
    });
    final components = (scene['entities'] as List).single['components'] as List;
    final rigid = _coreDefinitions.decode(components[0] as Map<String, dynamic>)! as RigidBody2D;
    final collider = _coreDefinitions.decode(components[1] as Map<String, dynamic>)! as Collider2D;
    expect(rigid.bodyType, BodyType.kinematic);
    expect(rigid.lockRotation, isTrue);
    expect(rigid.linearDamping, 0.5);
    expect(rigid.restitution, 0.8, reason: 'the default it was saved with');
    expect(collider.shape, ColliderShape2D.box);
    expect((collider.size.x, collider.size.y), (32.0, 48.0));
    expect(collider.oneWay, isTrue);
  });

  test('every core component type has a codec', () {
    // The engine's own components must all be saveable without an editor.
    const expected = {
      'TransformComponent',
      'VelocityComponent',
      'RectangleComponent',
      'CircleComponent',
      'CapsuleComponent',
      'RigidBody2D',
      'Collider2D',
      'DistanceJoint2D',
      'FixedJoint2D',
      'SliderJoint2D',
      'WheelJoint2D',
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
      'SimpleMovementComponent',
    };
    expect(_coreDefinitions.types.toSet(), containsAll(expected));
  });
}

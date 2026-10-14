import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// The engine's own definitions, fresh for this file.
final _coreDefinitions = ComponentDefinitionRegistry.core();
void main() {
  test('a scene mode reads back from its id, and anything else is 2-D', () {
    expect(SceneMode.fromId('3d'), SceneMode.threeD);
    expect(SceneMode.fromId('2d'), SceneMode.twoD);
    expect(SceneMode.fromId(null), SceneMode.twoD);
    expect(SceneMode.fromId('4d'), SceneMode.twoD);
  });

  test('dimensions allow the modes they name', () {
    expect(Dimensions.both.allows(SceneMode.threeD), isTrue);
    expect(Dimensions.twoD.allows(SceneMode.twoD), isTrue);
    expect(Dimensions.twoD.allows(SceneMode.threeD), isFalse);
    expect(Dimensions.threeD.allows(SceneMode.twoD), isFalse);
  });

  test('vector types name their channels, and which a 2-D scene shows', () {
    expect(FieldTypes.vector3.channels, ['x', 'y', 'z']);
    expect(FieldTypes.vector3.channels2D, {'x', 'y'});
    expect(FieldTypes.vector2.channels2D, {'x', 'y'});
    expect(FieldTypes.offset.channels, ['dx', 'dy']);
    expect(FieldTypes.decimal.channels, isEmpty);
  });

  test('the 2-D-only definitions say so, and the shared ones do not', () {
    final registry = _coreDefinitions;
    Dimensions of(String type) =>
        registry.definitionByType(type)!.hints.dimensions;
    for (final type in [
      'SpriteComponent',
      'SpriteAnimationComponent',
      'RectangleComponent',
      'CircleComponent',
      'PolygonComponent',
      'RigidBody2D',
      'Collider2D',
      'DistanceJoint2D',
      'LayerComponent',
      'LevelMapComponent',
      'CameraConfinerComponent',
      'CameraFramingComponent',
    ]) {
      expect(of(type), Dimensions.twoD, reason: type);
    }
    for (final type in [
      'TransformComponent',
      'VelocityComponent',
      'ParentComponent',
      'TagComponent',
      'VirtualCameraComponent',
      'TimelinePlayerComponent',
      'AudioSourceComponent',
    ]) {
      expect(of(type), Dimensions.both, reason: type);
    }
  });
}

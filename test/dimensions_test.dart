import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

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

  test('a scene saves its mode and reads it back; no node tree', () {
    final flat = Scene(name: 'flat').toJson();
    expect(flat['mode'], '2d');
    expect(flat.containsKey('root'), isFalse);
    expect(Scene.fromJson(flat).mode, SceneMode.twoD);
    final json = Scene(name: 'deep', mode: SceneMode.threeD).toJson();
    expect(json['mode'], '3d');
    expect(Scene.fromJson(json).mode, SceneMode.threeD);
  });

  test('vector types name their channels, and which a 2-D scene shows', () {
    expect(FieldTypes.vector3.channels, ['x', 'y', 'z']);
    expect(FieldTypes.vector3.channels2D, {'x', 'y'});
    expect(FieldTypes.vector2.channels2D, {'x', 'y'});
    expect(FieldTypes.offset.channels, ['dx', 'dy']);
    expect(FieldTypes.decimal.channels, isEmpty);
  });

  test('the 2-D-only definitions say so, and the shared ones do not', () {
    final registry = ComponentDefinitionRegistry.instance;
    registerCoreCodecs();
    Dimensions of(String type) =>
        registry.definitionByType(type)!.hints.dimensions;
    for (final type in [
      'SpriteComponent',
      'SpriteAnimationComponent',
      'RectangleComponent',
      'CircleComponent',
      'PolygonComponent',
      'PhysicsBodyComponent',
      'DistanceJointComponent',
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

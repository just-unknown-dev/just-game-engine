// A tiny platformer: the level comes from scene JSON (the format an editor
// saves), the player and some crates are built in code, a virtual camera
// follows the player, and the arrow keys (or a gamepad) move it.
//
// To run it, make a Flutter app that depends on just_game_engine and put
// this file in its lib/main.dart.

import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Build the whole game before the first frame.
  final engine = await createGame();
  runApp(ExampleApp(engine: engine));
}

/// Makes, fills and starts the engine.
Future<Engine> createGame() async {
  // The standard systems — input, physics, movement, audio, rendering,
  // sprites, level maps and cameras — are added as the engine initializes.
  final engine = Engine(
    config: const EngineConfig(defaultSystems: DefaultSystems.all),
  );
  await engine.initialize();

  // Input: actions and their bindings come from an input asset, usually a
  // `.input.json` file in the app's assets.
  engine.input.loadAsset(InputActionAsset.parse(inputAsset));
  await engine.input.attachGamepads(); // opt-in; no pads is fine

  final world = engine.world;

  // The level: a floor, a ledge and a camera, read from scene JSON.
  SceneLoader.loadString(world, levelScene);

  // The player, in code. The scene's camera follows the tag `player`, so it
  // finds this entity although the scene was loaded first.
  world.createEntityWithComponents([
    TransformComponent(position: Vector3.fromXY(-200, 100)),
    VelocityComponent(),
    RectangleComponent(
      width: 32,
      height: 48,
      cornerRadius: 6,
      fillStyle: const ShapePaintStyle(color: Color(0xFF4FC3F7)),
    ),
    RigidBody2D(restitution: 0, lockRotation: true), // stays upright
    Collider2D(shape: ColliderShape2D.matchShape), // the rectangle drawn
    InputComponent(), // player 1's actions, copied in by InputSystem
    TagComponent('player'),
  ], name: 'Player');

  // Crates and a ball to push around.
  for (var i = 0; i < 3; i++) {
    world.createEntityWithComponents([
      TransformComponent(position: Vector3.fromXY(60, 150 - i * 42.0)),
      RectangleComponent(
        width: 40,
        height: 40,
        fillStyle: const ShapePaintStyle(color: Color(0xFFFFB74D)),
      ),
      RigidBody2D(restitution: 0.1),
      Collider2D(shape: ColliderShape2D.matchShape),
    ], name: 'Crate $i');
  }
  world.createEntityWithComponents([
    TransformComponent(position: Vector3.fromXY(160, 0)),
    CircleComponent(
      radius: 18,
      fillStyle: const ShapePaintStyle(color: Color(0xFFE57373)),
    ),
    RigidBody2D(restitution: 0.6),
    Collider2D(shape: ColliderShape2D.matchShape),
  ], name: 'Ball');

  // The game's own rule, as a system of its own.
  world.addSystem(PlayerControlSystem());

  engine.start();
  return engine;
}

/// Moves whatever has input and a velocity: left and right with `move`, up
/// with `jump`.
class PlayerControlSystem extends System {
  static const double speed = 260;
  static const double jumpSpeed = 620;

  // After input is read, before physics steps: a press moves the player in
  // the same frame.
  @override
  int get priority => SystemPriorities.playerControl;

  @override
  List<Type> get requiredComponents => [InputComponent, VelocityComponent];

  @override
  void update(double deltaTime) {
    for (final entity in entities) {
      final input = entity.getComponent<InputComponent>()!;
      final velocity = entity.getComponent<VelocityComponent>()!.velocity;
      velocity.x = input.vector('move').dx * speed;
      // y points down. Only jump from the ground: the physics system keeps
      // the body's isGrounded.
      final grounded = entity.getComponent<RigidBody2D>()?.isGrounded ?? false;
      if (input.wasPressed('jump') && grounded) {
        velocity.y = -jumpSpeed;
      }
    }
  }
}

/// Shows the game.
class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key, required this.engine});

  final Engine engine;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: GameWidget(
          engine: engine,
          overlay: const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Arrow keys or left stick: move.  Space or A: jump.',
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ),
      ),
    );
  }
}

/// Scene JSON, as the editor saves it — a file under `assets/scenes/` in a
/// real game, loaded with `SceneLoader.loadAsset`. Fields left out keep
/// their defaults.
const levelScene = '''
{
  "version": 9,
  "name": "example",
  "entities": [
    {
      "name": "Floor",
      "components": [
        {"type": "TransformComponent",
         "fields": {"position": {"x": 0, "y": 200, "z": 0}}},
        {"type": "RectangleComponent",
         "fields": {"width": 1200, "height": 40}},
        {"type": "RigidBody2D", "fields": {"bodyType": "static"}},
        {"type": "Collider2D", "fields": {"shape": "matchShape"}}
      ]
    },
    {
      "name": "Ledge",
      "components": [
        {"type": "TransformComponent",
         "fields": {"position": {"x": 320, "y": 60, "z": 0}}},
        {"type": "RectangleComponent",
         "fields": {"width": 200, "height": 20}},
        {"type": "RigidBody2D", "fields": {"bodyType": "static"}},
        {"type": "Collider2D", "fields": {"shape": "matchShape"}}
      ]
    },
    {
      "name": "Camera",
      "components": [
        {"type": "TransformComponent", "fields": {}},
        {"type": "VirtualCameraComponent",
         "fields": {"follow": {"tag": "player"}}},
        {"type": "CameraFramingComponent",
         "fields": {"dampingX": 0.3, "dampingY": 0.3}}
      ]
    }
  ]
}
''';

/// An input asset: the `player` map's `move` and `jump` actions.
const inputAsset = '''
{
  "format": "just_inputs",
  "version": 3,
  "maps": [
    {
      "id": "m1",
      "name": "player",
      "actions": [
        {
          "id": "a1",
          "name": "move",
          "type": "vector2",
          "bindings": [
            {"id": "b1", "composite": "2DVector", "parts": [
              {"id": "b2", "part": "left", "path": "<Keyboard>/leftArrow"},
              {"id": "b3", "part": "right", "path": "<Keyboard>/rightArrow"}
            ]},
            {"id": "b4", "path": "<Gamepad>/leftStick"}
          ]
        },
        {
          "id": "a2",
          "name": "jump",
          "type": "button",
          "bindings": [
            {"id": "b5", "path": "<Keyboard>/space"},
            {"id": "b6", "path": "<Gamepad>/buttonSouth"}
          ]
        }
      ]
    }
  ]
}
''';

import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// A basic example demonstrating the core capabilities of the Just Game Engine.
/// This example sets up the Engine, physics bodies using the new advanced physics features,
/// and uses the built-in debug renderer to visualize the simulation.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize the engine
  final engine = Engine();
  await engine.initialize();

  // 2. Set up physics

  // Create a static ground body (mass = 0.0 makes it immovable)
  final ground = PhysicsBody(
    position: const Offset(0, 300), // Positioned lower on the screen
    shape: RectangleShape(800, 50),
    mass: 0.0,
    friction: 0.5,
  );
  engine.physics.addBody(ground);

  // Create a falling bouncing ball
  final ball = PhysicsBody(
    position: const Offset(50, -200), // Starts high up
    velocity: const Offset(100, 0), // Initial push to the right
    shape: CircleShape(30),
    mass: 1.0,
    restitution: 0.8, // Make it bouncy (0.0 to 1.0)
    friction: 0.2, // Slide lightly
  );
  engine.physics.addBody(ball);

  // Create a falling box to collide with the ball and ground
  final box = PhysicsBody(
    position: const Offset(200, -300),
    shape: RectangleShape(50, 50),
    mass: 2.0, // Heavier than the ball
    restitution: 0.3, // Less bouncy
    friction: 0.6,
  );
  engine.physics.addBody(box);

  // 3. Set up rendering
  // For this basic example, we will just use the physics debug renderer
  // which automatically draws the shapes, velocity vectors, and active states.
  engine.rendering.addRenderable(
    CustomRenderable(
      onRender: (canvas, size) {
        // Draw the physics world in the center of the screen
        canvas.save();
        canvas.translate(size.width / 2, size.height / 2);
        engine.physics.renderDebug(canvas, size);
        canvas.restore();
      },
    ),
  );

  // 4. Start the engine loop
  engine.start();

  // 5. Run the Flutter app with GameWidget
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor:
            Colors.grey[900], // Dark background to make debug lines pop
        body: Stack(
          children: [
            GameWidget(engine: engine),
            const Positioned(
              top: 40,
              left: 20,
              child: Text(
                'Just Game Engine Basic Example\nPhysics Simulation with SAT and True Impulse',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

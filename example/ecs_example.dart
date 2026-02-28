/// ECS Example
///
/// This example demonstrates how to use the Entity-Component System in the Just Game Engine.
library;

import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'dart:math' as math;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final engine = Engine();
  await engine.initialize();

  // Setup ECS example
  setupECSExample(engine);

  engine.start();
  runApp(ECSExampleApp(engine: engine));
}

void setupECSExample(Engine engine) {
  final world = engine.world;

  // Add systems
  world.addSystem(MovementSystem());
  world.addSystem(RenderSystem());
  world.addSystem(PhysicsSystem()..gravity = const Offset(0, 100));
  world.addSystem(
    BoundarySystem(
      bounds: const Rect.fromLTWH(-400, -300, 800, 600),
      behavior: BoundaryBehavior.bounce,
    ),
  );

  // Create player entity
  final player = world.createEntity(name: 'Player');
  player.addComponent(TransformComponent(position: const Offset(0, -100)));
  player.addComponent(
    VelocityComponent(velocity: const Offset(100, 0), maxSpeed: 200),
  );
  player.addComponent(
    RenderableComponent(
      renderable: CircleRenderable(radius: 30, fillColor: Colors.blue),
    ),
  );
  player.addComponent(
    PhysicsBodyComponent(radius: 30, mass: 1.0, restitution: 0.8),
  );
  player.addComponent(HealthComponent(maxHealth: 100));
  player.addComponent(TagComponent('player'));

  // Create enemy entities
  for (int i = 0; i < 5; i++) {
    final angle = (i / 5) * 2 * math.pi;
    final radius = 150.0;
    final x = math.cos(angle) * radius;
    final y = math.sin(angle) * radius;

    final enemy = world.createEntity(name: 'Enemy_$i');
    enemy.addComponent(TransformComponent(position: Offset(x, y)));
    enemy.addComponent(
      VelocityComponent(
        velocity: Offset(
          (math.Random().nextDouble() - 0.5) * 100,
          (math.Random().nextDouble() - 0.5) * 100,
        ),
      ),
    );
    enemy.addComponent(
      RenderableComponent(
        renderable: CircleRenderable(
          radius: 20,
          fillColor: HSLColor.fromAHSL(1.0, i * 72.0, 0.7, 0.6).toColor(),
        ),
      ),
    );
    enemy.addComponent(
      PhysicsBodyComponent(radius: 20, mass: 0.8, restitution: 0.9),
    );
    enemy.addComponent(HealthComponent(maxHealth: 50));
    enemy.addComponent(TagComponent('enemy'));
  }

  // Create some static walls
  final wall1 = world.createEntity(name: 'Wall_1');
  wall1.addComponent(TransformComponent(position: const Offset(0, 200)));
  wall1.addComponent(VelocityComponent()); // Static, no velocity
  wall1.addComponent(
    RenderableComponent(
      renderable: RectangleRenderable(
        size: const Size(400, 20),
        fillColor: Colors.grey,
      ),
    ),
  );
  wall1.addComponent(PhysicsBodyComponent(radius: 200, isStatic: true));

  // Create temporary entities with lifetime
  for (int i = 0; i < 3; i++) {
    final temp = world.createEntity(name: 'Temp_$i');
    temp.addComponent(
      TransformComponent(
        position: Offset(
          (math.Random().nextDouble() - 0.5) * 200,
          (math.Random().nextDouble() - 0.5) * 200,
        ),
      ),
    );
    temp.addComponent(
      RenderableComponent(
        renderable: CircleRenderable(
          radius: 15,
          fillColor: Colors.yellow.withValues(alpha: 0.5),
        ),
      ),
    );
    temp.addComponent(LifetimeComponent(5.0 + i * 2)); // 5, 7, 9 seconds
  }

  // Add lifetime system to handle expiring entities
  world.addSystem(LifetimeSystem());

  debugPrint('ECS Example setup complete:');
  debugPrint('  - ${world.entities.length} entities created');
  debugPrint('  - ${world.systems.length} systems active');
}

class ECSExampleApp extends StatelessWidget {
  final Engine engine;

  const ECSExampleApp({super.key, required this.engine});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ECS Example',
      theme: ThemeData.dark(),
      home: ECSExampleScreen(engine: engine),
    );
  }
}

class ECSExampleScreen extends StatefulWidget {
  final Engine engine;

  const ECSExampleScreen({super.key, required this.engine});

  @override
  State<ECSExampleScreen> createState() => _ECSExampleScreenState();
}

class _ECSExampleScreenState extends State<ECSExampleScreen> {
  bool showStats = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Game widget
          GameWidget(engine: widget.engine, showFPS: true),

          // ECS Stats
          if (showStats) Positioned(top: 60, left: 20, child: _buildStats()),

          // Controls
          Positioned(bottom: 20, left: 20, right: 20, child: _buildControls()),
        ],
      ),
    );
  }

  Widget _buildStats() {
    final stats = widget.engine.world.stats;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ECS Stats',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Entities: ${stats['totalEntities']} (${stats['activeEntities']} active)',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          Text(
            'Systems: ${stats['systems']} (${stats['activeSystems']} active)',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'ECS Entity-Component System Demo',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton(
                onPressed: _spawnEntity,
                child: const Text('Spawn Entity'),
              ),
              ElevatedButton(
                onPressed: _clearEntities,
                child: const Text('Clear All'),
              ),
              ElevatedButton(
                onPressed: () {
                  setState(() => showStats = !showStats);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: showStats ? Colors.green : Colors.grey,
                ),
                child: const Text('Stats'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _spawnEntity() {
    final world = widget.engine.world;
    final random = math.Random();

    final entity = world.createEntity(name: 'Spawned_${world.entities.length}');
    entity.addComponent(
      TransformComponent(
        position: Offset(
          (random.nextDouble() - 0.5) * 300,
          (random.nextDouble() - 0.5) * 300,
        ),
      ),
    );
    entity.addComponent(
      VelocityComponent(
        velocity: Offset(
          (random.nextDouble() - 0.5) * 200,
          (random.nextDouble() - 0.5) * 200,
        ),
      ),
    );
    entity.addComponent(
      RenderableComponent(
        renderable: CircleRenderable(
          radius: 15 + random.nextDouble() * 15,
          fillColor: HSLColor.fromAHSL(
            1.0,
            random.nextDouble() * 360,
            0.7,
            0.6,
          ).toColor(),
        ),
      ),
    );
    entity.addComponent(
      PhysicsBodyComponent(
        radius: 15 + random.nextDouble() * 15,
        mass: 0.5 + random.nextDouble() * 0.5,
      ),
    );

    setState(() {});
  }

  void _clearEntities() {
    widget.engine.world.destroyAllEntities();
    setState(() {});

    // Recreate the example
    setupECSExample(widget.engine);
    setState(() {});
  }

  @override
  void dispose() {
    widget.engine.dispose();
    super.dispose();
  }
}

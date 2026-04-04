# Just Game Engine - Quick Start Guide

Get up and running with the Just Game Engine in minutes!

## Installation

### Step 1: Add Dependency

Add the engine to your `pubspec.yaml`:

```yaml
dependencies:
  just_game_engine: latest_version
```

### Step 2: Get Packages

```bash
flutter pub get
```

## Your First Game

### Minimal Setup (5 lines)

```dart
import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final engine = Engine();
  await engine.initialize();
  engine.start();
  
  runApp(MaterialApp(
    home: Scaffold(
      body: GameWidget(engine: engine),
    ),
  ));
}
```

This creates an empty game canvas. Now let's add content!

## Adding Your First Object

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final engine = Engine();
  await engine.initialize();
  
  // Add a circle
  engine.rendering.addRenderable(
    CircleRenderable(
      radius: 50,
      fillColor: Colors.blue,
      position: Offset.zero,
    ),
  );
  
  engine.start();
  runApp(MaterialApp(home: Scaffold(body: GameWidget(engine: engine))));
}
```

**Result**: A blue circle in the center of the screen!

## Making It Move

Let's animate that circle:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final engine = Engine();
  await engine.initialize();
  
  // Create circle
  final circle = CircleRenderable(
    radius: 50,
    fillColor: Colors.blue,
    position: Offset(-100, 0),
  );
  engine.rendering.addRenderable(circle);
  
  // Animate it
  final animation = PositionTween(
    target: circle,
    start: Offset(-100, 0),
    end: Offset(100, 0),
    duration: 2.0,
    easing: Easings.easeInOutQuad,
    loop: true,
  );
  engine.animation.addAnimation(animation);
  animation.play();
  
  engine.start();
  runApp(MaterialApp(home: Scaffold(body: GameWidget(engine: engine))));
}
```

**Result**: The circle moves back and forth smoothly!

## Adding Particle Effects

```dart
void setupGame(Engine engine) {
  // Create fire effect
  final fire = ParticleEffects.fire(position: Offset.zero)
    ..emissionRate = 50;
  
  List<ParticleEmitter> emitters = [fire];
  
  // Render particles
  engine.rendering.addRenderable(
    CustomRenderable(
      onRender: (canvas, size) {
        for (final emitter in emitters) {
          emitter.update(1/60);  // Approximate frame time
          emitter.render(canvas, size);
        }
      },
    ),
  );
}
```

## Adding Physics

```dart
void setupPhysics(Engine engine) {
  // Create two colliding bodies
  final body1 = PhysicsBody(
    position: Offset(-100, 0),
    velocity: Offset(50, 0),
    shape: CircleShape(30),
  );
  
  final body2 = PhysicsBody(
    position: Offset(100, 0),
    velocity: Offset(-50, 0),
    shape: CircleShape(30),
  );
  
  engine.physics.addBody(body1);
  engine.physics.addBody(body2);
  
  // Visualize physics (optional)
  engine.rendering.addRenderable(
    CustomRenderable(
      onRender: (canvas, size) {
        engine.physics.renderDebug(canvas, size);
      },
    ),
  );
}
```

## Using the Entity-Component System (ECS)

The ECS is a flexible architecture for composing game entities from reusable components. It's ideal for games with many similar objects.

### Basic ECS Setup

```dart
void setupECS(Engine engine) {
  final world = engine.world;
  
  // Step 1: Add systems (the logic)
  world.addSystem(MovementSystem());
  world.addSystem(RenderSystem());
  
  // Step 2: Create an entity
  final player = world.createEntity(name: 'Player');
  
  // Step 3: Add components (the data)
  player.addComponent(TransformComponent(
    position: Offset.zero,
  ));
  player.addComponent(VelocityComponent(
    velocity: const Offset(100, 0),
  ));
  player.addComponent(RenderableComponent(
    renderable: CircleRenderable(
      radius: 30,
      fillColor: Colors.blue,
    ),
  ));
  
  // That's it! The systems will automatically process this entity
}
```

**What's happening:**
1. `MovementSystem` moves entities with Transform + Velocity
2. `RenderSystem` draws entities with Transform + Renderable
3. Your entity has all three components, so both systems process it

### Adding Physics with ECS

```dart
void setupECSPhysics(Engine engine) {
  final world = engine.world;
  
  // Add physics system
  final physicsSystem = PhysicsSystem()
    ..gravity = const Offset(0, 100);  // Downward gravity
  world.addSystem(physicsSystem);
  
  // Add other systems
  world.addSystem(MovementSystem());
  world.addSystem(RenderSystem());
  
  // Create a bouncing ball
  final ball = world.createEntity(name: 'Ball');
  ball.addComponent(TransformComponent(position: const Offset(0, -200)));
  ball.addComponent(VelocityComponent());
  ball.addComponent(RenderableComponent(
    renderable: CircleRenderable(radius: 25, fillColor: Colors.red),
  ));
  ball.addComponent(PhysicsBodyComponent(
    shape: CircleShape(25),
    mass: 1.0,
    restitution: 0.9,  // Bounciness (0-1)
  ));
  
  // Create a ground
  final ground = world.createEntity(name: '  ');
  ground.addComponent(TransformComponent(position: const Offset(0, 250)));
  ground.addComponent(VelocityComponent());  // Static (no velocity)
  ground.addComponent(RenderableComponent(
    renderable: RectangleRenderable(
      size: const Size(800, 20),
      fillColor: Colors.grey,
    ),
  ));
  ground.addComponent(PhysicsBodyComponent(
    shape: RectangleShape(const Size(800, 20)),
    mass: 0.0,  // mass = 0 means static
  ));
}
```

### Entity Lifetime and Health

```dart
void setupTemporaryEntities(Engine engine) {
  final world = engine.world;
  
  // Add lifetime system
  world.addSystem(LifetimeSystem());
  world.addSystem(HealthSystem()
    ..destroyOnDeath = true
    ..regenRate = 2.0);  // Regenerate 2 HP per second
  
  // Create a temporary particle
  final particle = world.createEntity(name: 'Particle');
  particle.addComponent(TransformComponent(position: Offset(100, 100)));
  particle.addComponent(RenderableComponent(
    renderable: CircleRenderable(radius: 10, fillColor: Colors.yellow),
  ));
  particle.addComponent(LifetimeComponent(3.0));  // Dies after 3 seconds
  
  // Create an enemy with health
  final enemy = world.createEntity(name: 'Enemy');
  enemy.addComponent(TransformComponent(position: Offset(-100, 0)));
  enemy.addComponent(RenderableComponent(
    renderable: CircleRenderable(radius: 30, fillColor: Colors.red),
  ));
  enemy.addComponent(HealthComponent(maxHealth: 50));
  
  // Damage the enemy
  Future.delayed(const Duration(seconds: 1), () {
    enemy.getComponent<HealthComponent>()?.damage(25);
    print('Enemy health: ${enemy.getComponent<HealthComponent>()?.health}');
  });
}
```

### Querying Entities

```dart
void findEntities(Engine engine) {
  final world = engine.world;
  
  // Find all entities that can move
  final movingEntities = world.query([TransformComponent, VelocityComponent]);
  print('Found ${movingEntities.length} moving entities');
  
  // Find all entities with health
  final livingEntities = world.query([HealthComponent]);
  for (final entity in livingEntities) {
    final health = entity.getComponent<HealthComponent>();
    print('${entity.name}: ${health?.health}/${health?.maxHealth} HP');
  }
  
  // Find specific entity by name
  final player = world.findEntityByName('Player');
  if (player != null) {
    player.addComponent(TagComponent('player'));
  }
}
```

### Creating a Custom System

```dart
class FlashingSystem extends System {
  double _time = 0;
  
  @override
  List<Type> get requiredComponents => [
    TransformComponent,
    RenderableComponent,
    HealthComponent,
  ];
  
  @override
  void update(double deltaTime) {
    _time += deltaTime;
    
    forEach((entity) {
      final health = entity.getComponent<HealthComponent>()!;
      final renderable = entity.getComponent<RenderableComponent>()!;
      
      // Flash red when damaged
      if (health.health < health.maxHealth * 0.5) {
        // Oscillate opacity
        final alpha = (math.sin(_time * 10) + 1) / 2;
        // Modify renderable color based on time
        // (This is simplified - you'd need to modify the actual renderable)
      }
    });
  }
}

// Use it
world.addSystem(FlashingSystem());
```

### ECS Best Practices

1. **Components are data only** - No methods except getters/setters
2. **Systems contain logic** - All game behavior goes in systems
3. **One system per behavior** - Keep systems focused and small
4. **Use queries wisely** - Query results are cached with selective invalidation
5. **System order matters** - Systems run by priority (higher = earlier): input (100) → physics (90) → movement (80) → rendering (40)
6. **Use CommandBuffer** - Call `world.commands.destroy()` instead of direct mutations inside system updates
7. **Use EventBus** - Subscribe to events with `world.events.on<CollisionEvent>()` for decoupled communication
8. **System order matters** — systems execute by descending priority: `TileMap` (110) → `Parallax` (105) → `Input` (100) → `Physics` (90) → `Movement` (80) → `Animation` (70) → `Effects` (65) → `Gameplay` (60) → `Hierarchy` (50) → `Particles` (48) → `Camera` (45) → `Render` (40) → `PostProcess` (35) → `Boundary` (30) → `Audio` (−10)

### ECS vs Scene Graph

**Use ECS when:**
- You have many similar entities (bullets, enemies, particles)
- You need flexible composition (add/remove abilities)
- Performance is critical (thousands of entities)

**Use Scene Graph when:**
- You need transform hierarchies (arms attached to body)
- Building UI and menus
- Simpler games with few objects

**You can use both!** The engine supports mixing ECS and Scene Graph in the same game.

## Common Patterns

### Pattern 1: Bouncing Ball

```dart
final ball = CircleRenderable(
  radius: 30,
  fillColor: Colors.red,
  position: Offset(0, -200),
);
engine.rendering.addRenderable(ball);

final bounce = AnimationSequence(
  animations: [
    PositionTween(
      target: ball,
      start: Offset(0, -200),
      end: Offset(0, 200),
      duration: 1.0,
      easing: Easings.easeInQuad,
    ),
    PositionTween(
      target: ball,
      start: Offset(0, 200),
      end: Offset(0, -200),
      duration: 1.0,
      easing: Easings.easeOutQuad,
    ),
  ],
  loop: true,
);
bounce.play();
```

### Pattern 2: Rotating Square

```dart
final square = RectangleRenderable(
  size: Size(60, 60),
  fillColor: Colors.green,
);
engine.rendering.addRenderable(square);

final rotation = RotationTween(
  target: square,
  start: 0,
  end: math.pi * 2,
  duration: 3.0,
  easing: Easings.linear,
  loop: true,
);
rotation.play();
```

### Pattern 3: Pulsing Circle

```dart
final circle = CircleRenderable(
  radius: 40,
  fillColor: Colors.purple,
);
engine.rendering.addRenderable(circle);

final pulse = ScaleTween(
  target: circle,
  start: 0.5,
  end: 1.5,
  duration: 1.0,
  easing: Easings.easeInOutSine,
  loop: true,
);
pulse.play();
```

### Pattern 4: Fading Text

```dart
final text = TextRenderable(
  text: 'Hello World',
  textStyle: TextStyle(fontSize: 32, color: Colors.white),
);
engine.rendering.addRenderable(text);

final fade = OpacityTween(
  target: text,
  start: 0.0,
  end: 1.0,
  duration: 2.0,
  easing: Easings.easeInOutQuad,
  loop: true,
);
fade.play();
```

### Pattern 5: ECS Particle Burst

Use `ParticleEmitterComponent` and `ParticleSystemECS` for fire-and-forget effects. The entity is automatically destroyed when all particles expire.

```dart
void spawnExplosion(Engine engine, Offset position) {
  final world = engine.world;

  // Register  once — safe to call multiple times
  if (!world.hasSystems([ParticleSystemECS, RenderSystem])) {
    world.addSystem(ParticleSystemECS());
    world.addSystem(RenderSystem());
  }

  final burst = world.createEntity(name: 'Explosion');
  burst.addComponent(TransformComponent(position: position));
  burst.addComponent(ParticleEmitterComponent(
    emitter: ParticleEffects.explosion(position: position),
    syncPositionFromTransform: false,
    removeEntityWhenComplete: true,  // Auto-destroy when done
  ));
}
```

### Pattern 6: ECS Camera Follow

Add `CameraFollowComponent` to any entity and `CameraFollowSystem` will drive the camera toward it with spring + lookahead.

```dart
void setupCameraFollow(Engine engine) {
  final world = engine.world;

  world.addSystem(MovementSystem());
  world.addSystem(RenderSystem());
  world.addSystem(CameraFollowSystem(cameraSystem: engine.cameraSystem));

  final player = world.createEntity(name: 'Player');
  player.addComponent(TransformComponent(position: Offset.zero));
  player.addComponent(VelocityComponent(velocity: const Offset(80, 0)));
  player.addComponent(RenderableComponent(
    renderable: CircleRenderable(radius: 20, fillColor: Colors.blue),
  ));
  player.addComponent(CameraFollowComponent(
    lookaheadDistance: 100,   // Look ahead in the movement direction
    deadZoneWidth: 40,         // Camera doesn't move until player drifts this far
  ));
}
```

When multiple entities carry a `CameraFollowComponent` with the same lowest `priority`, the system switches to multi-target mode and auto-zooms to keep all targets in view.

## Camera Controls

```dart
// In your widget
void moveCamera(Offset delta) {
  engine.rendering.camera.moveBy(delta);
}

void zoomIn() {
  engine.rendering.camera.zoomBy(1.2);
}

void resetCamera() {
  engine.rendering.camera.reset();
}
```

## Localization

Load JSON string tables and look up keys from anywhere in game code.

```dart
Future<void> setupLocalization() async {
  final l10n = LocalizationManager();

  // Load per-locale JSON files (flat or nested, auto-flattened)
  await l10n.load(const Locale('en'), 'assets/l10n/ui_en.json', ns: 'ui');
  await l10n.load(const Locale('fr'), 'assets/l10n/ui_fr.json', ns: 'ui');

  // Set a global singleton for convenience
  LocalizationManager.instance = l10n;
  l10n.setLocale(const Locale('fr'));
}

// Anywhere in game code:
final text = LocalizationManager.instance!.t('ui.start_game');
final plural = LocalizationManager.instance!.t('ui.item_count', args: {'count': 3});
```

**JSON format** (`assets/l10n/ui_en.json`):
```json
{
  "ui": {
    "start_game": "Start Game",
    "item_count": "{count, plural, =0{No items} =1{One item} other{{count} items}}"
  }
}
```

Use `LocalizedText('ui.start_game')` in widgets — it rebuilds automatically when `l10n.setLocale()` is called:

```dart
LocalizationScope(
  manager: LocalizationManager.instance!,
  child: LocalizedText('ui.start_game', style: TextStyle(fontSize: 24)),
)
```

## Post-Processing with Shaders

Apply fullscreen GLSL effects (bloom, vignette, chromatic aberration) by attaching a `ShaderComponent` to an entity and registering the `PostProcessSystem`.

**Step 1** — Declare the shader in `pubspec.yaml`:
```yaml
flutter:
  shaders:
    - shaders/vignette.frag
```

**Step 2** — Load and attach:
```dart
Future<void> setupPostProcess(Engine engine) async {
  final world = engine.world;

  world.addSystem(PostProcessSystem(
    engine.rendering,
    getTime: () => engine.time.totalTime,
  ));

  final program = await ui.FragmentProgram.fromAsset('shaders/vignette.frag');
  final vfxEntity = world.createEntity(name: 'vfx_vignette');
  vfxEntity.addComponent(ShaderComponent(
    program: program,
    isPostProcess: true,
    passOrder: 0,
    setUniforms: (s, w, h, t) {
      s.setFloat(0, w);   // uResolution.x
      s.setFloat(1, h);   // uResolution.y
      s.setFloat(2, t);   // uTime
    },
  ));
}
```

Chain multiple passes by giving each `ShaderComponent` a different `passOrder` — lower values are applied innermost (closest to the raw scene).

## Deterministic Effects (Multiplayer-safe)

Tick-based property effects guarantee the same result across platforms and reconnecting clients.

```dart
void setupEffects(Engine engine) {
  final world = engine.world;
  final fx = EffectSystemECS();
  world.addSystem(fx);

  // Hit flash: shake then fade out
  fx.scheduleEffect(
    entity: enemy,
    effect: SequenceEffect([
      ShakeEffect(amplitude: 8, durationTicks: 12),
      FadeEffect(to: 0.0, durationTicks: 30),
    ]),
  );

  // Move to position over 1 second (at 60 UPS = 60 ticks)
  fx.scheduleEffect(
    entity: coin,
    effect: MoveEffect(to: playerPos, durationTicks: 60),
  );
}
```

Take a rollback snapshot and restore it later (useful for client-side prediction):
```dart
final snap = fx.snapshot();
// ... simulate ahead ...
fx.restoreSnapshot(snap);
```

## Game Loop Integration

Access the game loop for custom update logic:

```dart
void setupCustomUpdate(Engine engine) {
  // Animation system automatically updates registered animations
  
  // For manual updates, use custom renderables
  engine.rendering.addRenderable(
    CustomRenderable(
      onRender: (canvas, size) {
        // This is called every frame
        myCustomUpdate();
        myCustomRender(canvas, size);
      },
    ),
  );
}
```

## Scene Structure

For complex games, use the scene graph:

```dart
void setupScene(Engine engine) {
  final scene = engine.sceneEditor.createScene('Level1');
  
  // Create player node
  final player = SceneNode('player')
    ..localPosition = Offset.zero
    ..renderable = CircleRenderable(radius: 20, fillColor: Colors.blue);
  
  // Create weapon child node
  final weapon = SceneNode('weapon')
    ..localPosition = Offset(30, 0)
    ..renderable = RectangleRenderable(
      size: Size(40, 10),
      fillColor: Colors.gray,
    );
  
  player.addChild(weapon);
  scene.addNode(player);
  
  // Move player - weapon follows automatically
  player.localPosition = Offset(100, 100);
}
```

## Debugging

Enable debug mode:

```dart
// Show debug info
engine.rendering.debugMode = true;

// Show FPS counter
GameWidget(
  engine: engine,
  showFPS: true,
  showDebug: true,
)
```

## Performance Tips

1. **Use SpriteBatch**: Group sprites sharing an atlas — the engine batches them into a single `Canvas.drawAtlas()` call. The `Quadtree` spatial index activates automatically when renderable count exceeds 200.
2. **Use layers**: Organize objects by layer for efficient rendering
3. **Use `ParticleEmitterComponent`**: ECS-managed emitters clean themselves up (`removeEntityWhenComplete: true`) and use `ObjectPool` internally
4. **Batch updates**: Update multiple objects together
5. **Profile**: Use Flutter DevTools to find bottlenecks
6. **Use Vec2**: For custom physics code, prefer mutable `Vec2` over `Offset` to avoid allocation pressure on hot paths
7. **Use `CommandBuffer`** inside systems: call `world.commands.destroy(entity)` rather than mutating the entity list directly — avoids concurrent-modification errors at zero extra cost

## Common Mistakes

### ❌ Forgetting to initialize

```dart
final engine = Engine();
engine.start();  // ERROR: Not initialized
```

### ✅ Correct

```dart
final engine = Engine();
await engine.initialize();
engine.start();
```

### ❌ Not adding to animation system

```dart
animation.play();  // Animation won't update
```

### ✅ Correct

```dart
engine.animation.addAnimation(animation);
animation.play();
```

### ❌ Forgetting to dispose

```dart
// Memory leak - engine still running
```

### ✅ Correct

```dart
@override
void dispose() {
  engine.dispose();
  super.dispose();
}
```

## Next Steps

1. **Read the full documentation**: Check [README.md](README.md)
2. **Explore the API**: See [API.md](API.md) for detailed reference
4. **Experiment**: Try combining different features

## Getting Help

- Check the example code in `example/`
- Read the API documentation in `API.md`

## Quick Reference

### Common Imports

```dart
import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'dart:math' as math;
```

### Typical Game Structure

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final engine = Engine();
  await engine.initialize();
  
  setupGame(engine);
  
  engine.start();
  runApp(MyGame(engine: engine));
}

void setupGame(Engine engine) {
  // Add renderables
  // Create animations
  // Setup physics
  // Configure camera
}

class MyGame extends StatelessWidget {
  final Engine engine;
  const MyGame({required this.engine});
  
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: GameWidget(
          engine: engine,
          showFPS: true,
        ),
      ),
    );
  }
}
```

Happy game development with Just Game Engine! 🎮

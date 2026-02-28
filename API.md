# Just Game Engine - API Reference

Comprehensive API documentation for all major classes and methods in the Just Game Engine.

## Table of Contents

1. [Core Engine](#core-engine)
2. [Rendering Engine](#rendering-engine)
3. [Sprite System](#sprite-system)
4. [Animation System](#animation-system)
5. [Particle Effects](#particle-effects)
6. [Physics Engine](#physics-engine)
7. [Scene Graph](#scene-graph)
8. [Entity-Component System](#entity-component-system)
9. [Asset Management](#asset-management)
10. [Audio Engine](#audio-engine)

---

## Core Engine

### Engine

Main orchestrator class for the entire game engine.

#### Properties

```dart
EngineState state              // Current engine state
bool isInitialized             // Whether engine is initialized
bool isRunning                 // Whether engine is running
bool isPaused                  // Whether engine is paused

// Subsystem references
RenderingEngine rendering
PhysicsEngine physics
InputManager input
AudioEngine audio
SceneEditor sceneEditor
AnimationSystem animation
AssetManager assets
NetworkManager network
```

#### Methods

```dart
// Initialization
Future<bool> initialize()      // Initialize engine and all subsystems

// Lifecycle
void start()                   // Start the game loop
void pause()                   // Pause the game loop
void resume()                  // Resume the game loop
void stop()                    // Stop the game loop
void dispose()                 // Clean up all resources

// Access
static Engine get instance     // Get singleton instance
```

#### Example

```dart
final engine = Engine();
await engine.initialize();
engine.start();

// Access subsystems
engine.rendering.addRenderable(myCircle);
engine.physics.addBody(myBody);

// Lifecycle control
engine.pause();
engine.resume();
engine.stop();
```

---

### GameLoop

Fixed timestep game loop with configurable update and render callbacks.

#### Properties

```dart
bool isRunning                 // Whether loop is running
double targetUPS               // Target updates per second (default: 60)
double fps                     // Current frames per second
```

#### Methods

```dart
void start()                   // Start the game loop
void pause()                   // Pause the loop
void resume()                  // Resume the loop
void stop()                    // Stop the loop
```

---

### TimeManager

Manages game time and delta time calculations.

#### Properties

```dart
double deltaTime               // Time since last frame (seconds)
double totalTime               // Total elapsed time
double timeScale               // Time scaling factor (default: 1.0)
double fps                     // Current FPS
```

#### Methods

```dart
void update(double dt)         // Update time tracking
void reset()                   // Reset time counters
```

---

## Rendering Engine

### RenderingEngine

Core 2D rendering system using Flutter's Canvas API.

#### Properties

```dart
Camera camera                  // Active camera
Color backgroundColor          // Background clear color
bool debugMode                 // Enable debug visualization
List<Renderable> renderables   // All renderable objects
```

#### Methods

```dart
void initialize()              // Initialize rendering system
void render(Canvas canvas, Size size)  // Render all objects
void addRenderable(Renderable r)       // Add object to render
void removeRenderable(Renderable r)    // Remove object
void clear()                           // Remove all renderables
```

#### Example

```dart
// Add objects
rendering.addRenderable(myCircle);
rendering.addRenderable(myRectangle);

// Configure
rendering.backgroundColor = Colors.black;
rendering.debugMode = true;

// Camera control
rendering.camera.moveBy(Offset(10, 0));
```

---

### Camera

2D camera with pan, zoom, and rotation.

#### Properties

```dart
Offset position                // Camera position
double zoom                    // Zoom level (1.0 = normal)
double rotation                // Camera rotation (radians)
```

#### Methods

```dart
void moveBy(Offset offset)     // Move camera by offset
void moveTo(Offset position)   // Move to absolute position
void zoomBy(double factor)     // Multiply zoom by factor
void zoomTo(double zoom)       // Set absolute zoom
void rotate(double angle)      // Rotate by angle
void lookAt(Offset target)     // Point camera at target
void reset()                   // Reset to default state
```

#### Example

```dart
final camera = rendering.camera;

// Pan
camera.moveBy(Offset(100, 50));
camera.moveTo(Offset.zero);

// Zoom
camera.zoomBy(1.5);    // Zoom in 50%
camera.zoomTo(2.0);    // 2x zoom

// Look at object
camera.lookAt(player.position);
```

---

### Renderable (Base Class)

Base class for all renderable objects.

#### Properties

```dart
Offset position                // World position
double rotation                // Rotation in radians
double scale                   // Uniform scale
double opacity                 // Opacity (0.0 to 1.0)
int layer                      // Z-order layer
bool visible                   // Visibility flag
```

#### Methods

```dart
void render(Canvas canvas, Size size)  // Render the object
```

---

### CircleRenderable

Renders a circle.

```dart
CircleRenderable({
  required double radius,
  Color? fillColor,
  Color? strokeColor,
  double strokeWidth = 1.0,
  Offset position = Offset.zero,
  int layer = 0,
})
```

---

### RectangleRenderable

Renders a rectangle.

```dart
RectangleRenderable({
  required Size size,
  Color? fillColor,
  Color? strokeColor,
  double strokeWidth = 1.0,
  Offset position = Offset.zero,
  double rotation = 0.0,
  int layer = 0,
})
```

---

### GameWidget

Flutter widget that integrates the game engine.

```dart
GameWidget({
  required Engine engine,
  bool showFPS = false,
  bool showDebug = false,
})
```

---

## Sprite System

### Sprite

Renders images and sprite sheet frames.

#### Properties

```dart
ui.Image? image                // The image to render
Rect? sourceRect               // Source rectangle for sprite sheets
double width                   // Display width
double height                  // Display height
bool flipX                     // Horizontal flip
bool flipY                     // Vertical flip
```

#### Constructors

```dart
Sprite()                       // Empty sprite
Sprite.fromAsset(String path)  // Load from asset (static method)
```

#### Methods

```dart
void render(Canvas canvas, Size size)  // Render the sprite
```

#### Example

```dart
// Load sprite
final sprite = Sprite.fromAsset('assets/player.png');

// Use with sprite sheet
sprite.sourceRect = Rect.fromLTWH(0, 0, 32, 32);
sprite.flipX = true;
```

---

### SpriteSheet

Manages sprite atlases with multiple frames.

```dart
SpriteSheet({
  required ui.Image image,
  required int columns,
  required int rows,
  int spacing = 0,
})
```

#### Methods

```dart
Rect getSprite(int index)      // Get source rect for frame
Rect getSpriteXY(int x, int y) // Get rect by column/row
```

---

## Animation System

### Animation (Base Class)

Base class for all animations.

#### Properties

```dart
double currentTime             // Current time in animation
double duration                // Total duration
bool loop                      // Whether to loop
double speed                   // Speed multiplier
bool isPaused                  // Paused state
bool isComplete                // Is animation finished
double normalizedTime          // Time normalized (0.0-1.0)
```

#### Methods

```dart
void update(double deltaTime)  // Update animation
void play()                    // Play animation
void pause()                   // Pause animation
void stop()                    // Stop and reset
void reset()                   // Reset to start
```

---

### PositionTween

Animates object position.

```dart
PositionTween({
  required Offset start,
  required Offset end,
  required Renderable target,
  required double duration,
  Easing easing = Easings.linear,
  bool loop = false,
  VoidCallback? onComplete,
})
```

#### Example

```dart
final anim = PositionTween(
  target: myObject,
  start: Offset(-100, 0),
  end: Offset(100, 0),
  duration: 2.0,
  easing: Easings.easeInOutQuad,
  loop: true,
);
anim.play();
```

---

### RotationTween

Animates object rotation.

```dart
RotationTween({
  required double start,
  required double end,
  required Renderable target,
  required double duration,
  Easing easing = Easings.linear,
  bool loop = false,
})
```

---

### ScaleTween

Animates object scale.

```dart
ScaleTween({
  required double start,
  required double end,
  required Renderable target,
  required double duration,
  Easing easing = Easings.linear,
  bool loop = false,
})
```

---

### OpacityTween

Animates object opacity.

```dart
OpacityTween({
  required double start,      // 0.0 to 1.0
  required double end,
  required Renderable target,
  required double duration,
  Easing easing = Easings.linear,
  bool loop = false,
})
```

---

### AnimationSequence

Chains multiple animations to play in sequence.

```dart
AnimationSequence({
  required List<Animation> animations,
  bool loop = false,
  VoidCallback? onComplete,
})
```

#### Example

```dart
final sequence = AnimationSequence(
  animations: [
    PositionTween(...),  // Play first
    RotationTween(...),  // Then this
    ScaleTween(...),     // Finally this
  ],
  loop: true,
);
sequence.play();
```

---

### AnimationGroup

Runs multiple animations in parallel.

```dart
AnimationGroup({
  required List<Animation> animations,
  bool loop = false,
})
```

---

### SpriteAnimation

Frame-based animation for sprites using sprite sheets.

```dart
SpriteAnimation({
  required Sprite sprite,
  required List<Rect> frames,
  required double duration,
  bool loop = true,
  VoidCallback? onComplete,
})
```

#### Methods

```dart
void updateAnimation(double deltaTime)   // Update current frame
static SpriteAnimation fromSpriteSheet({ // Create from sprite sheet
  required Sprite sprite,
  required int frameCount,
  required int frameWidth,
  required int frameHeight,
  required double duration,
  int startFrame = 0,
  bool loop = true,
})
```

#### Properties

```dart
int currentFrame              // Current frame index
List<Rect> frames            // List of frame rectangles
Sprite sprite                // Target sprite to animate
```

#### Example

```dart
// Create sprite
final sprite = Sprite();
sprite.image = mySpriteSheet;
sprite.renderSize = const Size(64, 64);

// Create animation from sprite sheet
final animation = SpriteAnimation.fromSpriteSheet(
  sprite: sprite,
  frameCount: 8,              // 8 frames in the animation
  frameWidth: 64,             // Each frame is 64px wide
  frameHeight: 64,            // Each frame is 64px tall
  duration: 1.0,              // 1 second total duration
  loop: true,                 // Loop continuously
);

// Add to animation system
engine.animation.addAnimation(animation);
animation.play();

// Control playback
animation.speed = 2.0;        // Play at 2x speed
animation.pause();            // Pause animation
animation.play();             // Resume animation
```

---

### ColorTween

Animates color transitions.

```dart
ColorTween({
  required Color start,
  required Color end,
  required void Function(Color color) onUpdate,
  required double duration,
  Easing easing = Easings.linear,
  bool loop = false,
})
```

---

### Easings

Static easing functions for smooth animations.

#### Available Easings

```dart
Easings.linear
Easings.easeInQuad
Easings.easeOutQuad
Easings.easeInOutQuad
Easings.easeInCubic
Easings.easeOutCubic
Easings.easeInOutCubic
Easings.easeInQuart
Easings.easeOutQuart
Easings.easeInOutQuart
Easings.easeInSine
Easings.easeOutSine
Easings.easeInOutSine
Easings.easeInExpo
Easings.easeOutExpo
Easings.easeInOutExpo
Easings.easeInElastic
Easings.easeOutElastic
Easings.easeInBounce
Easings.easeOutBounce
```

---

## Particle Effects

### ParticleEmitter

Emits and manages particles.

#### Properties

```dart
Offset position                // Emission position
double emissionRate            // Particles per second
double particleLifetime        // How long particles live
Color startColor               // Initial particle color
Color endColor                 // Final particle color
double startSize               // Initial size
double endSize                 // Final size
Offset velocity                // Base velocity
Offset velocityVariation       // Random velocity range
Offset gravity                 // Gravity acceleration
ParticleShape shape            // Particle shape
int maxParticles               // Maximum particle count
```

#### Methods

```dart
void emit()                    // Emit a single particle
void update(double deltaTime)  // Update all particles
void render(Canvas canvas, Size size)  // Render particles
void stop()                    // Stop emission
void clear()                   // Remove all particles
```

#### Example

```dart
final emitter = ParticleEmitter(
  position: Offset(100, 100),
  emissionRate: 50,
  particleLifetime: 2.0,
  startColor: Colors.orange,
  endColor: Colors.red.withOpacity(0),
  startSize: 10,
  endSize: 2,
  velocity: Offset(0, -50),
  gravity: Offset(0, 20),
);

// Update in game loop
emitter.update(deltaTime);
emitter.render(canvas, size);
```

---

### ParticleEffects

Built-in particle effect presets.

```dart
// Explosion
static ParticleEmitter explosion({
  required Offset position,
})

// Fire
static ParticleEmitter fire({
  required Offset position,
})

// Smoke
static ParticleEmitter smoke({
  required Offset position,
})

// Sparkle
static ParticleEmitter sparkle({
  required Offset position,
})

// Rain
static ParticleEmitter rain({
  required Offset position,
})

// Snow
static ParticleEmitter snow({
  required Offset position,
})
```

#### Example

```dart
final explosion = ParticleEffects.explosion(
  position: Offset.zero,
);

final fire = ParticleEffects.fire(
  position: Offset(100, 200),
)..emissionRate = 30;  // Customize
```

---

## Physics Engine

### PhysicsEngine

Manages physics simulation and collision detection.

#### Properties

```dart
Offset gravity                 // Global gravity
bool debugDraw                 // Enable debug rendering
```

#### Methods

```dart
void initialize()              // Initialize physics
void update(double deltaTime)  // Update simulation
void addBody(PhysicsBody body) // Add rigid body
void removeBody(PhysicsBody body)  // Remove body
void renderDebug(Canvas canvas, Size size)  // Debug visualization
void clear()                   // Remove all bodies
Future<void> cachePolygonShape(String id, List<Offset> vertices) // Cache heavy polygons
Future<List<Offset>?> getCachedPolygonShape(String id) // Fetch cached polygon
```

---

### PhysicsBody

Rigid body with collision.

#### Properties

```dart
Offset position                // Body position
Offset velocity                // Current velocity
Offset acceleration            // Current acceleration
CollisionShape shape           // Collision shape (Circle, Rectangle, Polygon)
double mass                    // Body mass
double restitution             // Bounciness (0-1)
double friction                // Surface friction
double drag                    // Velocity damping
double angle                   // Current rotation angle (radians)
double angularVelocity         // Current rotation speed
double torque                  // Accumulated torque
double inertia                 // Rotational inertia
bool isAwake                   // True if actively simulating
bool useGravity                // Whether affected by global gravity
bool isActive                  // Active state
```

#### Methods

```dart
void applyForce(Offset force)  // Apply linear force
void applyTorque(double torque) // Apply angular force
void applyImpulse(Offset impulse) // Apply instant velocity change
```

#### Example

```dart
final body = PhysicsBody(
  position: Offset(100, 0),
  velocity: Offset(50, 0),
  shape: CircleShape(30),
  mass: 1.0,
  restitution: 0.8,
  friction: 0.2,
  drag: 0.1,
);

engine.physics.addBody(body);
```

---

### CollisionShapes

Defines the physical boundaries for narrow-phase collision detection.

#### Available Shapes

```dart
// Circle
CircleShape(double radius)

// Rectangle (Width, Height)
RectangleShape(Size size)

// Arbitrary Convex Polygon
PolygonShape(List<Offset> vertices)
```

#### Example

```dart
final boxBody = PhysicsBody(
  position: Offset.zero,
  shape: RectangleShape(Size(100, 20)),
  mass: 0.0, // Static objects have 0 mass
);
```

---

## Scene Graph

### SceneEditor

Manages scenes and the active scene.

#### Methods

```dart
void initialize()              // Initialize editor
Scene createScene(String name) // Create new scene
void loadScene(String name)    // Load scene by name
void update(double deltaTime)  // Update active scene
void render(Canvas canvas, Size size)  // Render active scene
```

---

### Scene

Container for scene nodes.

#### Properties

```dart
String name                    // Scene name
SceneNode root                 // Root node
```

#### Methods

```dart
void addNode(SceneNode node)   // Add to root
void removeNode(SceneNode node)  // Remove from root
SceneNode? findNode(String name)  // Find by name
List<SceneNode> getAllNodes()  // Get all nodes (flat)
void update(double deltaTime)  // Update scene
void render(Canvas canvas, Size size)  // Render scene
```

---

### SceneNode

Hierarchical transform node.

#### Properties

```dart
String name                    // Node name
SceneNode? parent              // Parent node
List<SceneNode> children       // Child nodes
Offset localPosition           // Local position
double localRotation           // Local rotation
double localScale              // Local scale
Offset worldPosition           // World position (computed)
double worldRotation           // World rotation (computed)
double worldScale              // World scale (computed)
bool isActive                  // Active state
Renderable? renderable         // Attached renderable
int depth                      // Depth in tree
```

#### Methods

```dart
void addChild(SceneNode child)  // Add child node
void removeChild(SceneNode child)  // Remove child
SceneNode? findChild(String name)  // Find descendant
void update(double deltaTime)   // Update node tree
void render(Canvas canvas, Size size)  // Render node tree
```

#### Example

```dart
// Create hierarchy
final parent = SceneNode('parent')
  ..localPosition = Offset(100, 100);

final child = SceneNode('child')
  ..localPosition = Offset(50, 0)
  ..renderable = myCircle;

parent.addChild(child);
scene.addNode(parent);

// Child inherits parent's transform automatically
print(child.worldPosition);  // (150, 100)
```

---

## Type Definitions

### Easing Function

```dart
typedef Easing = double Function(double t);
```

### Lerp Function

```dart
typedef T Function(T a, T b, double t)
```

---

## Entity-Component System

The Entity-Component System (ECS) provides a flexible, data-oriented architecture for organizing game entities and logic. Use ECS when you need composition-based design with efficient processing.

### World

Central manager for all entities and systems in the ECS.

**Usage:**

```dart
final world = engine.world;  // Access from Engine
```

#### Properties

- `List<Entity> entities` - All active entities
- `List<System> systems` - All registered systems
- `Map<String, dynamic> stats` - Statistics (entity count, system count, etc.)

#### Methods

- `Entity createEntity({String? name})` - Create a new entity with optional name
- `void destroyEntity(Entity entity)` - Remove an entity and all its components
- `void destroyAllEntities()` - Remove all entities
- `void addSystem(System system)` - Register a system for processing
- `void removeSystem(System system)` - Unregister a system
- `void update(double deltaTime)` - Update all systems
- `void render(Canvas canvas, Size size)` - Render all systems
- `List<Entity> query(List<Type> componentTypes)` - Find entities with specific components
- `Entity? findEntityByName(String name)` - Find entity by name

#### Example

```dart
final world = engine.world;

// Add systems
world.addSystem(MovementSystem());
world.addSystem(RenderSystem());
world.addSystem(PhysicsSystem()..gravity = const Offset(0, 100));

// Create entity
final player = world.createEntity(name: 'Player');
player.addComponent(TransformComponent(position: Offset.zero));
player.addComponent(VelocityComponent(velocity: const Offset(100, 0)));

// Query entities
final movingEntities = world.query([TransformComponent, VelocityComponent]);
print('Found ${movingEntities.length} moving entities');

// Get stats
print('Total entities: ${world.stats['totalEntities']}');
```

### Entity

Container for components representing a game object.

#### Properties

- `int id` - Unique identifier
- `String? name` - Optional name for identification
- `Map<Type, Component> components` - All attached components

#### Methods

- `void addComponent(Component component)` - Attach a component
- `void removeComponent<T extends Component>()` - Remove component by type
- `T? getComponent<T extends Component>()` - Get component by type
- `bool hasComponent<T extends Component>()` - Check if component exists
- `bool hasComponents(List<Type> types)` - Check if all components exist

#### Example

```dart
final entity = world.createEntity(name: 'Enemy');

// Add components
entity.addComponent(TransformComponent(position: const Offset(100, 100)));
entity.addComponent(HealthComponent(maxHealth: 50));

// Check and get components
if (entity.hasComponent<HealthComponent>()) {
  final health = entity.getComponent<HealthComponent>();
  health?.damage(10);
}

// Remove component
entity.removeComponent<HealthComponent>();
```

### Component

Base class for all components (pure data, no logic).

#### Built-in Components

**TransformComponent**
```dart
TransformComponent({
  Offset position = Offset.zero,
  double rotation = 0.0,
  double scale = 1.0,
})

// Methods
void translate(Offset delta)
void rotate(double delta)
```

**VelocityComponent**
```dart
VelocityComponent({
  Offset velocity = Offset.zero,
  double? maxSpeed,
})

// Properties
double get speed  // Current speed magnitude

// Methods
void setFromAngle(double angle, double speed)
void clampToMaxSpeed()
```

**RenderableComponent**
```dart
RenderableComponent({
  required Renderable renderable,
  bool syncTransform = true,
})
```

**PhysicsBodyComponent**
```dart
PhysicsBodyComponent({
  required double radius,
  double mass = 1.0,
  double restitution = 0.8,
  double drag = 0.0,
  bool isStatic = false,
  int layer = 0,
  int collisionMask = 0xFFFFFFFF,
})

// Methods
bool canCollideWith(PhysicsBodyComponent other)
```

**HealthComponent**
```dart
HealthComponent({
  required double maxHealth,
  double? health,
  bool isInvulnerable = false,
})

// Properties
bool get isAlive
bool get isDead

// Methods
void damage(double amount)
void heal(double amount)
void reset()
```

**LifetimeComponent**
```dart
LifetimeComponent(double lifetime)

// Properties
bool get isExpired
double get progress  // 0.0 to 1.0
```

**TagComponent**
```dart
TagComponent(String tag)
```

**ParentComponent / ChildrenComponent**
```dart
ParentComponent({
  required int parentId,
  Offset localOffset = Offset.zero,
  double localRotation = 0.0,
})

ChildrenComponent()
// Methods: addChild(int), removeChild(int), hasChild(int)
```

**InputComponent**
```dart
InputComponent()

// Properties
Offset moveDirection
Map<String, bool> buttons
```

**AnimationStateComponent**
```dart
AnimationStateComponent()

// Properties
String? currentAnimation
double time
bool isPlaying
bool loop

// Methods
void play(String name, {bool loop = true})
void stop()
```

**SpriteComponent**
```dart
SpriteComponent({
  required String spritePath,
  int frame = 0,
  bool flipX = false,
  bool flipY = false,
  Color? tint,
})
```

### System

Base class for systems that process entities with specific components.

#### Properties

- `List<Type> requiredComponents` - Components needed for entity to be processed
- `List<Entity> entities` - Filtered entities matching requirements
- `bool enabled` - Whether system is active
- `int priority` - Processing order (lower = earlier)

#### Methods

- `void update(double deltaTime)` - Process entities each frame
- `void render(Canvas canvas, Size size)` - Render entities each frame
- `void forEach(void Function(Entity) action)` - Iterate over matching entities
- `void initialize()` - Called when system is added
- `void dispose()` - Called when system is removed

#### Built-in Systems

**MovementSystem**
- Requires: `TransformComponent`, `VelocityComponent`
- Applies velocity to position, clamps to max speed

**RenderSystem**
- Requires: `TransformComponent`, `RenderableComponent`
- Syncs transforms and renders entities

**PhysicsSystem**
- Requires: `TransformComponent`, `VelocityComponent`, `PhysicsBodyComponent`
- Handles gravity, drag, collision detection and resolution
- Properties: `Offset gravity`, `bool enableCollisions`

**LifetimeSystem**
- Requires: `LifetimeComponent`
- Updates lifetime and destroys expired entities

**HierarchySystem**
- Requires: `TransformComponent`, `ParentComponent`
- Propagates parent transforms to children

**HealthSystem**
- Requires: `HealthComponent`
- Handles health regeneration and death
- Properties: `double regenRate`, `bool destroyOnDeath`

**AnimationSystemECS**
- Requires: `AnimationStateComponent`
- Updates animation time

**BoundarySystem**
- Requires: `TransformComponent`
- Enforces world boundaries with configurable behavior
- Constructor: `BoundarySystem({required Rect bounds, BoundaryBehavior behavior})`
- Behaviors: `clamp`, `bounce`, `wrap`, `destroy`

#### Custom System Example

```dart
class DamageOnCollisionSystem extends System {
  @override
  List<Type> get requiredComponents => [
    TransformComponent,
    PhysicsBodyComponent,
    HealthComponent,
  ];

  @override
  void update(double deltaTime) {
    forEach((entity) {
      final transform = entity.getComponent<TransformComponent>()!;
      final health = entity.getComponent<HealthComponent>()!;
      
      // Check collision with other entities
      for (final other in world.query([TransformComponent, PhysicsBodyComponent])) {
        if (other.id == entity.id) continue;
        
        final otherTransform = other.getComponent<TransformComponent>()!;
        final distance = (transform.position - otherTransform.position).distance;
        
        if (distance < 50) {
          health.damage(10 * deltaTime);
        }
      }
    });
  }
}

// Use it
world.addSystem(DamageOnCollisionSystem());
```

### ECS Architecture Pattern

The ECS follows these principles:

1. **Entities** are just IDs with components
2. **Components** contain only data, no logic
3. **Systems** contain all logic and process entities
4. **World** coordinates entities and systems

**Benefits:**
- Composition over inheritance
- Better performance through cache-friendly data layout
- Flexible entity design without deep class hierarchies
- Easy to add/remove behaviors by adding/removing components

**When to use ECS:**
- Games with many similar entities (bullets, enemies, particles)
- When you need flexible entity composition
- Games requiring high performance with many entities

**When to use Scene Graph:**
- UI and menu systems
- Games with complex transform hierarchies
- When you need parent-child relationships

#### Complete ECS Example

```dart
void setupGame(Engine engine) {
  final world = engine.world;
  
  // Add systems in order
  world.addSystem(MovementSystem());
  world.addSystem(PhysicsSystem()..gravity = const Offset(0, 200));
  world.addSystem(BoundarySystem(
    bounds: const Rect.fromLTWH(-400, -300, 800, 600),
    behavior: BoundaryBehavior.bounce,
  ));
  world.addSystem(LifetimeSystem());
  world.addSystem(HealthSystem()
    ..regenRate = 5.0
    ..destroyOnDeath = true);
  world.addSystem(RenderSystem());
  
  // Create player
  final player = world.createEntity(name: 'Player');
  player.addComponent(TransformComponent(position: Offset.zero));
  player.addComponent(VelocityComponent(maxSpeed: 300));
  player.addComponent(RenderableComponent(
    renderable: CircleRenderable(radius: 30, fillColor: Colors.blue),
  ));
  player.addComponent(PhysicsBodyComponent(
    radius: 30,
    mass: 1.0,
    layer: 1,  // Player layer
    collisionMask: 0xFF,  // Collides with all
  ));
  player.addComponent(HealthComponent(maxHealth: 100));
  player.addComponent(InputComponent());
  
  // Create enemies
  for (int i = 0; i < 10; i++) {
    final enemy = world.createEntity(name: 'Enemy_$i');
    enemy.addComponent(TransformComponent(
      position: Offset(
        (i - 5) * 80.0,
        -200,
      ),
    ));
    enemy.addComponent(VelocityComponent(
      velocity: const Offset(0, 50),
    ));
    enemy.addComponent(RenderableComponent(
      renderable: CircleRenderable(radius: 20, fillColor: Colors.red),
    ));
    enemy.addComponent(PhysicsBodyComponent(
      radius: 20,
      mass: 0.8,
      layer: 2,  // Enemy layer
    ));
    enemy.addComponent(HealthComponent(maxHealth: 30));
    enemy.addComponent(LifetimeComponent(10.0));  // Die after 10 seconds
  }
  
  // Query and modify
  final allEnemies = world.query([HealthComponent])
    .where((e) => e.name?.startsWith('Enemy') ?? false);
  print('Created ${allEnemies.length} enemies');
}
```

---

## Asset Management

### AssetManager

Main coordinator for loading and caching game assets.

#### Methods

```dart
Future<Asset> load(Asset asset)                    // Load any asset type
Future<ImageAsset> loadImage(String path)          // Load image asset
Future<AudioAsset> loadAudio(String path)          // Load audio asset
Future<TextAsset> loadText(String path)            // Load text asset
Future<JsonAsset> loadJson(String path)            // Load JSON asset
Future<BinaryAsset> loadBinary(String path)        // Load binary asset
void unload(String path)                           // Unload asset from cache
void clear()                                       // Clear all cached assets
Map<String, dynamic> getCacheStats()               // Get cache statistics
```

#### Example

```dart
final assetManager = AssetManager();

// Load different asset types
final imageAsset = await assetManager.loadImage('assets/images/player.png');
final audioAsset = await assetManager.loadAudio('assets/audio/music.mp3');
final jsonAsset = await assetManager.loadJson('assets/data/config.json');
final textAsset = await assetManager.loadText('assets/data/level1.txt');

// Access loaded data
final image = imageAsset.image;
final audioData = audioAsset.data;
final configData = jsonAsset.data;
final levelText = textAsset.content;

// Check cache statistics
final stats = assetManager.getCacheStats();
print('Total assets: ${stats['totalAssets']}');
print('Memory used: ${stats['totalMemory']} bytes');

// Unload when no longer needed
assetManager.unload('assets/images/old_sprite.png');
```

---

### Asset (Base Class)

Base class for all asset types with lifecycle management.

#### Properties

```dart
String path                    // Asset path
bool isLoaded                  // Whether asset is loaded
```

#### Methods

```dart
Future<void> load()            // Load the asset
void unload()                  // Unload and free memory
int getMemoryUsage()           // Get memory usage in bytes
```

---

### ImageAsset

Loads and manages image assets.

#### Properties

```dart
ui.Image? image                // The loaded image
int? width                     // Image width in pixels
int? height                    // Image height in pixels
```

#### Methods

```dart
Future<void> load()            // Load image from asset bundle
void unload()                  // Dispose image and free memory
int getMemoryUsage()           // Calculate memory usage (width * height * 4)
```

---

### AudioAsset

Loads audio files as binary data for playback.

#### Properties

```dart
Uint8List? data                // Raw audio data
String? format                 // Audio format (mp3, wav, ogg, flac)
```

#### Methods

```dart
Future<void> load()            // Load audio data from asset bundle
void unload()                  // Clear audio data
int getMemoryUsage()           // Get audio data size in bytes
```

---

### TextAsset

Loads plain text files.

#### Properties

```dart
String? content                // Text file content
```

#### Methods

```dart
Future<void> load()            // Load text from asset bundle
void unload()                  // Clear text content
int getMemoryUsage()           // Get text size in bytes
```

---

### JsonAsset

Loads and parses JSON configuration files.

#### Properties

```dart
dynamic data                   // Parsed JSON data (Map or List)
```

#### Methods

```dart
Future<void> load()            // Load and parse JSON from asset bundle
void unload()                  // Clear JSON data
int getMemoryUsage()           // Estimate JSON memory usage
```

#### Example

```dart
final jsonAsset = await assetManager.loadJson('assets/config.json');
final config = jsonAsset.data as Map<String, dynamic>;
final playerSpeed = config['player']['speed'];
final enemyCount = config['enemies'].length;
```

---

### BinaryAsset

Loads raw binary data for custom formats.

#### Properties

```dart
Uint8List? data                // Raw binary data
```

#### Methods

```dart
Future<void> load()            // Load binary data from asset bundle
void unload()                  // Clear binary data
int getMemoryUsage()           // Get binary data size in bytes
```

---

### AssetBundle

Groups multiple assets for batch loading and unloading.

```dart
AssetBundle({
  required String name,
  required List<Asset> assets,
})
```

#### Methods

```dart
Future<void> load(AssetManager manager)    // Load all assets in bundle
void unload(AssetManager manager)          // Unload all assets in bundle
```

#### Example

```dart
final levelBundle = AssetBundle(
  name: 'Level1',
  assets: [
    ImageAsset(path: 'assets/level1/background.png'),
    ImageAsset(path: 'assets/level1/tileset.png'),
    AudioAsset(path: 'assets/level1/music.mp3'),
    JsonAsset(path: 'assets/level1/data.json'),
  ],
);

// Load entire bundle
await levelBundle.load(assetManager);

// Later, unload when level is complete
levelBundle.unload(assetManager);
```

---

## Audio Engine

### AudioEngine

Main coordinator for audio playback with multi-channel mixing.

#### Properties

```dart
Map<AudioChannel, double> channelVolumes   // Volume per channel (0.0-1.0)
Map<AudioChannel, bool> channelMuted       // Mute state per channel
double masterVolume                        // Master volume (0.0-1.0)
bool isMuted                               // Master mute state
```

#### Methods

```dart
Future<void> initialize()                  // Initialize audio engine
Future<AudioClip?> playSfx(
  String path,
  {AudioChannel channel = AudioChannel.sfx,
   double volume = 1.0,
   bool loop = false}
)                                          // Play sound effect
Future<AudioClip?> playMusic(
  String path,
  {double volume = 1.0,
   bool loop = true,
   double fadeInDuration = 0.0}
)                                          // Play background music
void stopMusic({double fadeOutDuration = 0.0})  // Stop music
void pauseMusic()                          // Pause current music
void resumeMusic()                         // Resume paused music
void setMasterVolume(double volume)        // Set master volume (0.0-1.0)
void setChannelVolume(
  AudioChannel channel,
  double volume
)                                          // Set channel volume (0.0-1.0)
void mute()                                // Mute all audio
void unmute()                              // Unmute all audio
void toggleMute()                          // Toggle master mute
void muteChannel(AudioChannel channel)     // Mute specific channel
void unmuteChannel(AudioChannel channel)   // Unmute specific channel
void dispose()                             // Release all audio resources
```

#### Example

```dart
final audioEngine = AudioEngine();
await audioEngine.initialize();

// Play background music with fade in
await audioEngine.playMusic(
  'assets/audio/background_music.mp3',
  volume: 0.7,
  loop: true,
  fadeInDuration: 2.0,
);

// Play sound effects
audioEngine.playSfx('assets/audio/jump.wav', volume: 0.8);
audioEngine.playSfx('assets/audio/shoot.wav', volume: 1.0);

// Control volumes
audioEngine.setMasterVolume(0.8);
audioEngine.setChannelVolume(AudioChannel.music, 0.5);
audioEngine.setChannelVolume(AudioChannel.sfx, 1.0);

// Mute/unmute
audioEngine.muteChannel(AudioChannel.music);
audioEngine.unmuteChannel(AudioChannel.music);
audioEngine.toggleMute();

// Stop music with fade out
audioEngine.stopMusic(fadeOutDuration: 1.5);
```

---

### AudioClip

Individual audio playback controller for a single audio source.

#### Properties

```dart
AudioState state               // Current state (stopped, playing, paused)
double volume                  // Clip volume (0.0-1.0)
bool isLooping                 // Whether clip is looping
```

#### Methods

```dart
Future<void> play()            // Play or resume the clip
void pause()                   // Pause playback
void resume()                  // Resume from pause
void stop()                    // Stop and reset playback
void setVolume(double volume)  // Set clip volume (0.0-1.0)
void setLoop(bool loop)        // Set looping state
void dispose()                 // Release audio resources
```

#### Example

```dart
final clip = await audioEngine.playSfx('assets/audio/explosion.wav');
if (clip != null) {
  clip.setVolume(0.8);
  clip.setLoop(false);
  
  // Later...
  clip.stop();
  clip.dispose();
}
```

---

### SoundEffectManager

Convenience wrapper for sound effect operations.

#### Methods

```dart
Future<AudioClip?> play(
  String path,
  {double volume = 1.0,
   bool loop = false}
)                              // Play sound effect
```

---

### MusicManager

Convenience wrapper for music control with fade effects.

#### Methods

```dart
Future<AudioClip?> play(
  String path,
  {double volume = 1.0,
   bool loop = true,
   double fadeInDuration = 0.0}
)                              // Play background music
void stop({double fadeOutDuration = 0.0})  // Stop music
void pause()                   // Pause music
void resume()                  // Resume music
```

---

### AudioMixer

Volume and mute control interface.

#### Methods

```dart
void setMasterVolume(double volume)        // Set master volume
void setChannelVolume(
  AudioChannel channel,
  double volume
)                                          // Set channel volume
void mute()                                // Mute all
void unmute()                              // Unmute all
void muteChannel(AudioChannel channel)     // Mute channel
void unmuteChannel(AudioChannel channel)   // Unmute channel
```

---

### AudioChannel (Enum)

Audio mixing channels for organizing sounds.

```dart
enum AudioChannel {
  master,      // Master channel (affects all)
  music,       // Background music
  sfx,         // Sound effects
  voice,       // Voice/dialogue
  ambient,     // Ambient sounds
}
```

---

### AudioState (Enum)

Playback state for audio clips.

```dart
enum AudioState {
  stopped,     // Not playing
  playing,     // Currently playing
  paused,      // Paused (can resume)
}
```

---

## Constants

```dart
const double DEFAULT_UPS = 60.0;           // Updates per second
const double DEFAULT_ZOOM = 1.0;           // Camera default zoom
const int DEFAULT_MAX_PARTICLES = 1000;    // Max particles per emitter
```

---

## Best Practices

1. **Initialize before use**: Always call `engine.initialize()` before starting
2. **Dispose when done**: Call `engine.dispose()` to clean up resources
3. **Use layers**: Organize renderables with layer numbers for proper z-ordering
4. **Pool objects**: Reuse particles and projectiles instead of creating new ones
5. **Check state**: Verify `engine.isInitialized` before accessing subsystems
6. **Animation management**: Add animations to `AnimationSystem` for automatic updates
7. **Scene graph**: Use for complex hierarchies, simple games can use flat rendering

---

For more examples and tutorials, see the README.md and check the demo application.

# Just Game Engine - API Reference

Comprehensive API documentation for all major classes and methods in the Just Game Engine.

## Table of Contents

1. [Core Engine](#core-engine)
2. [Rendering Engine](#rendering-engine)
3. [Sprite System](#sprite-system)
4. [Animation System](#animation-system)
5. [Particle Effects](#particle-effects)
6. [Physics Engine](#physics-engine)
7. [Ray Casting & Tracing](#ray-casting--tracing)
8. [Scene Graph](#scene-graph)
9. [Entity-Component System](#entity-component-system)
10. [Asset Management](#asset-management)
11. [Audio Engine](#audio-engine)
12. [Tiled Map Support](#tiled-map-support)

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

As of v1.2.1, `GameWidget` automatically calls `engine.world.render(canvas, size)` during each paint, so ECS entities registered with `RenderSystem` are drawn alongside the classic rendering pipeline without any extra wiring.

---

### RayRenderable

A `Renderable` that draws a glowing beam, laser, or bullet trail in world space and fades it out over its lifetime. Useful for visualising ray casts or projectile trails.

#### Constructor

```dart
RayRenderable({
  required Offset start,         // World-space start point
  required Offset end,           // World-space end point
  Color color = const Color(0xFFFFFF44),  // Core beam colour
  double width = 2.5,            // Core line stroke width (world units)
  double glowWidthMultiplier = 4.0,  // Glow width relative to core
  double glowBlurSigma = 5.0,    // Blur applied to glow (0 = no blur)
  double lifetime = 0.25,        // Fade duration in seconds (0 = permanent)
  int layer = 5,
  int zOrder = 10,
})
```

#### Properties

```dart
bool get isExpired             // true once the fade timer elapses
```

#### Methods

```dart
void update(double dt)         // Advance fade timer; call every frame before render
void render(Canvas canvas, Size size)  // Draw the glowing beam
```

#### Example

```dart
// Create a laser beam that fades over 0.5 seconds
final beam = RayRenderable(
  start: playerPos,
  end: hitPoint,
  color: Colors.cyanAccent,
  width: 3.0,
  lifetime: 0.5,
);
engine.rendering.addRenderable(beam);

// In game loop — advance timer and remove when expired
beam.update(deltaTime);
if (beam.isExpired) {
  engine.rendering.removeRenderable(beam);
}
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

## Ray Casting & Tracing

Spatial query system for hit detection, line-of-sight checks, and multi-bounce reflections. Added in v1.2.0.

### Ray

A 2D ray descriptor with an origin, normalised direction, and maximum travel distance.

```dart
Ray({
  required Offset origin,
  required Offset direction,   // Auto-normalised; Offset.zero falls back to +x axis
  double maxDistance = 2000.0,
})

// Convenience constructor
factory Ray.fromPoints(Offset from, Offset to, {double? maxDistance})
```

#### Methods

```dart
Offset at(double t)            // World-space point at distance t along the ray
```

---

### RaycastSystem

ECS system that provides ray-vs-collider intersection tests. Performs no per-frame work — it is a pure on-demand query API.

```dart
final raycastSys = RaycastSystem();
world.addSystem(raycastSys);
```

#### Methods

```dart
// Returns the closest hit entity, or null if nothing is intersected
RaycastHit? castRay(Ray ray, {String? filterTag})

// Returns all intersected entities, sorted nearest-first
List<RaycastHit> castRayAll(Ray ray, {String? filterTag})

// Returns true if no blocking collider exists between two points (LOS check)
bool hasLineOfSight(Offset from, Offset to, {String? ignoreTag})
```

---

### RaycastHit

Intersection result returned by `RaycastSystem`.

#### Properties

```dart
Entity entity                  // The entity that was intersected
Offset point                   // World-space hit point
double distance                // Distance from ray origin to hit point
Offset normal                  // Outward surface normal at hit point
```

---

### RayTracer

Performs multi-bounce ray tracing against reflective surfaces (`isReflective = true`).

```dart
RayTracer({
  required RaycastSystem raycastSystem,
  int maxBounces = 3,          // Maximum reflection bounces
  double minReflectivity = 0.1, // Minimum reflectivity to produce a bounce
})
```

#### Methods

```dart
// Trace ray through world, bouncing off reflective surfaces
RayTrace trace(Ray ray, {String? filterTag})
```

---

### RayTrace / RayTraceSegment

Result of a `RayTracer.trace()` call.

```dart
class RayTrace {
  List<RayTraceSegment> segments  // Ordered path segments (first = initial ray)
  List<RaycastHit> get hits       // All non-null hits across all segments
  double get totalLength          // Total path length (world units)
}

class RayTraceSegment {
  Offset from                  // World-space start of segment
  Offset to                    // World-space end of segment
  RaycastHit? hit              // Hit at 'to', or null if ray missed
}
```

#### Full Example

```dart
// Setup
final raycastSys = RaycastSystem();
world.addSystem(raycastSys);

// Mark entities as hittable
enemy.addComponent(RaycastColliderComponent(radius: 14.0, tag: 'enemy'));
wall.addComponent(RaycastColliderComponent(
  radius: 50.0, tag: 'wall',
  isReflective: true, reflectivity: 0.7,
));

// Simple ray cast
final ray = Ray(origin: playerPos, direction: aimDir);
final hit = raycastSys.castRay(ray, filterTag: 'enemy');
if (hit != null) {
  enemy.getComponent<HealthComponent>()?.damage(25);
  // Visualise the hit
  engine.rendering.addRenderable(RayRenderable(
    start: playerPos, end: hit.point,
    color: Colors.red, lifetime: 0.3,
  ));
}

// Line-of-sight check
final canSee = raycastSys.hasLineOfSight(guardPos, playerPos, ignoreTag: 'guard');

// Multi-bounce trace
final tracer = RayTracer(raycastSystem: raycastSys, maxBounces: 3);
final trace = tracer.trace(Ray(origin: laserPos, direction: laserDir));
for (final seg in trace.segments) {
  engine.rendering.addRenderable(RayRenderable(
    start: seg.from, end: seg.to,
    color: Colors.cyanAccent, lifetime: 0.5,
  ));
}
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

**RaycastColliderComponent**
```dart
RaycastColliderComponent({
  required double radius,    // Collision radius in world units
  String? tag,               // Optional filter tag (e.g. 'enemy', 'wall')
  bool isBlocker = true,     // When true ray terminates on hit; false = ray passes through
  bool isReflective = false, // Whether rays can bounce off this surface
  double reflectivity = 0.8, // Energy coefficient for reflected ray (0–1)
})
```

Used with `RaycastSystem` and `RayTracer`. Add to entities that should participate in ray queries.

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

**RaycastSystem**
- Requires: `TransformComponent`, `RaycastColliderComponent`
- Query-only: no per-frame logic. Call `castRay()`, `castRayAll()`, or `hasLineOfSight()` on demand.
- See the [Ray Casting & Tracing](#ray-casting--tracing) section for full API.

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

---

## Tiled Map Support

Tiled map integration is provided by the companion package [`just_tiled`](https://pub.dev/packages/just_tiled). Add it to your `pubspec.yaml`:

```yaml
dependencies:
  just_tiled: ^0.2.0
```

---

### TileMapParser

Async parser for Tiled `.tmx` map files and `.tsx` tileset files.

#### Methods

```dart
// Parse a map from the Flutter asset bundle
static Future<TileMap> parseAsset(String assetPath)

// Parse a map from a raw XML string
static Future<TileMap> parseString(String xmlContent)

// Parse a map from a file path (non-web platforms)
static Future<TileMap> parseFile(String filePath)
```

Supported tile encodings: **CSV**, **Base64**, **XML**.
Supported compressions: **GZIP**, **Zlib**, **Zstandard** (via `just_zstd`).

#### Example

```dart
import 'package:just_tiled/just_tiled.dart';

final tileMap = await TileMapParser.parseAsset('assets/maps/level1.tmx');
print('Map size: ${tileMap.width}x${tileMap.height} tiles');
print('Tile size: ${tileMap.tileWidth}x${tileMap.tileHeight}px');
print('Layers: ${tileMap.layers.length}');
```

---

### TileMap

The parsed map data model.

#### Properties

```dart
int width                      // Map width in tiles
int height                     // Map height in tiles
int tileWidth                  // Tile width in pixels
int tileHeight                 // Tile height in pixels
MapOrientation orientation     // orthogonal | isometric | staggered | hexagonal
List<Layer> layers             // All layers (tile, object, image, group)
List<Tileset> tilesets         // All referenced tilesets
Map<String, String> properties // Custom map properties
```

---

### Layer Types

**TileLayer** — grid of tile GIDs.
```dart
String name
List<int> data                 // Flat list of tile GIDs (width * height)
int width
int height
Map<String, String> properties
```

**ObjectLayer** — collection of map objects.
```dart
String name
List<MapObject> objects
DrawOrder drawOrder            // topDown | index
Map<String, String> properties
```

**ImageLayer** — background/foreground image.
```dart
String name
String imagePath
Offset offset
Map<String, String> properties
```

**GroupLayer** — contains nested layers.
```dart
String name
List<Layer> layers
Map<String, String> properties
```

---

### MapObject

Represents a Tiled object (rectangle, ellipse, point, polygon, polyline, or tile object).

#### Properties

```dart
int id
String name
String type
Rect bounds                    // position and size in world-space pixels
List<Offset>? polygon          // polygon vertices (relative to bounds.topLeft)
List<Offset>? polyline         // polyline points
bool isPoint
bool isEllipse
Map<String, String> properties // Custom properties
```

---

### TextureAtlas

Builds a packed texture atlas from all tilesets referenced by a `TileMap`.

#### Constructor

```dart
static Future<TextureAtlas> fromTileMap(TileMap tileMap)
```

#### Properties

```dart
ui.Image image                 // The packed atlas image
Map<int, Rect> sourceRects     // GID → source rect in the atlas
```

---

### TileMapRenderer

GPU-batched renderer that draws a single `TileLayer` using `Canvas.drawRawAtlas`, submitting all tiles in one draw call.

#### Constructor

```dart
TileMapRenderer({
  required TileMap tileMap,
  required TileLayer layer,
  required TextureAtlas atlas,
  Offset offset = Offset.zero,  // World-space render offset
})
```

#### Methods

```dart
void render(Canvas canvas)      // Draw all tiles in the layer
void update(double dt)          // Advance animated tile timers
```

#### Example

```dart
final tileMap = await TileMapParser.parseAsset('assets/maps/level1.tmx');
final atlas   = await TextureAtlas.fromTileMap(tileMap);

final renderers = tileMap.layers
    .whereType<TileLayer>()
    .map((layer) => TileMapRenderer(tileMap: tileMap, layer: layer, atlas: atlas))
    .toList();

engine.rendering.addRenderable(
  CustomRenderable(
    onRender: (canvas, size) {
      for (final r in renderers) {
        r.update(engine.time.deltaTime); // animate tiles
        r.render(canvas);
      }
    },
  ),
);
```

---

### SpatialHashGrid\<T\>

Generic $O(1)$ spatial hash grid for fast AABB, point, and radius queries. Ideal for indexing map objects and querying which ones overlap the camera or player.

#### Constructor

```dart
SpatialHashGrid<T>({
  required double cellSize,     // Grid cell size in world units
})
```

#### Methods

```dart
void insert(T item, Rect bounds)       // Insert item with AABB
void remove(T item, Rect bounds)       // Remove item
void update(T item, Rect oldBounds, Rect newBounds)  // Move item

List<T> queryAABB(Rect bounds)         // Items overlapping a rectangle
List<T> queryPoint(Offset point)       // Items containing a point
List<T> queryRadius(Offset center, double radius)    // Items within radius

void clear()                           // Remove all items
```

#### Example

```dart
// Index all map objects from object layers
final grid = SpatialHashGrid<MapObject>(cellSize: 128);
for (final layer in tileMap.layers.whereType<ObjectLayer>()) {
  for (final obj in layer.objects) {
    grid.insert(obj, obj.bounds);
  }
}

// Every frame: check which objects the player overlaps
final overlapping = grid.queryAABB(player.bounds);
for (final obj in overlapping) {
  if (obj.type == 'trigger') activateTrigger(obj);
  if (obj.type == 'enemy_spawn') spawnEnemy(obj.bounds.center);
}

// Radius-based interaction check
final nearby = grid.queryRadius(playerPos, interactRadius);
```

---

### Tileset

Describes a tileset referenced by a `TileMap`.

#### Properties

```dart
int firstGid                   // First global tile ID in this tileset
String name
int tileWidth
int tileHeight
int spacing
int margin
int columns
String? imagePath              // Path to the tileset image
Map<int, TileData> tiles       // Per-tile metadata (animations, properties)
```

---

### TileData / AnimationFrame

Per-tile metadata including animation sequences.

```dart
class TileData {
  int localId
  List<AnimationFrame> animation   // Non-empty = animated tile
  Map<String, String> properties
}

class AnimationFrame {
  int tileId      // Local tile ID for this frame
  int duration    // Frame duration in milliseconds
}
```

#### Example

```dart
// Log all animated tiles in a tileset
for (final entry in tileMap.tilesets.first.tiles.entries) {
  final tile = entry.value;
  if (tile.animation.isNotEmpty) {
    print('Tile ${entry.key}: ${tile.animation.length} frames');
  }
}
```

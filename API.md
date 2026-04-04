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
13. [Math Module](#math-module)
14. [Memory Management](#memory-management)
15. [System Priorities](#system-priorities)
16. [Post-Processing](#post-processing)
17. [Deterministic Effects](#deterministic-effects)
18. [Localization](#localization)
19. [Narrative / Dialogue](#narrative--dialogue)

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
CacheManager cache             // LRU binary cache (via just_storage / just_database)
CameraSystem cameraSystem      // Camera management subsystem
World world                    // ECS World
GameLoop gameLoop              // Game loop reference
SystemManager systemManager    // Frame scheduler and subsystem registry
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
engine.cache;           // CacheManager
engine.cameraSystem;    // CameraSystem
engine.world;           // ECS World
engine.gameLoop;        // GameLoop
engine.systemManager;   // SystemManager

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

### SystemManager

Frame scheduler and subsystem registry. Accessible via `engine.systemManager`.

#### Properties

```dart
bool isInitialized             // Whether initialized
int systemCount                // Number of registered subsystems
double lastFrameMs             // Total scheduler frame time in milliseconds
Map<String, dynamic> schedulerStats  // Per-frame timing snapshot (rebuilt once per cycle)
UnmodifiableMapView<String, double> lastTaskTimesMs  // Per-task timings in milliseconds
```

#### Methods

```dart
// Subsystem registry
void registerSystem<T>(String name, T system)  // Register by name + type
bool unregisterSystem(String name)             // Remove by name
T? getSystem<T>()                             // Lookup by type
dynamic getSystemByName(String name)           // Lookup by name
bool hasSystem(String name)                    // Name presence check
bool hasSystemOfType<T>()                      // Type presence check

// Frame scheduler
void registerUpdateTask(String name, UpdateTask task)  // Add ordered update task
bool unregisterUpdateTask(String name)                 // Remove update task
void runUpdateCycle(double deltaTime)                  // Execute all tasks in order
```

#### Example

```dart
final sm = engine.systemManager;

// Inspect per-task frame budget
final stats = sm.schedulerStats;
print('Frame: ${stats['lastFrameMs'].toStringAsFixed(2)} ms');
sm.lastTaskTimesMs.forEach((name, ms) {
  print('  $name: ${ms.toStringAsFixed(2)} ms');
});

// Register a custom update task
sm.registerUpdateTask('ai_update', (dt) => aiManager.update(dt));
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

As of v1.2.1, `GameWidget` automatically calls `engine.world.render(canvas, size)` during each paint, so ECS entities registered with `RenderSystem` are drawn alongside the classic rendering pipeline without any extra wiring. In v1.4.0, the rendering pipeline additionally supports `SpriteBatch` (via `Canvas.drawAtlas`) and `Quadtree` viewport culling for large renderable counts.

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
Offset position                // Body position (also available as Vec2 via .pos)
Offset velocity                // Current velocity (also available as Vec2 via .vel)
Offset acceleration            // Current acceleration (also available as Vec2 via .acc)
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

- `LinkedHashSet<Entity> entities` - All active entities (O(1) add/remove)
- `List<System> systems` - All registered systems
- `Map<String, dynamic> stats` - Statistics (entity count, system count, etc.)
- `CommandBuffer commands` - Deferred mutation queue (see [CommandBuffer](#commandbuffer))
- `EventBus events` - Typed event bus (see [EventBus](#eventbus))

#### Methods

- `Entity createEntity({String? name})` - Create a new entity with optional name
- `void destroyEntity(Entity entity)` - Remove an entity and all its components
- `void destroyAllEntities()` - Remove all entities
- `void addSystem(System system)` - Register a system for processing
- `void removeSystem(System system)` - Unregister a system
- `void update(double deltaTime)` - Update all systems, then flush CommandBuffer
- `void render(Canvas canvas, Size size)` - Render all systems
- `UnmodifiableListView<Entity> query(List<Type> componentTypes)` - Find entities with specific components (cached; selective invalidation via XOR hash)
- `Entity? findEntityByName(String name)` - Find entity by name
- `bool isEntityAlive(EntityId id)` - Generational check for stale entity references
- `EntityId instantiate(EntityPrefab prefab)` - Create entity from a reusable blueprint

#### Example

```dart
final world = engine.world;

// Add systems (priority order is automatic)
world.addSystem(InputSystem());          // priority 100
world.addSystem(MovementSystem());       // priority 80
world.addSystem(RenderSystem());         // priority 40
world.addSystem(PhysicsSystem()..gravity = const Offset(0, 100));

// Create entity from prefab
final enemyPrefab = EntityPrefab(
  name: 'Enemy',
  components: [
    TransformComponent(position: Offset.zero),
    VelocityComponent(velocity: const Offset(0, 50)),
    HealthComponent(maxHealth: 30),
  ],
);
final enemyId = world.instantiate(enemyPrefab);

// Deferred mutations via CommandBuffer
world.commands.destroyEntity(enemyId);  // queued, applied after update()

// Typed events via EventBus
world.events.on<CollisionEvent>((event) {
  print('Collision: ${event.entityA} vs ${event.entityB}');
});

// Check entity validity
if (world.isEntityAlive(enemyId)) {
  print('Entity is alive');
}

// Query entities (cached, returns UnmodifiableListView)
final movingEntities = world.query([TransformComponent, VelocityComponent]);
print('Found ${movingEntities.length} moving entities');

// Get stats
print('Total entities: ${world.stats['totalEntities']}');
```

### CommandBuffer

Queues entity mutations during system updates to prevent concurrent-modification errors. Flushed automatically at the end of `World.update()`.

#### Methods

- `void createEntity({String? name, List<Component>? components})` - Queue entity creation
- `void destroyEntity(EntityId id)` - Queue entity destruction
- `void addComponent(EntityId id, Component component)` - Queue component addition
- `void removeComponent<T extends Component>(EntityId id)` - Queue component removal
- `void flush(World world)` - Execute all queued operations (called automatically)

#### Example

```dart
class SpawnerSystem extends System {
  @override
  void update(double deltaTime) {
    // Safe to queue mutations during update — no ConcurrentModificationError
    world.commands.createEntity(
      name: 'Bullet',
      components: [
        TransformComponent(position: gunTip),
        VelocityComponent(velocity: Offset(500, 0)),
        LifetimeComponent(2.0),
      ],
    );
  }
}
```

### EventBus

Typed publish-subscribe event system. Events are dispatched synchronously.

#### Methods

- `void fire<T extends GameEvent>(T event)` - Publish an event to all subscribers
- `void on<T extends GameEvent>(void Function(T) callback)` - Subscribe to event type
- `void off<T extends GameEvent>(void Function(T) callback)` - Unsubscribe

#### Built-in Events

**CollisionEvent**
```dart
CollisionEvent({
  required EntityId entityA,
  required EntityId entityB,
  required Offset contactPoint,
  required Offset normal,
})
```

#### Custom Event Example

```dart
class DamageEvent extends GameEvent {
  final EntityId target;
  final double amount;
  DamageEvent({required this.target, required this.amount});
}

// Subscribe
world.events.on<DamageEvent>((event) {
  final health = world.getComponent<HealthComponent>(event.target);
  health?.damage(event.amount);
});

// Fire
world.events.fire(DamageEvent(target: enemyId, amount: 25));
```

### EntityPrefab

Reusable entity blueprint. Define once, instantiate many times.

#### Constructor

```dart
EntityPrefab({
  String? name,
  required List<Component> components,
})
```

#### Example

```dart
final bulletPrefab = EntityPrefab(
  name: 'Bullet',
  components: [
    TransformComponent(),
    VelocityComponent(maxSpeed: 800),
    PhysicsBodyComponent(radius: 4, mass: 0.1),
    LifetimeComponent(3.0),
    RenderableComponent(renderable: CircleRenderable(radius: 4, fillColor: Colors.yellow)),
  ],
);

// Stamp out bullets
for (int i = 0; i < 5; i++) {
  final id = world.instantiate(bulletPrefab);
  // Customize after creation
  final transform = world.getComponent<TransformComponent>(id);
  transform?.position = gunTip + Offset(i * 10.0, 0);
}
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
int frameCount                 // Total frames in current animation
double frameDuration           // Duration per frame (seconds)
int currentFrame               // Current frame index

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

**PhysicsBodyRefComponent**
```dart
PhysicsBodyRefComponent({
  required PhysicsBody body,   // Reference to a standalone PhysicsBody
})
```
Used with `PhysicsBridgeSystem` to sync standalone `PhysicsEngine` bodies into ECS components.

**JoystickInputComponent**
```dart
JoystickInputComponent()

// Properties
Offset direction               // Normalized joystick direction
double magnitude               // Joystick displacement (0.0–1.0)
```
Populated by `InputSystem` from `VirtualJoystick` widget data.

**AudioSourceComponent**
```dart
AudioSourceComponent({
  required String clipPath,
  double volume = 1.0,
  double pan = 0.0,
  bool loop = false,
  bool is3D = false,
  AudioChannel channel = AudioChannel.sfx,
})
```
Attach to an entity for ECS-driven audio playback via `AudioSystem`.

**AudioPlayComponent**
```dart
AudioPlayComponent({
  required String clipPath,
  double volume = 1.0,
})
```
One-shot audio trigger. `AudioSystem` plays the clip and removes the component.

**TileMapLayerComponent**
```dart
TileMapLayerComponent({
  required TileLayer tileLayer,
  required TileMapRenderer renderer,
})
```
Pairs a parsed `TileLayer` with its GPU-batched renderer for ECS-driven tile map rendering via `TileMapRenderSystem`.

**TiledObjectComponent**
```dart
TiledObjectComponent({
  required MapObject object,
  Map<String, String>? properties,
})
```
Attaches Tiled map object metadata to an entity for collision or trigger logic.

**UIComponent**
```dart
UIComponent({
  Size size = Size.zero,
  bool visible = true,
  bool enabled = true,
  int layer = 0,
})
```
Base UI element. Rendered by `RenderSystem`.

**TextComponent**
```dart
TextComponent({
  required String text,
  TextStyle? style,
  TextAlign alignment = TextAlign.left,
})
```

**ButtonComponent**
```dart
ButtonComponent({
  ButtonState state = ButtonState.normal,
  VoidCallback? onClick,
})
```

**LinearProgressComponent**
```dart
LinearProgressComponent({
  double progress = 0.0,       // 0.0 – 1.0
})
```

**CircularProgressComponent**
```dart
CircularProgressComponent({
  double progress = 0.0,       // 0.0 – 1.0
})
```

**ShaderComponent**
```dart
ShaderComponent({
  required ui.FragmentProgram program,
  bool isPostProcess = false,
  int passOrder = 0,
  bool enabled = true,
  void Function(ui.FragmentShader, double w, double h, double t)? setUniforms,
})
```
Attaches a GLSL `FragmentShader` to an entity. Per-entity mode wraps the entity's renderable in `canvas.saveLayer`; post-process mode registers a fullscreen `PostProcessPass` with the `RenderingEngine`. See [Post-Processing](#post-processing).

**EffectComponent**
```dart
EffectComponent()

// Properties
EffectPlayer player            // Active per-entity effect queue
```
Tick-driven effect queue. Created automatically by `EffectSystemECS.scheduleEffect`. See [Deterministic Effects](#deterministic-effects).

**ParallaxComponent**
```dart
ParallaxComponent({
  required ParallaxBackground background,
})
```
Attaches a `ParallaxBackground` (multi-layer scrolling backdrop) to an entity.

**ParticleEmitterComponent**
```dart
ParticleEmitterComponent({
  required ParticleEmitter emitter,
  bool syncPositionFromTransform = true,
  bool removeEntityWhenComplete = false,
})
```
ECS wrapper for `ParticleEmitter`. `syncPositionFromTransform` copies the entity's `TransformComponent.position` to the emitter each frame. `removeEntityWhenComplete` auto-destroys the entity via `CommandBuffer` when all particles expire.

**CameraFollowComponent**
```dart
CameraFollowComponent({
  bool enabled = true,
  double lookaheadDistance = 80.0,
  double deadZoneWidth = 0.0,
  double deadZoneHeight = 0.0,
  int priority = 0,
})
```
Marks an entity as a camera follow target for `CameraFollowSystem`. Multiple entities with the same lowest priority value trigger multi-target zoom-to-fit mode. Requires `VelocityComponent` for lookahead to be applied.

### System

Base class for systems that process entities with specific components.

#### Properties

- `List<Type> requiredComponents` - Components needed for entity to be processed
- `List<Entity> entities` - Filtered entities matching requirements
- `bool enabled` - Whether system is active
- `int priority` - Processing order (higher = runs first)

#### Methods

- `void update(double deltaTime)` - Process entities each frame
- `void render(Canvas canvas, Size size)` - Render entities each frame
- `void forEach(void Function(Entity) action)` - Iterate over matching entities
- `void initialize()` - Called when system is added
- `void dispose()` - Called when system is removed

#### Built-in Systems

**TileMapRenderSystem** (priority 110)
- Requires: `TileMapLayerComponent`
- Renders tile layers as background

**InputSystem** (priority 100)
- Requires: `InputComponent` (+ optional `JoystickInputComponent`)
- Bridges `InputManager` → `InputComponent` / `JoystickInputComponent` via configurable `ButtonMapping`

**PhysicsSystem** (priority 90)
- Requires: `TransformComponent`, `VelocityComponent`, `PhysicsBodyComponent`
- Handles gravity, drag, collision detection and resolution
- Fires `CollisionEvent` via `world.events`
- Properties: `Offset gravity`, `bool enableCollisions`

**PhysicsBridgeSystem** (priority 89)
- Requires: `TransformComponent`, `VelocityComponent`, `PhysicsBodyRefComponent`
- Syncs standalone `PhysicsBody.pos/vel/angle` → ECS components (runs after PhysicsSystem)

**MovementSystem** (priority 80)
- Requires: `TransformComponent`, `VelocityComponent`
- Applies velocity to position, clamps to max speed

**AnimationSystemECS** (priority 70)
- Requires: `AnimationStateComponent` (+ optional `SpriteComponent`)
- Advances animation timers, drives `SpriteComponent.frame`, stops non-looping animations

**HealthSystem** (priority 60)
- Requires: `HealthComponent`
- Handles health regeneration and death
- Properties: `double regenRate`, `bool destroyOnDeath`

**HierarchySystem** (priority 50)
- Requires: `TransformComponent`, `ParentComponent`
- Propagates parent transforms to children

**RenderSystem** (priority 40)
- Requires: `TransformComponent`, `RenderableComponent`
- Syncs transforms and renders entities
- Also renders UI components (`TextComponent`, `ButtonComponent`, `LinearProgressComponent`, `CircularProgressComponent`)

**BoundarySystem** (priority 30)
- Requires: `TransformComponent`
- Enforces world boundaries with configurable behavior via `world.commands`
- Constructor: `BoundarySystem({required Rect bounds, BoundaryBehavior behavior})`
- Behaviors: `clamp`, `bounce`, `wrap`, `destroy`

**DebugSystem** (priority 10)
- Internal diagnostics overlay (not exported)

**AudioSystem** (priority -10)
- Requires: `AudioSourceComponent` (+ optional `AudioPlayComponent`)
- Plays audio via `AudioSourceComponent`; consumes `AudioPlayComponent` one-shot triggers

**LifetimeSystem**
- Requires: `LifetimeComponent`
- Updates lifetime and destroys expired entities

**RaycastSystem**
- Requires: `TransformComponent`, `RaycastColliderComponent`
- Query-only: no per-frame logic. Call `castRay()`, `castRayAll()`, or `hasLineOfSight()` on demand.
- See the [Ray Casting & Tracing](#ray-casting--tracing) section for full API.

**TiledCollisionSystem**
- Requires: `TransformComponent`, `PhysicsBodyComponent`
- Collision detection against Tiled map obstacles

**EffectSystemECS** (priority 65)
- Requires: `EffectComponent`
- Drives all tick-based `DeterministicEffect`s each fixed-timestep update; implements `EffectRuntime`
- API: `scheduleEffect`, `cancelEffects`, `snapshot`, `restoreSnapshot`, `currentTick`
- See [Deterministic Effects](#deterministic-effects) for full API.

**ParticleSystemECS** (priority 48)
- Requires: `ParticleEmitterComponent`
- Syncs emitter position from `TransformComponent` (when `syncPositionFromTransform = true`), advances `ParticleEmitter.update`, auto-destroys completed one-shot emitters

**CameraFollowSystem** (priority 45)
- Requires: `TransformComponent`, `CameraFollowComponent`
- Single-target: spring + lookahead follow via `CameraSystem`; multi-target: auto-zoom to keep all targets in view
- Constructor: `CameraFollowSystem({required CameraSystem cameraSystem})`

**PostProcessSystem** (priority 35)
- Requires: `ShaderComponent` (with `isPostProcess = true`)
- Syncs post-process shader entities to `RenderingEngine.addPostProcessPass` / `removePostProcessPass` each frame
- Constructor: `PostProcessSystem(RenderingEngine, {double Function()? getTime})`
- See [Post-Processing](#post-processing) for full API.

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
  
  // Add systems — priority order is automatic
  world.addSystem(InputSystem());       // 100
  world.addSystem(MovementSystem());    // 80
  world.addSystem(PhysicsSystem()..gravity = const Offset(0, 200));  // 90
  world.addSystem(BoundarySystem(
    bounds: const Rect.fromLTWH(-400, -300, 800, 600),
    behavior: BoundaryBehavior.bounce,
  ));                                    // 30
  world.addSystem(LifetimeSystem());
  world.addSystem(HealthSystem()
    ..regenRate = 5.0
    ..destroyOnDeath = true);           // 60
  world.addSystem(RenderSystem());      // 40
  world.addSystem(AudioSystem());       // -10
  
  // Listen for collisions
  world.events.on<CollisionEvent>((event) {
    print('Collision between ${event.entityA} and ${event.entityB}');
  });
  
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
    layer: 1,
    collisionMask: 0xFF,
  ));
  player.addComponent(HealthComponent(maxHealth: 100));
  player.addComponent(InputComponent());
  player.addComponent(JoystickInputComponent());  // Touch controls
  
  // Create enemies from prefab
  final enemyPrefab = EntityPrefab(
    name: 'Enemy',
    components: [
      TransformComponent(),
      VelocityComponent(velocity: const Offset(0, 50)),
      RenderableComponent(
        renderable: CircleRenderable(radius: 20, fillColor: Colors.red),
      ),
      PhysicsBodyComponent(radius: 20, mass: 0.8, layer: 2),
      HealthComponent(maxHealth: 30),
      LifetimeComponent(10.0),
    ],
  );
  
  for (int i = 0; i < 10; i++) {
    final id = world.instantiate(enemyPrefab);
    final transform = world.getComponent<TransformComponent>(id);
    transform?.position = Offset((i - 5) * 80.0, -200);
  }
  
  // Query and check
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
4. **Use ObjectPool**: Recycle bullets, particles, and short-lived objects via `ObjectPool<T>` instead of allocating new ones
5. **Use CommandBuffer**: Queue entity creation/destruction inside systems via `world.commands` to avoid concurrent-modification errors
6. **Use EventBus**: Decouple systems with typed events via `world.events.fire()` / `world.events.on<T>()`
7. **Use EntityPrefab**: Define reusable entity templates and stamp them out with `world.instantiate(prefab)`
8. **Use Vec2 on hot paths**: Prefer mutable `Vec2` over `Offset` in per-frame physics/math code to avoid allocations
9. **Use SpriteBatch**: Combine sprites sharing an atlas into a single `Canvas.drawAtlas()` call
10. **Check state**: Verify `engine.isInitialized` before accessing subsystems
11. **Animation management**: Add animations to `AnimationSystem` for automatic updates
12. **Use system priorities**: Let the built-in priority order handle execution sequence; only override when adding custom systems

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

---

## Math Module

### Vec2

Mutable 2D vector for zero-allocation math on hot paths. Used internally by `PhysicsBody` for position, velocity, and acceleration.

#### Constructor

```dart
Vec2(double x, double y)
Vec2.zero()
Vec2.fromOffset(Offset offset)
```

#### Properties

```dart
double x
double y
double get length              // Euclidean magnitude
double get lengthSquared       // Squared magnitude (avoids sqrt)
```

#### Methods

```dart
Vec2 add(Vec2 other)           // this += other (mutates, returns this)
Vec2 sub(Vec2 other)           // this -= other
Vec2 scale(double s)           // this *= s
Vec2 normalize()               // Normalize in-place (returns this)
double dot(Vec2 other)         // Dot product
double cross(Vec2 other)       // 2D cross product (scalar)
Vec2 setFrom(Vec2 other)       // Copy values from other
Vec2 setValues(double x, double y)
Offset toOffset()              // Convert to immutable Offset

// Operator overloads
Vec2 operator +(Vec2 other)    // Returns NEW Vec2 (allocation)
Vec2 operator -(Vec2 other)
Vec2 operator *(double s)
```

#### Example

```dart
// Hot-path usage (zero allocation)
final pos = Vec2(100, 200);
final vel = Vec2(50, -10);
pos.add(vel.scale(dt));        // Mutates pos in-place

// Convenience conversion
final offset = pos.toOffset(); // For Flutter painting APIs
```

---

### Quadtree

Spatial index for efficient viewport culling. Used by `RenderingEngine` when renderable count exceeds ~200.

#### Constructor

```dart
Quadtree<T>({
  required Rect bounds,        // World-space coverage
  int maxObjects = 10,         // Split threshold per node
  int maxDepth = 5,            // Maximum tree depth
})
```

#### Methods

```dart
void insert(T item, Rect bounds)       // Insert item with AABB
void remove(T item)                    // Remove item
List<T> query(Rect region)             // Items intersecting region
void clear()                           // Remove all items
```

---

## Memory Management

### ObjectPool\<T\>

Generic object pool for GC-friendly recycling of short-lived objects.

#### Constructor

```dart
ObjectPool<T>({
  required T Function() factory,   // Creates new instances
  int initialSize = 0,            // Pre-allocated instances
  int? maxSize,                   // Maximum pool capacity (null = unlimited)
})
```

`T` should implement the `Recyclable` interface for automatic reset on release.

#### Methods

```dart
T acquire()                    // Get an object from the pool (or create new)
void release(T object)         // Return object to pool (calls reset() if Recyclable)
void clear()                   // Discard all pooled objects
int get available              // Number of idle objects in pool
int get activeCount            // Number of objects currently in use
Map<String, dynamic> get stats // Pool statistics
```

#### Example

```dart
final bulletPool = ObjectPool<Bullet>(
  factory: () => Bullet(),
  initialSize: 50,
  maxSize: 200,
);

// Acquire
final bullet = bulletPool.acquire();
bullet.position = gunTip;
bullet.velocity = aimDir * 500;

// Release when done
bulletPool.release(bullet);     // bullet.reset() called automatically

// Check stats
print(bulletPool.stats);        // {available: 49, active: 1, maxSize: 200}
```

### Recyclable

Interface for objects managed by `ObjectPool`.

```dart
abstract class Recyclable {
  void reset();                // Called automatically on release()
}
```

---

### CacheManager

LRU binary cache backed by `just_storage` / `just_database`. Accessible via `engine.cache`.

#### Properties

```dart
int maxBinaryEntries           // Maximum cached entries before eviction
bool isUsingMemoryFallback     // True when storage plugin unavailable (in-memory mode)
```

#### Methods

```dart
Future<void> initialize()
Future<void> store(String key, Uint8List data)   // Store binary data
Future<Uint8List?> retrieve(String key)          // Retrieve cached data
Future<void> evict(String key)                   // Remove specific entry
Future<void> clear()                             // Clear all cached data
Map<String, dynamic> get stats                   // Cache hit/miss statistics
```

#### Example

```dart
final cache = engine.cache;

// Store pre-computed data
await cache.store('level1_navmesh', navmeshBytes);

// Retrieve later
final data = await cache.retrieve('level1_navmesh');
if (data != null) {
  loadNavmesh(data);
}
```

---

## Post-Processing

Full-screen shader passes applied over the composed scene each frame. Passes are chained in ascending `passOrder` — lowest is innermost (applied closest to the raw scene), highest is outermost (composited last, visible to the viewer).

Shaders must be declared in `pubspec.yaml` under `flutter: shaders:` and loaded with `ui.FragmentProgram.fromAsset`.

### PostProcessPass

Data object describing one fullscreen shader pass. Register instances with `RenderingEngine.addPostProcessPass`.

#### Properties

```dart
ui.FragmentShader shader       // Compiled shader instance
int passOrder                  // Layering order (lower = innermost)
bool enabled                   // Toggle without removing from engine
void Function(ui.FragmentShader, double w, double h, double t)? setUniforms  // Per-frame uniform callback
```

#### Constructor

```dart
PostProcessPass({
  required ui.FragmentShader shader,
  int passOrder = 0,
  bool enabled = true,
  void Function(ui.FragmentShader, double w, double h, double t)? setUniforms,
})
```

---

### ShaderComponent

Attaches a GLSL `FragmentShader` to an ECS entity in one of two modes:

- **Per-entity** (`isPostProcess: false`, default) — wraps the entity's renderable in `canvas.saveLayer` with the shader as an `ImageFilter`.
- **Post-process** (`isPostProcess: true`) — registers a `PostProcessPass` with the `RenderingEngine` covering the full viewport.

#### Constructor

```dart
ShaderComponent({
  required ui.FragmentProgram program,
  bool isPostProcess = false,
  int passOrder = 0,
  bool enabled = true,
  void Function(ui.FragmentShader, double w, double h, double t)? setUniforms,
})
```

#### Properties

```dart
ui.FragmentProgram program     // Source program (owns shader lifetime)
bool isPostProcess             // Post-process vs per-entity mode
int passOrder                  // Chaining order (post-process only)
bool enabled                   // Activate / deactivate
```

#### Example

```dart
// Fullscreen vignette
final program = await ui.FragmentProgram.fromAsset('shaders/vignette.frag');
world.addComponent(vfxEntity, ShaderComponent(
  program: program,
  isPostProcess: true,
  passOrder: 2,
  setUniforms: (s, w, h, t) {
    s.setFloat(0, w);   // uResolution.x
    s.setFloat(1, h);   // uResolution.y
    s.setFloat(2, t);   // uTime
  },
));

// Per-entity chromatic aberration
world.addComponent(boss, ShaderComponent(program: chromaProgram));
```

---

### PostProcessSystem

ECS system that mirrors active `ShaderComponent(isPostProcess: true)` entities to the `RenderingEngine` pass list each frame.

**Priority**: 35 (runs after `RenderSystem` at 40)

#### Constructor

```dart
PostProcessSystem(
  RenderingEngine renderingEngine, {
  double Function()? getTime,  // Optional elapsed-time provider for uTime uniforms
})
```

#### Example

```dart
world.addSystem(PostProcessSystem(
  engine.rendering,
  getTime: () => engine.time.totalTime,
));
```

---

## Deterministic Effects

Tick-based property effects designed for multiplayer prediction and rollback. All effects are additive deltas computed from integer ticks, making them deterministic across platforms and frame rates regardless of wall-clock timing.

At 60 UPS, 60 ticks = 1 second. A reconnecting client can fast-forward any effect by passing a large `currElapsed` in a single `applyTick` call.

### DeterministicEffect (Base Class)

Abstract base for all tick-driven effects.

```dart
// Common constructor parameters
DeterministicEffect({
  required int durationTicks,   // 1 tick = 1 fixed-timestep update
  bool loop = false,
  VoidCallback? onComplete,
  VoidCallback? onLoopComplete,
})
```

#### Built-in Effect Types

| Effect | Description |
|---|---|
| `MoveEffect` | Translate `TransformComponent.position` by `to` (relative or absolute) |
| `ScaleEffect` | Animate `TransformComponent.scale` to `to` |
| `RotateEffect` | Rotate `TransformComponent.rotation` by `by` radians |
| `FadeEffect` | Animate `RenderableComponent.renderable.opacity` to `to` |
| `ColorTintEffect` | Blend `SpriteComponent` tint toward `to` |
| `ShakeEffect` | Oscillate position with decaying `amplitude` |
| `PathEffect` | Follow a `List<Offset>` spline |
| `SequenceEffect` | Run child effects one after another |
| `ParallelEffect` | Run child effects simultaneously |
| `RepeatEffect` | Wrap another effect and replay `count` times |
| `DelayEffect` | Insert a tick-counted gap in a sequence |

All built-in effects accept an optional `easing` parameter (`EasingType` enum; 16 types including `linear`, `easeInOut`, `easeInElastic`, `easeOutBounce`).

---

### EffectComponent

Attaches an `EffectPlayer` queue to an entity. Created automatically by `EffectSystemECS.scheduleEffect`.

```dart
EffectComponent()

// Properties
EffectPlayer player            // Per-entity effect queue; do not replace
```

---

### EffectSystemECS

ECS system **and** `EffectRuntime` implementation. Drives all `EffectComponent` entities every tick.

**Priority**: 65 (between `AnimationSystemECS` 70 and `HealthSystem` 60)

```dart
EffectSystemECS()

// EffectRuntime API
int get currentTick
void scheduleEffect({
  required Entity entity,
  required DeterministicEffect effect,
  int? startTick,              // Defaults to currentTick + 1
})
void cancelEffects(Entity entity)
void cancelEffect(Entity entity, EffectHandle handle)
EffectSnapshot snapshot()
void restoreSnapshot(EffectSnapshot snap)
```

#### Example

```dart
final fx = EffectSystemECS();
world.addSystem(fx);

fx.scheduleEffect(
  entity: enemy,
  effect: SequenceEffect([
    ShakeEffect(amplitude: 6, durationTicks: 15),
    FadeEffect(to: 0.0, durationTicks: 30),
  ]),
);

// Multiplayer: schedule at a specific server tick
fx.scheduleEffect(
  entity: player,
  effect: MoveEffect(to: Offset(400, 0), durationTicks: 60),
  startTick: serverTick,
);
```

---

### EffectSnapshot

Serializable point-in-time snapshot of all active effects across all entities. Used for network late-join, reconnect, and prediction rollback.

```dart
EffectSnapshot({
  required int tick,
  required Map<EntityId, List<Map<String, dynamic>>> entityEffects,
})

// Serialization
Map<String, dynamic> toJson()
factory EffectSnapshot.fromJson(Map<String, dynamic> json)
```

```dart
// Binary codec (compact wire format)
Uint8List EffectBinaryCodec.encode(EffectSnapshot snap)
EffectSnapshot EffectBinaryCodec.decode(Uint8List bytes)
```

---

## Localization

Engine-wide string localization with namespace support, ICU-lite plurals/selects, fallback chains, and reactive locale switching.

### LocalizationManager

```dart
LocalizationManager({Locale? fallbackLocale})
```

#### Properties

```dart
Locale currentLocale           // Active locale
Locale fallbackLocale          // Fallback when key is missing in active chain
Signal<Locale> localeChanged   // Reactive — emits on every setLocale() call
static LocalizationManager? instance  // Optional global singleton
```

#### Methods

```dart
// Loading — one file per locale/namespace combination
Future<LocaleStringTable> load(
  Locale locale,
  String assetPath,
  {String ns = 'default', AssetBundle? bundle},
)

// Lookup — all optional params are named
String t(
  String key, {
  Map<String, dynamic>? args,  // {var} substitution
  Locale? locale,              // Override active locale for this call
  String? ns,                  // Namespace override
})

void setLocale(Locale locale)
```

#### Example

```dart
final l10n = LocalizationManager();

await l10n.load(const Locale('en'), 'assets/l10n/ui_en.json', ns: 'ui');
await l10n.load(const Locale('fr'), 'assets/l10n/ui_fr.json', ns: 'ui');
l10n.setLocale(const Locale('fr'));

print(l10n.t('ui.start_game'));
print(l10n.t('ui.item_count', args: {'count': 3}));

// Global singleton access
LocalizationManager.instance = l10n;
final text = LocalizationManager.instance!.t('ui.back');
```

**JSON file format** — flat or nested, auto-flattened with `.` notation:
```json
{
  "ui": { "start_game": "Start Game", "back": "Back" },
  "game.hp.label": "HP",
  "item.count": "{count, plural, =0{No items} =1{One item} other{{count} items}}"
}
```

**Fallback chain** — for locale `fr_CA`: `fr_CA` → `fr` → `fallbackLocale` (`en`) → key itself.

---

### Localization Flutter Widgets

| Widget | Purpose |
|---|---|
| `LocalizationScope` | Provides `LocalizationManager` to the widget subtree |
| `LocalizationBuilder` | Rebuilds its child whenever the active locale changes |
| `LocalizedText` | `Text` widget that looks up a key and auto-rebuilds on locale change |
| `LocaleSelector` | Drop-down that calls `setLocale` on selection |
| `L10nContext` | Extension on `BuildContext` — `context.l10n.t(key)` |

---

## Narrative / Dialogue

Yarn Spinner 2.x compatible narrative system with Dart runtime, ECS integration, and reactive signals.

### DialogueManager

Central facade for loading dialogue graphs, running dialogue sessions, managing conditions/commands, and routing reactive signals.

```dart
DialogueManager({
  DialogueLocalizer? localizer,
  DialogueVariableStore? globalVariables,
})
```

#### Properties

```dart
DialogueVariableStore globalVariables  // Shared across all runners
DialogueLocalizer localizer            // Per-locale string tables
DialogueConditionRegistry conditions   // Named Dart condition predicates
DialogueCommandRegistry commands       // <<commandName args>> handlers
Signal<String?> activeGraphId          // Currently active graph id
Signal<bool> isAnyDialogueActive       // True while any runner is active
```

#### Methods

```dart
Future<void> loadGraph(String assetPath)  // Parse and register a .yarn asset
DialogueRunner createRunner(String graphId)
void clearRunners()
```

#### Example

```dart
final narrative = DialogueManager();

await narrative.localizer.loadLocale(const Locale('en'));
await narrative.loadGraph('assets/dialogue/innkeeper.yarn');

// Register custom logic
narrative.conditions.register('playerHasKey', (vars) => player.hasKey);
narrative.commands.register('play_sound', (ctx) async {
  await audio.playSfx(ctx.args[0]);
});

// Run dialogue
final runner = narrative.createRunner('innkeeper');
runner.signals.currentLine.addListener(() {
  print(runner.signals.currentLine.value?.text);
});
await runner.start('Start');
```

---

### Narrative ECS

| Class | Role |
|---|---|
| `DialogueComponent` | Marks an entity as a dialogue source; holds `graphId`, `entryNode` |
| `TriggerComponent` | Proximity / interaction trigger for starting dialogue |
| `DialogueSystem` | ECS system; checks proximity/interaction and starts runners |

```dart
// Priority: SystemPriorities.dialogue = 59 (gameplay - 1)
world.addSystem(DialogueSystem(narrative: narrativeManager));
world.addComponent(npc, DialogueComponent(graphId: 'innkeeper', entryNode: 'Start'));
world.addComponent(npc, TriggerComponent(radius: 80.0));
```

---

### Narrative UI Widgets

| Widget | Purpose |
|---|---|
| `DialogueBoxWidget` | Displays current line with speaker name and optional typing animation |
| `DialogueChoicesWidget` | Renders choice list and fires selection back to the runner |

---

## System Priorities

Built-in systems run in descending priority order. Higher priority = runs first.

| Priority | System | Responsibility |
|---|---|---|
| 110 | `TileMapRenderSystem` | Render tile layers (background) |
| 105 | `ParallaxSystem` | Render parallax background layers |
| 100 | `InputSystem` | Bridge InputManager → ECS components |
| 90 | `PhysicsSystem` | Gravity, drag, collision, impulse |
| 89 | `PhysicsBridgeSystem` | Sync standalone PhysicsBody → ECS |
| 80 | `MovementSystem` | Apply velocity to position |
| 70 | `AnimationSystemECS` | Advance animation timers |
| 65 | `EffectSystemECS` | Deterministic tick-driven property effects |
| 60 | `HealthSystem` | Regen, death events |
| 59 | `DialogueSystem` | Narrative proximity / interaction triggers |
| 50 | `HierarchySystem` | Parent-child transform propagation |
| 48 | `ParticleSystemECS` | Update particle emitters |
| 45 | `CameraFollowSystem` | Drive camera from `CameraFollowComponent` |
| 40 | `RenderSystem` | Sync transforms, draw entities + UI |
| 35 | `PostProcessSystem` | Sync fullscreen post-process shader passes |
| 30 | `BoundarySystem` | Enforce world boundaries |
| 10 | `DebugSystem` | Diagnostics overlay (internal) |
| -10 | `AudioSystem` | ECS-driven audio playback |

Custom systems can use any priority value to slot in at the desired execution point.

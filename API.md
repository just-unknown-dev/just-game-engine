# just_game_engine 2.0.0-dev.1 — API map

Per area: the types a game uses most, what each is for, and the members people call. The full reference is the dartdoc on pub.dev: <https://pub.dev/documentation/just_game_engine/latest/>.

Generated from `lib/` with an analyzer dump of the public libraries, so every name and signature is what 2.0.0-dev.1 exports. Typedefs are written out; long parameter lists keep positional and `required` parameters and cut the rest to `…`.

| Library | Exports |
|---|---|
| `package:just_game_engine/just_game_engine.dart` | 734 names: 589 from the engine, 145 [re-exported](#re-exported-packages) |
| `package:just_game_engine/widgets.dart` | 17 screen widgets ([list](#widgetsdart)) |
| `package:just_game_engine/physics_3d.dart` | 58 names: 26 from the engine, 32 re-exported from `just_physics_engine` ([3-D physics](#3-d-physics)) |

Achievements, sign-in, leaderboards, currency, inventory and ads are `EngineService`s in the separate package `just_game_services`.

## Engine and lifecycle

Make an `Engine`, `await initialize()`, show it in a `GameWidget`, call `start()`. `dispose()` is final.

- **`Engine`** — owns the subsystems, the world and the game loop.
  - `Engine({EngineConfig config = const EngineConfig(), EngineContext? context})`
  - `Future<void> initialize({EngineConfig? config})`
  - `void start()`
  - `Future<void> dispose()`
  - `T service<T extends EngineService>()`
  - `ValueListenable<EngineState> get stateListenable`
  - `rendering`, `physics`, `input`, `audio`, `music`, `sfx`, `cache`, `cameraSystem`, `world`, `time`, `gameLoop`, `systemManager` throw `EngineNotReadyError` before `initialize()` and after `dispose()`; `Engine.context`, `Engine.assets`, `Engine.plugins`, `Engine.services`, `Engine.layers`, `Engine.terminal` always work.
- **`EngineConfig`** — set once, when the engine is made.
  - `EngineConfig({RenderingEngine Function()? createRendering, AudioEngine Function()? createAudio, PhysicsEngine Function()? createPhysics, Physics3D? physics3D, bool? deferAudioUntilInput, List<ContextExtension> extensions = const [], List<EngineService> services = const [], Set<DefaultSystem> defaultSystems = const {}})`
- `enum EngineState { uninitialized, initializing, initialized, running, paused, failed, disposing, disposed }` — `engine.state`.
- `enum DefaultSystem { input, physics, movement, audio, rendering, sprites, levelMaps, mapCollision, cameras }` — the engine's standard systems ([which](#system-priorities)); `DefaultSystems.all` and `DefaultSystems.headless` are ready-made sets.
- `void registerDefaultSystems(World world, Engine engine, {Set<DefaultSystem> include = DefaultSystems.all, GameCamera? camera, List<String> inputMaps = const ['player']})` — adds standard systems to a world, each at most once; `EngineConfig.defaultSystems` calls it during `initialize()`.
- **`GameWidget`** — hosts an engine: ticks the game loop, paints the world, forwards keys and pointers, draws the layers.
  - `GameWidget({required Engine engine, …})`
- **`GameLayers`** — `engine.layers`: Flutter widgets over the game (HUD, menus), each a `GameLayer`.
  - `void register(GameLayer layer)`
  - `void setEnabled(String id, bool enabled)`

Also: `EngineInitException`, `EngineNotReadyError`, `GameLayer`, `TimeManager`, `GameLoop`, `SystemManager`; plugins `EnginePlugin`, `PluginHost`; `GameTerminal` (the developer console); `offload` (run a function on another isolate).

## Context and services

An engine's registries, loaders and package state live in its `EngineContext` (`engine.context`, also `world.context`); nothing is process-wide. A package teaches an engine through a `ContextExtension` listed in `EngineConfig.extensions`.

- **`EngineContext`** — per-engine definitions, registries, loaders and package state.
  - `EngineContext({Iterable<ContextExtension> extensions = const [], AssetBundle? bundle, bool withBuiltIns = true})`
  - `ComponentDefinitionRegistry definitions`
  - `void install(ContextExtension extension)`
  - Also holds `fieldTypes`, `migrations`, `trackKinds`, `easings`, `animatorBindings`, `collisionKinds`, `effectTypes`, `assets`, `sprites`, `animatorGraphs`, `timelines`, `tiles`, `signals`, `localization`, `bundle`; `slot` keeps a package's own state, `overrideLoaders` swaps the loaders.
- **`ContextExtension`** — what a package installs into a context.
  - `String get id`
  - `void install(EngineContext context)`
- **`EngineService`** — lives as long as the engine; listed in `EngineConfig.services`.
  - `Future<void> start(ServiceContext context)`
  - `Future<void> stop()`

Also: `ServiceHost` (`engine.services`), `ServiceContext`, `ContextResource`, `LoaderOverride`.

## ECS

Entities are ids with components, stored by archetype. Systems run each frame by priority, highest first. A system that creates or destroys entities inside its loop queues that on `world.commands`; the world applies the queue between systems.

- **`World`** — `engine.world`: entities, systems, queries, events.
  - `Entity createEntityWithComponents(List<Component> components, {String? name})`
  - `void destroyEntity(Entity entity, {bool withChildren = true})`
  - `void addSystem(System system)`
  - `List<Entity> query(List<Type> componentTypes)`
  - `Entity? findEntityByName(String name, {bool includeInactive = true})`
- **`Entity`** — a handle to one entity.
  - `T? getComponent<T extends Component>()`
  - `void addComponent(Component component)`
  - `bool get isActive`
- **`System`** — base class of systems.
  - `List<Type> get requiredComponents`
  - `void update(double deltaTime)`
- **`CommandBuffer`** — `world.commands`: deferred changes, applied in order between systems.
  - `void create(List<Component> components, {String? name})`
  - `void destroy(Entity entity, {bool withChildren = true})`
- **`EventBus`** — `world.events`: typed `GameEvent`s.
  - `EventSubscription on<T extends GameEvent>(void Function(T) callback)`
  - `void fire<T extends GameEvent>(T event)`
- **`TransformComponent`** — position, rotation, scale in 3-D (2-D: z = 0, turn about Z).
  - `TransformComponent({Vector3? position, double angle = 0.0, Vector3? euler, Vector3? scale})`
  - `Vector3 position`
- **`VelocityComponent`** — velocity; `MovementSystem` applies it.
  - `VelocityComponent({Vector3? velocity, double maxSpeed = 0.0})`
- **`ParentComponent`** — hangs an entity under a parent; the world lists it in the parent's `ChildrenComponent`. Given local values, the next hierarchy pass places it at them.
  - `ParentComponent({int? parentId, Vector3? localPosition, EulerRotation? localRotation, Vector3? localScale, bool inheritTransform = true})`

Also: `Component`, `GameEvent`, `EntityPrefab`, `SystemPriorities`; hierarchy `ChildrenComponent`, `TransformHierarchy`; gameplay `HealthComponent`, `HealthSystem`, `LifetimeComponent`, `LifetimeSystem`, `CheckpointComponent`, `CheckpointSystem`, `BoundarySystem`, `SimpleMovementComponent`, `SimpleMovementSystem`, `MovementSystem`.

## Serialization and scenes

A scene is JSON, format v9; older files are migrated on load. Components are read through the `ComponentDefinition`s in `context.definitions`: the engine's are always there, a package adds its own with its extension, and an unknown component stops the load with `UnknownComponentTypeException`.

- **`SceneLoader`** — loads scenes into a world.
  - `static Future<List<Entity>> loadAsset(World world, String assetPath, {AssetBundle? bundle, ComponentDefinitionRegistry? codecs, MigrationHooks? hooks, void Function(MigrationResult)? onMigrated})`
  - `static List<Entity> loadString(World world, String source, {…})`
- **`SceneFormat`** — the version and the migration chain.
  - `static int current`
  - `static MigrationResult migrateWithReport(Map<String, dynamic> json, {MigrationHooks? hooks})`
- **`ComponentDefinitionRegistry`** — what a context can save, load, inspect and draw.
  - `ComponentDefinitionRegistry.core()`
  - `void register(ComponentCodec<Component> codec, {bool override = false})`
- **`ComponentDefinition`** — one component type: factory, fields, editor hints, size, painter.
  - `ComponentDefinition<T>({required String type, required T Function() create, required List<SchemaField> fields, …})`
- **`SchemaField`** — one saved property.
  - `SchemaField({required String name, required FieldType<dynamic> kind, required Object? Function(Component) read, …})`

Also: `SceneAssets` (scenes live in `assets/scenes`, listed in `assets/scenes/scenes.json`); `ComponentSchema`, `FieldTypes` (for a game's own components), `MigrationHooks`, `MigrationResult`, `UnsupportedFormatVersionException`, `TagLibrary` (the project's tags, `assets/project/tags.json`).

## Rendering

`RenderSystem` draws renderable entities through the camera, sorted by `LayerComponent` layer, then z-order. `engine.rendering` owns the frame, its hooks and post-processing.

- **`RenderingEngine`** — `engine.rendering`.
  - `Color backgroundColor`
  - `void addPostProcessPass(PostProcessPass pass)`
  - `Map<String, dynamic> get stats`
- **`RenderSystem`** — draws the world; optional culling and shape batching.
  - `RenderSystem({GameCamera? camera, SpriteBatchRenderer Function(Image)? spriteBatchFactory, List<RenderPass>? passes, FrameView Function()? viewOf, bool batchShapes = false, bool cullOffscreen = false, RenderStatsSink? statsSink})`
- **`RenderableComponent`** — any `Renderable` on an entity.
  - `RenderableComponent({required Renderable renderable, bool syncTransform = true})`
- **`Renderable`** — base class of drawables.
  - `void render(Canvas canvas, Size size)`
- **`LayerComponent`** — draw order and editor grouping.
  - `LayerComponent({String layerId = 'main', int layer = 0, int zOrder = 0, bool visible = true, bool locked = false, int? mapLayer})`
- **`RectangleComponent`** — a rectangle shape.
  - `RectangleComponent({required double width, required double height, …})`
- **`ParallaxComponent`** — a background behind the world, drawn by `ParallaxRenderSystem`.
  - `ParallaxComponent({required ParallaxBackground background})`

Also: shapes `CircleComponent`, `PolygonComponent`, `LineComponent`, `CapsuleComponent`, `ShapePaintStyle`; `LevelLayers`, `ParallaxBackground`, `ParallaxLayer`, `ParallaxRenderSystem`; post-processing `ShaderComponent`, `PostProcessPass`, `PostProcessSystem`; `RenderHookChain`, `RenderStatsSink`, `Sprite`, `SpriteBatch`, `TextRenderable`, `CustomRenderable`; culling `ViewCullingSystem`, `CullStateComponent`; 3-D seam `SceneRenderer`, `FrameView`.

## Sprites and animation

Sprites are data: `SpriteComponent` (an image or atlas region) and `SpriteAnimationComponent` (an atlas clip). An `AnimatorComponent` runs a state-machine graph that picks the clip. The systems are in `DefaultSystem.sprites`.

- **`SpriteComponent`** — a still image or atlas region.
  - `SpriteComponent({required String spritePath, …})`
- **`SpriteAnimationComponent`** — plays an atlas clip.
  - `String clip`
  - `void switchClip(String name, {bool restartIfSame = false, bool? loop})`
- **`SpriteAnimationSystem`** — plays clips; reports frame events.
  - `Stream<SpriteAnimationSignal> get signals`
- `void registerSpriteSystems(World world, {…})` — adds the sprite, animator and timeline systems.
- **`SpriteAtlas`** — pages, regions and clips (TexturePacker, Aseprite, grid sheets).
  - `static Future<SpriteAtlas> fromAsset(String jsonPath, {required AssetManager assets})`
- **`AnimatorComponent`** — runs an `.animator.json` graph.
  - `AnimatorComponent({String graphPath = '', bool enabled = true, bool faceVelocity = false})`
  - `void setBool(String name, bool value)`
- **`AnimatorSystem`** — evaluates graphs and switches clips.
  - `Stream<AnimatorStateChange> get stateChanges`
- **`AnimatorBindings`** — `context.animatorBindings`: sources a parameter can be bound to.
  - `void register(String id, Object? Function(Entity) read)`

Also: `SpriteLoadSystem`, `SpriteAssetLoader`, `BundleSpriteAssetLoader`, `AtlasAnimationClip`, `SpriteRegion`, `SpriteAnimationSignal`, `AnimatorGraph`, `AnimatorStateChange`.

## Timelines

A timeline (`.timeline.json`, format v2) animates fields, switches entities on and off, plays audio and clips, cuts cameras and fires events. `TimelineSystem` (in `DefaultSystem.sprites`) runs each `TimelinePlayerComponent`.

- **`TimelinePlayerComponent`** — plays a timeline on its entity.
  - `String timelinePath`
  - `void play()`
  - `void playFrom(String marker)`
- **`TimelineSystem`** — runs the players.
  - `Stream<TimelineEventFired> get events`
- **`TimelineAsset`** — tracks, markers, duration, wrap.
  - `static TimelineAsset parse(String source, {TimelineTrackKinds? kinds, MigrationHooks? migrations})`
- **`TimelineSignals`** — `context.signals`, shared by every world on the engine.
  - `void emit(String name)`
  - `Stream<String> get stream`

Also: `TimelinePlayback`, `TimelineTriggerComponent`, `TimelineEventFired`, `TimelineFormat`; registries `TimelineTrackKinds`, `KeyEasings`; tracks `PropertyTrack`, `ActivationTrack`, `AudioTrack`, `SpriteClipTrack`, `CameraShotTrack`, `EventTrack`, `NestedTimelineTrack`.

## Cameras

A virtual camera is an entity with a `VirtualCameraComponent` and optional stage components. Each frame the `CameraBrain` picks the live camera by priority, blends between shots and drives the output `Camera`.

- **`CameraSystem`** — `engine.cameraSystem`.
  - `Camera mainCamera`
  - `CameraBrain brain`
- **`CameraBrain`** — picks, blends and evaluates cameras.
  - `Entity? get liveCamera`
  - `void emitImpulse(CameraImpulse impulse)`
- **`Camera`** — the output camera.
  - `Offset screenToWorld(Offset screenPos)`
  - `Offset worldToScreen(Offset worldPos)`
- **`VirtualCameraComponent`** — makes an entity a camera.
  - `int priority`
  - `EntityTarget follow`
- `void registerCameraSystems(World world, CameraSystem cameraSystem)` — adds the target-group, trigger and brain systems.

Also: `CameraFramingComponent`, `CameraConfinerComponent`, `CameraBoundsComponent`, `CameraTriggerComponent`, `CameraNoiseComponent`, `CameraDollyComponent`, `CameraTargetGroupComponent`, `CameraImpulse`, `CameraBlend`; managers `CameraBlendListComponent`, `CameraMixerComponent`, `CameraStateDrivenComponent`; `CameraImpulseSourceComponent`, `CameraImpulseListenerComponent`; effects `ScreenFadeEffect`, `LetterboxEffect`, `MotionBlurEffect`; extension points `CameraStageRegistry`, `CameraManagerRegistry`.

## Level maps

A tile map (orthogonal, isometric, staggered, hexagonal) placed by a `LevelMapComponent`, read from `.map.json`/`.tileset.json` or Tiled `.tmx`/`.tmj`. Layers marked as colliding get static bodies.

- **`LevelMapComponent`** — puts a map in the level.
  - `LevelMapComponent({String mapPath = '', LevelMapData? inline})`
- **`LevelMapSystem`** — loads and draws maps.
  - `Future<List<LevelMapLoadFailure>> preload()`
- `void registerLevelMapSystems(World world, {bool collision = true})` — adds `LevelMapSystem` and `MapCollisionSystem`.
- **`LevelMaps`** — finding maps in a world.
  - `static LevelMapHandle? primary(World world)`
- **`LevelMapHandle`** — reading and changing a map at run time.
  - `MapLayerData? layer(Object idOrName)`
  - `TileInfo? tileAt(MapLayerData layer, TileCoord c)`
  - `bool setTile(MapLayerData layer, TileCoord c, int cell)`

Also: `MapCollisionSystem`, `TileChangedEvent`, `TileAssets`, `LevelMapData`, `MapCollisionKinds`, `TilesetData`, `TiledInterop`, `BuiltInTilesets`, `MapGeometry`, `TileCoord`, `MapBodyComponent`.

## Physics

`engine.physics` is a `PhysicsEngine` from `just_physics_engine`: Box2D where its native library loads, pure Dart otherwise and on the web. `PhysicsSystem` makes a body per `Collider2D`, moved as the entity's `RigidBody2D` says (a static body without one), steps, and writes positions back. The names are 3-D physics' (`package:just_game_engine/physics_3d.dart`), with `2D` for `3D`.

- **`PhysicsSystem`** — bodies from components; contacts as events.
  - `PhysicsSystem(PhysicsEngine physics, {GameCamera? camera, bool reportContactStay = false})`
  - `Entity? entityForBody(PhysicsBody body)`, `PhysicsBody? bodyOf(Entity entity)`
- **`RigidBody2D`** — how a body moves: body type, mass, material (friction, restitution), motion (gravity scale, damping, continuous collision, sleep, locked rotation, start velocity), sensor, layer and what it collides with. After each step it holds `isGrounded`, `groundEntity`, `groundNormal`, `linearVelocity`, `angularVelocity` and `isAwake`.
  - `RigidBody2D({BodyType bodyType, double mass, double friction, double restitution, …, int layer, int? collidesWith})`
  - `void addForce(Offset force)`, `addImpulse(Offset impulse)`, `addTorque(double torque)`, `addAngularImpulse(double impulse)`, `setVelocity(Offset velocity)`, `setAngularVelocity(double velocity)`, `wakeUp()`
  - `bool get isStatic`, `isKinematic`, `isDynamic`
- **`Collider2D`** — a body's shape (`ColliderShape2D`: box, circle, capsule, polygon, segment, chain, or `matchShape` for what the entity draws), with its own offset, rotation and scale, and one-way. Alone, a static body. It follows the entity's scale.
  - `Collider2D({ColliderShape2D shape, Vector2? size, double radius, …, Offset offset, bool oneWay, …})`
- **`PhysicsLayers`** — sixteen named collision layers and which collide; `engine.context.physicsLayers`, read from `assets/project/physics.json` on `initialize()`.
  - `String nameOf(int layer)`, `labelOf(int layer)`, `Color colorOf(int layer)`, `String descriptionOf(int layer)`, `int? indexOf(String name)`, `int maskOf(int layer)`, `bool collides(int a, int b)`
  - `PhysicsLayers withName(int layer, String name)`, `withColor`, `withDescription`, `withCollision(int a, int b, bool collide)`, `cleared(int layer)`, `int? firstFree`, `String? problemWithName(String name, {int? except})`, `toJson()`, `fromJson(json)`
- **`ColliderGeometry`** — a collider as simulated: `build(shape, offset:, rotation:, sx:, sy:)`, `shapeOf(collider, entity:)`, `of(collider, transform)`, `boundsOf(shape)`, `paint(canvas, shape, paint)`.
- **`PhysicsEngine`** — `engine.physics`.
  - `void setGravity(double gx, double gy)`
  - `void applyLinearImpulse(PhysicsBody body, double ix, double iy)`
  - `RayBodyHit? castRay(Ray ray, {Set<PhysicsBody>? exclude})`
- **`CharacterBody2D`** — a character gameplay moves rather than the simulation (the 3-D `CharacterBody3D`, field for field): a capsule or a box (`CharacterShape2D`) that walks slopes, climbs steps, keeps to the floor, rides platforms and pushes bodies. It needs no rigid body or collider. `PhysicsSystem` moves it before each step (`PhysicsCharacters2D`).
  - `CharacterBody2D({CharacterShape2D shape, double radius, double width, double height, Offset offset, double maxSlopeAngle, double stepHeight, double stickToFloor, …, int layer, int? collidesWith, bool detectable})`
  - `Offset moveVelocity`, `void jump(double speed)`; after each step `velocity`, `groundState` (`GroundState2D`), `isGrounded`, `groundNormal`, `groundVelocity`, `groundEntity`
- **`Physics2DQueries`** — rays, casts and overlaps, answering with entities.
  - `Physics2DQueries(PhysicsEngine physics, PhysicsSystem system)`
  - `PhysicsHit2D? raycast(Offset origin, Offset direction, {double maxDistance, int layerMask, Entity? ignore, bool includeSensors})`, `List<PhysicsHit2D> raycastAll(…)`, `PhysicsHit2D? circleCast(…)`
  - `List<Entity> overlapCircle(…)`, `overlapBox(…)`
- **`CollisionEnter2DEvent`** — fired on `world.events`.
  - `Entity entityA`
  - `Entity entityB`
  - `Offset point`
  - `Offset normal`
  - `double depth`

Also: `RaycastSystem`, `RaycastColliderComponent` (rays without physics); `CollisionStay2DEvent`, `CollisionExit2DEvent`, `SensorEnter2DEvent`, `SensorExit2DEvent`; `PhysicsHit2D`; joints `Joint2D`, `DistanceJoint2D`, `FixedJoint2D`, `SliderJoint2D`, `WheelJoint2D`, `PhysicsJointBindingSystem`; `PhysicsDefinitions2D`; shapes `RectangleShape`, `CircleShape`, `CapsuleShape`, `PolygonShape`.


## 3-D physics

`package:just_game_engine/physics_3d.dart`. Give the engine a `Physics3D` and it saves, loads and simulates the 3-D components on Jolt Physics; without one a game is 2-D only and carries none of this.

- **`Physics3D`** — the one way in: installs the components, starts the physics engine, adds the system.
  - `Physics3D({PhysicsEngine3D? engine, Vector3? gravity, int workerThreads = -1, int maxBodies = 10240, bool reportContactStay = false, bool reportActivation = false, bool addSystem = true})`
  - `static void registerSchemas(EngineContext context)`, `static bool get isSupported`, `static String? get unsupportedReason`
  - `bool get isStarted`, `PhysicsEngine3D get engine`, `PhysicsSystem3D get system`, `Physics3DQueries get queries`, `bool get hasWorld`, `PhysicsWorld3D get world`
- **`EngineConfig.physics3D`**, **`Engine.physics3D`** — the `Physics3D` given, or null.
- **Components**: `RigidBody3D` (`bodyType`, `mass`, `friction`, `restitution`, `linearDamping`, `angularDamping`, `gravityScale`, `isSensor`, `lockRotation`, `continuousCollision`, `canSleep`, `layer`; `addForce`, `addImpulse`, `setVelocity`, …), `Collider3D` (`shape`: `ColliderShape3D`), `CharacterBody3D` (`moveVelocity`, `jump`, `isGrounded`, `groundVelocity`, …), joints `FixedJoint3D`, `PointJoint3D`, `HingeJoint3D`, `SliderJoint3D`, `DistanceJoint3D`, `SixDofJoint3D` (`Joint3D`), `CameraCollision3D`.
- **`PhysicsSystem3D`** — steps the world: `PhysicsSystem3D(PhysicsWorld3D physics, {ColliderGeometry3D? geometry})`, `PhysicsSystem3D.lazy(PhysicsWorld3D Function() create, …)`; `entityOf`, `bodyOf`, `characterOf`.
- **Events**: `CollisionEnter3DEvent`, `CollisionStay3DEvent`, `CollisionExit3DEvent`, `SensorEnter3DEvent`, `SensorExit3DEvent`.
- **`Physics3DQueries`** — `raycast`, `raycastAll`, `sphereCast`, `shapeCast`, `overlapSphere`, `overlapBox`, `overlap` (`PhysicsHit3D`).
- Also: `Physics3DSchemas`, `ColliderShapes3D`, `ColliderGeometry3D`, `AssetColliderGeometry3D`, `CameraCollisionStage`, and just_physics_engine's 3-D side: `PhysicsEngine3D`, `PhysicsWorld3D`, `JoltPhysicsEngine`, `PhysicsEngineFactory`, `Physics3DUnsupportedError`, the shapes (`BoxShape3D` … `CompoundShape3D`), settings, poses, hits and events.

## Input

`engine.input` is a `just_inputs` `InputService` running an `InputActionAsset` (`.input.json`). `InputSystem` copies each player's actions onto their entity's `InputComponent`, by action name.

- **`InputService`** — `engine.input`.
  - `void loadAsset(InputActionAsset asset)`
  - `Future<void> attachGamepads([GamepadSource? source])`
  - `InputActions get actions`
- **`InputActionAsset`** — maps, bindings, schemes, players.
  - `InputActionAsset.parse(String source)`
- **`InputAction`** — a live action.
  - `bool isPressed()`
  - `bool wasPressedThisFrame()`
  - `Offset readVector2()`
- **`InputComponent`** — a player's input on an entity.
  - `bool isDown(String action)`
  - `bool wasPressed(String action)`
  - `Offset vector(String action)`

Also: `InputSystem`, `PlayerInputManager`, `PlayerInput`, `CacheInputOverrideStore`, `KeyboardKeys`, `GamepadControls`. The `...Def` asset model and validation: import `package:just_inputs/just_inputs.dart`.

## Audio

`engine.audio`, `engine.music` and `engine.sfx` come from `just_audio_engine`. On the web audio starts at the first key or pointer press (`EngineConfig.deferAudioUntilInput`).

- **`AudioEngine`** — `engine.audio`.
  - `Future<String?> playSfx(String path, {…})`
  - `Future<void> playMusic(String path, {…})`
- **`AudioSourceComponent`** — a sound on an entity.
  - `AudioSourceComponent({required String clipPath, …})`
- **`AudioPlayComponent`** — a one-shot sound request.
  - `AudioPlayComponent({required String clipPath, …})`
- **`AudioListenerComponent`** — where 3-D sounds are heard from.
  - `AudioListenerComponent({bool atCamera = false, bool faceCamera = false})`
- **`AudioSpatial`** — how a 3-D sound is heard: `minDistance`, `maxDistance`, `rolloff`, `dopplerLevel`, `farCutoff`; `mix(...)` works it out.
- `enum AudioChannel { master, music, sfx, voice, ambient }` — mixer channels.
- `enum AudioRolloff { inverse, linear, none }` — how a 3-D sound fades with distance.

Also: `AudioSystem`, `MusicManager`, `SoundEffectManager`, `AudioStreamComponent`, `AudioStopComponent`, `AudioSpatialMix`.

## Particles and effects

A `ParticleEmitter` goes on an entity through `ParticleEmitterComponent`; `ParticleSystemECS` updates it (not a default system: add it) and `RenderSystem` draws it. Effects are deterministic tick-based tweens queued per entity.

- **`ParticleEmitter`** — emits and draws particles.
  - `void burst(int count)`
  - `void addForce(ParticleForce force)`
- **`ParticleForce`** — base class of forces; the emitter calls `advance` once per update, then `apply` per particle.
  - `void advance(double dt)`
  - `void apply(Particle particle, double dt)`
- **`ParticleEffects`** — ready-made emitters.
  - `static ParticleEmitter explosion({required Vector3 position, …})`
- **`ParticleEmitterComponent`** — an emitter on an entity.
  - `ParticleEmitterComponent({required ParticleEmitter emitter, …})`
- **`EffectSystemECS`** — runs `EffectComponent` queues; snapshots.
  - `EffectHandle scheduleEffect({required Entity entity, required DeterministicEffect effect, int? startTick})`

Also: `ParticleSystemECS`, `EffectComponent`, `EffectSerializer`, `EffectTypes`; forces `GravityForce`, `WindForce`, `DragForce`, `VortexForce`; effects `SequenceEffect`, `MoveEffect`, `ScaleEffect`, `RotateEffect`, `FadeEffect`, `ShakeEffect`, `PathEffect`, `ParallelEffect`, `RepeatEffect`.

## Tags, targets and spawners

- **`TagComponent`** — an entity's tags; look them up with `World.findTagged` and `World.allTagged`.
  - `TagComponent([String tag = ''])`
  - `TagComponent.of(Iterable<String> tags)`
- **`EntityTags`** — tags straight from an `Entity`.
  - `bool hasTag(String tag)`
  - `void addTag(String tag)`
- **`EntityTarget`** — who a component means: self, by name, or by tag.
  - `EntityTarget.tag(String value)`
  - `Entity? resolve(World world, Entity? owner, {bool includeInactive = false})`
- **`Spawner`** — what a spawn point can create; registered by the game.
  - `Spawner({required String id, required Entity Function(World, Entity) spawn, …})`
- **`SpawnPoints`** — finding and spawning spawn points.
  - `static List<Entity> spawnAll(World world, Iterable<Spawner> spawners, {…})`

Also: `SpawnComponent`, `EngineTags`, `TagLibrary`.

## Localization and narrative

Set `engine.context.localization`; `GameWidget` provides it through `LocalizationScope`. Dialogue is Yarn Spinner 2 syntax.

- **`LocalizationManager`** — string tables per locale.
  - `Future<LocaleStringTable> load(Locale locale, String assetPath, {…})`
  - `String t(String key, {Map<String, Object?> args = const {}, Locale? locale, String? ns})`
- **`LocalizationScope`** — the manager for a widget subtree.
  - `static LocalizationManager of(BuildContext context)`
- **`DialogueManager`** — loads and runs dialogue graphs.
  - `Future<DialogueGraph> loadGraph(String assetPath, {String? id, AssetBundle? bundle})`
  - `Future<DialogueRunner> startDialogue({required String graphId, String startNode = 'Start'})`
- **`DialogueRunner`** — one running dialogue.
  - `void advance()`
  - `void selectChoice(int index)`

Also: `DialogueSystem`, `DialogueComponent`, `DialogueTriggerComponent`, `YarnParser`, `LocaleStringTable`, `SubtitleTrack`, `SubtitleController`.

## Memory, assets and storage

`engine.assets` is a reference-counted `AssetManager` on the context's bundle. `engine.cache` keeps strings, JSON and settings in the engine's own store (under `<application support>/just_game_engine/` natively, a `just_game_engine/` namespace of local storage on the web) and binary entries in its own database.

- **`AssetManager`** — `engine.assets`.
  - `Future<ImageAsset> loadImage(String path)`
  - `Future<JsonAsset> loadJson(String path)`
  - `void release(String path)`
- **`CacheManager`** — `engine.cache`.
  - `Future<dynamic> getJson(String key)`
  - `Future<void> setJson(String key, dynamic data)`
- **`MemoryScope`** — disposes what it owns together.
  - `void own(FutureOr<void> Function() callback)`
  - `void dispose()`

Also: `ImageAsset`, `JsonAsset`, `AssetScope`; diagnostics `MemoryProfiler`, `PoolManager`.

## widgets.dart

`package:just_game_engine/widgets.dart`: optional screen UI over a game.

- **`DialogueBoxWidget`** — a `DialogueRunner`'s lines.
  - `DialogueBoxWidget({required DialogueRunner runner, …})`
- **`LocalizedText`** — text that follows the locale.
  - `LocalizedText(String key_, {…})`
- **`GameCameraControls`** — wheel, pinch and button zoom.
  - `GameCameraControls({required Camera camera, required Widget child, …})`
- **`OnScreenControls`** — touch sticks and buttons (`just_inputs`).
  - `OnScreenControls({required InputService input, …})`
- **`RebindList`** — a player's rebinding list (`just_inputs`).
  - `RebindList({required PlayerInput player, …})`

Also: `L10nContext`, `DialogueChoicesWidget`, `SubtitleOverlay`, `LocaleSelector`, `LocalizationBuilder`, `OnScreenVisibility`, `OnScreenButtonFace`, `OnScreenStickPainter`, `RebindButton`, `RebindRow`, `rebindRows`, `BindingLabel`.

## System priorities

`World.update` runs systems from the highest `priority` to the lowest; `addSystem` order does not matter, and equal priorities have no set order. The world settles parent–child transforms (`TransformHierarchy`) just before the first system below `hierarchy` (50). A system that sets no priority runs at 0. Generated from `SystemPriorities` and each engine system's `priority`; "Default set" is the `DefaultSystem` that adds it.

| Priority | Expression | Engine system | Default set |
|---:|---|---|---|
| 110 | `levelMap` | `LevelMapSystem` | `levelMaps` |
| 108 | `mapCollision` | `MapCollisionSystem` | `mapCollision` |
| 105 | `parallax` | `ParallaxRenderSystem` | `rendering` |
| 100 | `input` | `InputSystem` | `input` |
| 95 | `playerControl` | (genre packages) |  |
| 92 | `movingPlatform` | (genre packages) |  |
| 91 | `91` | `ViewCullingSystem` |  |
| 90 | `physics` | `PhysicsSystem` | `physics` |
| 88 | `physics - 2` | `PhysicsJointBindingSystem` |  |
| 86 | `86` | `FlowFieldSystem` |  |
| 81 | `movement + 1` | `SimpleMovementSystem` |  |
| 80 | `movement` | `MovementSystem` | `movement` |
| 73 | `animation + 3` | `TimelineTriggerSystem` | `sprites` |
| 72 | `animation + 2` | `TimelineSystem` | `sprites` |
| 70 | `animation` | `AnimatorSystem` | `sprites` |
| 69 | `animation - 1` | `SpriteLoadSystem` | `sprites` |
| 68 | `animation - 2` | `SpriteAnimationSystem` | `sprites` |
| 65 | `effects` | `EffectSystemECS` |  |
| 60 | `gameplay` | `HealthSystem` |  |
| 60 | `gameplay` | `LifetimeSystem` |  |
| 59 | `dialogue` | `DialogueSystem` |  |
| 59 | `genreRules` | (genre packages) |  |
| 58 | `checkpoint` | `CheckpointSystem` |  |
| 50 | `hierarchy` | `HierarchySystem` |  |
| 48 | `particles` | `ParticleSystemECS` |  |
| 47 | `camera + 2` | `CameraTargetGroupSystem` | `cameras` |
| 46 | `camera + 1` | `CameraTriggerSystem` | `cameras` |
| 45 | `camera` | `CameraBrainSystem` | `cameras` |
| 40 | `render` | `RenderSystem` | `rendering` |
| 35 | `postProcess` | `PostProcessSystem` |  |
| 30 | `boundary` | `BoundarySystem` |  |
| 10 | `debug` | `ColliderDebuggerSystem` |  |
| 0 | `(none)` | `RaycastSystem` |  |
| -10 | `audio` | `AudioSystem` | `audio` |

`HierarchySystem` is deprecated: the world settles the hierarchy itself.

## Re-exported packages

The engine library re-exports these names; anything else from these packages needs its own import:

- `just_audio_engine` (17): Audio3DListener, Audio3DPosition, AudioBackend, AudioBus, AudioBusGraph, AudioChannel, AudioClip, AudioEffect, AudioEffectType, AudioEngine, AudioRolloff, AudioSpatial, AudioSpatialMix, AudioState, AudioStream, MusicManager, SoundEffectManager
- `just_dart` (9): Aabb3, Frustum, JustMatrix4, Matrix4, Plane, Quaternion, Ray3, Vector2, Vector3
- `just_game_engine_formats` (37): AnimatorBlendMotion, AnimatorBlendTree, AnimatorBlendType, AnimatorCondition, AnimatorGraph, AnimatorOp, AnimatorParameter, AnimatorParameterType, AnimatorState, AnimatorTransition, ComponentMigration, EntityMigration, FieldMigration, MigrationHooks, MigrationNote, MigrationResult, MigrationRun, SceneFormat, SceneManifest, SceneMigration, SceneMigrations, SceneNames, SceneStarters, TimelineFormat, TimelineMigration, TimelineV1ToV2, TrackMigration, UnsupportedFormatVersionException, V0ToV1, V1ToV2, V2ToV3, V3ToV4, V4ToV5, V5ToV6, V6ToV7, V7ToV8, V8ToV9
- `just_inputs` (43): ActionValueType, BindingDisplay, BindingOverrides, DeviceChange, DeviceListener, GamepadControls, GamepadDevice, GamepadSource, InputAction, InputActionAsset, InputActionCallback, InputActionMap, InputActionPhase, InputActions, InputControl, InputDevice, InputEvent, InputOverrideStore, InputService, InputSubscription, JoinBehavior, JustGamepadsSource, KeyboardDevice, KeyboardKeys, LookActions, LookInput, LookSettings, MemoryInputOverrideStore, MouseControls, MouseDevice, OnScreenDevice, PlayerInput, PlayerInputManager, PointerLock, RawInputListener, RebindCanceled, RebindCompleted, RebindResult, RebindState, RebindingOperation, TouchscreenControls, TouchscreenDevice, rebindPlayer
- `just_memory` (11): ArenaStats, CacheBudgetStats, DisposeCallback, MemoryCleanupResult, MemoryProfileSnapshot, MemoryProfiler, MemoryScope, MemoryStats, PoolManager, PoolStats, SystemMemorySnapshot
- `just_physics_engine` (31): BodyPair, BodyType, Box2DJoint, Box2DPhysicsEngine, CapsuleShape, ChainShape, CircleShape, CollisionDetector, CollisionManifold, CollisionShape, DistanceJoint, ForceManager, GroundState2D, JointConstraint, JointType, MouseJoint, MoverShape, OneWayDirection, PhysicsBody, PhysicsEngine, PolygonShape, Ray, RayBodyHit, RectangleShape, RevoluteJoint, RigidBody, RoundedPolygonShape, SegmentShape, ShapeCastResult, SpatialGrid, WeldJoint

## Deprecated in 2.0

Still exported, to go in a later major release; the deprecation message says what to use instead, where there is a replacement. `Engine`: `getSystem`, `parallax`; `Entity`: `generation`; `HierarchySystem`; `IEnableable`; `IPausable`; `IRenderable`; `IUpdatable`; `LifecycleStateMixin`; `ParallaxSystem`; `RenderingEngine`: `addManagedEmitter`, `addRenderable`, `layerCount`, `markLayerOrderDirty`, `markSpatialIndexDirty`, `onRenderBackground`, `onRenderOverlay`, `removeManagedEmitter`, `removeRenderable`, `renderableCount`, `renderables`, `updateManagedEmitters`, `useSpatialIndex`; `TagComponent`: `tag`. Parameters: `Entity(generation:)`, `ViewCullingSystem(gridCellSize:)`.

What changed since 1.x: [CHANGELOG](https://github.com/just-unknown-dev/just-game-engine/blob/main/CHANGELOG.md), [MIGRATION](https://github.com/just-unknown-dev/just-game-engine/blob/main/MIGRATION.md).

# just_game_engine 2.0.0-dev.4 — API map

Per area: the types a game uses most, what each is for, and the members people call. The full reference is the dartdoc on pub.dev: <https://pub.dev/documentation/just_game_engine/2.0.0-dev.4/> (`latest` there is the 1.x line).

Generated from `lib/` with an analyzer dump of the public libraries, so every name and signature is what 2.0.0-dev.4 exports. Typedefs are written out; long parameter lists keep positional and `required` parameters and cut the rest to `…`.

| Library | Exports |
|---|---|
| `package:just_game_engine/just_game_engine.dart` | 757 names: 610 from the engine, 147 [re-exported](#re-exported-packages) |
| `package:just_game_engine/widgets.dart` | 17 screen widgets ([list](#widgetsdart)) |
| `package:just_game_engine/just_game_engine_3d.dart` | 159 names: 72 from the engine ([3-D graphics](#3-d-graphics), [3-D physics](#3-d-physics)), 87 re-exported: 43 from `just_graphics_engine`, 30 from `just_physics_engine`'s 3-D side, 9 maths types (the main library's) and 5 from `just_game_engine_formats` |

Achievements, sign-in, leaderboards, currency, inventory and ads are `EngineService`s in the separate package `just_game_services` (not yet published).

## Engine and lifecycle

Make an `Engine`, `await initialize()`, show it in a `GameWidget`, call `start()`. `dispose()` is final.

- **`Engine`** — owns the subsystems, the world and the game loop.
  - `Engine({EngineConfig config = const EngineConfig(), EngineContext? context})`
  - `Future<void> initialize({EngineConfig? config})`
  - `void start()`
  - `Future<void> dispose()`
  - `T service<T extends EngineService>()`
  - `ValueListenable<EngineState> get stateListenable`
  - `void releaseUnused()` — after a level change, lets go of the maps, tilesets, 2-D material files and images, and each `SceneCacheService`'s models and 3-D materials, that the world no longer uses
  - `rendering`, `physics`, `input`, `audio`, `music`, `sfx`, `cache`, `camera`, `world`, `time`, `gameLoop`, `systemManager` throw `EngineNotReadyError` before `initialize()` and after `dispose()`; `Engine.context`, `Engine.assets`, `Engine.plugins`, `Engine.services`, `Engine.layers`, `Engine.terminal` never throw it (after `dispose()`, read them, don't use them: the layers, the terminal and a context the engine made are disposed).
- **`EngineConfig`** — set once, when the engine is made. 3-D is two services from `just_game_engine_3d.dart`: `services: [Graphics3D(), Physics3D()]`.
  - `EngineConfig({RenderingEngine Function()? createRendering, AudioEngine Function()? createAudio, Physics2DEngine Function()? createPhysics, bool? deferAudioUntilInput, List<ContextExtension> extensions = const [], List<EngineService> services = const [], Set<DefaultSystem> defaultSystems = const {}})`
- `enum EngineState { uninitialized, initializing, initialized, running, paused, failed, disposing, disposed }` — `engine.state`.
- `enum DefaultSystem { input, physics, movement, audio, rendering, sprites, animation, timelines, levelMaps, mapCollision, cameras }` — the engine's standard systems ([which](#system-priorities)); `DefaultSystems.all` and `DefaultSystems.headless` are ready-made sets.
- `void registerDefaultSystems(World world, Engine engine, {Set<DefaultSystem> include = DefaultSystems.all, GameCamera? camera, List<String> inputMaps = const ['player']})` — adds standard systems to a world, each at most once; `EngineConfig.defaultSystems` calls it during `initialize()`.
- **`GameWidget`** — hosts an engine: ticks the game loop, paints the world, forwards keys and pointers, draws the layers.
  - `GameWidget({required Engine engine, …})`
- **`GameLayers`** — `engine.layers`: Flutter widgets over the game (HUD, menus), each a `GameLayer`.
  - `void register(GameLayer layer)`
  - `void setEnabled(String id, bool enabled)`

Also: `EngineInitException`, `EngineNotReadyError`, `GameLayer`, `TimeManager`, `GameLoop`, `SystemManager`; plugins `EnginePlugin`, `PluginHost`; `GameTerminal` (the developer console).

## Context and services

An engine's registries, loaders and package state live in its `EngineContext` (`engine.context`, also `world.context`); nothing is process-wide. A package teaches an engine through a `ContextExtension` listed in `EngineConfig.extensions`. The engine's own features come from `BuiltInComponents.extension`, which an `Engine` installs first.

- **`EngineContext`** — per-engine definitions, registries, loaders and package state.
  - `EngineContext({Iterable<ContextExtension> extensions = const [], AssetBundle? bundle, bool withBuiltIns = true})`
  - `ComponentDefinitionRegistry definitions`
  - `void install(ContextExtension extension)`
  - Also holds `fieldTypes`, `migrations`, `assets`, `bundle` and `withBuiltIns`; `slot` keeps a feature's or a package's own state.
  - Each feature adds its members as an extension: `ContextTimeline` (`trackKinds`, `easings`, `signals`, `timelineAudio`, `timelines`), `ContextAnimation` (`animatorBindings`, `animationTargets`, `animatorGraphs`), `ContextLevelMap` (`collisionKinds`, `tiles`), `ContextEffects` (`effectTypes`), `ContextPhysics` (`physicsLayers`, `loadPhysicsLayers`), `ContextLocalization` (`localization`), `ContextSprites` (`sprites`), `ContextPrefabs` (`prefabs`, `prefabLibrary`), `ContextMaterials2D` (`material2DText`, `material2DLibrary`), `ContextCameraRegistries` (`cameraRegistries`), and in the 3-D library `ContextRenderProviders` (`renderProviders`) and `ContextGraphics3DModels` (`graphics3DModels`, set by `Graphics3D`); `ContextLoaders` (`overrideLoaders`, `useBundle`) swaps the file seams together.
- **`BuiltInComponents`** — every feature's component definitions.
  - `static const ContextExtension extension`
  - `static ComponentDefinitionRegistry registry()` — the ECS core's components and these, without a context.
  - `static List<ComponentCodec> get all`
  - `static List<FieldType> get fieldTypes` — the features' own field types (physics layers and shapes, 2-D material overrides).
  - `static const List<String> graphics3DTypes`, `physics3DTypes` — the 3-D components, named so a scene without `Graphics3D`/`Physics3D` says how to turn them on.
- **`ContextExtension`** — what a package installs into a context.
  - `String get id`
  - `void install(EngineContext context)`
- **`EngineService`** — lives as long as the engine; listed in `EngineConfig.services`.
  - `Future<void> start(ServiceContext context)`
  - `Future<void> stop()`

Also: `ServiceHost` (`engine.services`), `ServiceContext`, `SceneCacheService` (a service whose scene caches `Engine.releaseUnused` empties, as `Graphics3D`'s), `ContextResource`, `LoaderOverride`.

## ECS

Entities are ids with components, stored by archetype. Systems run each frame by priority, highest first. A system that creates or destroys entities inside its loop queues that on `world.commands`; the world applies the queue between systems.

- **`World`** — `engine.world`: entities, systems, queries, events.
  - `World({EngineContext? context, Iterable<ContextExtension> extensions = const []})` — on its own, a fresh context with the ECS core's components and [extensions]; `World(extensions: [BuiltInComponents.extension])` reads the engine's scenes.
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

A scene is JSON, format 11; older files are migrated on load. Components are read through the `ComponentDefinition`s in `context.definitions`: the engine's are always there, a package adds its own with its extension, and an unknown component stops the load with `UnknownComponentTypeException`.

- **`SceneLoader`** — loads scenes into a world.
  - `static Future<List<Entity>> loadAsset(World world, String assetPath, {AssetBundle? bundle, ComponentDefinitionRegistry? codecs, MigrationHooks? hooks, void Function(SceneMigrationResult)? onMigrated})`
  - `static List<Entity> loadString(World world, String source, {…})`
- **`SceneFormat`** — the version and the migration chain.
  - `static int current`
  - `static SceneMigrationResult migrateWithReport(Map<String, dynamic> json, {MigrationHooks? hooks})`
- **`ComponentDefinitionRegistry`** — what a context can save, load, inspect and draw.
  - `ComponentDefinitionRegistry()` — empty; `BuiltInComponents.registry()` is one with the engine's components
  - `void register(ComponentCodec<Component> codec, {bool override = false})`
  - `void registerUnknownTypeHint(String type, String hint)` — what `UnknownComponentTypeException.hint` says for a type nobody registered.
- **`ComponentDefinition`** — one component type: factory, fields, editor hints, size, painter.
  - `ComponentDefinition<T>({required String type, required T Function() create, required List<FieldDefinition> fields, …})`
- **`FieldDefinition`** — one saved property.
  - `FieldDefinition({required String name, required FieldType<dynamic> kind, required Object? Function(Component) read, …})`

Also: `SceneAssets` (scenes live in `assets/scenes`, listed in `assets/scenes/scenes.json`); `ComponentDefinition`, `FieldTypes` (for a game's own components), `MigrationHooks`, `SceneMigrationResult`, `UnsupportedFormatVersionException`, `TagLibrary` (the project's tags, `assets/project/tags.json`).

## Rendering

`RenderSystem` draws renderable entities through the camera, sorted by `LayerComponent` layer, then z-order. `engine.rendering` owns the frame, its hooks and post-processing.

- **`RenderingEngine`** — `engine.rendering`.
  - `Color backgroundColor`
  - `void addPostProcessPass(PostProcessPass pass)`
  - `Map<String, dynamic> get stats`
  - `int? get drawingFrame` — the number of the frame `render` is drawing, null between frames; every view drawn in it shares the number
- **`RenderSystem`** — draws the world; optional culling and shape batching.
  - `RenderSystem({GameCamera? camera, SpriteBatchRenderer Function(Image)? spriteBatchFactory, List<RenderPass>? passes, FrameView Function()? viewOf, bool batchShapes = false, bool cullOffscreen = false, RenderStatsSink? statsSink, double Function()? clock})` — `clock` is the time animated 2-D materials run on; the default system passes `() => engine.time.totalTime`, and without it they stand still
- **`RenderableComponent`** — any `Renderable` on an entity.
  - `RenderableComponent({required Renderable renderable, bool syncTransform = true})`
- **`Renderable`** — base class of drawables.
  - `void render(Canvas canvas, Size size)`
- **`LayerComponent`** — draw order and editor grouping.
  - `LayerComponent({String layerId = 'main', int layer = 0, int zOrder = 0, bool visible = true, bool locked = false, int? mapLayer})`
- **`Rectangle2DComponent`** — a rectangle shape.
  - `Rectangle2DComponent({required double width, required double height, …})`
- **`ParallaxComponent`** — a background behind the world, drawn by `ParallaxRenderSystem`.
  - `ParallaxComponent({required ParallaxBackground background})`
- **`Material2DComponent`** — draws the entity's sprite or shape through a 2-D material file (`*.material2d.json`): outline, flash, dissolve, wave, … (`Material2DEffects`).
  - `Material2DComponent({String material = '', Map<String, Object>? overrides})`
  - `void set(String key, Object value)`, `remove(String key)` — the entity's own values, by key (`flash.amount`)
  - the files are read by `context.material2DLibrary` (`Material2DLibrary`: `fileOf`, `preview`, `reload`, and `List<String> retainOnly(Iterable<String> keep)` between levels)
- **`ScreenMaterialComponent`** — draws the whole view through a `screen` material (vignette, colour grade, scanlines, …); the enabled one with the highest `order` wins.
  - `ScreenMaterialComponent({String material = '', bool enabled = true, int order = 0, Map<String, Object>? overrides})`
- **`Lighting2DComponent`** — turns 2-D lighting on for its scene, over an ambient light.
  - `Lighting2DComponent({bool enabled = true, Color ambient, double ambientIntensity = 1, double shadowSoftness = 0.3})`
- **`Light2DComponent`** — a point or spot light (`Light2DKind`) at its entity, shading by the materials' normal maps.
  - `Light2DComponent({Light2DKind kind = Light2DKind.point, Color color, double intensity = 1, double radius = 240, …, bool castShadows = true, bool enabled = true})`
- **`ShadowCaster2DComponent`** — makes the entity's sprite or shape cast shadows.
  - `ShadowCaster2DComponent({bool enabled = true, double depth = 12})`

Also: shapes `Circle2DComponent`, `Polygon2DComponent`, `Line2DComponent`, `Capsule2DComponent`, `ShapePaintStyle`; `LevelLayers`, `ParallaxBackground`, `ParallaxLayer`, `ParallaxRenderSystem`; post-processing `ShaderComponent`, `PostProcessPass`, `PostProcessSystem`; `RenderHookChain`, `RenderStatsSink`, `Sprite`, `SpriteBatch`, `TextRenderable`, `CustomRenderable`; culling `ViewCullingSystem`, `CullStateComponent`; 3-D seam `SceneRenderer`, `FrameView`.

## Sprites and animation

Sprites are data: `SpriteComponent` (an image or atlas region) and `SpriteAnimationComponent` (an atlas clip). An `AnimatorComponent` runs a state-machine graph that picks the clip. The systems are in `DefaultSystem.sprites` (sprites and clips) and `DefaultSystem.animation` (the animator).

- **`SpriteComponent`** — a still image or atlas region.
  - `SpriteComponent({required String spritePath, …})`
- **`SpriteAnimationComponent`** — plays an atlas clip.
  - `String clip`
  - `void switchClip(String name, {bool restartIfSame = false, bool? loop})`
- **`SpriteAnimationSystem`** — plays clips; reports frame events.
  - `Stream<SpriteAnimationSignal> get signals`
- `void registerSpriteSystems(World world, {…, bool animators = true, bool timelines = true})` — adds the sprite systems, and the animator and timeline systems unless told not to; `registerAnimatorSystems` and `registerTimelineSystems` add those alone.
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

A timeline (`.timeline.json`, format 3) animates fields, switches entities on and off, plays audio and clips, cuts cameras and fires events. `TimelineSystem` (in `DefaultSystem.timelines`) runs each `TimelinePlayerComponent`.

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

A virtual camera is an entity with a `VirtualCameraComponent` and optional stage components. Each frame the `CameraBrain` picks the live camera by priority, blends between shots and drives the output camera, an `OutputCamera`.

- **`CameraEngine`** — `engine.camera`.
  - `OutputCamera mainCamera`
  - `CameraBrain brain`
- **`CameraBrain`** — picks, blends and evaluates cameras.
  - `Entity? get liveCamera`
  - `void emitImpulse(CameraImpulse impulse)`
- **`OutputCamera`** — the output camera.
  - `Offset screenToWorld(Offset screenPos)`
  - `Offset worldToScreen(Offset worldPos)`
- **`VirtualCameraComponent`** — makes an entity a camera.
  - `int priority`
  - `EntityTarget follow`
- `void registerCameraSystems(World world, CameraEngine cameraEngine)` — adds the target-group, trigger and brain systems.

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
  - `static void evictUnused(World world)`, `static Set<String> materialsIn(World world)` — between levels (`Engine.releaseUnused` calls them)
- **`LevelMapHandle`** — reading and changing a map at run time.
  - `MapLayerData? layer(Object idOrName)`
  - `TileInfo? tileAt(MapLayerData layer, TileCoord c)`
  - `bool setTile(MapLayerData layer, TileCoord c, int cell)`

Also: `MapCollisionSystem`, `TileChangedEvent`, `TileAssets`, `LevelMapData`, `MapCollisionKinds`, `TilesetData`, `TiledInterop`, `BuiltInTilesets`, `MapGeometry`, `TileCoord`, `MapBodyComponent`.

## Physics

`engine.physics` is a `Physics2DEngine` from `just_physics_engine`: Box2D where its native library loads, pure Dart otherwise and on the web. `Physics2DSystem` makes a body per `Collider2DComponent`, moved as the entity's `RigidBody2DComponent` says (a static body without one), steps, and writes positions back. The names are 3-D physics' (`package:just_game_engine/just_game_engine_3d.dart`), with `2D` for `3D`.

- **`Physics2DSystem`** — bodies from components, the joints between them and the characters; contacts as events. It draws nothing: collider outlines are a `Collider2DDebuggerSystem`'s.
  - `Physics2DSystem(Physics2DEngine physics, {bool reportContactStay = false})`
  - `Entity? entityOf(Physics2DBody body)`, `Physics2DBody? bodyOf(Entity entity)`, `Physics2DQueries queries`
- **`RigidBody2DComponent`** — how a body moves: body type, mass, material (friction, restitution), motion (gravity scale, damping, continuous collision, sleep, locked rotation, start velocity), sensor, layer and what it collides with. After each step it holds `isGrounded`, `groundEntity`, `groundNormal`, `linearVelocity`, `angularVelocity` and `isAwake`.
  - `RigidBody2DComponent({Body2DType bodyType, double mass, double friction, double restitution, …, int layer, int? collidesWith})`
  - `void addForce(Offset force)`, `addImpulse(Offset impulse)`, `addTorque(double torque)`, `addAngularImpulse(double impulse)`, `setVelocity(Offset velocity)`, `setAngularVelocity(double velocity)`, `wakeUp()`
  - `bool get isStatic`, `isKinematic`, `isDynamic`
- **`Collider2DComponent`** — a body's shape (`Collider2DShape`: box, circle, capsule, polygon, segment, chain, or `matchShape` for what the entity draws), with its own offset, rotation and scale, and one-way; and `reflectivity`, how much of a `RayTracer2D` ray it sends back (0, the default, absorbs it). Alone, a static body. It follows the entity's scale.
  - `Collider2DComponent({Collider2DShape shape, Vector2? size, double radius, …, Offset offset, bool oneWay, …, double reflectivity = 0.0})`
- **`PhysicsLayers`** — sixteen named collision layers and which collide; `engine.context.physicsLayers`, read from `assets/project/physics.json` on `initialize()`.
  - `String nameOf(int layer)`, `labelOf(int layer)`, `Color colorOf(int layer)`, `String descriptionOf(int layer)`, `int? indexOf(String name)`, `int maskOf(int layer)`, `bool collides(int a, int b)`
  - `PhysicsLayers withName(int layer, String name)`, `withColor`, `withDescription`, `withCollision(int a, int b, bool collide)`, `cleared(int layer)`, `int? firstFree`, `String? problemWithName(String name, {int? except})`, `toJson()`, `fromJson(json)`
- **`Collider2DGeometry`** — a collider as simulated: `build(shape, offset:, rotation:, sx:, sy:)`, `shapeOf(collider, entity:)`, `of(collider, transform)`, `boundsOf(shape)`, `paint(canvas, shape, paint)`.
- **`Physics2DEngine`** — `engine.physics`.
  - `void setGravity(double gx, double gy)`
  - `void applyLinearImpulse(Physics2DBody body, double ix, double iy)`
  - `Ray2DHit? raycast(Ray2D ray, {Set<Physics2DBody>? exclude})`
- **`CharacterBody2DComponent`** — a character gameplay moves rather than the simulation (the 3-D `CharacterBody3DComponent`, field for field): a capsule or a box (`CharacterBody2DShape`) that walks slopes, climbs steps, keeps to the floor, rides platforms and pushes bodies. It needs no rigid body or collider. `Physics2DSystem` moves it before each step (`Physics2DCharacters`).
  - `CharacterBody2DComponent({CharacterBody2DShape shape, double radius, double width, double height, Offset offset, double maxSlopeAngle, double stepHeight, double stickToFloor, …, int layer, int? collidesWith, bool detectable})`
  - `Offset moveVelocity`, `void jump(double speed)`; after each step `velocity`, `groundState` (`Ground2DState`), `isGrounded`, `groundNormal`, `groundVelocity`, `groundEntity`
- **`Physics2DQueries`** — rays, casts and overlaps, answering with entities; `physicsSystem.queries` is the system's own.
  - `Physics2DQueries(Physics2DSystem system)`
  - `Physics2DHit? raycast(Offset origin, Offset direction, {double maxDistance, int layerMask, Entity? ignore, bool includeSensors})`, `List<Physics2DHit> raycastAll(…)`, `Physics2DHit? circleCast(…)`
  - `List<Entity> overlapCircle(…)`, `overlapBox(…)`
- **`RayTracer2D`** — a ray that bounces, built on the physics ray: each stretch is a `Physics2DQueries.raycast` (the same layers, sensors and `ignore`), and a hit collider whose `reflectivity` is above 0 mirrors it about the hit normal with what is left of its length times the reflectivity; `maxBounces` caps it.
  - `RayTracer2D(Physics2DQueries queries, {int maxBounces = 3, double minReflectivity = 0})`
  - `RayTrace2D trace(Offset origin, Offset direction, {double maxDistance, int layerMask, Entity? ignore, bool includeSensors})` — `segments` (`RayTrace2DSegment`: `from`, `to`, `hit`), `hits`, `totalLength`
- **`CollisionEnter2DEvent`** — fired on `world.events`.
  - `Entity entityA`
  - `Entity entityB`
  - `Offset point`
  - `Offset normal`
  - `double depth`

Also: `CollisionStay2DEvent`, `CollisionExit2DEvent`, `SensorEnter2DEvent`, `SensorExit2DEvent`; `Physics2DHit`; joints `Joint2DComponent`, `DistanceJoint2DComponent`, `FixedJoint2DComponent`, `SliderJoint2DComponent`, `WheelJoint2DComponent` (made by `Physics2DSystem`); `Collider2DDebuggerSystem` (collider outlines, for debugging: `GameWidget(showDebug: true)` adds one); `Physics2DDefinitions`, `PhysicsDefinitions`; shapes `Rectangle2DShape`, `Circle2DShape`, `Capsule2DShape`, `Polygon2DShape`.


## 3-D graphics

`package:just_game_engine/just_game_engine_3d.dart`. Give the engine a `Graphics3D` and it saves, loads and draws the 3-D components with `just_graphics_engine` on Flutter GPU; without one a game is 2-D only, makes no GPU device and loads no shaders.

- **`Graphics3D`** — the one way in: installs the components, loads models for the asset manager, adds a `Graphics3DSceneRenderer` to the frame and an `Animation3DSystem` to the world. List it in `EngineConfig.services` before any service that loads models as it starts. It is a `SceneCacheService`: `releaseUnused()` (which `Engine.releaseUnused` calls) lets go of the models, 3-D material files and maps the world no longer draws.
  - `Graphics3D({GpuDevice? device, double renderScale = 1.0, void Function(String reason)? onUnsupported, bool? keepEdges})`
  - `static void registerDefinitions(EngineContext context)` — the components alone, for tools that read and write 3-D scenes without drawing them
  - `Renderer3D get renderer`, `Graphics3DModels get models`, `Graphics3DSceneRenderer get sceneRenderer` (throw before the engine initializes); `bool get isStarted`, `bool get isSupported`, `String? get unsupportedReason`
- **`engine.graphics3D`** (an extension in `just_game_engine_3d.dart`) — the `Graphics3D` given in `EngineConfig.services`, or null.
- **`ModelComponent`** — a `.glb` / `.gltf` model.
  - `ModelComponent({String model = '', Map<String, String>? materials, bool castShadows = true, bool visible = true})` — `materials` lays material files over the model's own, by name
- **`AnimationPlayerComponent`** — plays the model's clips. `clip`, `speed` and `loop` are what was authored and saved; what plays is `playingClip`, `playingSpeed` and `playingLoop` (set those after `play()`).
  - `AnimationPlayerComponent({String clip = '', double speed = 1.0, bool loop = true, bool playing = true, double crossfade = 0.2})`
  - `void play(String name, {double? fade, bool restart = false})`, `playBlend(…)`, `setBlendWeights(List<double> weights)`, `release({double? fade})`
- **`SocketComponent`** — pins its entity to a joint of its parent's model.
  - `SocketComponent({String node = ''})`
- **`Light3DComponent`** — a directional, point or spot light (`Light3DKind`), shining along the entity's +Z; a scene with no lights gets a default sun.
  - `Light3DComponent({Light3DKind kind = Light3DKind.point, Color color, double intensity = 10.0, double range = 0.0, double innerConeAngle = 0.0, double outerConeAngle})`
- **`EnvironmentComponent`** — sky (gradient or `.hdr`), ambient light, reflections, fog and exposure.
  - `EnvironmentComponent({bool sky = true, Color zenith, Color horizon, Color ground, …, double exposure = 1.0, bool fog = false, …})`
- **`Primitive3DComponent`** — base of the eleven shapes made from their own sizes: `Cube3DComponent`, `Sphere3DComponent`, `Plane3DComponent`, `Cylinder3DComponent`, `Capsule3DComponent`, `Cone3DComponent`, `Torus3DComponent`, `Ramp3DComponent`, `Stairs3DComponent`, `Arch3DComponent`, `Polygon3DComponent`. Each has a material of its own or a material file (`material`).
- **`MaterialOverrides3DComponent`** — the entity's own values over its material files, by key.
  - `MaterialOverrides3DComponent({Map<String, Object>? values})`
- **`Material3DLibrary`** — `sceneRenderer.materials`: material files (`*.material.json`, `Material3DFile`) read and made into GPU materials in the background.
  - `GpuMaterial? gpuOf(String path, {Map<String, Object?> overrides = const {}})`, `Material3DFile? fileOf(String path)`, `void reload(String path)`
- **`RenderProviders`** — `context.renderProviders`: lets a package draw a component of its own as meshes and instance batches.
  - `void register(RenderProvider<Component> provider)`
- **`Animation3DSystem`** — advances each player's clip and crossfade, then moves socket entities to their nodes (priority `animation`, 70); added by `Graphics3D`.

Also: `Graphics3DSceneRenderer` (`dynamicResolution`, `renderScale`; it looks the world over once per engine frame, however many views it draws, through its `frame:` callback), `Graphics3DModels`, `Graphics3DModelAsset`, `Graphics3DModelLoader`, `Graphics3DShapes`, `SkeletalClipTrack` and `SkeletalAnimationTarget` (timelines and animator graphs on a skeleton), `RenderProvider`, `RenderProviderContext`, `RenderProviderOutput`, `MaterialSlots`, `LinearColor`, `Material3DOverridesFieldType`; definitions `Graphics3DDefinitions`, `Shape3DDefinitions`, `Material3DDefinitions`, `Lighting3DDefinitions`; and the just_graphics_engine types a game names (the renderer and its views, lights and settings, the GPU resources the engine hands out, model, mesh and material data), re-exported. Its GPU plumbing, model cooking, test doubles and `RenderView` (which clashes with Flutter's) come from `package:just_graphics_engine/just_graphics_engine.dart` itself.

## 3-D physics

`package:just_game_engine/just_game_engine_3d.dart`. Give the engine a `Physics3D` and it saves, loads and simulates the 3-D components on Jolt Physics; without one a game is 2-D only and carries none of this.

- **`Physics3D`** — the one way in: installs the components, starts the physics engine, adds the system.
  - `Physics3D({Physics3DEngine? engine, Vector3? gravity, int workerThreads = -1, int maxBodies = 10240, bool reportContactStay = false, bool reportActivation = false, bool addSystem = true})`
  - `static void registerDefinitions(EngineContext context)`, `static bool get isSupported`, `static String? get unsupportedReason`
  - `bool get isStarted`, `Physics3DEngine get engine`, `Physics3DSystem get system`, `Physics3DQueries get queries`, `bool get hasWorld`, `Physics3DWorld get world`
- **`engine.physics3D`** (an extension in `just_game_engine_3d.dart`) — the `Physics3D` given in `EngineConfig.services`, or null.
- **Components**: `RigidBody3DComponent` (`bodyType`, `mass`, `friction`, `restitution`, `linearDamping`, `angularDamping`, `gravityScale`, `isSensor`, `lockRotation`, `continuousCollision`, `canSleep`, `layer`; `addForce`, `addImpulse`, `setVelocity`, …), `Collider3DComponent` (`shape`: `Collider3DShape`), `CharacterBody3DComponent` (`moveVelocity`, `jump`, `isGrounded`, `groundVelocity`, …), joints `FixedJoint3DComponent`, `PointJoint3DComponent`, `HingeJoint3DComponent`, `SliderJoint3DComponent`, `DistanceJoint3DComponent`, `SixDofJoint3DComponent` (`Joint3DComponent`), `CameraCollision3DComponent`.
- **`Physics3DSystem`** — steps the world: `Physics3DSystem(Physics3DWorld physics, {Collider3DGeometry? geometry})`, `Physics3DSystem.lazy(Physics3DWorld Function() create, …)`; `entityOf`, `bodyOf`, `characterOf`.
- **Events**: `CollisionEnter3DEvent`, `CollisionStay3DEvent`, `CollisionExit3DEvent`, `SensorEnter3DEvent`, `SensorExit3DEvent`.
- **`Physics3DQueries`** — `raycast`, `raycastAll`, `sphereCast`, `shapeCast`, `overlapSphere`, `overlapBox`, `overlap` (`Physics3DHit`).
- Also: `Physics3DDefinitions`, `Collider3DShapes`, `Collider3DGeometry`, `AssetCollider3DGeometry`, `CameraCollision3DStage`, and just_physics_engine's 3-D side: `Physics3DEngine`, `Physics3DWorld`, `JoltPhysicsEngine`, `Physics3DUnsupportedError`, the shapes (`Box3DShape` … `Compound3DShape`), settings, hits and events.

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
- **`AudioSourceComponent`** — a sound on an entity; `play()`, `pause()`, `resume()` and `stop()` ask the `AudioSystem` to control it (`AudioRequests`); `playOnAdd` is never changed by the system.
  - `AudioSourceComponent({required String clipPath, …})`
- **`AudioSystem`** — plays the world's sounds.
  - `void playOneShot(String clipPath, {Vector3? position, …})` — a sound played once, with nothing added to an entity.
- **`AudioListenerComponent`** — where 3-D sounds are heard from.
  - `AudioListenerComponent({bool atCamera = false, bool faceCamera = false})`
- **`AudioSpatial`** — how a 3-D sound is heard: `minDistance`, `maxDistance`, `rolloff`, `dopplerLevel`, `farCutoff`; `mix(...)` works it out.
- `enum AudioChannel { master, music, sfx, voice, ambient }` — mixer channels.
- `enum AudioRolloff { inverse, linear, none }` — how a 3-D sound fades with distance.

Also: `MusicManager`, `SoundEffectManager`, `AudioStreamComponent`, `AudioRequests`, `AudioRequest`, `AudioSpatialMix`; `Engine.suspendAudio()` / `resumeAudio()` (what `GameWidget` does as the app goes to the background and comes back).

## Particles and effects

A `ParticleEmitter` goes on an entity through `ParticleEmitterComponent`; `ParticleSystem` updates it (not a default system: add it) and `RenderSystem` draws it. Effects are deterministic tick-based tweens queued per entity.

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
- **`EffectSystem`** — runs `EffectComponent` queues; snapshots.
  - `EffectHandle scheduleEffect({required Entity entity, required DeterministicEffect effect, int? startTick})`

Also: `ParticleSystem`, `EffectComponent`, `EffectSerializer`, `EffectTypes`; forces `GravityForce`, `WindForce`, `DragForce`, `VortexForce`; effects `SequenceEffect`, `MoveEffect`, `ScaleEffect`, `RotateEffect`, `FadeEffect`, `ShakeEffect`, `PathEffect`, `ParallelEffect`, `RepeatEffect`.

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
  - `void release(String path, AssetType type)` — counts are kept per path and type
  - `void retainOnly(Iterable<String> paths)` — lets go of every asset not named and not held, after a level change
- **`CacheManager`** — `engine.cache`.
  - `Future<dynamic> getJson(String key)`
  - `Future<void> setJson(String key, dynamic data)`
- **`MemoryScope`** — disposes what it owns together.
  - `void own(FutureOr<void> Function() callback)`
  - `void dispose()`

Also: `ImageAsset`, `JsonAsset`, `AssetScope`; diagnostics `MemoryProfiler`, `PoolManager`.

## widgets.dart

`package:just_game_engine/widgets.dart`: optional screen UI over a game.

- **`DialogueBox`** — a `DialogueRunner`'s lines.
  - `DialogueBox({required DialogueRunner runner, …})`
- **`LocalizedText`** — text that follows the locale.
  - `LocalizedText(String key_, {…})`
- **`GameCameraControls`** — wheel, pinch and button zoom.
  - `GameCameraControls({required Camera camera, required Widget child, …})`
- **`OnScreenControls`** — touch sticks and buttons (`just_inputs`).
  - `OnScreenControls({required InputService input, …})`
- **`RebindList`** — a player's rebinding list (`just_inputs`).
  - `RebindList({required PlayerInput player, …})`

Also: `BuildContextLocalization`, `DialogueChoices`, `SubtitleOverlay`, `LocaleSelector`, `LocalizationBuilder`, `OnScreenVisibility`, `OnScreenButtonFace`, `OnScreenStickPainter`, `RebindButton`, `RebindRow`, `rebindRows`, `BindingLabel`.

## System priorities

`World.update` runs systems from the highest `priority` to the lowest; systems of equal priority run in the order they were added. The world settles parent–child transforms (`TransformHierarchy`) just before the first system below `hierarchy` (50). A system that sets no priority runs at 0. Generated from `SystemPriorities` and each engine system's `priority`; "Default set" is the `DefaultSystem` that adds it.

| Priority | Expression | Engine system | Default set |
|---:|---|---|---|
| 110 | `levelMap` | `LevelMapSystem` | `levelMaps` |
| 108 | `mapCollision` | `MapCollisionSystem` | `mapCollision` |
| 105 | `parallax` | `ParallaxRenderSystem` | `rendering` |
| 100 | `input` | `InputSystem` | `input` |
| 95 | `playerControl` | (genre packages) |  |
| 92 | `movingPlatform` | (genre packages) |  |
| 91 | `91` | `ViewCullingSystem` |  |
| 90 | `physics` | `Physics2DSystem` | `physics` |
| 90 | `physics` | `Physics3DSystem` (3-D library) | added by `Physics3D` unless `addSystem: false` |
| 86 | `86` | `FlowFieldSystem` |  |
| 81 | `movement + 1` | `SimpleMovementSystem` |  |
| 80 | `movement` | `MovementSystem` | `movement` |
| 73 | `animation + 3` | `TimelineTriggerSystem` | `timelines` |
| 72 | `animation + 2` | `TimelineSystem` | `timelines` |
| 70 | `animation` | `AnimatorSystem` | `animation` |
| 70 | `animation` | `Animation3DSystem` (3-D library) | added by `Graphics3D` |
| 69 | `animation - 1` | `SpriteLoadSystem` | `sprites` |
| 68 | `animation - 2` | `SpriteAnimationSystem` | `sprites` |
| 65 | `effects` | `EffectSystem` |  |
| 60 | `gameplay` | `HealthSystem` |  |
| 60 | `gameplay` | `LifetimeSystem` |  |
| 59 | `dialogue` | `DialogueSystem` |  |
| 59 | `genreRules` | (genre packages) |  |
| 58 | `checkpoint` | `CheckpointSystem` |  |
| 50 | `hierarchy` | (the world's `TransformHierarchy`, not a system) |  |
| 48 | `particles` | `ParticleSystem` |  |
| 47 | `camera + 2` | `CameraTargetGroupSystem` | `cameras` |
| 46 | `camera + 1` | `CameraTriggerSystem` | `cameras` |
| 45 | `camera` | `CameraBrainSystem` | `cameras` |
| 40 | `render` | `RenderSystem` | `rendering` |
| 35 | `postProcess` | `PostProcessSystem` |  |
| 30 | `boundary` | `BoundarySystem` |  |
| 10 | `debug` | `Collider2DDebuggerSystem` |  |
| -10 | `audio` | `AudioSystem` | `audio` |

## Re-exported packages

The engine library re-exports these names; anything else from these packages needs its own import:

- `just_audio_engine` (17): Audio3DListener, Audio3DPosition, AudioBackend, AudioBus, AudioBusGraph, AudioChannel, AudioClip, AudioEffect, AudioEffectType, AudioEngine, AudioRolloff, AudioSpatial, AudioSpatialMix, AudioState, AudioStream, MusicManager, SoundEffectManager
- `just_dart` (9): Aabb3, Frustum, JustMatrix4, Matrix4, Plane, Quaternion, Ray3, Vector2, Vector3
- `just_game_engine_formats` (40): AnimatorBlendMotion, AnimatorBlendTree, AnimatorBlendType, AnimatorCondition, AnimatorGraph, AnimatorOp, AnimatorParameter, AnimatorParameterType, AnimatorState, AnimatorTransition, ComponentMigration, EntityMigration, FieldMigration, Material2DEffect, Material2DEffects, Material2DFile, Material2DKind, Material2DParam, Material2DValue, MaterialChain, MigrationHooks, MigrationNote, MigrationRun, PrefabApply, PrefabCollapse, PrefabEntity, PrefabExpander, PrefabFile, PrefabInstance, PrefabNode, PrefabOverride, ResolvedMaterial, SceneFormat, SceneManifest, SceneMigrationResult, SceneNames, SceneStarters, TimelineFormat, TrackMigration, UnsupportedFormatVersionException (the 3-D library adds Material3DAlpha, Material3DFile, Material3DKind and Material3DUv; the migration steps, `V0ToV1` … `V10ToV11` and the timeline's, are formats' own: import `package:just_game_engine_formats/just_game_engine_formats.dart` to name one)
- `just_inputs` (43): ActionValueType, BindingDisplay, BindingOverrides, DeviceChange, DeviceListener, GamepadControls, GamepadDevice, GamepadSource, InputAction, InputActionAsset, InputActionCallback, InputActionMap, InputActionPhase, InputActions, InputControl, InputDevice, InputEvent, InputOverrideStore, InputService, InputSubscription, JoinBehavior, JustGamepadsSource, KeyboardDevice, KeyboardKeys, LookActions, LookInput, LookSettings, MemoryInputOverrideStore, MouseControls, MouseDevice, OnScreenDevice, PlayerInput, PlayerInputManager, PointerLock, RawInputListener, RebindCanceled, RebindCompleted, RebindResult, RebindState, RebindingOperation, TouchscreenControls, TouchscreenDevice, rebindPlayer
- `just_memory` (11): ArenaStats, CacheBudgetStats, DisposeCallback, MemoryCleanupResult, MemoryProfileSnapshot, MemoryProfiler, MemoryScope, MemoryStats, PoolManager, PoolStats, SystemMemorySnapshot
- `just_physics_engine` (25): Body2DType, Box2DJoint, Box2DPhysicsEngine, Capsule2DShape, Chain2DShape, Circle2DShape, CircleCast2DHit, DistanceJoint2D, Ground2DState, Joint2D, Joint2DKind, MouseJoint2D, Mover2DShape, OneWayDirection, Physics2DBody, Physics2DEngine, Polygon2DShape, Ray2D, Ray2DHit, Rectangle2DShape, RevoluteJoint2D, RoundedPolygon2DShape, Segment2DShape, Shape2D, WeldJoint2D
- `just_signals` (2): Computed, Signal

## Removed in 2.0

The compatibility members earlier 2.0 dev releases kept are gone; [MIGRATION](MIGRATION.md#removed-apis) says what replaces each. `Engine`: `getSystem` (use `subsystem<T>()`), `parallax`; `Entity`: `generation`; `HierarchySystem`; `ILifecycle`, `IEnableable`, `IPausable`, `IRenderable`, `IUpdatable`, `LifecycleStateMixin`; `ParallaxSystem`; `RenderingEngine`: `addRenderable`, `layerCount`, `markLayerOrderDirty`, `markSpatialIndexDirty`, `onRenderBackground`, `onRenderOverlay`, `removeRenderable`, `renderableCount`, `renderables`, `useSpatialIndex`, `spriteBatchFactory`; `RectangleRenderable`, `CircleRenderable`, `LineRenderable`; `SpriteSheet`; `ParallaxLayer.repeat` (use `repeatX`/`repeatY`); `TagComponent`: `tag`; `offload`, `offloadUnit`; the `GameLoop` typedefs `UpdateCallback`, `RenderCallback`, `FrameCallback`; `VelocitySignals`, `HealthSignals`; `PhysicsJointBindingSystem` (`Physics2DSystem` makes the joints); `Physics2DSystem`'s `camera`, `drawsOutlines`, `outlineFilter` and `render` (a `Collider2DDebuggerSystem` draws the outlines); `TrackBindingKind`; `RaycastSystem`, `RaycastColliderComponent`, `RaycastHit`, `RayTracer`, `RayTrace` and `RayTraceSegment` (rays go through the physics: `Physics2DQueries`, and `RayTracer2D` for bounces off a collider's `reflectivity`). Parameters: `Entity(generation:)`, `ViewCullingSystem(gridCellSize:)`.

The 2.0.0-dev.4 renames (`CameraSystem` → `CameraEngine`, `Camera` → `OutputCamera`, `ComponentSchema` and `SchemaField` → `ComponentDefinition` and `FieldDefinition`, `PrefabLibrary.of(context)` → `context.prefabLibrary`, …) are listed in the [CHANGELOG](CHANGELOG.md) and [MIGRATION](MIGRATION.md#renamed-in-200-dev4).

What changed since 1.x: [CHANGELOG](https://github.com/just-unknown-dev/just-game-engine/blob/main/CHANGELOG.md), [MIGRATION](https://github.com/just-unknown-dev/just-game-engine/blob/main/MIGRATION.md).

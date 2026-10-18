# Changelog

All notable changes to the Just Game Engine will be documented in this file.

## [2.0.0-dev.2] - 2026-10-17

The 3-D Level Designer's runtime seams, prefab files for every scene, and materials for 2-D and 3-D.

- **Prefab files** (`*.prefab.json`): a scene entry can place a prefab — its changes kept as overrides, entities removed or added, components added or removed, prefabs nested. `PrefabLibrary.of(context)` loads them (`load`, `loadAll`, `loadScene`) and makes one at run time (`instantiate`); `Spawner.prefab` spawns one; `EngineContext.prefabs` is the seam an editor points at its project (`overrideLoaders(prefabs:)`). `SceneLoader.placeFromHome` places an instance's inner entities, kept in the prefab's space. What an entity came from is marked at run time (`PrefabInstanceComponent`, `PrefabLink`; never saved). Scene format 10.
- **Material files** (`*.material.json`): `MaterialLibrary` loads them for the 3-D renderer, maps in sRGB or linear by slot; `Primitive3D.material` draws a shape with one; `ModelComponent.materials` replaces a model's own materials by name, index or `*` (`MaterialSlots`). Texture coordinates natural, in metres or from the world; a layered material blends four layers by vertex colour.
- **2-D materials**: `Material2D` draws an entity's sprite — or a shape, drawn once into an image while it looks the same (`ShapeSheets`) — through a 2-D material file (`*.material2d.json`): wave, scroll, palette swap, gradient map, greyscale, tint, flash, shine, outline, glow, drop shadow and dissolve, each a switch. A Level Map layer has one too (`MapLayerData.material`): water that scrolls and waves, lava that glows. `Material2DLibrary.of(context)` reads the files through the new `material2DText` seam (`overrideLoaders(material2DText:)`), resolves variants and shows unsaved edits (`preview`).
- **One draw per material**: every sprite sharing a material and a sheet is drawn in one `drawVertices` call through the engine's shader (`shaders/material_2d.frag`, declared in the pubspec), in the order the layers say; what differs per sprite — its frame, tint, place and an entity's own values (`Material2D.overrides`, `flash.amount`) — goes in a small image made each frame. It works the same under Impeller, Skia and on the web, where a shader per sprite would be slow (Windows) or wrong (one shader object read once a frame).
- **Screen materials**: `ScreenMaterial` (on the camera, or any entity; the highest `order` wins) draws the whole view through a 2-D material of the `screen` kind — pixelate, CRT, colour grade, gradient map, greyscale, scanlines, vignette (`shaders/material_2d_screen.frag`). `RenderingEngine.screenPass` (a `ScreenPass`; the engine installs `ScreenMaterialPass`) draws the frame into an image first: the game's drawing goes under it, overlay hooks from `RenderingEngine.screenPassOrder` (100: an editor's) over it, and it works on every renderer — unlike a post-process pass, which needs Impeller. `RenderHookChain.callRange` runs part of a chain; `RenderingEngine.pixelRatio` sets the image's resolution.
- **2-D lighting**: `Lighting2D` (one per scene: ambient light) turns it on; `Light2D` (point or spot: colour, intensity, radius, height, falloff, cone) lights the frame. Sprites, shapes and tile layers are shaded by their 2-D materials' normal maps (`normalMap`, turned and mirrored with the sprite; the shape is the sprite's own, and a map smaller than its sheet repeats across it, as a texture that tiles; green up, or down where `normalMap.directX` says so) and glow where `emissive`. `Lighting2DPass.showNormals` draws the normals the frame is lit by instead, as a normal map draws them: an editor's view of them. It is a screen pass (`Lighting2DPass`, first in `RenderingEngine.screenPasses`): the frame and its normals (`RenderSystem.renderNormals`, through `shaders/material_2d_normals.frag`) are lit by up to 16 lights in `shaders/lighting_2d.frag`; a scene without it pays nothing.
- **2-D shadows**: a `Light2D` that `castsShadows` is stopped by sprites and shapes with a `ShadowCaster2D`, and by Level Map layers that cast them (`MapLayerData.castsShadows`, `shadowDepth`): their shapes drawn into a mask (`RenderSystem.renderOccluders`), how far each light reaches every way found from it (`shaders/shadow_map_2d.frag`), soft edges from `Lighting2D.shadowSoftness`; a caster's own face stays lit `depth` units in.
- **Material values on the Timeline**: `Material2D.overrides`, `ScreenMaterial.overrides` and `MaterialOverrides3D.values` are `MaterialOverridesFieldType`s whose channels are the numbers a material may override (a pair as `key#0`, `key#1`), so a property track keys a hit flash, a dissolve, a glow or a sliding texture.
- `RenderingEngine.screenPasses` (a list, run in order, each from what the one before drew) replaces a single screen pass. Where layers can be filtered (Impeller), the last passes that can be filters (`ScreenPass.filter`; `ScreenMaterialPass` can, `Lighting2DPass` cannot) filter a layer the frame is drawn into instead of drawing from an image of it (`ScreenPassPlan`, which the material editor's preview uses too): a lit scene under a screen material no longer draws from images of images, which filled the GPU's memory on Windows.
- `RenderSystem(clock:)` gives moving effects their time (`engine.time.totalTime` by default); `RenderContext.time` hands it to render items.
- **Material variants**: `MaterialLibrary` draws a material that names a `parent` over its parents (`fileOf` is the resolved material, `sourceOf` the file as saved, `problemsOf` a missing parent or a loop); a parent saved again changes its variants.
- **Unsaved edits in the scene**: `MaterialLibrary.preview(path, file)` draws a material as an editor holds it — what uses it, its variants and the layered materials it is a layer of follow — until `endPreview`.
- **An entity's own material values**: `MaterialOverrides3D` (saved with the entity) lays values over the material files its shape or model is drawn with — a glow, a colour, how the maps repeat (`MaterialFile.animatableKeys`); `gpuOf(path, overrides:)`.
- **Transparency as the file says**: opaque, cutout (`alphaCutoff`) or blend; `opacity` counts only when it blends. A material file's maps can be moved (`offset`) and turned (`rotation`), and its occlusion map weakened (`occlusionStrength`).
- A material file saved again is drawn as it was until the new one is read, instead of the shape's own look in between; only what uses a file is made again when it changes.
- **Render providers**: `RenderProvider`, `RenderProviders.of(context)` and `RenderProviderOutput` let a package draw its own components as meshes and instance batches, built again only when its revision changes.
- **Editor aids in the renderer**: `SceneEditorAids` (what is hidden, the selection's outline, view modes, a slice plane, views to skip), `Camera.inSpace`, `Graphics3D(keepEdges:)`; up to 8 render surfaces.
- **Collision**: `SolidMesh` (triangles) and `SolidHeightField` (with holes) are parts a `SolidShapeSource` can give a `Collider3D` set to match its shape.
- Requires just_game_engine_formats ^0.2.0, just_physics_engine ^1.5.0 and just_graphics_engine ^0.1.0-dev.2.

## [2.0.0-dev.1] - 2026-10-15

A dev release of 2.0.0, a breaking release. The engine is now an object a game creates, initializes and disposes, with its own registries, loaders and world. Levels are JSON scenes described by component definitions that the game and an editor share. Cameras, input, sprites, tile maps, animation and the transform hierarchy were rebuilt, and the game services moved to a package of their own. 3-D graphics (drawn by just_graphics_engine) and 3-D physics (on Jolt) are there to opt into, on transforms, cameras and render and culling seams built for both. A 2-D game draws, moves and saves as before, and carries none of the 3-D.

Depend on it with `just_game_engine: ^2.0.0-dev.1`: a `^2.0.0` constraint does not pick up a dev release.

**Upgrading from 1.6? Read [MIGRATION.md](MIGRATION.md)**, which has the full lists of removed, renamed and deprecated APIs. Scene files saved by any earlier version still load: they are migrated in memory, format 0 to 9, and nothing on disk changes until you save.

The engine has 1,874 passing tests.

### Breaking changes

- **Lifecycle**: `Engine()` is an ordinary constructor (`Engine.instance` and `resetInstance()` are gone); `initialize()` throws `EngineInitException` and undoes what it built; `dispose()` is async and final; subsystem getters throw `EngineNotReadyError` outside that window ([engine setup](MIGRATION.md#engine-setup-and-lifecycle)).
- **Game services** (achievements, auth, leaderboards, currency, inventory, ads) moved to [`just_game_services`](https://pub.dev/packages/just_game_services) and are opt-in through `EngineConfig(services: ...)` ([game services](MIGRATION.md#game-services)).
- **Physics**: `PhysicsSystem(engine.physics)` replaces the 1.x solver and `PhysicsBridgeSystem`. `PhysicsBodyComponent` is split into `RigidBody2D` (how a body moves) and `Collider2D` (its shape), with the names, defaults (friction 0.5, no bounce, damping 0.05, and a mass worked out from the collider when it is 0) and events (`CollisionEnter2DEvent`, `SensorEnter2DEvent`, …) of the 3-D bodies; a collider alone is a static body. The joints are `DistanceJoint2D`, `FixedJoint2D`, `SliderJoint2D` and `WheelJoint2D`. A body has one `bodyType` and a named `layer` (0–15) with `collidesWith` instead of category and mask bits, and its collider follows the entity's scale ([physics bodies](MIGRATION.md#physics-bodies)). Saved scenes keep every old setting.
- **Transforms**: `rotation` is `angle` and `rotationX` / `rotationY` are `eulerX` / `eulerY`. Every `World` runs the hierarchy, and destroying a parent destroys its children ([transforms](MIGRATION.md#transforms), [hierarchy](MIGRATION.md#the-transform-hierarchy)).
- **Cameras** are virtual cameras and a brain; behaviours, `CameraFollowComponent`, springs, shake and `worldBounds` are removed ([cameras](MIGRATION.md#cameras)).
- **Input** comes from `just_inputs`: `engine.input` is an `InputService`, and `InputComponent` reads actions by name ([input](MIGRATION.md#input)).
- **Moved or replaced**: in-game UI components went to `just_ui_editor`, the Tiled components to `LevelMapComponent`, and the legacy animation system and scene graph to sprite animation, timelines and `SceneLoader` ([in-game UI](MIGRATION.md#in-game-ui), [level maps](MIGRATION.md#tile-maps-and-level-maps), [sprites](MIGRATION.md#sprites-and-animation), [scenes](MIGRATION.md#scenes-and-saving)).
- **No global instances**: localization and effect types live on `engine.context`, and asset loaders take `assets: engine.assets` ([localization](MIGRATION.md#localization), [assets](MIGRATION.md#assets)).
- **Imports**: widgets are in `package:just_game_engine/widgets.dart`, and re-exported packages use `show` lists ([imports](MIGRATION.md#imports)).
- **Draw order**: `RenderSystem` sorts by `LayerComponent` and draws particle emitters itself ([draw order](MIGRATION.md#draw-order)).
- **Storage**: the engine keeps its own storage file and prefixes cache keys; entries written with `setString` / `setJson` before 2.0 are not read ([storage](MIGRATION.md#storage-and-the-cache)).
- **Removed and renamed**: the networking stubs, the Steam and Epic providers, the `Reactive*Component`s and the particle `shape` / `gravity` deprecated in 1.6, and `AudioListenerComponent`'s fixed `forwardX` … `upZ` directions (the entity's rotation, `atCamera` and `faceCamera` say where the listener is and which way it faces); `AssetBundle` is `GameAssetBundle`, `typedef Easing` is `EasingFunction` and `SystemPriorities.tileMap` is `levelMap` ([removed](MIGRATION.md#removed-apis), [renamed](MIGRATION.md#renamed-apis)).
- **Audio is played and controlled by calls, not components**: `AudioPlayComponent`, `AudioPauseComponent`, `AudioResumeComponent` and `AudioStopComponent` are gone. `AudioSystem.playOneShot(...)` plays a sound once, and `play()`, `pause()`, `resume()` and `stop()` on an `AudioSourceComponent` or `AudioStreamComponent` control it (`AudioRequests`), so a sound no longer changes the world's structure twice. The system no longer clears `playOnAdd` when it starts a sound — it remembers what it started — so a scene an editor saves keeps its sounds starting ([audio](MIGRATION.md#removed-apis)).
- **A switched-off parent switches off its subtree**: queries, tag lookups, `findEntityByName` and the engine's systems go by the new `Entity.isActiveInHierarchy`; each entity's own `isActive` (the saved Enabled flag) is kept as it is ([behaviour](MIGRATION.md#behaviour-you-may-notice)).
- **Requires** Flutter 3.47.1 or newer, the first stable where Flutter GPU can be switched on in Windows and Linux release builds (for just_graphics_engine). Every app builds the renderer's shaders; a 2-D game never loads them.

### Added

- **3-D graphics** (`package:just_game_engine/graphics_3d.dart`): `EngineConfig(graphics3D: Graphics3D())` gives the engine `ModelComponent`, `LightComponent`, `EnvironmentComponent`, `AnimationPlayerComponent`, `SocketComponent` and the shapes `Cube3D` to `Polygon3D` (base `Primitive3D`), saved in scenes and drawn from the engine's camera by just_graphics_engine on Flutter GPU (`GraphicsSceneRenderer`, `GraphicsModels`, `GraphicsShapes`, `AnimationSystem3D`, `SkeletalAnimationTarget`, `SkeletalClipTrack`). Physics bodies and characters are drawn between their last two poses. A game without a `Graphics3D` is 2-D only: no GPU device, no shaders loaded, and a scene holding a 3-D component fails to load with an `UnknownComponentTypeException` whose `builtInHint` says how to turn 3-D graphics, or 3-D physics, on. Where Flutter GPU can't draw, the game runs anyway, the 3-D view shows a note, and `Graphics3D.unsupportedReason` and `onUnsupported` say why. `engine.graphics3D` is the one given; it starts before the game's own services.
- **3-D physics** (`package:just_game_engine/physics_3d.dart`): `EngineConfig(physics3D: Physics3D())` gives the engine `RigidBody3D`, `Collider3D` (box, sphere, capsule, cylinder, convex hull, mesh, height field, or matching a 3-D shape), `CharacterBody3D` and the joints `FixedJoint3D`, `PointJoint3D`, `HingeJoint3D`, `SliderJoint3D`, `DistanceJoint3D` and `SixDofJoint3D`, stepped by `PhysicsSystem3D` on Jolt Physics (just_physics_engine's `JoltPhysicsEngine`), with `CollisionEnter3DEvent` and the rest, `Physics3DQueries` and the camera's `CameraCollisionStage`. A game without a `Physics3D` is 2-D only and its release build carries none of it; the world is made only with the first 3-D body. The app's pubspec builds Jolt (`hooks: user_defines: just_jolt: build: true`); where 3-D cannot run, `initialize()` fails with a `Physics3DUnsupportedError` (`Physics3D.isSupported` asks first). `engine.physics3D` is the one given.
- `ModelAsset` and `ModelGeometry`: what the engine knows about a 3-D model (bounds, mesh names, CPU triangles for picking and mesh colliders). A renderer registers the loader for `AssetType.model`.
- `SolidShapeSource` and its convex `SolidPart`s (`SolidBox`, `SolidSphere`, `SolidCapsule`, `SolidCylinder`, `SolidHull`): a component whose look is a solid of known shape says so, and a physics package gives a collider that same shape (just_graphics_engine's 3-D shapes, and a `Collider3D` set to match the shape).
- **Saved formats in pure Dart**: `SceneFormat` and its migrations, `TimelineFormat`, `AnimatorGraph` and `UnsupportedFormatVersionException` now live in [`just_game_engine_formats`](https://pub.dev/packages/just_game_engine_formats), so the editor and the `just` command-line tool migrate files with the engine's own code. The engine re-exports them: no import changes. New there: `SceneStarters` (what a new level starts from), `SceneManifest` (`scenes.json`) and `SceneNames` (the naming rules).
- **The engine object**: `EngineConfig` (`defaultSystems`, `extensions`, `services`, `createRendering`, `createAudio`, and `createPhysics`, which makes `engine.physics`, the 2-D physics engine; null keeps the standard one, native Box2D or pure Dart on the web), `DefaultSystems.all` / `headless`, `Engine.stateListenable`, `Engine.cursor` (the mouse cursor `GameWidget` shows over the game; `SystemMouseCursors.none` hides it for mouse-look), and `EngineContext`: one engine's definitions, field types, migrations, loaders, signals and localization, which a package extends through a `ContextExtension`.
- **A per-frame phase.** `FrameSystem`: a `System` that also implements `frame(deltaTime, alpha)` runs once per rendered frame, after the frame's fixed updates and before it is drawn (`World.frame`, `GameLoop.onFrame`, `SystemManager.registerFrameTask`/`runFrameCycle`). Systems that don't implement it pay nothing.
- **Services, plugins and widget layers**: `EngineService` and `ServiceHost`; `EnginePlugin`, updated even while paused; `GameLayers`, which draw real Flutter widgets over the game; `GameWidget.overlay`.
- **Scenes**: a `ComponentDefinition` describes a component's fields, save format and editor hints once, for the game and an editor alike. `SceneLoader` loads scenes and the `scenes.json` manifest. Scene format 9, with step-by-step migrations (`MigrationHooks`, `MigrationResult`); files from a newer engine are refused with `UnsupportedFormatVersionException`.
- **Level maps**: `LevelMapComponent` (inline, a `.map.json`, or a Tiled `.tmx` / `.tmj`), all four Tiled orientations, sparse chunked layers drawn among the sprites, merged collision bodies (`MapCollisionSystem`), entities on map layers, run-time edits through `LevelMaps.of(...)`, Wang fills, `TiledInterop`, and a built-in `basicShapes` tileset.
- **Sprites and animation**: `SpriteComponent` and `SpriteAnimationComponent` play TexturePacker and Aseprite atlases; `AnimatorGraph` (`.animator.json`) state machines read velocity, health and other bindings with no code, crossfade a transition over its `duration` on targets that can blend, and weigh several clips in a state's `blend` tree by one or two parameters (`AnimatorBlendTree`, `AnimatorBlendMotion`, `AnimatorBlendType`; a sprite plays a blend tree's heaviest motion and always cuts); one `Easings` table.
- **Animation targets**: `AnimationTarget` and `context.animationTargets`. An entity with an `AnimatorComponent` and no sprite plays its graph on the first registered target that drives it (just_graphics_engine registers a model's skeleton).
- **Timelines**: `TimelineAsset` and `TimelinePlayerComponent` with property, sprite-clip, camera-shot, audio, activation, nested and event tracks, each bound to `self`, a name or a tag; `TimelinePlayback` for editors. `TimelineTrackOffer`: a kind of track can say what an editor's Add track menu calls it and how to make an empty one (`TimelineTrackKinds.register(offer:)`, `offerFor`, `offered`); the engine's own kinds, but the field-bound property track, are offered.
- **Cameras**: `VirtualCameraComponent` and `CameraBrain` with blends, stages (framing, dolly, group framing, noise, impulses, confiner) and manager cameras (state-driven, blend list, mixer).
- **3-D camera rigs**: `OrbitFollowComponent` (a third-person camera circling its target, turned by `yaw`/`pitch`), `FirstPersonComponent` and `LookAtComponent`, with their stages (`OrbitFollowStage`, `FirstPersonStage`, `LookAtStage`), definitions and `cameraForward`/`cameraAnglesOf`.
- `CameraBrain.updateMode`: `CameraUpdateMode.frame` runs the brain once per rendered frame, following targets blended between their last two fixed updates (`CameraBrain.sampleTargets`, `CameraStageContext.targetPosition3`, `targetRotation` and `alpha`), so a camera follows a body smoothly at any frame rate. `fixed` is the default.
- `CameraRegistries`: the camera stages and managers are one set per `EngineContext` (`CameraRegistries.of(context)`), so a kit's extension registers its stages once for every brain of an engine. A `CameraBrain` made on its own keeps a set of its own.
- **Input**: actions from an input asset across keyboard, mouse, gamepads, touch and on-screen controls; local multiplayer; rebinding saved per player. Input keeps running while the game is paused. `LookActions`, `LookInput` and `LookSettings` (just_inputs) are re-exported: a 3-D game's camera reads its look through them.
- **Pointer lock** for mouse look (Windows, from just_inputs; `PointerLock` is re-exported): `engine.input.pointerLock` holds the mouse in the window and feeds its raw movement to the look actions, and with `engine.input.lockPointerOnClick` a mouse click on `GameWidget` takes hold. Escape lets go, whatever widget has the keyboard — `GameWidget` keeps every key, so a game's own Escape handler above it never saw one.
- **3-D sound.** An `AudioSourceComponent` with `is3d` is heard from where its entity is: full volume within `minDistance`, silent beyond `maxDistance`, faded between by `rolloff` (`AudioRolloff`), with `dopplerLevel` and `farCutoff` (muffling with distance) — saved in scenes, all of them, with `channel` and `pan` (an older scene loads with the defaults). Changing them on a playing source applies at once. `AudioSystem.playOneShot(position:, spatial:)` does the same for a one-shot. `AudioSpatial`, `AudioRolloff` and `AudioSpatialMix` are re-exported.
- **The listener** (`AudioListenerComponent`, saved in scenes): at its entity and facing the way the entity's rotation turns the world's forward, or from the output camera — `atCamera`, `faceCamera` (a third-person game puts it on the player, facing like the camera). With no listener, the camera hears. `AudioSystem` takes the `camera` (the default systems pass the engine's).
- **Tags, targets and spawners**: `TagComponent` holds a set of tags behind a world index (`findTagged`); `EntityTarget`, `Spawner`, `SpawnPoints` and the project's `TagLibrary`.
- **Rendering**: `LayerComponent` draw order, `RenderHookChain`, `RenderPass`, `ParallaxRenderSystem`, opt-in shape batching and view culling (`ViewCullingSystem`), and `RenderStatsSink`. `FrameView` carries the view's `frustum`, `cameraPosition` and `cameraForward`, and the game loop's `interpolation` (`RenderingEngine.interpolation`, set by `GameWidget` every tick).
- `ViewCullingSystem` culls by frustum when the camera is in space (`isPlanar` false): an entity's box is the union of its components' 3-D extents, placed by its full transform; out of view it stays active within `activeDistance`. A 2-D camera culls by its rectangle.
- **Ready for 3-D**: `WorldAxes`, Euler and quaternion transforms (2-D code keeps a plain `angle`), the hierarchy inside `World.update`, a camera with depth, pitch, yaw and a perspective lens, and the `SceneRenderer`, `ViewVolume` and `SpatialIndex` seams. See [ARCHITECTURE.md](ARCHITECTURE.md).
- **Previous poses for 3-D render interpolation**: `TransformComponent.captureCount` (how many times the previous pose was captured, so a renderer can tell a fresh previous pose from a stale one), `previousRotationInto` (the captured rotation whether the transform was planar or not), `capturePreviousWithRotation` (for a mover whose entity gameplay turns before the step) and `interpolatedToWorldInto` (the matrix between the previous pose and the pose). `World.updateCount` counts updates.
- **Physics and gameplay**: distance, fixed, slider and wheel joints, joined to the body an `EntityTarget` names; `SimpleMovementComponent`; `PhysicsLayers`, sixteen named layers and a collision grid in `assets/project/physics.json`; `Collider2D` shapes (box with rounded corners, circle, capsule, polygon, segment, chain, and `matchShape`, which follows what the entity draws) with their own offset, rotation and scale; `RigidBody2D` `friction`, `gravityScale`, `lockRotation`, `continuousCollision`, `canSleep`, initial velocities, ground contact, velocities read back and forces from code (`addForce`, `addImpulse`, `setVelocity`, …); `CollisionStay2DEvent` (opt-in); `Physics2DQueries` (rays, circle casts, overlaps by layer); `ColliderGeometry`. **`CharacterBody2D`**, the 2-D twin of `CharacterBody3D`: a capsule or a box gameplay moves (`moveVelocity`, `jump`) that walks slopes up to a steepest angle, climbs steps, keeps to the floor going down, rides moving platforms, stands on one-way platforms and jumps up through them, and pushes dynamic bodies — the same on native Box2D and on the web (just_physics_engine's `CharacterMover2D`). A `RigidBody2D` of `mass` 0 weighs what its collider's area says (`PhysicsSystem.autoMassPerSquareUnit`: a 100 × 100 box weighs 1000 kg, as a 1 m cube does), and a `CharacterBody2D` 70 kg.
- The package declares all six platforms and builds for the web with dart2js and dart2wasm.
- **An entity keeps its components in its own order**: `Entity.components` lists them as they were added — a scene's entity as its file lists them — rather than in the order of the archetype it shares with every entity of the same types, which was whatever came first. `Entity.reorderComponents(types)` rearranges them (an editor's inspector does) and `Entity.componentTypes` reads the order. A scene saves it. Systems find components by type, so nothing runs differently.
- **Hot reload, for an editor**: `EngineContext.refreshDefinitions()` puts every component definition in place again as the code now makes it — the engine's own, then each installed `RefreshableExtension`'s — so an editor shows a field added to a component without a restart. `ComponentDefinitionRegistry.refresh` replaces by type and leaves a project's deliberate replacement alone (`register(override: true)`, or one an `ifAbsent` registration found in place). `World.sortSystems()` puts a changed `System.priority` in effect. The engine's definitions (`CoreDefinitions`, `CoreComponentSchemas`, `CameraDefinitions`, `LevelMapDefinitions`, `TimelineDefinitions`) are getters rather than `static final`s, which a hot reload never rebuilds; read one through `context.definitions` where its identity matters. A game never calls any of this.
- **Query versions**: `World.queryVersion(types)` moves only when what that query matches may have changed (an entity with those types made, destroyed, given or rid of a component, or switched on or off), so a system rebuilds what it keeps per entity only when its own queries change. It replaces a world-wide structure counter that moved on any change at all.
- **Audio control**: `AudioSystem.playOneShot(clipPath, ...)` (flat, or placed in 3-D with `position` and `spatial`), the `AudioRequests` `play()`, `pause()`, `resume()` and `stop()` on sources and streams, and `Engine.suspendAudio()` / `resumeAudio()` / `isAudioSuspended`, which `GameWidget` calls as the app goes to the background and comes back. A timeline's audio track plays through `TimelineAudio.viaAudioSystem`.
- ECS helpers: `Entity.isActiveInHierarchy`, `Entity.getComponentByType`, `World.profiling` and `SystemManager.profiling` (on by default except in release builds), `System.profileName` (the stats key; override it for readable names in web release builds), `TransformComponent.setPreviousPose` and `previousIsPlanar`, `ComponentDefinitionRegistry.revision`, `EntitySpatialGrid(maxCellSpan:)`, `ReactiveSystem.unwatchEntity` / `unwatchAll`, and `TimeManager.unscaledTotalTime`.
- `Signal` and `Computed` from `just_signals` are re-exported: the reactive wrappers return them.
- **Dialogue (Yarn)**: `<<set $x to v>>` and `<<declare $x = v>>`; option conditions `-> text <<if cond>>`; Yarn escapes (`\#`, `\{`, `\}`, `\<`, `\>`, `\\`, `\[`, `\]`, `\/`); `{$var}` in speaker names and command arguments, and quoted command arguments kept whole; expressions with `and`, `or`, `not`, `xor`, `eq`, `is`, `neq`, `gt`, `gte`, `lt`, `lte` and `+ - * / %`, in Yarn's precedence (`TokenType.commandDeclare`, `SetStatement.isDeclaration`).
- Physics: `PhysicsSystem.scaleTolerance` and `PhysicsSystem3D.scaleTolerance`, `ColliderGeometry.inertiaOf`, `PhysicsJointBindingSystem.dartSpring`, `Physics3D.reloadModel` (a model loaded again rebuilds its mesh and hull colliders; `Graphics3D` calls it), `ColliderShapes3D.forgetModel` and its cache limits.
- 3-D and rendering: `ShapeValues` with `Primitive3D.writeShapeValues` / `writeMaterialValues` (a custom shape may override them to skip building its key each frame), `GraphicsShapes(inUse:)`, `AnimationPlayerComponent.fadingFromSpeed` / `fadingFromLoop` / `fadingFromSpeeds`, `AssetManager.unregisterLoader`, `CameraStageRegistry.revision`, `SpriteAssetLoader.callerDisposesImages`, and an opt-in `CircleParticleRenderer(batched: true)` that draws every circle in one atlas draw.
- `LocalizationManager.hasTable` and `tagOf`; locale tags keep their script (`zh_Hans`). Timelines: `TimelineContext.endsAt` and `BlockTrack.blockAt(includeEnd:)`. `Sprite.tintedAlpha` and `SpriteAtlasPage.dispose`.

### Changed

The full list is in [MIGRATION.md](MIGRATION.md#behaviour-you-may-notice). The ones most likely to matter:

- Entity ids are never reused, `Component.onDetach` always runs, switching `isActive` takes effect at once, and `CommandBuffer` applies commands in the order they were queued.
- Damping slows only a dynamic body, as in 3-D: a kinematic one (a moving platform) keeps the velocity it is given. Box2D slowed it as well.
- Bundle assets are no longer copied into the persistent cache, and `CacheManager.clearAll()` clears only the engine's own keys.
- Sprite batches honour each sprite's `filterQuality`, mirroring and stretch; `RenderingEngine.stats` count the whole frame.
- Wind and noise particle forces give the same values on every platform and advance once per frame, not once per particle.
- Shader effects are skipped with one log line where they are unsupported (the web, Skia) instead of throwing every frame.
- `GameWidget` resumes only a pause the app lifecycle caused, and wires up an engine that finishes initializing after the widget is built. Its FPS badge keeps clear of a phone's status bar and notch.
- `AudioSystem` is a `FrameSystem`: playback starts and stops on the fixed step, but where the listener and 3-D sources are is read once per rendered frame, after the camera has moved. The engine's `audio` task is a frame task, run last, so every 3-D sound is placed once a frame with what moved; it is not an update task.
- `AudioSystem` stops a source's sound when the component or its entity goes (a picked-up coin's sparkle used to play on), and when it is removed; a sound that plays to its end sets the source's `handle` back to null. Nothing plays before the audio engine has started: sources and streams wait (on the web, for the first key or tap, so they don't start a browser's audio context early, silent), and a one-shot asked for before then is dropped.
- `just_audio_engine` ^1.1.0: 3-D sound worked out the same on every platform, one platform call a frame, the master volume applied once; package assets play, and hot restart, `setLoop`, `cancelFade` and iOS work (see its changelog).
- The engine's lifecycle lines (initialized, started, a system registered, disposed, …) print only in debug builds; warnings and errors still print in every build.
- `lib/` no longer imports `dart:io` (except, conditionally, to find its storage folder) or depends on `web`.
- Children of moving bodies are drawn between their last two poses with their parent: `RenderSystem` interpolates every transform whose previous pose was captured in the last step (`captureCount`), and the hierarchy gives a child its previous pose from its parent's. It also settles again after the frame phase, so children of what moved in `frame()` follow in the same frame.
- While the engine is paused, game time (`TimeManager.totalTime`, `deltaTime`) stands still, audio still updates (a volume changed in a pause menu is heard at once), and camera effects such as `ScreenFadeEffect` and `LetterboxEffect` run on real time; the `camera` update task is gone. The per-frame phase gets the frame time clamped to `maxDeltaTime`.
- `RenderSystem` is a `FrameSystem` and takes its interpolation from the frame phase; the engine, not `GameWidget`, sets `RenderingEngine.interpolation`.
- A switched-off entity's sound pauses and plays on when it is switched back on; a volume change on a playing source or stream is heard.
- Systems of equal priority run in the order they were added, adding a system twice does nothing, and systems and plugins can be added or removed while they run (a system may remove itself).
- `Entity.components` is an unmodifiable `List`; `Archetype.getColumn` and `entityIds` are `@internal`.
- Profiling timings (`systemTimesMs`, `lastUpdateMs`) are taken only while profiling is on, so release builds skip them.
- **Physics events are per pair of entities**: a chain or compound collider sends one enter and one exit, an end and a begin in the same update cancel, and a body rebuilt because its collider, scale or sensor flag changed keeps its contacts instead of entering again. Scale changes smaller than `scaleTolerance` do not rebuild a body. 2-D joint springs are hertz and damping ratio on every backend; slider and wheel axes are in the joint entity's space. A kinematic `RigidBody2D` moved through its transform carries what stands on it. Torque and angular impulses turn a 2-D body by its rotational inertia.
- A clip fading out keeps its own speed and looping; set `speed` / `loop` for the new clip after `play()`. `CameraState.lerp` extrapolates outside 0..1, so blends with overshooting curves overshoot. `PlayerScratch` and `samplePlayer` are no longer exported.
- A sprite's tint alpha multiplies its opacity, as a shape's does (it was ignored). An entity without a `LayerComponent` is ordered by its renderable's own `layer` and `zOrder`; the built-in shapes' renderables are on layer 0. `Renderable.ySort` sorts within its layer (after the rest of its layer and zOrder, by world y), keeps its `ShaderComponent` and batches.
- Post-process passes and motion blur include the background colour and parallax.
- A timeline block that reaches the end of a `once` (or ping-pong) timeline holds there, so an activation, sprite clip or camera shot stays as the timeline left it.
- Dialogue conditions follow Yarn: `!` binds tightest, and anything unreadable (bare words, `visited()`, trailing text) is false, with a debug message. A `<<set>>` that assigns nothing is a `YarnParseException`. Localization tables for the same locale and namespace merge, and a fallback such as `en_US` also falls back to `en`.
- On the web the engine's storage keys sit beside `JustStorage.standard()`'s rather than among them, so an app's own `clear()` leaves the engine's cache and settings alone.
- A scene with a value of the wrong type fails with a `FormatException` naming the entity, component and field (the world is left untouched); a loop of parents in a scene is cut, with a debug message.
- `AssetManager` keeps assets by path and type (an atlas and its JSON are two), and `unload(path)` unloads every type at the path; a load that `unload`, `unloadAll` or `dispose` overtakes is not kept; `acquire` counts at once, so a `release` while loading counts.

### Performance

Drawing 10,000 shapes went from about 19.5 ms to 12.9 ms a frame, and 2,000 physics bodies step and sync in 1.56 ms (`test/perf/transform_hot_path_test.dart`, Windows, debug JIT). Shapes cache their paints and paths, `RenderSystem` iterates archetype columns and batches sprites with `drawRawAtlas`, queries are invalidated per archetype, and audio positions are sent only when they change. A 2-D physics world with no bodies is not stepped (`PhysicsEngine.bodyCount`). With query versions, spawning and removing unrelated entities no longer makes systems rebuild: preparing 10,000 shapes for drawing while other entities come and go went from 5.3–6.5 ms to about 0.5 ms a frame. Audio one-shots no longer change the world's structure. Release builds skip the per-system timings. The 3-D scene renderer keeps what still stands across structural changes and checks shapes, lights and the environment without allocating; each socket parent is posed once per update. Particle colours no longer allocate per particle, timeline vector channels skip the save codec, the camera brain caches each camera's pipeline, sprite systems look each sprite up once, and the physics systems find each body's shape source once per change instead of every step.

### Fixed

- **Rendering**: batched sprites drew above every layer, and mirrored ones vanished; `ParticleEmitterComponent` emitters, and `RenderableComponent` subclasses without `componentType`, were never drawn; a replaced `ShaderComponent` kept its disposed shader; sprite batches, images and shaders leaked.
- **Physics**: changing bounciness, damping, friction, `isSensor` or `shape` at run time reached only the Dart side of a native Box2D body; static bodies shook after a scene load; the collider outline ignored the body's turn; a weld joint was not remade when its anchor changed; wheel joints without native support were a slider; `RaycastSystem` missed default-sized colliders, and `ColliderDebuggerSystem`'s filters also hid raycast outlines.
- **Cameras**: a standby blend list did not start over when it went live again; emitting the same `CameraImpulse` twice doubled it; `DollyPath.closed` and `CameraRigMemory.reset()` were wrong.
- **Maps, animation and timelines**: Aseprite ping-pong tags showed a frame twice; hidden Tiled image layers imported as visible, without their parallax and tint; `TileChunkData` took any number of cells; hidden cells could change without a redraw; `AnimatorComponent.getFloat`, `getInt` and `getBool` misread parameter types; `TrackBinding.fromJson` and `KeyCurve.numberAt` mishandled some values.
- **Audio**: 3-D sources were panned as well; a stream's fade-in did not start from silence; `.flac` and upper-case extensions went undetected; every sound effect played on the sfx channel, whatever its component's `channel` said.
- **Dialogue**: `autoAdvance` never ran; `YarnParser` silently cut nodes short on malformed `<<if>>` blocks (now a `YarnParseException`); `DialogueBoxWidget` leaked its old runner's listener.
- **Game loop**: two `GameWidget`s showing one engine ran the game about three times too fast (each frame is now counted once, by the vsync frame's timestamp); music and sounds kept playing when the app went to the background; with the dev terminal open, a key held as it opened stayed down; a service added to a running engine and disposed before its `start()` finished was never stopped.
- **ECS**: adding or removing a system or plugin while they ran threw; equal-priority systems lost their order past 32 systems; listing an entity's components while it changed showed another entity's; a parent cycle hung the hierarchy (it is now refused with an `ArgumentError`); `TransformComponent(scale:)` kept the caller's vector; one failing command dropped the rest of a `CommandBuffer` batch; `ReactiveSystem` leaked listeners; `EntitySpatialGrid` broke on NaN or huge bounds; `destroyAllEntities` left parent links bound.
- **Saving and loading**: `CacheManager`'s `maxBinaryEntries` never evicted anything; two `initialize()` calls opened the stores twice, and a `dispose()` during `initialize()` left the database open; `ComponentDefinitionRegistry` kept a stale by-type entry after an override or `unregister`, let an alias shadow a real type, and stopped refreshing the built-ins after they were registered twice; a gradient with one colour or mismatched stops threw on every paint; an enum overriding `toString` saved its display text; `SceneLoader.loadManifest` broke on a non-string entry; `AssetScope.dispose()` during an acquire leaked a count.
- **Effects**: cancelling from an effect's own callback dropped or repeated others, and `cancelAll()` there threw; a looping effect fast-forwarded lost its phase; a fade along an overshooting easing ended off target; an absolute `PathEffect` never reached its waypoints; `ScaleEffect` flipped mirrored entities; `PredictionEffectRuntime` duplicated effects on a second rollback.
- **2-D physics**: on native Box2D every chain segment fired its own enter and exit and left `isGrounded` stuck; a body rebuilt by a scale or collider change entered again with no exit (3-D too), and joints on it were remade every step; waking a body never reached Box2D, so a sleeping body ignored a gravity change; a wheel joint orbited the chassis; a static sensor reported static colliders; view culling did not freeze native bodies; angles wrapped at ±π and flicked when drawn; a capsule was too short under non-uniform scale; a ray along a box's edge hit its far side; `ColliderDebuggerSystem` drew only circles and boxes.
- **3-D**: textured shapes flashed white after standing unchanged for a few seconds; a one-shot clip fading out jumped back to its start; sockets were drawn a step ahead of the hand holding them, and each one posed its parent again; a socket parent's posed model leaked once it was destroyed; `Graphics3D.stop()` left the renderer and model loader behind; a 3-D body refused for a bad layer was never made after the layer was fixed; mesh and hull collider caches grew without limit and kept old triangles after a model reload.
- **Cameras and particles**: group framing let outlying members leave the shot; a camera a trigger switched on stayed on after the trigger went; `GameCameraControls` panned the wrong way on a rolled camera; a capped emitter saved up emission, short bursts emitted nothing on a long first frame, and `isComplete` ignored live sub-emitters; `SpriteLoadSystem` never disposed the images it owned.
- **Rendering**: a rolled 2-D camera culled things at the screen's corners (`getVisibleBounds` is now the box around the turned view); a tinted sprite or parallax layer below full opacity was faded twice and changed opacity when it left a sprite batch; sprites from different atlases on one layer swapped order when batched; a per-entity shader clipped turned sprites' corners; a trimmed atlas frame's anchor was mirrored, and a frame without `sourceSize` was invisible; unloading an atlas page's image asset left the cached atlas drawing a disposed image.
- **Level maps**: orthogonal layers with tiles bigger than the grid drew out of order across tilesets, mirrors and chunks; Tiled import dropped the rotation of tile collision objects and could not read tilesets saved before Tiled 0.15; `MapGeometry.boundsOf` was half a tile short on staggered and hexagonal maps.
- **Dialogue and localization**: `<<set $rich = $gold >= 100>>` read one variable named `gold >= 100`, and `"a" == "b"` was stored as a string; restarting a runner broke `stop()`, a command from an old session drove the new one, a call from a signal listener was lost, and a throwing command left the runner running; `selectChoice` with an invalid index used up the choices; the typewriter split emoji; `DialogueManager.startDialogue` with a missing node let the error escape; `DialogueLocalizer` never switched the locale it loaded; tables for one locale replaced each other; plurals mishandled fractional counts and infinity; script codes (`zh_Hans` / `zh_Hant`) overwrote each other.
- **Timelines**: an event handler destroying a later player crashed the update; ping-pong landed wrong on long steps, kept a stale direction after `stop` / `seek`, and played its start cue only once; a looping nested block fired an extra lap, and one crossed in a single step never applied its end; `forwards()` restarted from 0; a sprite clip spanning a loop's wrap froze after one lap; a new `timelinePath` then `play()` played the old timeline; a range moved behind the playhead fired events backwards; a colour field keyed without `"color": true` threw; zero-length timelines did nothing; a signal emitted from a listener was lost; instant (audio) blocks counted their drawn length.
- **Audio**: starting a sound cleared its `playOnAdd`, so a scene saved from an editor after the system had run once (the third-person template's level was) never started its loops and music again; sounds still loading survived `stopAll()`, removing the system and `dispose()`.
- **Other**: asset bytes ignored their offset; paths with spaces, `@`, `+` or non-ASCII characters could not be cached; the dev terminal leaked the backquote and could not type capitals; two component classes with the same name could not share a world; `CheckpointSystem` drew its radii in the wrong space and crashed without a transform; `RayRenderable(lifetime: 0)` expired at once; `EntitySignal` started active and lost components on `sync()`; `ShakeEffect` drifted; dartdoc crashed on `engine.dart`.

### Deprecated

Removed in 3.0: `Engine.getSystem`, the legacy `RenderingEngine` renderable path, `Engine.parallax` and `ParallaxSystem`, `onRenderBackground` / `onRenderOverlay`, `TagComponent.tag`, `HierarchySystem`, `Entity.generation`, and the unused `I*` lifecycle interfaces ([full list](MIGRATION.md#deprecated-apis)).

### Known limitations

Joint anchors are not passed to the physics engine, the pure-Dart backend still pushes jointed bodies apart with `collideConnected` off, native queries skip bodies with collision mask 0, a stream's channel volume does not apply, and a playing sound's pitch, pan, speed and loop cannot change; they wait on `just_physics_engine` and `just_audio_engine` ([details](MIGRATION.md#known-limitations-in-200)).

## [1.6.1] - 2026-08-02

### Added

- Unified shape styling: `ShapePaintStyle` and `ShapeGradient` (linear, radial, sweep) now back `fillStyle`/`strokeStyle` on every shape component (`CircleComponent`, `RectangleComponent`, `PolygonComponent`, `LineComponent`, `CapsuleComponent`), replacing the old flat `color` property.
- `Entity.removeComponentByType(Type type)` and `Entity.hasComponentByType(Type type)` for runtime-type component access when the static type isn't known at the call site.

### Changed

- `ColliderDebuggerSystem` relocated from `core/debugger/` to `core/` and exported via `core.dart` and `systems.dart`.
- `just_physics_engine` dependency upgraded to `^1.2.2`.

## [1.6.0] - 2026-05-30

### Added

- In-game developer terminal for commands and debugging, including GameWidget integration.
- Achievement subsystem with tracking, events, and provider abstraction.
- Authentication and leaderboard subsystems with platform provider support.
- Currency and inventory subsystems with event-driven updates.
- Ads subsystem with banner, interstitial, and rewarded support.
- Subtitle subsystem with cue controller and overlay widget.
- Checkpoint collision/respawn flow and checkpoint component support.
- Physics improvements: sensor support, collision event enhancements, and `ColliderDebuggerSystem`.

### Changed

- Transform pipeline refactored for 3D-compatible data flow.
- Checkpoint respawn positions migrated to `Vector3`.
- Physics integration migrated to `just_physics_engine` and upgraded.
- Math utilities migrated to `just_dart`; obsolete math files removed.
- Achievement persistence moved from storage-backed flow to database-backed flow.
- GameWidget debugger integration simplified and legacy debugger path removed.
- Dependency metadata updated; `pubspec_overrides.yaml` added to `.gitignore`.

---

## [1.5.3] - 2026-04-19

### Added

- **Debugger Tooling** — Added the new `just_debugger` integration to improve engine inspection, diagnostics, and runtime debugging workflows.

### Changed

- **Memory Management** — Moved shared memory-related code out of `just_game_engine` into the dedicated `just_memory` package for clearer package boundaries and better reuse across the ecosystem.

---

## [1.5.2] - 2026-04-08

### Added

- **Shape Components** — Five self-rendering ECS components that extend `RenderableComponent` and draw themselves each frame with no additional render system required.
  - `CircleComponent` — Circle centered on the entity's `TransformComponent` position. Properties: `radius`, `color`, `filled`, `strokeWidth`.
  - `RectangleComponent` — Axis-aligned rectangle with optional rounded corners. Properties: `width`, `height`, `color`, `filled`, `strokeWidth`, `cornerRadius`. Convenience `size` getter returns a `Size` object.
  - `PolygonComponent` — Convex or concave polygon defined by a list of local-space `vertices`. Properties: `vertices`, `color`, `filled`, `strokeWidth`.
  - `LineComponent` — Straight line segment in local space. Properties: `start`, `end`, `color`, `strokeWidth`, `roundCaps`. Convenience `length` getter for segment distance.
  - `CapsuleComponent` — Rectangle with two semicircular end caps (horizontal or vertical depending on aspect ratio). Properties: `width`, `height`, `color`, `filled`, `strokeWidth`. Computed `capRadius` getter (half of the shorter side).

---

## [1.5.1] - 2026-04-06

### Fixed

- Update Archetype signature to use string keys and improve entity validation in addEntity method

---

## [1.5.0] - 2026-04-04

### Added

- **Post-Processing** — `PostProcessPass` (full-screen `FragmentShader`, ordered chaining), `ShaderComponent` (per-entity or post-process mode), `PostProcessSystem` (priority 35).
- **Sprite Atlas** — `SpriteAtlas`, `AtlasParser` (auto-detects TexturePacker JSON Array/Hash/multi-page and Aseprite), `AtlasAnimationClip`, `AtlasSpriteAnimation`.
- **Deterministic Effects** — 11 tick-based effects (`MoveEffect`, `ScaleEffect`, `RotateEffect`, `FadeEffect`, `ColorTintEffect`, `SequenceEffect`, `ParallelEffect`, `DelayEffect`, `RepeatEffect`, `ShakeEffect`, `PathEffect`), `EffectSystemECS` (priority 65), JSON + binary serialization, `EffectSnapshot` for rollback.
- **Localization** — `LocalizationManager` with namespace support, fallback chain (`fr_CA → fr → en`), `Signal<Locale>`, ICU-lite `{plural}`/`{select}` via `StringInterpolator`, and Flutter widgets (`LocalizationScope`, `LocalizedText`, `LocaleSelector`).
- **Narrative / Dialogue** — Full Yarn Spinner 2.x parser and runtime (`DialogueManager`, `YarnParser`, `DialogueRunner`), `DialogueLocalizer`, ECS components (`DialogueComponent`, `TriggerComponent`, `DialogueSystem`), and UI widgets (`DialogueBoxWidget`, `DialogueChoicesWidget`).
- **New ECS components**: `ShaderComponent`, `EffectComponent`, `ParallaxComponent`, `ParticleEmitterComponent`, `CameraFollowComponent`.
- **New ECS systems**: `PostProcessSystem`, `EffectSystemECS`, `ParticleSystemECS`, `CameraFollowSystem`.

### Changed

- **Audio** — Replaced `flutter_soloud` with `just_audio_engine` (`^1.0.0`); graceful degradation in headless/test environments; no user-facing API changes.
- **SystemManager** — Promoted to authoritative frame scheduler (`registerUpdateTask`, `runUpdateCycle`, `schedulerStats`); `Engine.systemManager` getter exposed publicly.
- **Performance** — Hot-path allocation audit: persistent `Stopwatch` fields, pre-allocated collision pair buffer, sub-frame render interpolation, `LinkedHashSet` render layers, archetype integer signatures, Zobrist query-cache keys, accumulator cap `5× → 3×`, `SpatialGrid` hash entropy fix.
- **Observability** — Per-subsystem timing stats in `GameWidget` debug HUD; Quadtree caching in `RenderingEngine`; incremental `SpatialGrid` body tracking.
- **Cache** — `CacheManager` falls back to in-memory stores on plugin failure (`isUsingMemoryFallback`).
- **CI** — GitHub Actions (`flutter analyze --fatal-infos` + `flutter test`); `@experimental` on all networking stubs; `analysis_options.yaml` hardened; `meta: ^1.9.0` dependency added.

---


## [1.4.2] - 2026-04-02

- Engine performance improved
- Engine stats updated

## [1.4.1] - 2026-03-25

### Changed - Documentation & Examples

- **README**: Overhauled and streamlined — removed outdated sections and links to provide a cleaner, more up-to-date overview.
- **Example**: Consolidated the example suite into a single `example.dart` file covering the core engine setup. Removed the separate `core_system_example.dart`, `ecs_example.dart`, and `input_test_example.dart` files to reduce onboarding friction.

---

## [1.4.0] - 2026-03-21

### Changed - Architecture & Performance

- Major change in architecture and imporved performance

### Added - Parallax Background System

New first-class subsystem for multi-layer scrolling backgrounds, accessible via `Engine.parallax`.

- **ParallaxLayer** — Individual layer with depth-based scrolling.
  - `scrollFactorX` / `scrollFactorY` control camera-relative scroll speed (0.0 = fixed, 1.0 = camera speed).
  - `velocityX` / `velocityY` for continuous auto-scroll independent of camera movement.
  - `scale`, `repeat`, `offset`, `opacity`, and `tint` for full visual control.
  - `ParallaxLayer.uniform()` convenience constructor for equal X/Y scroll factors.
- **ParallaxBackground** — Ordered container of `ParallaxLayer` instances (index 0 = furthest back).
  - `addLayer()`, `insertLayer()`, `removeLayer()` for runtime layer management.
  - `update(deltaTime)` advances auto-scroll offsets; `render(canvas, size)` paints all layers back-to-front.
  - Per-layer camera-driven + auto-scroll + static offset compositing.
  - Tiling logic handles images smaller than the viewport with seamless horizontal/vertical wrapping.
- **ParallaxSystem** — Engine subsystem managing all registered backgrounds.
  - `addBackground()` / `removeBackground()` / `clear()` lifecycle methods.
  - `update(deltaTime, cameraPosition)` feeds camera position into every background each frame.
  - `render(canvas, size)` called via `RenderingEngine.onRenderBackground` in screen space (before camera transform).

### Added - Virtual Joystick Widget

Reusable Flutter widget for touch-based directional input on mobile platforms.

- **VirtualJoystick** — `StatefulWidget` that handles pointer events and emits normalised direction vectors.
  - `JoystickVariant.fixed` — always-visible joystick anchored at a set position.
  - `JoystickVariant.floating` — appears at the touch-down point and follows the finger.
  - `JoystickAxis` constraint: `both`, `horizontal`, or `vertical` axis locking.
  - Configurable `radius`, `showWhenInactive`, `inactiveOpacity`, and `anchorAlignment`.
  - `onDirectionChanged` callback delivers a normalised `Offset` each frame for ECS integration.
  - Rendered via `CustomPaint` with base ring and thumb knob visuals.
- **JoystickInputComponent** — ECS component storing joystick state on an entity.
  - `direction`, `basePosition`, `thumbPosition` for runtime access.
  - `layout` (fixed / floating) and `axis` constraint properties.
  - `hasInput`, `reset()`, `setDirectionFromDelta()` helpers.
  - Automatically processed by `InputSystem._updateJoystickComponents()` alongside keyboard input.

---

## [1.3.0] - 2026-03-15

### Added - Tiled Map ECS Integration

`just_tiled` is now a first-class runtime dependency of `just_game_engine`. The engine ships four new types that bridge parsed Tiled map data directly into the ECS world, covering rendering, collision, and object-to-entity spawning.

- **TileMapLayerComponent** — ECS component that attaches a `TileLayer` and its pre-compiled `TileMapRenderer` to a single entity. One entity per tile layer keeps the world free of per-tile entity bloat.
- **TiledObjectComponent** — ECS component for Tiled map objects. Exposes `properties`, `type`, and `name` directly on the entity for easy custom-logic dispatch.
- **TiledMapFactory** — Static factory that translates an entire `TiledMap` into ECS entities in one call.
  - Tile layers → one entity with `TileMapLayerComponent` + `TransformComponent` (respects layer offset).
  - Object groups → one entity per visible `TiledObject` with `TransformComponent` + `TiledObjectComponent`.
  - `GroupLayer` children are traversed recursively.
  - `ComponentMapper` callback maps any Tiled class name + custom properties to additional engine components (e.g. `HealthComponent`, `EnemyAIComponent`).
- **TileMapRenderSystem** — ECS `System` that GPU-batches all `TileMapLayerComponent` entities. Uses `Camera.getVisibleBounds()` for viewport frustum culling so only in-view tiles are processed. Runs at priority `100` so tile layers are painted before game entities.
- **TiledCollisionSystem** — ECS `System` that converts TMX object-group collision shapes into static `PhysicsBody` instances and registers them with `PhysicsEngine`.
  - Supports **rectangle**, **polygon**, and **ellipse** shapes (mapped to `RectangleShape`, `PolygonShape`, `CircleShape`).
  - Per-object `restitution` and `friction` read from Tiled custom properties.
  - Optional `SpatialHashGrid<PhysicsBody>` for O(1) proximity queries.
  - `loadCollisions(TiledMap)` / `loadObjectGroupCollisions(ObjectGroup)` / `clearCollisions()` lifecycle methods.
---

## [1.2.1] - 2026-03-15

### Changed
- **GameWidget**: `_GamePainter.paint()` now also calls `engine.world.render(canvas, size)`, so ECS entities registered with `RenderSystem` are drawn automatically alongside the classic rendering pipeline.

### Added - Audio ECS Integration

Audio playback is now fully ECS-driven alongside the existing `AudioEngine` API.

- **AudioSourceComponent** — Persistent audio source on an entity. Properties: `clipPath`, `volume`, `pan`, `loop`, `playOnAdd`, `channel` (`AudioChannel`), `is3d`. When `is3d` is `true`, stereo pan is ignored and 3D position is derived from `TransformComponent`.
- **AudioPlayComponent** — Fire-and-forget one-shot playback trigger. `AudioSystem` plays the sound and removes the component automatically.
- **AudioListenerComponent** — Marks an entity (typically the camera or player) as the SoLoud 3D listener. `AudioSystem` forwards the entity's `TransformComponent` position to the native listener each frame.
- **AudioSystem** — ECS `System` that drives all audio ECS components. Runs at priority `-10` (after transforms) to ensure 3D positions are up to date before the listener and source positions are sent to SoLoud.

### Fixed
- **Example**: Simplified `example/example.dart` to a minimal renderer setup for easier onboarding.

---

## [1.2.0] - 2026-03-12

### Added - Ray Casting & Ray Tracing
- **Ray** — 2-D ray descriptor with origin, normalised direction, and maximum travel distance.
  - `Ray.fromPoints()` convenience constructor for aiming between two world positions.
  - `at(t)` helper returns the world-space point at a given distance along the ray.
- **RaycastColliderComponent** — ECS component that marks an entity as hittable by rays.
  - Configurable `radius`, semantic `tag` for filtering, `isBlocker` flag, and `isReflective` / `reflectivity` properties for multi-bounce tracing.
- **RaycastHit** — intersection result containing the hit entity, world-space point, distance, and outward surface normal.
- **RaycastSystem** — query-only ECS system for ray-vs-collider tests.
  - `castRay()` returns the closest hit; `castRayAll()` returns all hits sorted nearest-first.
  - `hasLineOfSight()` performs a line-of-sight / LOS check between two points.
- **RayTracer** — multi-bounce ray tracing against reflective surfaces.
  - Configurable `maxBounces` and `minReflectivity` thresholds.
  - `trace()` returns a `RayTrace` containing every `RayTraceSegment` (path segment + optional hit).

### Added - Ray Renderable
- **RayRenderable** — a `Renderable` that draws a glowing beam / laser / bullet trail in world space.
  - Two-layer visual: a sharp core line and a wider blurred glow halo for a neon/laser effect.
  - Automatic fade-out over a configurable `lifetime`; `isExpired` flag for easy cleanup.
  - Customisable `color`, `width`, `glowWidthMultiplier`, and `glowBlurSigma`.

---

## [1.1.2] - 2026-03-08

### Changed
- **Audio Engine**: Replaced `audioplayers` with `flutter_soloud` (^3.5.0) as the audio backend.
  - SoLoud is a low-latency, C++-based audio engine purpose-built for games.
  - Removed the fixed-size `AudioPlayer` pool; SoLoud handles unlimited concurrent voices natively.
  - `AudioClip` now holds an `AudioSource` + `SoundHandle` instead of an `AudioPlayer`.
  - `AudioEngine.initialize()` is now `async` and calls `SoLoud.instance.init()`; the engine properly `await`s it during startup so audio is guaranteed ready before any play calls.
  - Added `isInitialized` guard in `initialize()` to be safe against duplicate init (e.g. hot restart).
  - `playSfx()` and `playMusic()` return early with a debug message if called before initialization.
  - Music fade-in/fade-out now delegates to `SoLoud.instance.fadeVolume()` instead of a manual step loop.
  - `dispose()` calls `SoLoud.instance.deinit()` to fully shut down the engine.

## [1.1.1] - 2026-03-07

- Homepage URL updated in `pubspec.yaml`.
- Added reactive ECS components and signals for improved state management.

## [1.1.0] - 2026-03-01

### Added - Advanced Physics Engine

- **Rigid Body Dynamics**
  - Upgraded physics integration to Semi-Implicit Euler.
  - Added new dynamic properties to `PhysicsBody`: `angularVelocity`, `angle`, `torque`, `inertia`, and `friction`.
  - Added support for static bodies by setting `mass: 0.0`.
- **Advanced Collision Shapes**
  - Implemented `CollisionShape` hierarchy replacing simple `radius`.
  - Added `CircleShape`, `RectangleShape`, and `PolygonShape`.
  - Implemented Separating Axis Theorem (SAT) for true polygon-polygon and circle-polygon collision detection.
- **Impulse-Based Resolution**
  - Added rigorous impulse delivery resolving velocity along collision normals using inverse mass scaling.
  - Included Coulomb friction handling for sliding objects.
- **Broad-Phase Optimization**
  - Implemented $O(n)$ `SpatialGrid` broad-phase for massive performance gains in dense scenes.
  - Added Object Sleeping: resting bodies are excluded from integration until awoken, saving CPU cycles.
- **Physics Caching**
  - Integrated `CacheManager` utilizing `just_storage` and `just_database`.
  - Added `cachePolygonShape` and `getCachedPolygonShape` routines to persist heavy math computations across sessions.

---

## [1.0.1] - 2026-02-24
### Fixed

- **Audio Engine**
  - Fixed `AudioClip.play()` crash caused by `AudioCache` double-prefixing the asset path (`assets/assets/...`) when the caller passed a path already starting with `assets/`. The path is now stripped of the `assets/` prefix before being passed to `AssetSource`.

### Changed

- **License**
  - Changed project license from Apache 2.0 to BSD-3-Clause.

---

## [1.0.0] - 2026-02-16

### Added - Core Systems

- **Engine Core**
  - Main `Engine` singleton class for orchestrating all subsystems
  - `GameLoop` with fixed timestep (60 UPS) and variable rendering
  - `TimeManager` for delta time tracking and FPS calculation
  - `SystemManager` for coordinating subsystems
  - Full lifecycle management (initialize, start, pause, resume, stop, dispose)
  - Engine state machine with 6 states (uninitialized, initializing, initialized, running, paused, error)

- **Rendering Engine**
  - Canvas-based 2D rendering system
  - `Camera` class with pan, zoom, rotation, and lookAt functionality
  - Layer-based rendering with Z-order sorting
  - Built-in renderables: `CircleRenderable`, `RectangleRenderable`, `LineRenderable`, `TextRenderable`, `CustomRenderable`
  - `GameWidget` for Flutter integration with CustomPainter
  - Debug mode with bounding boxes and coordinate grids
  - Background color support
  - FPS display overlay

### Added - Advanced Features

- **Sprite System**
  - `Sprite` class for image rendering with source rectangles
  - `SpriteSheet` for managing sprite atlases
  - `NineSliceSprite` for scalable UI elements
  - Horizontal and vertical flipping support
  - Static `fromAsset` method for easy loading

- **Animation System**
  - Base `Animation` class with play, pause, stop, reset controls
  - `SpriteAnimation` for frame-based sprite animations:
    - Automatic frame cycling based on normalized time
    - `fromSpriteSheet()` factory method for easy creation
    - Support for variable frame counts (any number of frames)
    - Configurable frame dimensions (width/height)
    - Manual frame list support via `List<Rect>` frames parameter
  - Generic `TweenAnimation<T>` with custom lerp functions
  - Property tweens: `PositionTween`, `RotationTween`, `ScaleTween`, `OpacityTween`, `ColorTween`
  - `AnimationSequence` for chaining animations
  - `AnimationGroup` for parallel animations
  - `Easings` class with 15+ easing functions:
    - Linear
    - Quadratic (in, out, in-out)
    - Cubic (in, out, in-out)
    - Quartic (in, out, in-out)
    - Sine (in, out, in-out)
    - Exponential (in, out, in-out)
    - Elastic (in, out, in-out)
    - Bounce (in, out, in-out)
  - Loop and ping-pong support
  - Speed control (0.1x - 5.0x) with dynamic adjustment
  - Normalized time (0.0 - 1.0) for progress tracking
  - Completion callbacks

- **Particle Effects**
  - `ParticleEmitter` with configurable emission rate and lifetime
  - Individual `Particle` class with full lifecycle
  - Size gradient support (start → end)
  - Color gradient support with smooth transitions
  - Gravity and velocity simulation
  - Multiple particle shapes: circle, square, star
  - Built-in effect presets:
    - Explosion (burst of orange/yellow particles)
    - Fire (rising orange flames with flicker)
    - Smoke (upward gray particles with fade)
    - Sparkle (twinkling yellow/white particles)
    - Rain (falling blue droplets)
    - Snow (gentle falling white flakes)
  - Custom particle system creation

- **Physics Engine**
  - `PhysicsBody` rigid body class
  - Circular collision detection
  - Elastic collision resolution with restitution
  - Mass, velocity, drag, and radius properties
  - Gravity simulation (configurable)
  - Debug rendering with:
    - Body visualization (green = active, red = inactive)
    - Velocity vector arrows
    - Collision boundary circles
  - Broad-phase and narrow-phase collision optimization

- **Scene Graph**
  - Hierarchical `SceneNode` structure
  - Parent-child transform relationships
  - Local and world-space coordinate systems
  - Transform propagation (position, rotation, scale)
  - `SceneEditor` for scene management
  - `Scene` container class
  - Node finding by name (recursive search)
  - Active/inactive state per node
  - Depth calculation
  - Custom update callbacks per node
  - Renderable attachment to nodes

- **Entity-Component System (ECS)**
  - `World` class for managing all entities and systems
  - `Entity` class representing game objects with components
  - `Component` base class for pure data containers
  - `System` base class for processing logic
  - Entity lifecycle management (create, destroy, query)
  - Component filtering and queries
  - System priority and ordering
  - Entity statistics and debugging
  - 13 built-in components:
    - `TransformComponent` - Position, rotation, scale with transform methods
    - `VelocityComponent` - Velocity vector with max speed and angle utilities
    - `RenderableComponent` - Links to renderable objects with sync options
    - `PhysicsBodyComponent` - Radius, mass, restitution, drag, collision layers
    - `TagComponent` - Simple string tagging for entity identification
    - `LifetimeComponent` - Time-based entity expiration
    - `HealthComponent` - HP system with damage, heal, and invulnerability
    - `ParentComponent` - Parent reference with local offset and rotation
    - `ChildrenComponent` - Child entity list management
    - `InputComponent` - Movement direction and button state
    - `AnimationStateComponent` - Current animation state tracking
    - `SpriteComponent` - Sprite path, frame, flip flags, and tint color
  - 9 built-in systems:
    - `MovementSystem` - Applies velocity to transform with max speed clamping
    - `RenderSystem` - Renders entities with transform sync
    - `LifetimeSystem` - Updates lifetime and destroys expired entities
    - `PhysicsSystem` - Full physics with gravity, drag, collision detection/resolution, layer-based filtering
    - `HierarchySystem` - Propagates parent transforms to children
    - `HealthSystem` - Health regeneration and death handling
    - `AnimationSystemECS` - Animation time updates
    - `BoundarySystem` - World boundary enforcement with 4 behaviors (clamp, bounce, wrap, destroy)
  - Data-oriented architecture for performance
  - Composition over inheritance design
  - Query system for finding entities by components
  - Example implementation in `ecs_example.dart`

### Added - Supporting Systems

- **Input Management**
  - `InputManager` main coordinator with subsystem access
  - `KeyboardInput` with key press/hold/release detection
  - Key state tracking with previous frame comparison
  - Horizontal and vertical axis support for WASD/Arrow keys
  - `MouseInput` with position, button, and scroll tracking
  - Mouse delta and scroll delta calculation
  - Support for left, right, and middle mouse buttons
  - Screen-to-world coordinate conversion support
  - `TouchInput` with multi-touch support
  - Touch point tracking with pressure and size
  - Touch start/end events per frame
  - `ControllerInput` with gamepad support
  - Analog stick support (left/right sticks)
  - Trigger and button detection
  - Configurable dead zone for analog inputs
  - Event callback system for custom input handling
  - Automatic integration with `GameWidget` via Focus and Listener
  - Input state updates each frame in game loop

- **Audio Engine**
  - `AudioEngine` main coordinator with multi-channel mixing
  - `AudioClip` wrapper for individual audio playback control
  - `SoundEffectManager` for managing sound effects
  - `MusicManager` for background music with fade effects
  - `AudioMixer` for volume and mute control
  - 5 audio channels: Master, Music, SFX, Voice, Ambient
  - Per-channel volume control with independent mute/unmute
  - Unlimited concurrent SFX via SoLoud's native voice management
  - Automatic cleanup of finished audio clips
  - Music fade in/out support (configurable duration)
  - Looping support for music and ambient sounds
  - Built on `audioplayers` package (^6.1.0) *(replaced by flutter_soloud in v1.1.2)*
  - Supports MP3, WAV, OGG, FLAC audio formats
  - State tracking (stopped, playing, paused)
  - Integration methods: `playSfx()`, `playMusic()`, `stopMusic()`, `setMasterVolume()`

- **Asset Management**
  - `AssetManager` for loading and caching game resources
  - `Asset` base class with load/unload lifecycle
  - `ImageAsset` for loading PNG/JPG images with `ui.Image`
  - `AudioAsset` for loading audio files as binary data
  - `TextAsset` for loading plain text files
  - `JsonAsset` for loading and parsing JSON configuration
  - `BinaryAsset` for loading raw binary data
  - `AssetBundle` for grouping related assets
  - Automatic caching system to prevent duplicate loads
  - Memory usage tracking per asset (in bytes)
  - Cache statistics: total assets, images, audio, text, JSON, binary counts
  - Total memory usage calculation
  - Async loading with futures
  - Integration with Flutter's rootBundle
  - Support for atlas/sprite sheet metadata
  - Unload functionality to free memory
  - Type-safe asset retrieval methods

- **Networking** (Placeholder)
  - Structure for multiplayer support
  - Client-server communication

### Examples

- `core_system_example.dart` - Complete engine setup example
- `ecs_example.dart` - Entity-Component System with physics and collisions
- `input_test_example.dart` - Comprehensive input system demo with keyboard, mouse, and touch

### Technical Details

- Minimum Flutter SDK: 3.11.0
- Minimum Dart SDK: 3.0.0
- External dependencies:
  - `audioplayers: ^6.1.0` (for Audio Engine) *(replaced by flutter_soloud in v1.1.2)*
- Singleton pattern for Engine
- Observer pattern for lifecycle events
- Component-based architecture
- Fixed timestep game loop (60 UPS)
- Variable rendering for smooth visuals
- Efficient collision detection with spatial awareness

### Performance

- Maintains 60 FPS with 20+ objects
- Handles 100+ particles simultaneously
- Real-time collision detection for multiple bodies
- Optimized rendering pipeline
- Low memory footprint

---

## Version History

- **1.5.3** - Moved memory code to `just_memory` and added the new debugger tool
- **1.5.2** - Shape Components: `CircleComponent`, `RectangleComponent`, `PolygonComponent`, `LineComponent`, `CapsuleComponent` (all self-rendering, extend `RenderableComponent`)
- **1.5.1** - Bug fixes: Update Archetype signature to use string keys and improve entity validation in addEntity method
- **1.5.0** - Post-Processing shaders, Sprite Atlas, Deterministic Effects, Localization, Narrative/Dialogue, audio backend swap (`just_audio_engine`), SystemManager frame scheduler, hot-path allocation audit, runtime observability, CI/CD
- **1.4.2** - Performance improvements
- **1.4.1** - Documentation overhaul and example consolidation
- **1.4.0** - Parallax Background System, Virtual Joystick Widget, and showcase app improvements
- **1.3.0** - Tiled Map ECS integration (TiledMapFactory, TileMapRenderSystem, TiledCollisionSystem) and Audio ECS integration (AudioSourceComponent, AudioSystem)
- **1.2.1** - GameWidget ECS rendering integration and example cleanup
- **1.2.0** - Ray Casting, Ray Tracing, and Ray Renderable systems
- **1.1.0** - Complete Physics Engine overhaul (Rigid Body Dynamics, SAT Shapes, Spatial Grid, and Impulse Resolution)
- **1.0.1** - Bug fix for audio asset path and license update to BSD-3-Clause
- **1.0.0** - Full production release with all core features

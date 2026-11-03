# 3D graphics

_Graphics_ · Opt in to 3D drawing on Flutter GPU: glTF models, lights, sky, skeletal animation and eleven built-in shapes, in metres with +Y down.

3D is opt-in. Give the engine a `Graphics3D` and it saves, loads and draws 3D components with [just_graphics_engine](https://pub.dev/packages/just_graphics_engine), a renderer built on Flutter GPU: glTF models, physically based materials, lights and shadows, a sky, skeletal animation, and eleven shapes you can build levels from without a model file.

A game without a `Graphics3D` is 2D only: it makes no GPU device and loads no shaders, and a scene holding 3D components fails to load with an `UnknownComponentTypeException` that says how to turn 3D on. 3D physics is a separate switch; see [3D physics](/docs/physics-3d).

## Turning 3D on

Import `package:just_game_engine/graphics_3d.dart` and pass a `Graphics3D` to `EngineConfig`. As the engine is made it registers the 3D components. As it initializes, it makes the GPU device and the renderer, loads models through `engine.assets`, adds a `GraphicsSceneRenderer` to the frame and an `AnimationSystem3D` to the world. `engine.graphics3D` returns the one you gave, or null in a 2D game.

```dart lib/main.dart
import 'package:flutter/material.dart';
import 'package:just_game_engine/graphics_3d.dart';
import 'package:just_game_engine/just_game_engine.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final engine = Engine(
    config: EngineConfig(
      defaultSystems: DefaultSystems.all,
      graphics3D: Graphics3D(
        onUnsupported: (reason) => debugPrint('No 3D here: $reason'),
      ),
    ),
  );
  await engine.initialize();

  // A perspective camera, in metres: 3 m up (+Y is down), 8 m back,
  // tilted down a little.
  engine.cameraSystem.mainCamera
    ..lens = const CameraLens.perspective(near: 0.1, far: 500)
    ..position = const Offset(0, -3)
    ..z = -8
    ..pitch = -0.36;

  final world = engine.world;
  world.createEntityWithComponents([
    TransformComponent(),
    Plane3DComponent(width: 20, depth: 20, color: const Color(0xFF7A8B6F)),
  ], name: 'Ground');
  world.createEntityWithComponents([
    TransformComponent(position: Vector3(-1.5, -0.5, 0)),
    Cube3DComponent(color: Colors.orange, roughness: 0.6),
  ], name: 'Crate');
  world.createEntityWithComponents([
    TransformComponent(position: Vector3(1.5, -0.5, 0)),
    Sphere3DComponent(color: const Color(0xFFFFD54F), metallic: 1, roughness: 0.25),
  ], name: 'GoldBall');

  // The sun shines along its entity's +Z axis, here turned to point down.
  world.createEntityWithComponents([
    TransformComponent(euler: Vector3(-0.9, 0.4, 0)),
    Light3DComponent(kind: LightKind.directional, intensity: 3),
  ], name: 'Sun');
  world.createEntityWithComponents([
    TransformComponent(),
    EnvironmentComponent(fog: true, fogStart: 15),
  ], name: 'Sky');

  engine.start();
  runApp(
    MaterialApp(
      home: Scaffold(body: GameWidget(engine: engine)),
    ),
  );
}
```

Units are metres. The axes are the engine's own: +X right, +Y down (so up is -Y) and +Z into the screen. glTF models, which are Y-up, are turned into these axes as they load.

The 3D view is drawn as an image beneath the 2D world, so sprites, shapes, particles and Flutter UI draw on top of it, and post-processing and camera effects still apply.

## Switching on Flutter GPU

Flutter GPU needs Impeller and a switch in each platform's runner. The engine needs Flutter 3.47.1 or newer, the first stable release where Flutter GPU can be switched on in Windows and Linux release builds. From the Getting started of `just_graphics_engine`:

| Platform | Where | What to set |
|---|---|---|
| Windows | `windows/runner/main.cpp`, after the `DartProject` is made | `project.set_enable_flutter_gpu(true);` |
| Linux | `linux/runner/my_application.cc` | `fl_dart_project_set_enable_flutter_gpu(project, TRUE);` |
| Android | `android/app/src/main/AndroidManifest.xml`, inside the application element | `meta-data` entries `io.flutter.embedding.android.EnableImpeller` and `io.flutter.embedding.android.EnableFlutterGPU` set to `true`, and `io.flutter.embedding.android.ImpellerBackend` set to `vulkan` |
| iOS, macOS | `Info.plist` | `FLTEnableFlutterGPU` set to `true`, and `FLTEnableImpeller` on macOS |

On Windows, `flutter run --enable-flutter-gpu` also works, but only in debug builds. Android devices without Vulkan fall back to OpenGL ES, where 3D is not drawn.

## The camera

A 3D scene is seen through the same main camera as a 2D one, given a perspective lens. `CameraLens.perspective` takes a `fieldOfView` (60 degrees by default, in radians), `near` and `far`. Besides its `position` (x and y), the camera has a depth `z`, a `pitch` (below 0 looks down) and a `yaw`. For a camera that follows a player, use a perspective virtual camera with an orbit, first-person or look-at rig; see [Cameras](/docs/cameras).

## Models and animation

- `ModelComponent(model: ...)` draws a glTF 2.0 model (`.glb`, or `.gltf` with its files beside it) at its entity's transform. `castShadows` and `visible` switch it, and `bounds` fills in once it has loaded. List the files under `flutter: assets:`.
- `AnimationPlayerComponent` plays the model's clips: `clip`, `speed` (negative plays backwards), `loop`, `playing` and `crossfade` (0.2 s by default). `play('Walk')` fades to another clip; set `speed` and `loop` for the new clip after calling it, since the old one fades out as it was. `playBlend(clips, weights)` plays several clips in step, and `setBlendWeights` moves the weights.
- An `AnimatorComponent` on the same entity drives the player from an animator graph: a transition's `duration` crossfades, and blend trees really blend (see [Sprites & animation](/docs/sprites)). A timeline's `skeletalClip` track plays clips too.
- `SocketComponent(node: ...)` on a child entity pins it to a joint of its parent's model, keeping its own scale: a sword in a hand, a hat on a head.

```dart
import 'package:just_game_engine/graphics_3d.dart';
import 'package:just_game_engine/just_game_engine.dart';

Entity addKnight(World world) {
  final knight = world.createEntityWithComponents([
    TransformComponent(),
    ModelComponent(model: 'assets/models/knight.glb'),
    AnimationPlayerComponent(clip: 'Idle'),
    TagComponent('player'),
  ], name: 'Knight');

  // A sword in the right hand: a child pinned to the hand joint.
  world.createEntityWithComponents([
    TransformComponent(),
    ParentComponent(parentId: knight.id),
    SocketComponent(node: 'hand_r'),
    ModelComponent(model: 'assets/models/sword.glb'),
  ], name: 'Sword');
  return knight;
}

void walk(Entity knight) {
  final player = knight.getComponent<AnimationPlayerComponent>()!;
  player.play('Walk', fade: 0.3);
  player.speed = 1.2; // after play(): it applies to the new clip
}
```

## Lights and sky

`Light3DComponent` lights the scene from its entity:

- `LightKind.directional`: a sun, shining along the entity's +Z axis; turn the entity to aim it. The first one is the sun the renderer uses, and it casts the shadows.
- `LightKind.point`, the default: shines every way from the entity, out to `range` metres (0 for no limit).
- `LightKind.spot`: a cone along +Z, at full brightness inside `innerConeAngle` and dark outside `outerConeAngle` (radians).

`color` is sRGB, as picked, and `intensity` (10 by default) is lux-like for a directional light and candela-like for the others. The renderer takes up to 8 point and spot lights. A scene with no lights at all gets a default sun, so a model you drop in is never black.

`EnvironmentComponent` sets the sky and ambient light; the first enabled one in the scene is used. It draws a gradient sky (`zenith`, `horizon`, `ground`) or, with `sky: false`, a flat `background`, and a `skybox` (an equirectangular `.hdr`) replaces the gradient and lights the scene. `ambientSky` and `ambientGround` set the ambient light, `reflections` and `reflectionStrength` the reflections, `exposure` the brightness, and `fog`, `fogColor`, `fogDensity` and `fogStart` the distance fog.

## Shapes

Eleven shapes build their own meshes from their sizes, in metres, centred on their entity:

| Shape | Sizes, with defaults |
|---|---|
| `Cube3DComponent` | `width`, `height`, `depth` (1 each) |
| `Plane3DComponent` | `width`, `depth` (10 each); flat, seen from both sides |
| `Sphere3DComponent` | `radius` (0.5), `segments`, `rings` |
| `Cylinder3DComponent` | `radius` (0.5), `height` (1), `segments` |
| `Capsule3DComponent` | `radius` (0.5), `height` (2, ends included) |
| `Cone3DComponent` | `radius` (0.5), `height` (1), tip up |
| `Torus3DComponent` | `radius` (0.5, to the middle of the tube), `tubeRadius` (0.2) |
| `Ramp3DComponent` | `width` (1), `height` (1, at its back), `depth` (2), rising towards +Z |
| `Stairs3DComponent` | `width` (1), `height` (1), `depth` (2), `steps` (5) |
| `Arch3DComponent` | `radius` (1.5, outside), `thickness` (0.3), `depth` (0.5), `angle` (half a turn) |
| `Polygon3DComponent` | `points`, an (x, z) outline (a hexagon by default), and `height` (1) |

Every shape also carries its material: `color`, `metallic` (0 to 1), `roughness` (0 a mirror, 1 chalk), `emission` and `emissionStrength` for a glow, `opacity` (below 1 draws blended), `unlit`, and a `texture` repeated `tiling` times per face, or per metre with `tileInMetres`. `castShadows` and `visible` switch it, and round shapes take `smooth: false` for a faceted look.

An entity has at most one shape: find it with `entity.getComponent<Primitive3DComponent>()`. Equal shapes share a mesh and a material, so a hundred equal crates are one draw. In [3D physics](/docs/physics-3d), `Collider3DComponent(shape: ColliderShape3D.matchShape)` gives a body the same shape.

## Performance and stats

- `Graphics3D(renderScale: 0.75)` renders fewer pixels, and `engine.graphics3D!.sceneRenderer.renderScale` changes it later. The scene renderer's `dynamicResolution` lowers the resolution while frames run slow: set `enabled` and `targetFps`, with `minScale` and `maxScale` as limits.
- `engine.graphics3D!.renderer.stats` says what the last frame did: `drawCalls`, `shadowDrawCalls`, `instances`, `skinnedInstances`, `shadowCasters`, `triangles`, `culled`, `lights` and `joints`.
- Physics bodies and characters are drawn between their last two poses, so they move smoothly at any frame rate.

## Where Flutter GPU can't draw

On the web, on Android without Vulkan, with Impeller turned off, or in a plain `flutter test`, the game still runs: scenes and models load (models for their bounds), and the 3D view shows a short note instead of the picture. `engine.graphics3D!.unsupportedReason` says why and `isSupported` is false, and `Graphics3D(onUnsupported: ...)` is told once as the engine initializes. See [Platforms](/docs/platforms) for what else differs on each platform.

# Introduction

_Getting started_ · What Just Game Engine is, the tools that come with it, the platforms it runs on and where the 2.0 release stands.

Just Game Engine is a game engine for Flutter. It is 2D, with 3D graphics and 3D physics you can opt into. A game is entities, components and systems (ECS) in a `World`, and its levels are JSON scenes that the game loads at run time. The engine draws inside an ordinary Flutter widget, `GameWidget`, so a game can be a whole app or one screen of a larger one.

It brings level maps, sprites and animator graphs, timelines, virtual cameras, physics, particles, audio and action-based input. The level editor saves the same scene files the game loads, so nothing stands between saving a level and shipping it.

## A first look

This is a whole game: a floor, and a ball that falls onto it.

```dart lib/main.dart
import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The engine, with its standard systems.
  final engine = Engine(
    config: const EngineConfig(defaultSystems: DefaultSystems.all),
  );
  await engine.initialize();

  // y points down, and (0, 0) is the middle of the screen until a
  // virtual camera takes over.
  engine.world
    ..createEntityWithComponents([
      TransformComponent(position: Vector3(0, 200, 0)),
      Rectangle2DComponent(width: 600, height: 24),
      // A collider alone is a static body; this one is the drawn rectangle.
      Collider2DComponent(shape: Collider2DShape.matchShape),
    ], name: 'Floor')
    ..createEntityWithComponents([
      TransformComponent(position: Vector3(0, -150, 0)),
      Circle2DComponent(radius: 24),
      RigidBody2DComponent(),
      Collider2DComponent(shape: Collider2DShape.matchShape),
    ], name: 'Ball');

  engine.start();
  runApp(MaterialApp(home: GameWidget(engine: engine)));
}
```

- `Engine()` makes a new engine each time. `initialize()` builds its subsystems and world; finish it before you use the engine.
- `engine.start()` starts the game loop. `GameWidget` runs it on Flutter's frame ticker, draws the world, and passes keys and pointers to `engine.input`.
- When you are done, `await engine.dispose()`. Disposal is final: to start over, make a new `Engine()`.

[Your first game](/docs/quick-start) builds on this step by step.

## The toolkit

The engine is one package. These are the others you will meet:

| Package | What it is | Version |
|---|---|---|
| `just_game_engine` | The engine: the ECS world, scenes, rendering, physics, audio, input and the rest. | `2.0.0-dev.4` |
| `just_game_engine_editor` | A level editor that runs inside your game in a desktop debug build. See [Level editor](/docs/editor). | `0.1.0` dev releases, one made for each engine release |
| `just_core_cli` | `just`, the command-line tool: it creates projects, checks their setup and upgrades them. | `0.1.x` |
| `just_game_engine_cli` | The `just game` commands: run, build, scenes, release checks and migrations. See [The just CLI](/docs/cli). | `0.1.x` |
| `just_game_engine_formats` | The saved file formats (scenes, timelines, animator graphs) and their migrations, in pure Dart. The engine re-exports it, and the editor and the CLI migrate files with the same code. | comes with the engine |
| `just_game_services` | Achievements, sign-in, leaderboards, currency, inventory and ads, as opt-in engine services. See [Game services](/docs/services). | `0.1.0`, not yet on pub.dev |

Under the engine sit packages of the same family: `just_physics_engine` (Box2D v3 through FFI where its native library loads, a pure-Dart engine with the same API elsewhere, and Jolt Physics for 3D), `just_graphics_engine` (3D on Flutter GPU), `just_inputs`, `just_audio_engine`, `just_tiled` and a few smaller ones. You rarely import them yourself.

## Platforms

- **The engine** runs on Android, iOS, Windows, macOS, Linux and the web, compiled to JavaScript or WebAssembly.
- **3D graphics** draw where Flutter GPU does: not on the web, and not on Android devices without Vulkan. There the game still runs, and the 3D view shows a short note.
- **3D physics** runs where Jolt is built, which is everywhere but the web.
- **On the web**, 2D physics runs on the pure-Dart engine, audio starts at the first key or pointer press, and fragment-shader effects are skipped.
- **The editor** edits on Windows, macOS and Linux, in a debug build. On other platforms, and in any profile or release build, the game runs on its own.
- **The `just` tool** runs on Windows, macOS and Linux.

[Platforms](/docs/platforms) has the details for each one.

## What's included

- [The engine object](/docs/engine): `Engine`, `EngineConfig`, the default systems and the game loop.
- [Entities, components and systems](/docs/ecs): `World`, `Entity`, `System`, queries, events and the transform hierarchy.
- [Scenes](/docs/scenes): levels as JSON, `SceneLoader`, component definitions and format migrations.
- [Rendering](/docs/rendering): `RenderSystem`, shapes, draw order, render hooks and post-processing.
- [Sprites and animation](/docs/sprites): sprites, TexturePacker and Aseprite atlases, and animator graphs.
- [Timelines](/docs/timelines): keyframed component fields, events, camera shots and audio.
- [Cameras](/docs/cameras): virtual cameras, framing, confiners, impulses and blends.
- [Particles and effects](/docs/particles): emitters, presets and deterministic, tick-based effects.
- [3D graphics](/docs/graphics-3d): models, lights, environments and built-in shapes on Flutter GPU.
- [2D physics](/docs/physics-2d): `RigidBody2DComponent`, `Collider2DComponent`, `CharacterBody2DComponent`, joints, queries and events.
- [3D physics](/docs/physics-3d): the same model on Jolt Physics.
- [Input](/docs/input): named actions from `just_inputs`, local multiplayer, rebinding and touch controls.
- [Level maps](/docs/level-maps): tile maps, Tiled import and export, and tile collision.
- [Tags, targets and spawners](/docs/tags-spawners): finding entities by tag, and spawn points.
- [Audio](/docs/audio): music, sound effects and 3D sound.
- [Assets](/docs/assets), [Localization](/docs/localization) and [Dialogue](/docs/dialogue) (Yarn Spinner 2.x scripts).
- [GameWidget and Flutter UI](/docs/game-widget): overlays, widget layers and ready-made widgets.
- [Game services](/docs/services), [Debugging](/docs/debugging) and [Testing](/docs/testing).

## Version status

2.0 is a breaking release, out first as dev releases. The latest is 2.0.0-dev.4, and these docs are written for it. The latest stable release is 1.6.1.

> **Note:** A `^2.0.0` constraint does not pick up dev releases. Depend on `just_game_engine: ^2.0.0-dev.4`, as [Installation](/docs/installation) shows.

- **Coming from 1.x?** Read [Migrating from 1.x](/docs/migration). Scene files saved by earlier versions still load: they are migrated in memory as they are read.
- **Between dev releases**, read the [CHANGELOG](https://github.com/just-unknown-dev/just-game-engine/blob/main/CHANGELOG.md) before you move up.
- **The examples site** at [examples.engine.justunknown.com](https://examples.engine.justunknown.com) was written for 1.x.
- **The editor and the CLI** are first releases (0.1). Use the editor release made for this engine; `just game` keeps the engine's packages on versions that work together.

## License

The engine, the editor and the CLI packages are open source under the BSD 3-Clause license. Each repository has its LICENSE file.

## Getting help

- **Discord:** ask questions and share what you build at [discord.gg/VXFxVj4Y](https://discord.gg/VXFxVj4Y).
- **Issues:** report bugs against the [engine](https://github.com/just-unknown-dev/just-game-engine/issues), the [editor](https://github.com/just-unknown-dev/just-game-engine-editor/issues) or the [CLI](https://github.com/just-unknown-dev/just-game-engine-cli/issues).
- **API reference:** every public class and member is on [pub.dev](https://pub.dev/documentation/just_game_engine/2.0.0-dev.4/).
- **The repository's own docs:** the [engine on GitHub](https://github.com/just-unknown-dev/just-game-engine) has its README, QUICKSTART, MIGRATION, ARCHITECTURE and an API map by area.

# Platforms & the web

_Flutter & shipping_ · Where the engine runs, what changes on the web and WebAssembly, what Linux builds need, and where 3D graphics and 3D physics are available.

The engine is built for Android, iOS, Windows, macOS, Linux and the web, compiled to JavaScript or WebAssembly. It is made for Flutter 3.47 (3.47.1 or newer; see "Flutter versions" in [Installation](/docs/installation)). It is verified on Windows, Android (Vulkan) and the web. Linux, iOS and macOS are untested: they are expected to build, but have never been run. A 2-D game is meant to run on all of them; 3-D drawing and 3-D physics depend on what each platform can do.

## Platform support

| Platform | Tested | 2-D physics | 3-D graphics (Flutter GPU) | 3-D physics (Jolt) |
|---|---|---|---|---|
| Windows | Verified | Box2D, native | Supported | Supported (x64) |
| Android | Verified (Vulkan) | Box2D, native | Vulkan devices only | arm64-v8a and x86_64 |
| Linux | Untested | Box2D, native | Expected to work, untested | Should build, untested |
| macOS | Untested | Box2D, native | Expected to work, untested | Should build, untested |
| iOS | Untested | Box2D, native | Expected to work, untested | Should build, untested |
| Web (JS and Wasm) | Verified | Pure Dart | Not drawn | Not available |

The 3-D statuses come from the `just_graphics_engine` and `just_jolt` packages the engine builds on. A game without a `Graphics3D` or `Physics3D` in its config is 2-D only and carries none of that code.

## The web and WebAssembly

The engine's library imports `dart:io` in one place only, behind a conditional import, so a game builds for the web with JavaScript or WebAssembly. What differs there:

| Area | On the web |
|---|---|
| Physics | The pure-Dart engine instead of Box2D, with the same API. |
| Audio | Starts at the first key or pointer press, because browsers keep audio silent until the player interacts. `EngineConfig.deferAudioUntilInput` changes this; null means on the web only. |
| Shaders | Post-process passes and `ShaderComponent` effects are skipped and the content is drawn unshaded, as on native platforms still drawing with Skia. The 2-D materials added in 2.0.0-dev.2 draw the same everywhere, the web included. |
| Storage | `engine.cache` keeps its data in the browser's local storage, under a `just_game_engine/` namespace. |
| Gamepads | Work in JavaScript and WebAssembly builds once a button is pressed; browsers hide pads until then. |
| 3-D graphics | Scenes and models load, but nothing is drawn: Flutter GPU is not on the web, and the 3-D view shows a short note instead. |
| 3-D physics | Cannot run. `initialize()` fails with an `EngineInitException` whose `cause` is a `Physics3DUnsupportedError`. |

A game that targets both the web and native platforms asks before it turns 3-D physics on:

```dart
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/just_game_engine_3d.dart';

final engine = Engine(
  config: EngineConfig(
    defaultSystems: DefaultSystems.all,
    // Left out on the web and wherever Jolt was not built into the app.
    services: [if (Physics3D.isSupported) Physics3D()],
  ),
);
```

`Physics3D.unsupportedReason` says why 3-D physics cannot run. For 3-D drawing, a `Graphics3D` never fails the engine: where Flutter GPU cannot draw, the game runs anyway, `unsupportedReason` on your `Graphics3D` says why, and `Graphics3D(onUnsupported: ...)` hears it once.

## 3-D graphics and 3-D physics

3-D drawing uses Flutter GPU, which must be switched on in each platform's runner: see the Getting started section of the `just_graphics_engine` README, and [3D graphics](/docs/graphics-3d). On Android it needs the Vulkan backend; on a device without Vulkan the game runs without the 3-D view, which shows a short note instead.

3-D physics runs on Jolt, compiled from source by the `just_jolt` build hook, which compiles nothing unless your app's own pubspec asks for it:

```yaml pubspec.yaml
hooks:
  user_defines:
    just_jolt:
      build: true
```

See [3D physics](/docs/physics-3d) for the components.

## Native physics

On native platforms, `engine.physics` is Box2D v3 through FFI, compiled by the `just_box_2d` build hook. If the native library does not load, the engine logs it and falls back to the pure-Dart simulation; `engine.physics.isNative` then reads `false` (and the diagnostics key `engine.physics.stats['backend']` reads `dart_fallback`). A web-only game, or one that uses the pure-Dart engine everywhere, can skip compiling Box2D with `hooks: user_defines: just_box_2d: build: false` in its pubspec.

## Linux

To build for Linux, install what the audio plugin links: OpenAL Soft and libsndfile. Players need the runtime libraries, `libopenal1` and `libsndfile1`.

```bash
sudo apt install libopenal-dev libsndfile1-dev
```

The Box2D build hook compiles with clang, which Flutter's Linux toolchain needs anyway.

## Storage

`engine.cache` keeps its data in a store of its own, apart from your app's: `<application support>/just_game_engine/just_storage.json` on desktop and mobile, and the browser's local storage under `just_game_engine/` on the web. When a store cannot be opened, as in tests, the cache keeps everything in memory for the rest of the run.

## No process-wide state

Everything an engine knows lives in its own `EngineContext`, and everything a world holds lives in that `World`. Two engines in one process, or two tests, never see each other's registrations. The engine's own test suite enforces this: it fails on any non-const `static` field in the engine's source that is not on a reviewed list. When you write a package for the engine, keep per-engine state in `context.slot(...)` rather than in a static, so it follows the same rule.

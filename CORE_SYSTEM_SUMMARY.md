# Just Game Engine — status summary, 2.0.0

What the engine contains at 2.0.0, with numbers counted on the release tree on 2026-10-01. This file lives only in the repository (it is excluded from the pub.dev package). What changed since 1.x is in [CHANGELOG.md](CHANGELOG.md) and [MIGRATION.md](MIGRATION.md); how it is built is in [ARCHITECTURE.md](ARCHITECTURE.md); the public API is mapped in [API.md](API.md) and documented in full on [pub.dev](https://pub.dev/documentation/just_game_engine/latest/).

## What it is

A 2-D game engine for Flutter. Transforms, cameras and the renderer seam are 3-D ready; drawing is 2-D, on Flutter's `Canvas`. A game makes one `Engine`, awaits `initialize()`, and shows it in a `GameWidget`. Everything an engine knows (component definitions, loaders, registries, migration hooks) lives in its `EngineContext`, so two engines in one process share nothing; `test/no_process_state_test.dart` fails when a `static` field that is not `const` appears under `lib/src` without a reason on its allow-list.

## What it contains

| Area | Contents |
|---|---|
| Core | `Engine` lifecycle (`initialize` / `start` / `dispose`, a `failed` state with `EngineInitException`), fixed-step `GameLoop`, `TimeManager`, `GameWidget` and `GameLayers` (Flutter widgets over the game), plugins, `EngineService`s, opt-in default systems |
| ECS | Archetype `World`, systems run by priority, `CommandBuffer`, `EventBus`, 3-D `TransformComponent` with a parent–child hierarchy, multi-tag entities, `EntityTarget`, spawners |
| Scenes | JSON scene format v7 with a migration chain from v0; `ComponentDefinition`s per context; `SceneLoader` |
| Rendering | `RenderSystem` with layer / z-order sorting, shapes, sprites and sprite batching, optional off-screen culling, fragment-shader post-processing, parallax backgrounds |
| Sprites and animation | Atlases (TexturePacker, Aseprite, grid sheets), clip playback with frame events, animator state machines (`.animator.json`, format 1) |
| Timelines | `.timeline.json` (format 2) with 7 track kinds: property, event, sprite clip, camera shot, audio, activation, nested timeline |
| Cameras | Virtual cameras and a `CameraBrain` with blends; framing, confiner, noise, dolly and group stages; impulses; blend-list, mixer and state-driven managers; fade, letterbox and motion-blur effects |
| Level maps | Orthogonal, isometric, staggered and hexagonal tile maps; the engine's own map and tileset JSON and Tiled `.tmx` / `.tmj`; Wang terrain; collision kinds; tile changes at run time |
| Physics | `just_physics_engine`: bodies, joints, sensors, one-way platforms, ray casts |
| Input | `just_inputs` action assets (`.input.json`), local multiplayer, rebinding saved in the engine's storage |
| Audio | `just_audio_engine`: music, sound effects, channels, 3-D sources and listener, audio components |
| Particles and effects | Emitters, forces and presets; 11 deterministic tick-based effects with snapshots |
| Narrative and localization | Yarn Spinner 2 dialogue, string tables per locale, subtitles |
| Assets, memory, storage | Reference-counted `AssetManager`; `CacheManager` with the engine's own key-value store and binary database |
| Screen widgets | `package:just_game_engine/widgets.dart`: dialogue box, subtitles, localized text, camera zoom controls, on-screen controls, rebinding list |

Achievements, sign-in, leaderboards, currency, inventory and ads are not part of the engine; they are `EngineService`s in the separate package `just_game_services`.

## Numbers

| What | Count |
|---|---|
| Dart files in `lib/` | 317 |
| Lines in `lib/` (with comments and blank lines) | 56,568 |
| Names exported by `just_game_engine.dart` | 679: 577 declared by the engine, 102 re-exported from `just_inputs`, `just_physics_engine`, `just_audio_engine`, `just_memory`, `just_dart` |
| Names exported by `widgets.dart` | 17 |
| Component classes | 64 |
| System classes | 33: 31 concrete (one of them, `HierarchySystem`, deprecated) and 2 abstract bases (`ReactiveSystem`, `AutoSyncSystem`) |
| Default systems | 9 `DefaultSystem` sets, adding 16 systems |
| Test files (`*_test.dart`) | 119 |
| Tests (`flutter test`) | 1,490 passed, 0 skipped, 0 failed |
| `flutter analyze` / `dart format` | no issues / no changes |

How they were counted, from the package root:

- files and lines: `find lib -name '*.dart' | wc -l` and `find lib -name '*.dart' -exec cat {} + | wc -l`;
- exported names, and component and system classes (subclasses of `Component` and `System` among the exported classes): an analyzer dump of the two libraries' export namespaces;
- tests: `flutter test` on Windows with Flutter 3.47.5 (Dart 3.13.4).

`test/perf/transform_hot_path_test.dart` prints two timings. Medians of five runs on a quiet machine: 10,000 moving shapes, update and render, 12.9 ms per frame (runs ranged from 10.7 to 15.6 ms); 2,000 physics bodies, step and transform sync, 1.56 ms per frame (1.34 to 1.75 ms). Before this release's rendering work the shapes figure was about 19.5 ms. They come from `flutter test` (JIT, not a release build) on one development machine, so compare them only with runs on the same machine.

## Platforms

`pubspec.yaml` declares Android, iOS, Linux, macOS, Windows and web. The minimum SDKs are Dart 3.12 and Flutter 3.44.

- `lib/` imports `dart:io` in one file, `lib/src/memory/engine_storage_io.dart`, and only through a conditional import; nothing imports `dart:html`. The engine therefore compiles for the web with both dart2js and dart2wasm. On 2026-10-01 a small web app depending on the engine was built with `flutter build web --wasm` without errors.
- Physics: Box2D through FFI where its native library loads; otherwise, and always on the web, the pure-Dart backend of `just_physics_engine`.
- Audio: on the web the audio engine starts at the first key or pointer press, because browsers keep audio suspended until a user gesture (`EngineConfig.deferAudioUntilInput`).
- Shaders: a fragment shader used as an image filter (post-process passes, `ShaderComponent`) needs Impeller. On the web and on Skia the effect is skipped and the content draws unshaded (`ShaderFilterSupport`).
- Gamepads come from `just_gamepads` through `just_inputs`; its own documentation says which platforms it supports.
- Storage: native platforms keep the engine's settings in `<application support>/just_game_engine/just_storage.json`; on the web they go in local storage, under the `just_game_engine/` namespace.

There is no CI workflow in this repository; the checks above were run locally.

## Dependencies

`just_physics_engine`, `just_inputs`, `just_audio_engine`, `just_storage`, `just_database`, `just_signals`, `just_memory`, `just_tiled`, `just_dart`, `just_deflate`, `path_provider`, `meta`, and the Flutter SDK packages `flutter` and `flutter_web_plugins`. Versions are in [pubspec.yaml](pubspec.yaml).

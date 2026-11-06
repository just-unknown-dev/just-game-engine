# Just Game Engine — status summary, 2.0.0

What the engine contains at 2.0.0, with numbers counted on 2026-11-06. This file lives only in the repository (it is excluded from the pub.dev package). What changed since 1.x is in [CHANGELOG.md](CHANGELOG.md) and [MIGRATION.md](MIGRATION.md); how it is built is in [ARCHITECTURE.md](ARCHITECTURE.md); the public API is mapped in [API.md](API.md) and documented in full on [pub.dev](https://pub.dev/documentation/just_game_engine/2.0.0/).

## What it is

A game engine for Flutter: 2-D, with 3-D graphics and physics to opt into. 2-D draws on Flutter's `Canvas`. 3-D drawing on Flutter GPU (`Graphics3D`, through `just_graphics_engine`) and 3-D physics on Jolt (`Physics3D`) come from `package:just_game_engine/just_game_engine_3d.dart`, switched on with `EngineConfig(services: [Graphics3D(), Physics3D()])`; a 2-D game carries neither. A game makes one `Engine`, awaits `initialize()`, and shows it in a `GameWidget`. Everything an engine knows (component definitions, loaders, registries, migration hooks) lives in its `EngineContext` — the features' state in slots, through `ContextX` extensions — so two engines in one process share nothing; `test/no_process_state_test.dart` fails when a `static` field that is not `const`, or a top-level variable, appears under `lib/src` without a reason on its allow-list.

## What it contains

| Area | Contents |
|---|---|
| Core | `Engine` lifecycle (`initialize` / `start` / `dispose`, a `failed` state with `EngineInitException`), fixed-step `GameLoop`, `TimeManager`, `GameWidget` and `GameLayers` (Flutter widgets over the game), plugins, `EngineService`s, opt-in default systems |
| ECS | Archetype `World`, systems run by priority, `CommandBuffer`, `EventBus`, 3-D `TransformComponent` with a parent–child hierarchy, multi-tag entities, `EntityTarget`, spawners |
| Scenes | JSON scene format 11 with a migration chain from 0; prefab files (`*.prefab.json`) placed in scenes and nested; `ComponentDefinition`s per context; `SceneLoader` |
| Rendering | `RenderSystem` with layer / z-order sorting, shapes, sprites and sprite batching, optional off-screen culling, fragment-shader post-processing, parallax backgrounds |
| 2-D materials and lights | `Material2DComponent` (material files: outline, flash, dissolve, …), `ScreenMaterialComponent` (whole-view effects), 2-D lighting with normal maps and shadows (`Lighting2DComponent`, `Light2DComponent`, `ShadowCaster2DComponent`) |
| Sprites and animation | Atlases (TexturePacker, Aseprite, grid sheets), clip playback with frame events, animator state machines (`.animator.json`, format 2) |
| Timelines | `.timeline.json` (format 3) with 7 track kinds: property, event, sprite clip, camera shot, audio, activation, nested timeline |
| Cameras | Virtual cameras and a `CameraBrain` with blends; framing, confiner, noise, dolly and group stages; impulses; blend-list, mixer and state-driven managers; fade, letterbox and motion-blur effects |
| Level maps | Orthogonal, isometric, staggered and hexagonal tile maps; the engine's own map and tileset JSON and Tiled `.tmx` / `.tmj`; Wang terrain; collision kinds; tile changes at run time |
| Physics | `just_physics_engine`. 2-D: Box2D v3 through FFI (`just_box_2d`) where its native library loads, pure Dart elsewhere and on the web; rigid bodies and colliders, characters, joints, sensors, one-way platforms, queries. 3-D (opt-in, `Physics3D`): Jolt through `just_jolt`, with the same component names (`3D` for `2D`) |
| 3-D graphics (opt-in) | `Graphics3D`: glTF models with skeletal animation and sockets, eleven primitive shapes, PBR material files, lights, a sky and fog (`EnvironmentComponent`), render providers for a package's own meshes |
| Input | `just_inputs` action assets (`.input.json`), local multiplayer, rebinding saved in the engine's storage |
| Audio | `just_audio_engine`: music, sound effects, channels, 3-D sources and listener, audio components |
| Particles and effects | Emitters, forces and presets; 11 deterministic tick-based effects with snapshots |
| Narrative and localization | Yarn Spinner 2 dialogue, string tables per locale, subtitles |
| Assets, memory, storage | `AssetManager`, reference-counted per path and type, with `retainOnly` for level changes; `CacheManager` with the engine's own key-value store and binary database |
| Screen widgets | `package:just_game_engine/widgets.dart`: dialogue box, subtitles, localized text, camera zoom controls, on-screen controls, rebinding list |

Achievements, sign-in, leaderboards, currency, inventory and ads are not part of the engine; they are `EngineService`s in the separate package `just_game_services`.

## Numbers

| What | Count |
|---|---|
| Dart files in `lib/` | 404 |
| Lines in `lib/` (with comments and blank lines) | 84,228 |
| Names exported by `just_game_engine.dart` | 759: 614 declared by the engine, 145 re-exported from `just_inputs` (44), `just_game_engine_formats` (39), `just_physics_engine` (26), `just_audio_engine` (14), `just_memory` (11), `just_dart` (9) and `just_signals` (2) |
| Names exported by `just_game_engine_3d.dart` | 162: 71 declared by the engine, 91 re-exported from `just_graphics_engine` (45), `just_physics_engine`'s 3-D side (32), the maths types of `just_dart` (9, the main library's) and `just_game_engine_formats` (5) |
| Names exported by `widgets.dart` | 17 |
| Component classes | 101: 72 in the main library (plus the `Component` base), 29 in the 3-D library |
| System classes | 32: 30 concrete (28 in the main library; `Physics3DSystem` and `Animation3DSystem` in the 3-D library) and 2 abstract bases (`ReactiveSystem`, `AutoSyncSystem`) |
| Default systems | 11 `DefaultSystem` sets, adding 16 systems |
| Test files (`*_test.dart`) | 269 |
| Tests (`flutter test`) | 2,551 passed, 7 skipped, 0 failed |
| `flutter analyze` / `dart format` | no issues / no changes in `lib/` or `example/` |

How they were counted, from the package root:

- files and lines: `find lib -name '*.dart' | wc -l` and `find lib -name '*.dart' -exec cat {} + | wc -l`;
- exported names, and component and system classes (subclasses of `Component` and `System` among the exported classes): an analyzer dump of the three libraries' export namespaces;
- tests: `flutter test` on Windows with Flutter 3.47.9 (Dart 3.13.7). The skipped tests are the four that draw with Flutter GPU (run them with `flutter test --enable-impeller --enable-flutter-gpu --tags gpu`) and the three timing files tagged `perf` (`flutter test --tags perf --run-skipped`).

`test/perf/transform_hot_path_test.dart` (tagged `perf`, so it runs only with `flutter test --tags perf --run-skipped`) prints two timings. Medians of five runs on a quiet machine, measured on 2026-10-01 (not re-measured for this summary): 10,000 moving shapes, update and render, 12.9 ms per frame (runs ranged from 10.7 to 15.6 ms); 2,000 physics bodies, step and transform sync, 1.56 ms per frame (1.34 to 1.75 ms). Before this release's rendering work the shapes figure was about 19.5 ms. They come from `flutter test` (JIT, not a release build) on one development machine, so compare them only with runs on the same machine.

## Platforms

`pubspec.yaml` declares Android, iOS, Linux, macOS, Windows and web. The minimum SDKs are Dart 3.11 (`^3.11.0`) and Flutter 3.47.1; the release is made for Flutter 3.47 and tested on 3.47.9 (the README's "Flutter versions"). It is verified on Windows, Android (Vulkan) and the web; Linux, iOS and macOS are untested (expected to build, never run).

- `lib/` imports `dart:io` in one file, `lib/src/storage/engine_storage_io.dart`, and only through a conditional import; nothing imports `dart:html` or `package:web`, and the web storage branch uses `dart:js_interop`. The engine therefore compiles for the web with both dart2js and dart2wasm. The 2-D library reaches no 3-D code; `flutter_gpu` is reached only from `just_game_engine_3d.dart`. The example builds with `flutter build web` and `flutter build web --wasm`.
- 3-D: `Graphics3D` draws where Flutter GPU runs (Impeller with Vulkan or Metal); on the web and on Android without Vulkan scenes and models load, but the 3-D view shows a short note instead. `Physics3D` needs Jolt built (`hooks: user_defines: just_jolt: build: true`) and does not run on the web (`Physics3D.isSupported`).
- Physics: Box2D through FFI where its native library loads; otherwise, and always on the web, the pure-Dart backend of `just_physics_engine`.
- Audio: on the web the audio engine starts at the first key or pointer press, because browsers keep audio suspended until a user gesture (`EngineConfig.deferAudioUntilInput`).
- Shaders: a fragment shader used as an image filter (post-process passes, `ShaderComponent`) needs Impeller. On the web and on Skia the effect is skipped and the content draws unshaded (`ShaderFilterSupport`).
- Gamepads come from `just_gamepads` through `just_inputs`, and work in browsers too, WebAssembly included (its `js_interop` backend); its own documentation says which platforms it supports.
- Storage: native platforms keep the engine's settings in `<application support>/just_game_engine/just_storage.json`; on the web they go in local storage, under the `just_game_engine/` namespace.

There is no CI workflow in this repository; the checks above were run locally.

## Dependencies

`just_physics_engine`, `just_inputs`, `just_audio_engine`, `just_storage`, `just_database`, `just_signals`, `just_memory`, `just_tiled`, `just_dart`, `just_deflate`, `path_provider`, `meta`, `just_graphics_engine`, `just_game_engine_formats`, and the Flutter SDK package `flutter`. Versions are in [pubspec.yaml](pubspec.yaml).

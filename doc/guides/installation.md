# Installation

_Getting started_ · Start a new game with the just CLI, or add the engine to an existing Flutter app, then opt into 3D where you need it.

There are two ways in. A new project made with the `just` command-line tool comes with the engine, the editor and the wiring between them. An existing Flutter app adds the engine like any other package.

## Requirements

- **Flutter 3.47.1 or newer.** It is the first stable release where Flutter GPU can be switched on in Windows and Linux release builds, which the 3D renderer needs. Every app builds the renderer's shaders; a 2D game never loads them.
- **A desktop for the editor.** The editor runs in a debug build on Windows, macOS or Linux.
- **Linux builds** also need what the audio plugin links: OpenAL Soft and libsndfile (`sudo apt install libopenal-dev libsndfile1-dev` on Debian and Ubuntu). Players need `libopenal1` and `libsndfile1`.

## Path 1: a new game with the CLI

Install the `just` tool once, then create and run a game:

```bash
dart pub global activate just_core_cli
just create my_game
cd my_game
just game run            # the game
just game run --editor   # the game with the level editor (desktop, debug)
```

`just create` runs `flutter create`, writes `just.json`, and adds `just_core_cli` and `just_game_engine_cli` to the dev dependencies. It then hands the folder to the game plugin, which lays the game template over it on engine versions that work together, writes the first level (`level_01`), and adds the editor through the Asset Store. If a step fails, `just create` deletes the folder it made (or empties the empty folder you gave it).

| Path | What it holds |
|---|---|
| `lib/main.dart` | The game, as it ships. It never imports the editor. |
| `lib/main_editor.dart` | The game with the editor over it, in debug builds only. |
| `lib/game/` | The game: its boot, systems and spawners. |
| `lib/editor/` | What the editor needs from the game. It never ships. |
| `assets/scenes/` | The levels, as the JSON the editor saves. |
| `just.json` | The project's title and the tool set it is on. |

`just game run` runs `flutter run` on `lib/main.dart`; with `--editor` it runs `lib/main_editor.dart` on this desktop. If `just` is already another program on your machine (such as the `just` command runner), type `ju` instead: it is the same tool. [The just CLI](/docs/cli) covers every command and option.

## Path 2: add the engine to an existing app

Add the engine to `pubspec.yaml`, list the asset folders your game loads from, and run `flutter pub get`:

```yaml pubspec.yaml
environment:
  sdk: ^3.11.0
  flutter: ">=3.47.1"

dependencies:
  flutter:
    sdk: flutter
  # just_audio_engine registers a web plugin without depending on
  # flutter_web_plugins; depending on it here keeps web builds compiling.
  flutter_web_plugins:
    sdk: flutter
  just_game_engine: ^2.0.0-dev.2

flutter:
  assets:
    - assets/scenes/
    - assets/input/
    - assets/sprites/
    - assets/audio/
    - assets/project/physics.json
```

> **Warning:** Write the dev release into the constraint. `^2.0.0` alone does not pick up dev releases, so it will not find 2.0.0-dev.2.

One import gives you the engine: `package:just_game_engine/just_game_engine.dart`. The ready-made widgets (dialogue boxes, on-screen controls, rebinding lists) are in `package:just_game_engine/widgets.dart`; import it only if you use them.

To add the editor to an existing app as well, see [Level editor](/docs/editor).

## Declaring assets

The engine reads scenes, input actions, atlases, maps, timelines and sounds through Flutter's asset bundle, so each file must be listed under `flutter: assets:`, by itself or through its folder.

- **A folder entry does not include its subfolders.** List each folder you load from.
- **Scenes** live in `assets/scenes/` as `<name>.scene.json`, with the play order in `assets/scenes/scenes.json`. List `assets/scenes/`.
- **Collision layers** live in `assets/project/physics.json`, which the editor's Physics Layers dock writes. The engine reads it during `initialize()` when the app bundles it; without it, every body collides with every other.
- **A sprite that does not show** is most often a file missing from this list, or an atlas image that is not beside its JSON.

## Opting into 3D graphics

A game is 2D unless you give the engine a `Graphics3D`, from `package:just_game_engine/graphics_3d.dart`. Without one, the engine makes no GPU device and loads no shaders, and a scene holding 3D components fails to load with a message saying how to turn 3D on.

3D draws with Flutter GPU, which must be switched on in each platform's runner. `just create` does this for you when the template it starts from draws in 3D. Otherwise, add the switch by hand:

| Platform | File | What to add |
|---|---|---|
| Windows | `windows/runner/main.cpp` | `project.set_enable_flutter_gpu(true);` after `project.set_dart_entrypoint_arguments(...)`. Release builds ignore the `--enable-flutter-gpu` flag, so the switch belongs in code. |
| Linux | `linux/runner/my_application.cc` | `fl_dart_project_set_enable_flutter_gpu(project, TRUE);` after the entry-point arguments. |
| Android | `android/app/src/main/AndroidManifest.xml` | `meta-data` entries setting `io.flutter.embedding.android.EnableImpeller` and `io.flutter.embedding.android.EnableFlutterGPU` to `true`, and `io.flutter.embedding.android.ImpellerBackend` to `vulkan`. |
| iOS | `ios/Runner/Info.plist` | `FLTEnableFlutterGPU` set to true. |
| macOS | `macos/Runner/Info.plist` | `FLTEnableImpeller` and `FLTEnableFlutterGPU` set to true. |

The `just_graphics_engine` README (Getting started) is the reference for these switches. Where Flutter GPU cannot draw, the game runs anyway: scenes and models load, the 3D view shows a short note, `unsupportedReason` says why, and `Graphics3D(onUnsupported: ...)` hears about it.

## Opting into 3D physics

3D physics runs on Jolt Physics, which your app's pubspec must build:

```yaml pubspec.yaml
hooks:
  user_defines:
    just_jolt:
      build: true
```

Then give the engine a `Physics3D`, from `package:just_game_engine/physics_3d.dart`. A game without one is 2D only, and its release build holds no 3D physics code and no Jolt. Where 3D physics cannot run (the web, or Jolt not built), `initialize()` throws an `EngineInitException` whose `cause` is a `Physics3DUnsupportedError`. Ask `Physics3D.isSupported` first in a game that also targets the web:

```dart lib/main.dart
import 'package:just_game_engine/graphics_3d.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/physics_3d.dart';

Future<Engine> start3D() async {
  final engine = Engine(
    config: EngineConfig(
      defaultSystems: DefaultSystems.all,
      services: [
        Graphics3D(),
        // Jolt does not run on the web: ask before giving the engine 3D physics.
        if (Physics3D.isSupported) Physics3D(),
      ],
    ),
  );
  await engine.initialize();
  engine.start();
  return engine;
}
```

[3D graphics](/docs/graphics-3d) and [3D physics](/docs/physics-3d) cover what to do next.

## The web

The engine has no `dart:io` outside one conditional import, so a game builds for the web with JavaScript or WebAssembly (`flutter build web`, or `flutter build web --wasm`). A few things work differently there:

- **2D physics** runs on the pure-Dart engine, with the same API as native Box2D.
- **Audio** starts at the first key or pointer press, because browsers keep audio made before a user gesture silent. `EngineConfig.deferAudioUntilInput` changes this.
- **Shader effects** (`PostProcessPass`, `ShaderComponent`) are skipped, and the content draws unshaded.
- **Gamepads** appear once a button is pressed, because browsers hide them until then.
- **3D** scenes and models load but are not drawn, and 3D physics does not run.
- **`flutter_web_plugins`** must be a dependency, as in the pubspec above. Games made with `just create` have it.

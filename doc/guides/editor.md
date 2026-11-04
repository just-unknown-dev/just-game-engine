# Level editor

_Tools_ · Install the level editor, give it an entry point that never ships, register your components, and find your way around its tools.

The Just Game Engine editor is a level editor that runs inside your game while you develop it. You start the game's editor entry point in a debug build on Windows, macOS or Linux, and the running game is the scene you edit. 2D and 3D scenes, the Level Map, physics, cameras, timelines, materials and play-testing share one undo stack, and a profile or release build of the game holds none of it. The [editor overview](/editor) has screenshots and the feature list.

> **Tip:** A project made with `just create` already has the editor, its entry point and its wiring. Run `just game run --editor` and skip to "Open the editor" below.

## Install

The editor is a dev dependency: only your editor entry point imports it, so it never ships, and a release build also leaves out the native plugins only the editor brings. Add it from the project folder with `flutter pub add --dev just_game_engine_editor`, which puts it under `dev_dependencies`. Each editor release is made for one engine release: use the one made for `just_game_engine` 2.0.0-dev.4, with Flutter 3.47.1 or newer.

## The editor entry point

Keep `lib/main.dart` free of the editor, and give the editor an entry point of its own, `lib/main_editor.dart`:

```dart lib/main_editor.dart
// The editor is a dev dependency, imported by this entry point alone.
// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'main.dart' show MyGame; // the game, as lib/main.dart runs it

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // kDebugMode is a compile-time constant: a profile or release build keeps
  // only the else branch, so it holds no editor.
  if (kDebugMode) {
    await _runEditor();
  } else {
    runApp(const MyGame());
  }
}

Future<void> _runEditor() async {
  final engine = Engine(
    config: const EngineConfig(
      extensions: [MyGameExtension()], // your components (below)
      defaultSystems: DefaultSystems.all,
    ),
  );
  await engine.initialize(); // boot the game's world here, as main.dart does
  final plugin = await JustGameEditorPlugin.register(
    engine: engine,
    modules: [MyGameModule()], // what your game adds to the editor
    spawners: mySpawners, // what Play spawns at each spawn point
    onReassemble: (plugin) => rewire(engine, plugin),
  );
  engine.start();
  runApp(
    MaterialApp(
      home: JustGameEngineEditor(engine: engine, plugin: plugin),
    ),
  );
}

/// Runs after every hot reload: what main handed the editor from code.
void rewire(Engine engine, JustGameEditorPlugin plugin) {
  plugin.syncModules([MyGameModule()]); // a module added since launch joins
  plugin.scope.spawners.value = mySpawners; // read at the next Play
}
```

- **Why `if (kDebugMode)`.** Because `kDebugMode` is a constant, the compiler keeps one branch and drops the other, so a release build of this file is the game alone. An early `if (!kDebugMode) { ...; return; }` is not the same: code after a `return` is still compiled in. `just doctor` checks that `main` keeps this shape.
- **`JustGameEditorPlugin.register`** returns null in a profile or release build, and where the editor cannot run (`JustGameEditorPlugin.supportsPlatform`). `JustGameEngineEditor` is then a plain `GameWidget`.
- **The `ignore_for_file` line** is there because `flutter_lints` reports a `lib/` import of a package that is only a dev dependency.
- **Spawners** are the game's own `Spawner` list. Play spawns through them, so the editor makes exactly the player the shipped game does.

## Run it

Run `flutter run -t lib/main_editor.dart -d windows` (or `macos`, `linux`), or `just game run --editor` in a project made with `just create`. Start it from the project folder: the editor reads and saves the project's own files, relative to the working directory.

## Hot reload

The editor runs in a debug build, so hot reload (**r**) and hot restart (**R**) work on it. A hot reload swaps the code but runs nothing again: not `main`, not a constructor. So after each reload the editor calls your `onReassemble`, where you hand over again what `main` did once (modules, spawners, systems added since launch). It then puts the component definitions in place again, including each `RefreshableExtension`'s, so a field you added shows in the inspector and is saved; rebuilds its docks, commands, prefabs and inspector sections from the modules; and brings live components up to a definition that changed.

Write what is built from code as a getter, not a `static final`, which is built once and kept: component definitions, prefabs, workspaces. Some changes still need a hot restart: a changed argument of a module or system that is already running, and the engine's configuration.

## Register your components

A component is described once, in the game, by a `ComponentDefinition`. That one description saves it, loads it in the shipped game, and builds its inspector section:

```dart lib/game/health.dart
import 'package:flutter/material.dart' show Icons;
import 'package:just_game_engine/just_game_engine.dart';

class MyHealthComponent extends Component {
  int maxHp = 3;
}

// A getter, so a hot reload builds it again from the code.
ComponentDefinition<MyHealthComponent> get myHealthDefinition =>
    ComponentDefinition(
      type: 'MyHealthComponent',
      create: MyHealthComponent.new,
      fields: [
        FieldDefinition(
          name: 'maxHp',
          kind: FieldTypes.integer,
          min: 0,
          read: (c) => (c as MyHealthComponent).maxHp,
          write: (c, v) => (c as MyHealthComponent).maxHp = v as int,
        ),
      ],
      // What the inspector shows. The game ignores it.
      hints: const ComponentHints(
        name: 'Health',
        group: 'Gameplay',
        icon: Icons.favorite,
        fields: {
          'maxHp': FieldHint(label: 'Max HP', scrub: ScrubHint(integer: true)),
        },
      ),
    );

// Registers the game's components on the engine it is given, and again,
// as the code now makes them, after a hot reload.
class MyGameExtension implements RefreshableExtension {
  const MyGameExtension();

  @override
  String get id => 'my_game';

  @override
  void install(EngineContext context) =>
      context.definitions.register(myHealthDefinition);

  @override
  void refresh(EngineContext context) =>
      context.definitions.refresh([myHealthDefinition]);
}
```

Give the extension to every engine the game makes, in `lib/main.dart` as well as in the editor entry point: `EngineConfig(extensions: [MyGameExtension()])`. A component with no registered definition is not shown, and is left out of the save with a warning in the log, because the shipped game could not load it. The engine has a `HealthComponent` of its own, so a game's component needs a type name of its own.

## Add an editor module

An `EditorModule` is where the editor's side of your game goes: prefabs, viewport tools, overlays, icons, checks and inspector editors for field types of your own. It lives in the editor entry point, or in a file only it imports, never in `lib/main.dart`'s imports:

```dart lib/editor/my_game_module.dart
import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import '../game/health.dart';

class MyGameModule extends EditorModule {
  @override
  String get id => 'my_game';

  @override
  String get name => 'My Game';

  // In every Level Designer, beside the editor's own shapes.
  @override
  List<PrefabDefinition> get sharedPrefabs => [
    PrefabDefinition(
      id: 'my_game.enemy',
      name: 'Enemy',
      category: 'Enemies',
      icon: Icons.bug_report,
      color: const Color(0xFFE57373),
      placement: PrefabPlacement.point,
      defaultSize: const Size(32, 32),
      build: (position, size) => [
        TransformComponent(position: Vector3(position.dx, position.dy, 0)),
        Rectangle2DComponent(width: size.width, height: size.height),
        MyHealthComponent(),
      ],
    ),
  ];
}
```

- **Prefabs** in `sharedPrefabs` appear in every Level Designer. Prefabs in `prefabs` make the module a Level Designer of its own, picked in the designer switch.
- **More contributions:** scene-tree icons (`entityIcons`), docks, toolbar buttons, settings pages, commands and key bindings, checks for the Problems dock, kinds of file for the Assets dock, and the tags its code relies on.
- **Lifecycle:** `onRegister` runs once and `onReassemble` after each hot reload. Everything a module contributes is rebuilt from it on every reload, so nothing piles up.
- **Built-ins:** the editor's own tools arrive the same way, as `BuiltInEditorModule`, `BuiltInMaterialsModule`, `BuiltInAssetStoreModule` (the Asset Store, for plugins, kits and assets) and, for a game with 3D graphics, `BuiltInGraphicsModule`. Kits and plugins build their modules on `just_editor_core`, which this package re-exports.

## Open the editor

Press **F1** at run time to show or hide the editor. The game viewport shifts left, and the right panel shows the scene tree, the inspector and the Scenes list.

With no scene open, the viewport shows a start card: New scene, Reopen the last scene, the steps to a saved level, and the tools that need no scene. New scene asks for a name and whether the scene is 2D or 3D, and writes the same starter scene as `just game scene new`: a camera and the player's spawn point, plus, in 2D, the bounds the camera keeps to. The Scenes list searches, sorts and reorders: dragging a scene, or Alt+Up/Down, sets the play order in `scenes.json`, and the first scene is where the game starts.

## A tour of the tools

- **Scenes and saving.** A scene is one file, `assets/scenes/<name>.scene.json`, and the game loads the same file through `SceneLoader`. **Ctrl+S** saves it and any map files it uses; saving during a play-test saves the level as authored, not as the game left it. Autosave runs every 2 minutes by default and keeps backups in `.editor_backups/<scene>/`; when a backup holds changes the file lacks, opening the scene offers to recover them. Older scene formats are migrated as they open, and the file changes only when you save.
- **Level Designer.** **F3**, or the map icon on the play toolbar, opens it. Its tool strip has Draw (B), Paint (P), Sample (I), Stamp (S), Fill (G), Terrain (T), Erase (D), Select tiles (V) and Measure (M). A scene has one Level Map: tiles on square, isometric, staggered and hexagonal grids, with a built-in Basic shapes tileset (blocks, slopes, a one-way plank and more, each colliding as drawn) to block out a level before there is art. Everything you place becomes an entity on one of the map's layers, and Tiled maps import and export. A 3D scene gets a 3D Level Designer with its own Default 3D kit.
- **Inspector.** It is built from each component's `ComponentDefinition`, with an editor for every field type, a colour picker, and tag and entity pickers. Physics bodies get one card for 2D and 3D alike: body type, material presets, Fit to visual, collider handles in the viewport, and collision layers picked by name and saved to `assets/project/physics.json`.
- **Play-testing.** **F5** plays in place, **F6** pauses, **F10** steps one frame and **Shift+F5** restarts, with speeds from a quarter to double. Play spawns at every spawn point through your spawners, the game's camera brain drives the view, and **Stop** puts every authored entity back exactly as it was. **F4** shows what the game camera frames while you work.
- **Timeline.** The Timeline dock edits timelines that animate any component field, with a dope sheet, a curve editor, record mode and motion paths drawn in the viewport. See [Timelines](/docs/timelines).
- **Materials.** 3D materials (`*.material.json`) and 2D materials (`*.material2d.json`) are pictured in the Assets dock, edited in a Material window with a live preview, presets and variants, and dropped on what they draw. The 3D previews need Flutter GPU switched on in the game's runner ([Installation](/docs/installation)); the 2D ones need nothing.
- **Docks.** One tabbed panel at the foot of the editor, opened and shut with **F2**: Console (Ctrl+Shift+C), Assets (Ctrl+Shift+A), Timeline (Ctrl+Shift+T), Profiler (Ctrl+Shift+P), World (Ctrl+Shift+W), Search (Ctrl+Shift+F), History (Ctrl+Shift+H), Problems (Ctrl+Shift+E), Tags, Physics Layers and Animator. Problems lists what is wrong with the open scene, many items with a one-click fix. Tabs reorder and pop out, and the layout is remembered.

## Key shortcuts

These are the defaults; change any of them in Settings (Ctrl+,) under Keyboard. On macOS, read Cmd wherever this page says Ctrl.

| Key | Action |
|---|---|
| `F1` | Show or hide the editor |
| `F2` | Open or shut the dock panel |
| `F3` | Open or close the Level Designer |
| `F4` | The game camera preview |
| `F5` / `Shift+F5` | Play or stop / restart |
| `F6`, `F10` | Pause or resume, step one frame |
| `Ctrl+S` | Save the scene |
| `Ctrl+Z` / `Ctrl+Shift+Z` or `Ctrl+Y` | Undo / redo |
| `Ctrl+C`, `Ctrl+V`, `Ctrl+D`, `Delete` | Copy, paste, duplicate, delete |
| `Q`, `W`, `E`, `R` | All, Move, Scale, Rotate |
| `F` / `Shift+F` | Frame the selection / everything |
| `Ctrl+Shift+G` | The Asset Store window |

## Platforms

- **The package compiles everywhere Flutter does**, so a game that imports it in its editor entry point still builds for Android, iOS and the web.
- **Editing runs on a desktop** (Windows, macOS or Linux), in a debug build launched from the project folder. On a phone, a tablet or the web the app has only its bundled, read-only assets, so `register` returns null and the game runs on its own.
- **macOS:** a sandboxed debug app cannot write the project folder. Set `com.apple.security.app-sandbox` to `false` in `macos/Runner/DebugProfile.entitlements`; the release entitlements stay as they are. The Asset Store window also needs `com.apple.security.network.client` there, which `just create` adds and `just doctor` checks. Cmd is the primary modifier, and Backspace deletes as Delete does.

## Asset Store, plugins and kits

A module reaches other projects inside a package. There are two kinds:

| Kind | What it brings | In the game's pubspec |
|---|---|---|
| Plugin | Tools for the editor only, such as a window, a dock or an asset editor. Nothing of it ships. | `dev_dependencies` |
| Kit | Game code and its editor half: components and systems the game runs, plus the prefabs, tools and inspector fields to place them. | `dependencies` |

- **From the Asset Store.** Ctrl+Shift+G opens the store window, to browse, install, update and remove items. In a terminal, `just add <id>`, `just remove <id>` and `just store list` do the same. The store adds the package to `pubspec.yaml` and rewrites `lib/editor/store_modules.g.dart` (the editor modules) and `lib/game/store_extensions.g.dart` (the kits' engine extensions), which a project made with `just create` already uses. Hot restart (**R**) the editor after installing code.
- **By hand.** Add the package to `pubspec.yaml`, add its module to `modules` in `lib/main_editor.dart`, and for a kit, give its engine extension to every engine the game makes, in `lib/main.dart` too. Import a package's editor library from `lib/main_editor.dart` only.

First-party modules include `PlatformerModule` (`just_platformer_kit`), `ThirdPersonModule` (`just_third_person_kit`), `WorldBuilderModule` (`just_world_builder_kit`), `SpriteStudioModule` (`just_sprite_editor`) and `InputEditorModule` (`just_input_editor`). The [editor's README](https://github.com/just-unknown-dev/just-game-engine-editor) explains how to make and publish a plugin or kit of your own.

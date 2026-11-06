# The just CLI

_Tools_ · Install just, create a game with it, and run, build, check, upgrade and migrate the game with the just game commands.

`just` is the Just ecosystem's command-line tool. It comes in two packages, and the [CLI overview](/cli) shows them side by side:

- **`just_core_cli`** is the tool itself. It knows no product of its own: it makes projects, keeps their tools on versions that work together, checks their setup, links them to local checkouts, changes them all or nothing, and runs the commands and hooks that plugins add.
- **`just_game_engine_cli`** is the game plugin. It adds `just game ...`: run the game and its editor, build releases that provably hold no editor, manage the levels, keep the engine's packages on versions that work together, and keep saved files in the current formats. Every game made with `just create` has it as a dev dependency, and `just` runs it at the version the project resolved.

## Install

```bash
dart pub global activate just_core_cli
just doctor
```

Or download `just` and `ju` for Windows, macOS or Linux from the [releases](https://github.com/just-unknown-dev/just-core-cli/releases). The install scripts in the repository's `tool/` folder (`install.sh` and `install.ps1`) do it for you, and never put this `just` in front of another one. Then `just doctor` checks Flutter, the tools' versions and the rest.

- **Projects pin their Flutter.** A game's `just.json` names the exact Flutter it is built with (`"flutter": "3.47.9"`), the one its engine release is made for, and its pubspec gets the matching range (`flutter: ">=3.47.1 <3.48.0"`). Every `just` command that runs Flutter uses that version: `just` finds it among the SDKs it installed (`~/.just/flutter/<version>`), `FLUTTER_ROOT`, the SDK that last fetched the project's packages, `flutter` on the `PATH` and fvm's SDKs, or installs it from Flutter's own downloads once you say so (`just sdk install`). `just upgrade` moves the pin with the game plugin. Why the pin: see "Flutter versions" in [Installation](/docs/installation).
- **Run Flutter and Dart through `just`.** `just flutter ...` and `just dart ...` use the project's Flutter. Plain `flutter` may be another version, and `just doctor` says when it is.
- **Flutter**, for a project that pins none, is found through `FLUTTER_ROOT` first, then the SDK that last fetched the project's packages, then `flutter` on the `PATH`.
- **Projects pin their own `just`.** A project lists `just_core_cli` in its dev dependencies, and a global `just` run inside it hands over to that version (all but `upgrade`, which moves the pin itself), so a team runs the same tool whatever each person installed.

## just and ju

`ju` is the same tool under a second name, for machines where `just` is already another program, such as the `just` command runner. Every command on this page works with `ju` too.

## Create a game

```bash
just create my_game
just create space_rocks --title "Space Rocks" --org com.mystudio --platforms windows,macos,web
```

The folder name becomes the Dart package name, so it must be a valid one. `create` runs `flutter create` with the Flutter the kind's plugin names (installing it when you say so), writes `just.json`, adds `just_core_cli` and the kind's plugin to the dev dependencies as pub.dev versions, fetches the packages, and hands the project to the plugin's `create` hook. For a game, that is `just game init`: the game template on the engine's version set, the first level, the editor (`just_game_engine_editor`, with `just_asset_store`) from pub.dev as dev dependencies, and Flutter GPU switched on for a 3D game. Plugins and kits come later, from the editor's Asset Store; the store also links `--local` checkouts and lays a store `--template` over the game. On a failure the folder is deleted when `create` made it, or emptied when it was there already, empty.

| Option | What it does |
|---|---|
| `--kind` | What to make. `game`, the default, is filled in by `just_game_engine_cli`. |
| `--template`, `-t` | What to start from, passed to the plugin: `empty` by default, or a template from the Asset Store. |
| `--title` | The project's name as people see it (default: from the folder). |
| `--org` | The reverse-domain organisation for app ids (default `com.example`). |
| `--platforms` | The platforms to create, separated by commas (default `windows,macos,linux,android,ios,web`). |
| `--local <folder>` | Points every `just_*` package in that folder at its checkout (`pubspec_overrides.yaml`), for working on the ecosystem itself. |
| `--source <catalog>` | Where the plugin finds a `--template`; repeat it for several catalogs. |

`just.json` holds the project's title, the tool set it is on and the Flutter it is built with (`flutter`). Its `entry.game` and `entry.editor` keys change where the game and the editor start; they default to `lib/main.dart` and `lib/main_editor.dart`.

## The game commands

| Command | What it does |
|---|---|
| `just game run` | Runs the game, or with `--editor` the game with the editor over it. |
| `just game build <platform>` | A release build, then a check that it holds no editor. |
| `just game scene ...` | Makes, lists, renames, deletes, orders, migrates and validates the scenes in `assets/scenes/`. |
| `just game check` | No editor code reachable from the game, and saved files in formats this engine reads. |
| `just game doctor` | Checks the game's setup. |
| `just game upgrade` | Moves the engine's packages in `pubspec.yaml` to the versions this plugin carries. |
| `just game migrate` | Rewrites old scenes, timelines and animator graphs in the current formats. |
| `just game mcp` | Serves the engine's docs and API, at the game's versions, to an AI assistant. |

`just help game build` shows any command's own help. Some examples:

```bash
just game run --editor                        # the editor, on this desktop
just game run --release                       # the game in release
just game build windows                       # build, then check it holds no editor
just game build web -- --wasm                 # anything after -- goes to flutter build
just game scene new cave --after level_01     # a level, as the editor's New scene writes it
just game scene order level_01 cave           # the play order; the first is where the game starts
just game check release-build --platform web  # check an existing release build
just game upgrade --check                     # what the engine's packages would move to
just game migrate --check                     # whether old files could be migrated now
```

### run

- `--editor` (`-e`) runs `lib/main_editor.dart`, on this desktop unless `--device` says otherwise. The editor runs in debug builds only, so `--editor` with `--release` or `--profile` is refused.
- `--device` (`-d`), `--profile` and `--release` go to `flutter run`, as does anything after `--`. The command hands the terminal to `flutter run` and exits with its code.

### build

- `just game build <platform>` first checks that no editor code is reachable from `lib/main.dart`, then runs `flutter build <platform> --release`, then reads the build's files for editor code and, in a 2D game, 3D physics.
- The build check reads `windows`, `macos`, `linux` and `web` builds (the JavaScript, and the WebAssembly from a `--wasm` build). Other platforms, such as `apk` or `ios`, are checked through their source only.
- `--editor-entry` builds `lib/main_editor.dart` instead: its release build must be the game, with no editor in it.

### scene

- `list` shows the play order first, then any scene not in it.
- `new [<name>]` makes a scene as the editor does, with a camera and a player spawn. `--3d` makes a 3D scene, `--after <scene>` places it in the play order, and `--unlisted` leaves it out. With no name, one is suggested.
- `rename <old> <new>` renames the file, the name inside, and its place in the play order.
- `delete <name>` puts a copy in `.editor_trash/scenes/` and takes the scene out of the play order.
- `order <name>...` sets the play order. A scene left out stays on disk, unlisted.
- `migrate [<name>...]` rewrites scenes saved in an older format in the current one (`SceneFormat.current`). `--engine-only` goes ahead with the engine's rules alone, though a kit may have its own.
- `validate [<name>...]` checks scenes without changing them: they parse, their format is readable, entity names are unique and parents exist.

Commands that write refuse while the editor has the project open, because it would save over the change. Close the editor, make the change in it, or pass `--force`.

### check, doctor, upgrade and migrate

- **`check [release-imports] [release-build] [formats]`** runs the checks named, or `release-imports` and `formats` when none is named. `--platform` picks the build `release-build` reads: `windows`, `macos`, `linux` or `web` (default: this desktop).
- **`doctor`** checks that the editor entry point keeps the editor to debug builds, that the game imports no editor and ships no editor package, the git ignores for `.editor_backups/`, `.editor_logs/` and `.editor_trash/`, the macOS network entitlement for the Asset Store, Flutter and Dart against the engine's floors, the engine's packages against the version set, and store items linked to checkouts that are gone.
- **`upgrade`** makes one-line bumps of the engine's packages in `pubspec.yaml` to the plugin's version set. A package already as new as the set, or newer, stays. It runs no `pub get`, and `--check` only says what would move. You normally run it through `just upgrade`.
- **`migrate`** rewrites scenes, timelines and animator graphs saved in an older format. `--check` changes nothing and fails, saying why, when a migration could not run now; `--engine-only` goes ahead with the engine's rules alone though a kit may have its own; `--force` goes ahead though the editor is open.

### mcp

`just game mcp` is an MCP server on stdin and stdout. An AI assistant starts it; you don't run it yourself. A new game's `.mcp.json` (Claude Code) and `.vscode/mcp.json` (VS Code) start it, and its `AGENTS.md` tells the assistant how the game is built. For an older game, add that config:

```json .mcp.json
{
  "mcpServers": {
    "just_game_engine": { "command": "just", "args": ["game", "mcp"] }
  }
}
```

Its tools only read:

- `search_docs`, `read_doc` and `get_api` serve these guides, the packages' notes and their public API, at the versions the game resolved: the signature and import of a class or member, and what replaces a deprecated one.
- `project_info`, `list_scenes`, `validate_scenes` and `check_game` report the game's packages, its scenes and its setup, as `scene list`, `scene validate`, `doctor` and `check` do.

## Project commands

These come from `just_core_cli` and run each plugin's hooks:

- **`just check`** runs every installed plugin's checks, and fails when nothing was checked.
- **`just doctor`** checks Flutter, the tools, `just.json` and links, then each plugin's checks.
- **`just upgrade`** moves the tools, then each plugin's packages, with `pub get`, in one transaction, then runs the plugins' migrations. Anything after `--` goes to them: `just upgrade -- --engine-only`.
- **`just dev link <folder>`** points the project at local checkouts; **`just dev unlink`** undoes it.
- **`just flutter ...`** and **`just dart ...`** run the project's Flutter and Dart. **`just sdk list`** lists the Flutter SDKs `just` installed and the others it can use, **`just sdk install`** installs the one the project pins, and **`just sdk path`** prints its folder.
- **`just version`** and **`just help`**.

The Asset Store is a plugin too: it adds `just store`, `just add` and `just remove` ([Level editor](/docs/editor)).

## Hooks

The game plugin's `just_plugin.json` gives `just` six hooks:

| Hook | Command | When |
|---|---|---|
| `create` | `game init` (hidden) | `just create` made a Flutter project: lay the game template over it with the editor from pub.dev in the dev dependencies, link `--local` store items or lay a store `--template`, switch Flutter GPU on for a 3D game |
| `check` | `game check` | `just check`: release imports and saved formats |
| `doctor` | `game doctor` | `just doctor`: the game's setup |
| `upgrade` | `game upgrade` | `just upgrade`, inside its transaction: bump the engine's packages |
| `migrate` | `game migrate` | `just upgrade`: with `--check` before it changes anything, again with the new packages before it commits, then for real |
| `link` | `game link` (hidden) | after `just dev link`, and around `just dev unlink`: register Asset Store items among the checkouts |

## Global flags and exit codes

Every command takes these, before or after its name but before a `--`:

- `--json`: one JSON document on stdout, messages on stderr.
- `--yes`: go ahead without asking, for scripts and CI. It never allows a plugin that is not trusted.
- `--verbose`: say more.
- `--project <folder>`: run on that project. A folder without a `pubspec.yaml` is no project.

| Code | Meaning |
|---|---|
| 0 | Done, or nothing to do. |
| 1 | Failed. A change that fails is rolled back first. |
| 2 | Called wrongly: an unknown command, a missing argument or a bad option. |
| other | A plugin's command, or a run handed to the project's pinned `just`, exits with that process's code; a process ended by a signal gives 128 plus the signal's number. |

Two steps come after a change is kept, and a failure there exits 1 while keeping it: a plugin's migrations at the end of `just upgrade`, and a plugin's `link` hook after `just dev link` or `unlink`. The message says which.

## Transactions and the trash

- **All or nothing.** Every change to a project is journalled and backed up first. A failure puts every byte back, and a crash is rolled back the next time a command changes the project.
- **One change at a time.** A project lock says who holds it, and is taken over when its holder stops renewing it or has stopped running.
- **The trash.** What a change replaces or removes goes to `.just_trash/<tool>/`, unless the tool keeps its own. The game commands and the Asset Store use the editor's `.editor_trash/`, so you can restore from the editor.
- **Pubspecs keep every other byte.** A tool edits only its own marked block of `pubspec.yaml`, and leaves comments, order and line endings as they were.
- **Plugin trust.** The ecosystem's own plugins run without asking when they come from a local checkout, from github.com/just-unknown-dev, or from pub.dev under the names the ecosystem publishes there (`just_game_engine_cli` and `just_asset_store`). Any other plugin is asked about once in a terminal, and the answer is kept in the project's `just.json` or your user `plugins.json`.

## As a library

`package:just_game_engine_cli/just_game_engine_cli.dart` holds the toolkit the commands use, for a game's own scripts and tests. A script that reads a game on disk:

```dart tool/check_release.dart
import 'package:just_game_engine_cli/just_game_engine_cli.dart';

void main() {
  final project = JustProject('.');
  final rules = project.releaseRules(); // the editor's packages + each store item's
  // Throws ReleaseImportsUnchecked when the walk could not look everywhere.
  final reachable = project.editorReachableFrom('lib/main.dart', rules: rules);
  if (reachable.isNotEmpty) throw StateError('The editor would ship: $reachable');
}
```

- **On every platform, the web included**, the text-based checks work: `GameSet` (the engine's packages at versions that work together), `GameTemplate`, `GameEntries`, `ReleaseRules`, `ReleaseImports`, `ReleaseBuild` and `FormatsCheck`.
- **Where `dart:io` is**, the `ProjectGame` extension on `JustProject` reads a game on disk: `releaseRules()`, `editorReachableFrom()`, `checkReleaseBuild()`, `checkFormats()` and `editorIsOpen()`. `editorReachableFrom()` throws `ReleaseImportsUnchecked` when it could not look everywhere (no entry point, packages never fetched, an import of a file that isn't there), rather than report nothing reachable.
- **To write a plugin of your own**, build on `just_core_cli`: a package with a `just_plugin.json` and a `bin/just_plugin.dart` adds commands. Its repository has an example plugin that adds `just hello`.

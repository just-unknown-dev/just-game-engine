# Contributing to Just Game Engine

Thank you for your interest in contributing to **Just Game Engine**. Bug fixes, features, tests and documentation are all welcome.

---

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Reporting Bugs and Suggesting Features](#reporting-bugs-and-suggesting-features)
- [Development Setup](#development-setup)
- [Working Against Unpublished Dependencies](#working-against-unpublished-dependencies)
- [Running the Tests](#running-the-tests)
- [Coding Guidelines](#coding-guidelines)
- [Submitting a Pull Request](#submitting-a-pull-request)
- [Commit Message Convention](#commit-message-convention)
- [License](#license)

---

## Code of Conduct

This project follows our [Code of Conduct](CODE_OF_CONDUCT.md). By taking part you agree to its terms. Please report unacceptable behaviour to the maintainers.

---

## Reporting Bugs and Suggesting Features

Before opening an issue, search the [existing issues](https://github.com/just-unknown-dev/just-game-engine/issues) and check that the problem happens on the latest version.

A bug report should have:

- a clear title;
- steps to reproduce, and what you expected instead of what happened;
- the output of `flutter --version`, and the platform (Android, iOS, Linux, macOS, Windows, web; for the web, whether it was a JavaScript or a WebAssembly build);
- a minimal code sample, or a link to a repository that shows the problem.

For a feature, open an issue labelled **`enhancement`** that describes the problem it solves and how it should behave. The engine's scope is games in Flutter: 2-D, with 3-D graphics and physics to opt into. For a large change, open the issue first so the approach can be agreed before you write it.

---

## Development Setup

| Tool | Minimum version |
|------|-----------------|
| Flutter | 3.47.1 |
| Dart | 3.13 (comes with Flutter 3.47) |

This repository **is** the `just_game_engine` package. There is no app to run here: you work on the package, its tests and `example/example.dart`. To try a change in a real game, add the engine to a Flutter app as a path dependency (`path: ../just-game-engine`).

```bash
git clone https://github.com/just-unknown-dev/just-game-engine.git
cd just-game-engine
flutter pub get
flutter test
```

---

## Working Against Unpublished Dependencies

The engine depends on several `just_*` packages from pub.dev: `just_physics_engine`, `just_graphics_engine`, `just_game_engine_formats`, `just_inputs`, `just_audio_engine`, `just_storage`, `just_database`, `just_signals`, `just_memory`, `just_tiled`, `just_deflate` and `just_dart`. `just_game_engine_formats` (the saved file formats and their migrations) is the one most likely to need a local override, since a new scene format lands there first. When a change needs an unreleased version of one of them, check that package out next to this repository and point the engine at it with a `pubspec_overrides.yaml` in the repository root:

```yaml
# pubspec_overrides.yaml — local only; .gitignore keeps it out of commits.
dependency_overrides:
  just_inputs:
    path: ../just_inputs
  # A dependency of a dependency is overridden the same way:
  just_gamepads:
    path: ../just_gamepads
```

Then run `flutter pub get`. Delete the file (or the entry) and run `flutter pub get` again to go back to the published versions.

Do not change `pubspec.yaml` to a path dependency. If your pull request needs a version of a dependency that is not published yet, say which one in the pull request: the engine can only be released after it.

---

## Running the Tests

Run every command from the repository root. Some tests read `lib/` from disk and expect that working directory.

Tests sit in the folder named after the feature they test, as in `lib/src/` (`test/timeline/` tests `lib/src/timeline/`); `test/perf/` holds the timing checks, and only the tests about the whole package (the public library, the guides, the process-state guard) sit in `test/` itself. Put a new test in its feature's folder, and name it after what it tests (`timeline_playback_test.dart`), not after the review that found the bug; a test of several fixes from one review is `<feature>_audit_fixes_test.dart`.

```bash
# The whole suite (the timings and the GPU tests are skipped: see below).
flutter test

# One file.
flutter test test/core/engine_lifecycle_test.dart

# The 2-D engine alone, without the 3-D tests.
flutter test -x physics3d -x graphics3d
```

The tags are declared in `dart_test.yaml`: `physics3d` and `graphics3d` (the 3-D tests), `gpu` (tests that draw with Flutter GPU) and `perf` (timings).

**The GPU tests.** `test/graphics/graphics_3d/engine_gpu_test.dart` and `shapes_gpu_test.dart` draw real pixels through Flutter GPU, and skip themselves when it is not switched on, so a plain `flutter test` reports them as skipped. Run them, on a machine with a GPU, whenever you change the 3-D renderer, the scene renderer, 3-D shapes or materials, and before a release:

```bash
flutter test --enable-impeller --enable-flutter-gpu --tags gpu
```

That runs four tests; all four must pass and none may be skipped. A skip means Flutter GPU did not start, and the tests proved nothing.

**The process-state guard.** `test/no_process_state_test.dart` fails when a `static` field that is not `const`, or a top-level variable, appears under `lib/src` and is not on the test's allow-list. A static field is shared by every engine and every test in the process, so per-engine state belongs in `EngineContext` (a registry, or `context.slot(...)` for a package's own state) and per-world state in `World`. Add a field to the allow-list only when it really is immutable, and write down why next to it.

```bash
flutter test test/no_process_state_test.dart
```

**The timings.** Tests tagged `perf` time something against a wall clock, so `dart_test.yaml` skips them in a plain `flutter test`: on a busy machine they fail for no reason. `test/perf/transform_hot_path_test.dart` times the paths that touch every transform every frame and prints lines such as `PERF shapes10k: … ms/frame` and `PERF physics2k: … ms/frame`; `test/perf/performance_test.dart` holds further timing checks (engine start-up, rendering, physics, particles, ECS queries, the frame scheduler), and `test/perf/physics_3d_perf_test.dart` the 3-D physics ones. They assert only generous ceilings. For a change to rendering, the ECS core, physics sync or the transform hierarchy, run them before and after the change on the same machine and put both numbers in the pull request:

```bash
flutter test --tags perf --run-skipped
```

---

## Coding Guidelines

- **Formatting.** Code is formatted with `dart format`. This must report no changes:

  ```bash
  dart format --output=none --set-exit-if-changed lib example
  ```

  Format the test files you add or change too. Some older test files are not formatted yet; format them in a pull request of their own, not mixed into a change.

- **Analysis.** `flutter analyze` must report no issues at all — errors, warnings or infos. The rules are in `analysis_options.yaml`: `flutter_lints` plus a few additions.
- **Web and WebAssembly.** The engine runs on every Flutter platform, including web builds compiled to JavaScript and to WebAssembly. Nothing in `lib/` may import `dart:io` or `dart:html` directly. Platform-specific code goes in a pair of files chosen by a conditional import, the way `lib/src/storage/engine_storage.dart` picks its storage:

  ```dart
  import 'engine_storage_web.dart'
      if (dart.library.io) 'engine_storage_io.dart'
      as platform;
  ```

  Today `lib/src/storage/engine_storage_io.dart` is the only file that imports `dart:io`. Check with `grep -rnE "import 'dart:(io|html)'" lib` before you open a pull request.
- **No process-wide state.** See the guard above: keep state in `EngineContext` or `World`, never in a mutable `static` field.
- **Documentation.** Give every public API you add a `///` doc comment. If you add, rename or remove a public type, update [API.md](API.md), and describe user-visible changes in [CHANGELOG.md](CHANGELOG.md).
- **Tests.** Add or update tests for any behaviour you change.
- **Dependencies.** Do not add a dependency without discussing it in an issue first.
- **Structure.** Match the existing folders under `lib/src/` (one per feature; see [ARCHITECTURE.md](ARCHITECTURE.md) §2). Export a new file from its folder's barrel (`lib/src/<feature>/<feature>.dart`), which `lib/just_game_engine.dart` exports — never from `lib/just_game_engine.dart` directly. 3-D API goes through `lib/just_game_engine_3d.dart`, so 2-D builds carry no 3-D code; optional screen widgets go through `lib/widgets.dart`. Other code imports those libraries, not files under `lib/src/`.

---

## Submitting a Pull Request

1. Create a topic branch from `main`:
   ```bash
   git checkout -b feat/my-new-feature
   ```
2. Make your change, following the [Coding Guidelines](#coding-guidelines).
3. Check that everything passes:
   ```bash
   dart format --output=none --set-exit-if-changed lib example
   flutter analyze
   flutter test
   ```
4. Commit with a [conventional commit message](#commit-message-convention).
5. Push to your fork and open a pull request against `main`. Say what changed and why, and list any unpublished dependency versions it needs.
6. Answer review feedback.

Small pull requests are easier to review.

---

## Commit Message Convention

We use [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <short summary>
```

| Type | When to use |
|------|-------------|
| `feat` | New feature |
| `fix` | Bug fix |
| `docs` | Documentation only |
| `refactor` | Code change that neither fixes a bug nor adds a feature |
| `perf` | Performance improvement |
| `test` | Adding or updating tests |
| `chore` | Build process, tooling, dependencies |

**Examples:**
```
feat(physics): add mass-proportional collision resolution
fix(rendering): correct camera transform for non-square viewports
docs(contributing): explain pubspec_overrides.yaml
```

---

## License

By contributing to Just Game Engine you agree that your contributions will be licensed under the [BSD-3-Clause License](LICENSE).

/// Where the engine keeps its settings and cache entries — not exported.
///
/// The folder of the engine's file is found by a plugin that needs the
/// VM's file system. It is reached only through `engine_storage_io.dart`,
/// behind the conditional import below (on `dart.library.io`), so a web
/// build never imports it and everything else in the engine stays free of
/// the VM's io library — WASM-ready.
library;

import 'package:just_storage/just_storage.dart';

import 'engine_storage_web.dart'
    if (dart.library.io) 'engine_storage_io.dart'
    as platform;

/// Opens the engine's own key-value store.
///
/// On desktop and mobile it is a file of its own,
/// `<application support>/just_game_engine/just_storage.json` — beside the
/// `just_storage.json` that app code opens with `JustStorage.standard()`,
/// not in it. `just_storage` rewrites a whole file from the copy an
/// instance loaded, so two instances on one file drop each other's keys.
///
/// On the web it is browser storage under the engine's own key prefix:
/// there each value is a key of its own, and nothing is rewritten whole.
Future<JustStandardStorage> openEngineStorage() => platform.openEngineStorage();

/// Opens the store the engine shared with the app before 2.0 —
/// `JustStorage.standard()` — for moving the engine's entries out of it.
Future<JustStandardStorage> openSharedStorage() => JustStorage.standard();

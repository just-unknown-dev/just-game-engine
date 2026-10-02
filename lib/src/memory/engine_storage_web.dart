/// The engine's store where there is no file system — the web: browser
/// storage under the engine's own key prefix — not exported.
library;

import 'package:just_storage/just_storage.dart';

import 'namespaced_storage.dart';

/// `JustStorage.standard()` (browser `localStorage`, where each value is a
/// key of its own) with every key under [engineStorageNamespace].
Future<JustStandardStorage> openEngineStorage() async =>
    engineNamespaceOf(await JustStorage.standard());

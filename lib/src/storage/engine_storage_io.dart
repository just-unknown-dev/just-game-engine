/// The engine's store on desktop and mobile: a file of its own — not
/// exported.
///
/// The one file in the engine that imports `dart:io` (and
/// `package:path_provider`). `engine_storage.dart` reaches it only through
/// a conditional import on `dart.library.io`, so web builds never see it.
library;

import 'dart:io';

import 'package:just_storage/just_storage.dart';
import 'package:meta/meta.dart' show internal;
import 'package:path_provider/path_provider.dart';

/// The folder, in the app's support directory, that holds the engine's
/// `just_storage.json`.
@internal
const String engineStorageFolder = 'just_game_engine';

/// `<application support>/just_game_engine/just_storage.json`.
@internal
Future<JustStandardStorage> openEngineStorage() async {
  final support = await getApplicationSupportDirectory();
  return JustStorage.standard(
    Directory('${support.path}${Platform.pathSeparator}$engineStorageFolder'),
  );
}

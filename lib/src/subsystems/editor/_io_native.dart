// Native (dart:io) implementation of the thin file-IO helpers used by
// SceneEditor.  This file is selected by the conditional import in
// scene_editor.dart on every platform except web.
import 'dart:io';

/// Write [contents] to the file at [path], creating it if necessary.
void writeFile(String path, String contents) =>
    File(path).writeAsStringSync(contents);

/// Read the contents of the file at [path].
String readFile(String path) => File(path).readAsStringSync();

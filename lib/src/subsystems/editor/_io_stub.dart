// Web stub for the file-IO helpers used by SceneEditor.  Selected by the
// conditional import when dart.library.html is available.
void writeFile(String path, String contents) => throw UnsupportedError(
  'SceneEditor.saveScene: file I/O is not supported on web.',
);

String readFile(String path) => throw UnsupportedError(
  'SceneEditor.loadSceneFromFile: file I/O is not supported on web.',
);

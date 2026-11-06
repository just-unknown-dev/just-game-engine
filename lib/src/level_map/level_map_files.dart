/// What a level map's own file is called.
library;

/// The names of map files.
///
/// A map kept out of the scene is saved as [suffix]. Files saved before the
/// Level Map rename end in [legacySuffix] and are still read — never written.
abstract final class LevelMapFiles {
  /// What a map file is saved as.
  static const String suffix = '.map.json';

  /// What map files were saved as before; still read.
  static const String legacySuffix = '.tilemap.json';

  /// Whether [path] is a map file of the engine's own, of either name.
  static bool isMapFile(String path) {
    final p = path.toLowerCase();
    return p.endsWith(suffix) || p.endsWith(legacySuffix);
  }

  /// [path]'s file name without its folder or its map ending: what a map is
  /// named after.
  static String stem(String path) {
    final name = path.substring(
      path.replaceAll('\\', '/').lastIndexOf('/') + 1,
    );
    final lower = name.toLowerCase();
    // The longer first: '.tilemap.json' also ends in 'map.json'.
    for (final ending in const [legacySuffix, suffix]) {
      if (lower.endsWith(ending)) {
        return name.substring(0, name.length - ending.length);
      }
    }
    return name;
  }
}

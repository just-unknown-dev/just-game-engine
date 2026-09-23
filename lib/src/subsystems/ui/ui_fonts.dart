/// Fonts a game drops into its assets, loaded while it runs.
///
/// Flutter normally wants every family declared in `pubspec.yaml`, which
/// means editing a build file — and restarting — to try a font. A font
/// loaded here works the moment it is on disk, so the editor can offer
/// whatever is in `assets/fonts/` and a scene can name it.
library;

import 'package:flutter/services.dart';

abstract final class UiFonts {
  /// Families that are ready to draw with.
  static final Set<String> _loaded = {};

  /// Loads in flight, so asking twice does not read the file twice.
  static final Map<String, Future<void>> _loading = {};

  /// Where the bytes come from. A tool points this at the project's files;
  /// a game reads its bundle.
  static Future<ByteData> Function(String path) read = rootBundle.load;

  /// The families loaded so far.
  static List<String> get families => _loaded.toList()..sort();

  static bool isLoaded(String family) => _loaded.contains(family);

  /// Makes [family] drawable from [paths] — one file per weight or style.
  ///
  /// Returns once it can be drawn with. Asking again is free, so a widget
  /// may call this in its build without thinking.
  static Future<void> ensureLoaded(String family, List<String> paths) {
    if (family.isEmpty || paths.isEmpty || _loaded.contains(family)) {
      return Future.value();
    }
    return _loading[family] ??= _load(family, paths);
  }

  static Future<void> _load(String family, List<String> paths) async {
    try {
      final loader = FontLoader(family);
      for (final path in paths) {
        loader.addFont(read(path));
      }
      await loader.load();
      _loaded.add(family);
    } catch (_) {
      // A font that will not load leaves text in the fallback family —
      // worth a line in the Problems dock, never worth a crash mid-frame.
    } finally {
      _loading.remove(family);
    }
  }

  /// Forgets what has been loaded. Flutter keeps the glyphs, so this is for
  /// tests and for an editor reloading a font that changed on disk.
  static void reset() {
    _loaded.clear();
    _loading.clear();
  }

  /// The family a font file is named for: `assets/fonts/PressStart2P.ttf`
  /// is `PressStart2P`, and `Inter-Bold.ttf` is `Inter`.
  ///
  /// How the editor turns a folder of files into a list of families, and
  /// how several weights land under one name.
  static String familyOf(String path) {
    final file = path.split('/').last.split('\\').last;
    final dot = file.lastIndexOf('.');
    final stem = dot < 0 ? file : file.substring(0, dot);
    final dash = stem.indexOf('-');
    final name = dash <= 0 ? stem : stem.substring(0, dash);
    return name.replaceAll('_', ' ').trim();
  }

  /// Groups font files by the family they belong to.
  static Map<String, List<String>> familiesIn(Iterable<String> paths) {
    final out = <String, List<String>>{};
    for (final path in paths) {
      final lower = path.toLowerCase();
      if (!lower.endsWith('.ttf') &&
          !lower.endsWith('.otf') &&
          !lower.endsWith('.ttc')) {
        continue;
      }
      out.putIfAbsent(familyOf(path), () => []).add(path);
    }
    for (final files in out.values) {
      files.sort();
    }
    return out;
  }

  /// Loads every family under [paths] — what a game calls at boot with the
  /// contents of its fonts folder.
  static Future<void> loadAll(Iterable<String> paths) async {
    final families = familiesIn(paths);
    await Future.wait([
      for (final entry in families.entries)
        ensureLoaded(entry.key, entry.value),
    ]);
  }
}

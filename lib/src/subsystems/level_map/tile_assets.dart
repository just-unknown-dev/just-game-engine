/// Where tilesets and map files come from.
library;

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:just_tiled/just_tiled.dart' as tiled;

import 'built_in_tilesets.dart';
import 'level_map_data.dart';
import 'tiled/tiled_interop.dart';
import 'tileset_data.dart';

/// Loads tilesets (`.tileset.json`) and map files (`.map.json` or `.tilemap.json`, and
/// Tiled's `.tmx` / `.tmj`), and keeps what it loaded.
///
/// The game reads the asset bundle. An authoring tool replaces [readText]
/// with one that reads the project's files — a tileset saved a second ago
/// is not in the bundle yet — and calls [evict] when a file changes.
///
/// A Tiled map's tilesets have no file of their own in the engine's form;
/// they are kept under `<map path>#<index>`, which is what the map loaded
/// from it names them by. The engine's own tilesets ([BuiltInTilesets])
/// have none either: they are always there, whatever is cleared.
abstract final class TileAssets {
  /// Reads a text file. The bundle by default.
  static Future<String> Function(String path) readText = _fromBundle;

  static Future<String> _fromBundle(String path) =>
      rootBundle.loadString(path, cache: false);

  /// Back to the asset bundle, forgetting everything loaded.
  static void useBundle() {
    readText = _fromBundle;
    clear();
  }

  static final Map<String, Future<TilesetData>> _tilesetLoads = {};
  static final Map<String, TilesetData> _tilesets = {};
  static final Map<String, Future<LevelMapData>> _mapLoads = {};
  static final Map<String, LevelMapData> _maps = {};

  /// Bumped whenever something loaded is forgotten or replaced, so whoever
  /// drew with it knows to look again.
  static int revision = 0;

  /// Whether [path] names no file: a built-in tileset or picture, or a
  /// tileset kept inside a Tiled map. Nothing should look for it on disk.
  static bool isVirtual(String path) =>
      path.contains('#') || BuiltInTilesets.isBuiltIn(path);

  /// The tileset at [path], loaded once.
  static Future<TilesetData> tileset(String path) {
    final builtIn = BuiltInTilesets.tileset(path);
    if (builtIn != null) return Future.value(builtIn);
    final ready = _tilesets[path];
    if (ready != null) return Future.value(ready);
    return _tilesetLoads.putIfAbsent(path, () async {
      final ts = TilesetData.fromJson(
        jsonDecode(await readText(path)) as Map<String, dynamic>,
      );
      _tilesets[path] = ts;
      return ts;
    });
  }

  /// The tileset at [path] if it has loaded, without waiting.
  static TilesetData? loadedTileset(String path) =>
      BuiltInTilesets.tileset(path) ?? _tilesets[path];

  /// Makes [tileset] what [path] loads as — an editor's live copy, or a
  /// tileset that came inside a Tiled map.
  static void putTileset(String path, TilesetData tileset) {
    if (BuiltInTilesets.isBuiltIn(path)) return;
    _tilesets[path] = tileset;
    _tilesetLoads[path] = Future.value(tileset);
    revision++;
  }

  /// The map file at [path], loaded once and shared: whoever changes one
  /// changes a copy.
  static Future<LevelMapData> map(String path) =>
      _mapLoads.putIfAbsent(path, () async {
        final lower = path.toLowerCase();
        final map = lower.endsWith('.tmx') || lower.endsWith('.tmj')
            ? await _loadTiled(path)
            : LevelMapData.fromJson(
                jsonDecode(await readText(path)) as Map<String, dynamic>,
              );
        return _maps[path] = map;
      });

  /// The map file at [path] if it has loaded, without waiting — the
  /// document an editor edits in place.
  static LevelMapData? loadedMap(String path) => _maps[path];

  /// Makes [map] what [path] loads as: a map just written to that file.
  static void putMap(String path, LevelMapData map) {
    _maps[path] = map;
    _mapLoads[path] = Future.value(map);
    revision++;
  }

  static Future<LevelMapData> _loadTiled(String path) async {
    final text = await readText(path);
    final dir = directoryOf(path);
    final provider = _Provider(dir);
    final parsed = path.toLowerCase().endsWith('.tmj')
        ? await tiled.TmjParser.parse(text, tsxProvider: provider)
        : await tiled.TileMapParser.parse(text, tsxProvider: provider);
    final result = TiledInterop.importMap(
      parsed,
      tilesetPath: (i, _) => '$path#$i',
      imagePath: (ts) {
        // Relative to the tileset's own file when it has one.
        final base = ts.source == null
            ? dir
            : directoryOf(join(dir, ts.source!));
        return join(base, ts.imageSource ?? '');
      },
    );
    for (var i = 0; i < result.tilesets.length; i++) {
      final ts = result.tilesets[i];
      if (ts != null) putTileset('$path#$i', ts);
    }
    return result.map;
  }

  /// Forgets [path] — or everything — so it is read again.
  static void evict([String? path]) {
    if (path == null) {
      clear();
      return;
    }
    _tilesets.remove(path);
    _tilesetLoads.remove(path);
    _mapLoads.remove(path);
    _maps.remove(path);
    // A Tiled map's tilesets go with it.
    _tilesets.removeWhere((key, _) => key.startsWith('$path#'));
    _tilesetLoads.removeWhere((key, _) => key.startsWith('$path#'));
    revision++;
  }

  /// Forgets everything.
  static void clear() {
    _tilesets.clear();
    _tilesetLoads.clear();
    _mapLoads.clear();
    _maps.clear();
    revision++;
  }

  /// The folder [path] is in, with no trailing slash.
  static String directoryOf(String path) {
    final p = path.replaceAll('\\', '/');
    final i = p.lastIndexOf('/');
    return i < 0 ? '' : p.substring(0, i);
  }

  /// [relative] resolved against [dir]: `..` and `.` worked out, forward
  /// slashes only.
  static String join(String dir, String relative) {
    final r = relative.replaceAll('\\', '/');
    if (r.startsWith('/') || dir.isEmpty) return _normalise(r);
    return _normalise('$dir/$r');
  }

  static String _normalise(String path) {
    final out = <String>[];
    for (final part in path.split('/')) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..' && out.isNotEmpty && out.last != '..') {
        out.removeLast();
      } else {
        out.add(part);
      }
    }
    return out.join('/');
  }
}

class _Provider implements tiled.TsxProvider {
  _Provider(this.dir);
  final String dir;

  @override
  Future<String> getTsx(String source) =>
      TileAssets.readText(TileAssets.join(dir, source));

  @override
  Future<String> getTemplate(String source) =>
      TileAssets.readText(TileAssets.join(dir, source));
}

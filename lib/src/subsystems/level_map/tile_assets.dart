/// Where tilesets and map files come from.
library;

import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:just_tiled/just_tiled.dart' as tiled;

import 'built_in_tilesets.dart';
import 'collision/map_collision_kinds.dart';
import 'level_map_data.dart';
import 'tiled/tiled_interop.dart';
import 'tileset_data.dart';

/// Reads a text file by path.
typedef TextReader = Future<String> Function(String path);

/// Loads tilesets (`.tileset.json`) and map files (`.map.json` or
/// `.tilemap.json`, and Tiled's `.tmx` / `.tmj`), and keeps what it loaded.
///
/// One per engine: `engine.context.tiles` (`world.context.tiles`). The game
/// reads the asset bundle. An authoring tool replaces [readText] with one
/// that reads the project's files — a tileset saved a second ago is not in
/// the bundle yet — and calls [evict] when a file changes; another engine
/// in the same process is not affected.
///
/// A Tiled map's tilesets have no file of their own in the engine's form;
/// they are kept under `<map path>#<index>`, which is what the map loaded
/// from it names them by. The engine's own tilesets ([BuiltInTilesets])
/// have none either: they are always there, whatever is cleared, and their
/// pictures ([builtInImage]) are drawn once and disposed with this.
///
/// A file that will not load — missing, unreadable, or saved by a newer
/// engine — is reported once through [log], and its failure is kept: asked
/// for again, it fails again at once instead of being read again, until it
/// is evicted ([evict], [clear]) or replaced ([putMap], [putTileset]).
///
/// What is loaded stays loaded until it is evicted. A game that moves from
/// level to level can let go of what the next level does not use with
/// `LevelMaps.evictUnused` (or [retainOnly]).
final class TileAssets {
  /// Tile assets read through [readText]; a Tiled map's collision classes
  /// are matched against [collisionKinds] (the engine's own when null).
  TileAssets({required this.readText, MapCollisionKinds? collisionKinds})
    : collisionKinds = collisionKinds ?? MapCollisionKinds.builtIn;

  /// The kinds a Tiled map's collision shapes may name.
  final MapCollisionKinds collisionKinds;

  /// Reads a text file. The context's bundle by default.
  TextReader readText;

  /// Where a map, tileset or tileset image that would not load is reported,
  /// once per path until it is evicted. `debugPrint` by default; a game can
  /// send it to its own log.
  void Function(String message) log = _debugLog;

  static void _debugLog(String message) => debugPrint(message);

  final Map<String, Future<TilesetData>> _tilesetLoads = {};
  final Map<String, TilesetData> _tilesets = {};
  final Map<String, Future<LevelMapData>> _mapLoads = {};
  final Map<String, LevelMapData> _maps = {};

  /// The built-in tilesets and their pictures, made when first asked for.
  final Map<String, TilesetData> _builtIn = {};
  final Map<String, ui.Image> _builtInImages = {};

  /// Loads that failed, by path, with why.
  final Map<String, (Object, StackTrace)> _failures = {};

  /// Paths already reported through [log].
  final Set<String> _reported = {};

  int _revision = 0;

  /// Bumped whenever something loaded is forgotten or replaced, so whoever
  /// drew with it knows to look again.
  int get revision => _revision;

  /// Whether [path] names no file: a built-in tileset or picture, or a
  /// tileset kept inside a Tiled map. Nothing should look for it on disk.
  static bool isVirtual(String path) =>
      path.contains('#') || BuiltInTilesets.isBuiltIn(path);

  TilesetData? _builtInTileset(String path) {
    if (!BuiltInTilesets.isBuiltIn(path)) return null;
    final made = _builtIn[path];
    if (made != null) return made;
    final built = BuiltInTilesets.build(path);
    if (built != null) _builtIn[path] = built;
    return built;
  }

  /// The built-in picture at [path] — a built-in tileset's, which has no
  /// file — drawn the first time it is asked for and kept until [dispose];
  /// null when there is none.
  ui.Image? builtInImage(String path) {
    final made = _builtInImages[path];
    if (made != null) return made;
    final tilesetPath = BuiltInTilesets.tilesetOfImage(path);
    if (tilesetPath == null) return null;
    return _builtInImages[path] = BuiltInTilesets.draw(
      _builtInTileset(tilesetPath)!,
    );
  }

  /// The tileset at [path], loaded once. Fails, at once, while an earlier
  /// load of it has failed (see [failureOf]).
  Future<TilesetData> tileset(String path) {
    final builtIn = _builtInTileset(path);
    if (builtIn != null) return Future.value(builtIn);
    final ready = _tilesets[path];
    if (ready != null) return Future.value(ready);
    final pending = _tilesetLoads[path];
    if (pending != null) return pending;
    final failed = _failures[path];
    if (failed != null) return Future.error(failed.$1, failed.$2);
    final load = _readTileset(path);
    _tilesetLoads[path] = load;
    _settle(path, load, _tilesetLoads, (ts) => _tilesets[path] = ts, 'tileset');
    return load;
  }

  Future<TilesetData> _readTileset(String path) async => TilesetData.fromJson(
    jsonDecode(await readText(path)) as Map<String, dynamic>,
  );

  /// The tileset at [path] if it has loaded, without waiting.
  TilesetData? loadedTileset(String path) =>
      _builtInTileset(path) ?? _tilesets[path];

  /// Makes [tileset] what [path] loads as — an editor's live copy, or a
  /// tileset that came inside a Tiled map.
  void putTileset(String path, TilesetData tileset) {
    if (BuiltInTilesets.isBuiltIn(path)) return;
    _tilesets[path] = tileset;
    _tilesetLoads[path] = Future.value(tileset);
    _failures.remove(path);
    _reported.remove(path);
    _revision++;
  }

  /// The map file at [path], loaded once and shared: whoever changes one
  /// changes a copy. Fails, at once, while an earlier load of it has failed
  /// (see [failureOf]).
  Future<LevelMapData> map(String path) {
    final pending = _mapLoads[path];
    if (pending != null) return pending;
    final failed = _failures[path];
    if (failed != null) return Future.error(failed.$1, failed.$2);
    final load = _readMap(path);
    _mapLoads[path] = load;
    _settle(path, load, _mapLoads, (map) => _maps[path] = map, 'map');
    return load;
  }

  Future<LevelMapData> _readMap(String path) async {
    final lower = path.toLowerCase();
    return lower.endsWith('.tmx') || lower.endsWith('.tmj')
        ? await _loadTiled(path)
        : LevelMapData.fromJson(
            jsonDecode(await readText(path)) as Map<String, dynamic>,
          );
  }

  /// Keeps what [load] of [path] gives — unless [path] was evicted or put
  /// meanwhile, when it is no longer what [path] means — or remembers why
  /// it failed and reports it.
  void _settle<T>(
    String path,
    Future<T> load,
    Map<String, Future<T>> loads,
    void Function(T value) keep,
    String what,
  ) {
    load.then<void>(
      (value) {
        if (identical(loads[path], load)) keep(value);
      },
      onError: (Object error, StackTrace stack) {
        if (!identical(loads[path], load)) return;
        loads.remove(path);
        _failures[path] = (error, stack);
        report(path, error, what: what);
      },
    );
  }

  /// Why [path] last failed to load, while that failure is kept; null when
  /// it loaded or was never asked for.
  Object? failureOf(String path) => _failures[path]?.$1;

  /// Reports through [log] that [path] would not load, the first time only:
  /// again only once [path] has been evicted. [what] says what it is — a
  /// `map`, a `tileset`, a `tileset image`.
  void report(String path, Object error, {String what = 'file'}) {
    if (!_reported.add(path)) return;
    log('Level map: could not load $what "$path": $error');
  }

  /// The map file at [path] if it has loaded, without waiting — the
  /// document an editor edits in place.
  LevelMapData? loadedMap(String path) => _maps[path];

  /// Makes [map] what [path] loads as: a map just written to that file.
  void putMap(String path, LevelMapData map) {
    _maps[path] = map;
    _mapLoads[path] = Future.value(map);
    _failures.remove(path);
    _reported.remove(path);
    _revision++;
  }

  Future<LevelMapData> _loadTiled(String path) async {
    final text = await readText(path);
    final dir = directoryOf(path);
    final provider = _Provider(dir, readText);
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
      kinds: collisionKinds,
    );
    for (var i = 0; i < result.tilesets.length; i++) {
      final ts = result.tilesets[i];
      if (ts != null) putTileset('$path#$i', ts);
    }
    return result.map;
  }

  /// Forgets [path] — or everything — so it is read again.
  void evict([String? path]) {
    if (path == null) {
      clear();
      return;
    }
    bool mine(String key) => key == path || key.startsWith('$path#');
    // A Tiled map's tilesets go with it.
    _tilesets.removeWhere((key, _) => mine(key));
    _tilesetLoads.removeWhere((key, _) => mine(key));
    _mapLoads.remove(path);
    _maps.remove(path);
    _failures.removeWhere((key, _) => mine(key));
    _reported.removeWhere(mine);
    _revision++;
  }

  /// Forgets every map and tileset whose path is not in [paths], and every
  /// failure kept for one: a Tiled map's tilesets stay while the map does.
  /// Nothing happens (and [revision] stays) when all of it is kept.
  ///
  /// Not for an authoring tool that edits maps here in place
  /// ([loadedMap]): what it forgets is read again from the file.
  void retainOnly(Set<String> paths) {
    bool gone(String key) {
      if (paths.contains(key)) return false;
      final hash = key.indexOf('#');
      return hash < 0 || !paths.contains(key.substring(0, hash));
    }

    final before =
        _tilesets.length +
        _tilesetLoads.length +
        _maps.length +
        _mapLoads.length +
        _failures.length;
    _tilesets.removeWhere((key, _) => gone(key));
    _tilesetLoads.removeWhere((key, _) => gone(key));
    _maps.removeWhere((key, _) => gone(key));
    _mapLoads.removeWhere((key, _) => gone(key));
    _failures.removeWhere((key, _) => gone(key));
    _reported.removeWhere(gone);
    final after =
        _tilesets.length +
        _tilesetLoads.length +
        _maps.length +
        _mapLoads.length +
        _failures.length;
    if (after != before) _revision++;
  }

  /// Forgets everything loaded. The built-in tilesets stay.
  void clear() {
    _tilesets.clear();
    _tilesetLoads.clear();
    _mapLoads.clear();
    _maps.clear();
    _failures.clear();
    _reported.clear();
    _revision++;
  }

  /// Forgets everything and disposes the built-in pictures.
  void dispose() {
    clear();
    for (final image in _builtInImages.values) {
      image.dispose();
    }
    _builtInImages.clear();
    _builtIn.clear();
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
  _Provider(this.dir, this.readText);
  final String dir;
  final TextReader readText;

  @override
  Future<String> getTsx(String source) =>
      readText(TileAssets.join(dir, source));

  @override
  Future<String> getTemplate(String source) =>
      readText(TileAssets.join(dir, source));
}

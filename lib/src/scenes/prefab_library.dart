import 'package:flutter/foundation.dart' show debugPrint;
import 'package:just_dart/just_dart.dart' show Vector3;
import 'package:just_game_engine_formats/just_game_engine_formats.dart';

import '../ecs/ecs.dart';
import 'scene_loader.dart';
import 'prefabs_context.dart';

/// The prefab files (`*.prefab.json`) one engine has read, by path: what
/// scenes holding instances of them and spawners placing them make their
/// entities from.
///
/// Reading is asynchronous (through `EngineContext.prefabs`, the bundle by
/// default); making entities is not, so a prefab is loaded before it is
/// used — [SceneLoader.loadAsset] loads a scene's, and [load] or
/// [loadAll] any other. Loading one loads the prefabs nested in it. Files
/// written in an older scene format have their components brought up to
/// date as they are read.
///
/// Each engine has one, on its context: `context.prefabLibrary`
/// ([ContextPrefabs.prefabLibrary]).
final class PrefabLibrary {
  /// A library reading through [context]'s loader and migrations; an
  /// engine's own is `context.prefabLibrary`.
  PrefabLibrary(this.context);

  /// Whose loader and migrations it reads with.
  final EngineContext context;

  final Map<String, PrefabFile> _files = {};
  final Map<String, ({Future<PrefabFile> task, Object token})> _loading = {};
  final Map<String, Object> _errors = {};

  /// The prefab each prefab still loading is waiting on now (one of its
  /// nested ones), to tell a loop of nested prefabs from a wait that ends.
  final Map<String, String> _waitingOn = {};

  /// The prefab at [path] if it has been read; null otherwise. What scene
  /// loading resolves instances with.
  PrefabFile? loaded(String path) => _files[path];

  /// Why [path] could not be read, when it could not.
  Object? errorOf(String path) => _errors[path];

  /// Reads the prefab at [path] — once; asking again while it reads waits
  /// for the same read — and every prefab nested in it, and completes once
  /// all of them are read: also when another scene or spawner asked for it
  /// first. Throws what reading it throws (a nested one that cannot be read
  /// is only remembered: [errorOf]).
  Future<PrefabFile> load(String path) {
    final pending = _loading[path];
    if (pending != null) return pending.task;
    final known = _files[path];
    if (known != null) return Future.value(known);
    final token = Object();
    final task = _read(path, token);
    _loading[path] = (task: task, token: token);
    return task;
  }

  /// Whether the read of [path] holding [token] is still the one that
  /// counts — not overtaken by [reload] or [clear].
  bool _current(String path, Object token) =>
      identical(_loading[path]?.token, token);

  Future<PrefabFile> _read(String path, Object token) async {
    try {
      // A loader that throws at once fails this read, as one that fails
      // later does.
      final read = await Future.sync(() => context.prefabs(path));
      final file = canonical(
        read.migrated(
          (scene) => SceneFormat.migrate(scene, hooks: context.migrations),
        ),
      );
      // Reloaded or cleared while it read: what it read may be stale, so
      // read it again.
      if (!_current(path, token)) return await load(path);
      // Kept before its nested prefabs load, so a loop of them ends here.
      _files[path] = file;
      _errors.remove(path);
      await _loadNested(path, token, PrefabExpander.pathsInPrefab(file));
      return file;
    } on Object catch (error) {
      if (_current(path, token)) _errors[path] = error;
      rethrow;
    } finally {
      if (_current(path, token)) {
        _loading.remove(path);
        _waitingOn.remove(path);
      }
    }
  }

  /// Reads the prefabs [owner] nests, waiting for those other reads hold —
  /// except one that is waiting, through its own nested ones, for [owner]:
  /// a loop of prefabs, cut here.
  Future<void> _loadNested(
    String owner,
    Object token,
    Iterable<String> paths,
  ) async {
    for (final path in paths) {
      final reading = _loading.containsKey(path);
      if (!reading && _files.containsKey(path)) continue;
      if (path == owner || _waitsFor(path, owner)) continue;
      if (_current(owner, token)) _waitingOn[owner] = path;
      try {
        await load(path);
      } on Object catch (error) {
        debugPrint('PrefabLibrary: could not read the prefab $path: $error');
      } finally {
        if (_current(owner, token)) _waitingOn.remove(owner);
      }
    }
  }

  /// Whether the read of [path] is waiting, through the prefabs it nests,
  /// for [target].
  bool _waitsFor(String path, String target) {
    final seen = <String>{};
    String? at = path;
    while (at != null && seen.add(at)) {
      if (at == target) return true;
      at = _waitingOn[at];
    }
    return false;
  }

  /// [file] with each component as the engine writes it — every field,
  /// defaults too — so that a field a file leaves out compares equal to
  /// what an instance has; a component of a kind no definition knows, and
  /// the tree links, as they were.
  PrefabFile canonical(PrefabFile file) {
    final definitions = context.definitions;
    Map<String, dynamic> written(Map<String, dynamic> json) {
      if (PrefabCollapse.links.contains(json['type'])) return json;
      try {
        final component = definitions.decode(json);
        return (component == null ? null : definitions.encode(component)) ??
            json;
      } on Object {
        return json;
      }
    }

    return PrefabFile(
      name: file.name,
      sceneFormat: file.sceneFormat,
      entities: [
        for (final e in file.entities)
          e.prefab != null
              ? e
              : e.withComponents([
                  for (final c in e.components)
                    if (!PrefabCollapse.links.contains(c['type'])) written(c),
                ]),
      ],
    );
  }

  /// Reads every prefab at [paths] (see [load]); one that cannot be read
  /// is remembered ([errorOf]) and passed over.
  Future<void> loadAll(Iterable<String> paths) async {
    for (final path in paths) {
      try {
        await load(path);
      } on Object catch (error) {
        debugPrint('PrefabLibrary: could not read the prefab $path: $error');
      }
    }
  }

  /// Reads every prefab the scene [json] places (its entries' `prefab`
  /// blocks), and those nested in them.
  Future<void> loadScene(Map<String, dynamic> json) {
    final list = json['entities'];
    if (list is! List) return Future.value();
    return loadAll(
      PrefabExpander.pathsIn(list.whereType<Map<String, dynamic>>()),
    );
  }

  /// Forgets the prefab at [path], so it is read again (it changed). A read
  /// of it still under way does not put the old file back: it reads again.
  void reload(String path) {
    _files.remove(path);
    _errors.remove(path);
    _loading.remove(path);
    _waitingOn.remove(path);
  }

  /// Forgets every prefab; reads under way read again.
  void clear() {
    _files.clear();
    _errors.clear();
    _loading.clear();
    _waitingOn.clear();
  }

  /// Makes an instance of the loaded prefab at [path] in [world]: its top
  /// entity named [name] (the prefab's name when null), at [position]
  /// when given — everything under it keeping its place against it.
  /// Returns the top entity. Throws a [StateError] when the prefab has not
  /// been loaded.
  Entity instantiate(
    World world,
    String path, {
    String? name,
    Vector3? position,
  }) {
    final file = _files[path];
    if (file == null) {
      throw StateError(
        'The prefab $path is not loaded: load it first (PrefabLibrary.load).',
      );
    }
    final made = SceneLoader.load(world, {
      'version': SceneFormat.current,
      'entities': [
        {
          'name': name ?? file.name,
          'prefab': {'path': path},
        },
      ],
    });
    final top = made.first;
    final transform = top.getComponent<TransformComponent>();
    if (position != null && transform != null) {
      // Settled where the prefab put everything, then moved: what is under
      // it comes along.
      world.transformHierarchy.propagateFrom(top);
      transform.position.setFrom(position);
      world.transformHierarchy.propagateFrom(top);
    }
    return top;
  }
}

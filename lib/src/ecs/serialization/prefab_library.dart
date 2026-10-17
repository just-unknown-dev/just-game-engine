import 'package:flutter/foundation.dart' show debugPrint;
import 'package:just_dart/just_dart.dart' show Vector3;

import '../base/engine_context.dart';
import '../components/components.dart';
import '../ecs.dart';
import 'prefab_format.dart';
import 'scene_format.dart';
import 'scene_loader.dart';

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
final class PrefabLibrary {
  /// The library of [context]'s engine; see [of].
  PrefabLibrary(this.context);

  /// The library of [context]'s engine, made the first time it is asked
  /// for.
  static PrefabLibrary of(EngineContext context) =>
      context.slot(PrefabLibrary, () => PrefabLibrary(context));

  /// Whose loader and migrations it reads with.
  final EngineContext context;

  final Map<String, PrefabFile> _files = {};
  final Map<String, Future<PrefabFile>> _loading = {};
  final Map<String, Object> _errors = {};

  /// The prefab at [path] if it has been read; null otherwise. What scene
  /// loading resolves instances with.
  PrefabFile? loaded(String path) => _files[path];

  /// Why [path] could not be read, when it could not.
  Object? errorOf(String path) => _errors[path];

  /// Reads the prefab at [path] — once; asking again while it reads waits
  /// for the same read — and every prefab nested in it. Throws what reading
  /// it throws (a nested one that cannot be read is only remembered:
  /// [errorOf]).
  Future<PrefabFile> load(String path) {
    final known = _files[path];
    if (known != null) return Future.value(known);
    return _loading[path] ??= () async {
      try {
        final read = await context.prefabs(path);
        final file = canonical(
          read.migrated(
            (scene) => SceneFormat.migrate(scene, hooks: context.migrations),
          ),
        );
        _files[path] = file;
        _errors.remove(path);
        await loadAll(PrefabExpander.pathsInPrefab(file));
        return file;
      } on Object catch (error) {
        _errors[path] = error;
        rethrow;
      } finally {
        _loading.remove(path);
      }
    }();
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
        return (component == null ? null : definitions.encode(component)) ?? json;
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
      if (_files.containsKey(path)) continue;
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

  /// Forgets the prefab at [path], so it is read again (it changed).
  void reload(String path) {
    _files.remove(path);
    _errors.remove(path);
  }

  /// Forgets every prefab.
  void clear() {
    _files.clear();
    _errors.clear();
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

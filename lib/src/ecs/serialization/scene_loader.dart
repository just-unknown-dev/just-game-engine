library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import '../components/components.dart';
import '../ecs.dart';
import 'component_codec.dart';
import 'component_definition_registry.dart';
import 'scene_format.dart';

/// Where scenes live in a game's assets, and how to find them.
///
/// Flat on purpose: `assets/scenes/` is declared once in `pubspec.yaml`, and
/// every level saved there ships. A folder per scene would need a pubspec
/// edit for each new level — forget it and the level silently is not in the
/// build.
abstract final class SceneAssets {
  /// Directory scenes are saved to and loaded from.
  static const String directory = 'assets/scenes';

  /// The manifest listing every scene, in order.
  static const String manifest = '$directory/scenes.json';

  /// Asset path of the scene named [name].
  static String pathFor(String name) => '$directory/$name.scene.json';
}

/// Loads levels saved by the editor into a [World], with no editor present.
///
/// Components are read with the world's own definitions
/// (`world.context.definitions`): core components always, a package's once
/// its extension is installed into the context.
///
/// ```dart
/// final engine = Engine(
///   config: const EngineConfig(extensions: [PlatformerKit.extension]),
/// );
/// await engine.initialize();
/// await SceneLoader.loadAsset(engine.world, SceneAssets.pathFor('level_01'));
/// ```
abstract final class SceneLoader {
  /// Instantiates every entity in [json] into [world] and links parents
  /// ([parentIndices]). Returns them in the file's order.
  ///
  /// Throws [UnsupportedFormatVersionException] for a scene saved by a newer
  /// engine.
  ///
  /// Throws [UnknownComponentTypeException] if the scene uses a component
  /// type no codec is registered for — naming the type and the entity — rather
  /// than creating the entity without it.
  ///
  /// Throws a [FormatException] naming the entity (and the component and
  /// field) when the file holds a value of the wrong type. Either way the
  /// world is left untouched.
  ///
  /// A parent link that would make a loop (A under B under A) is left out,
  /// with a debug message; a second component of a type an entity already
  /// has replaces the first, also with a message.
  ///
  /// [codecs] defaults to the world's `context.definitions`, and [hooks] —
  /// the packages' migration rules — to its `context.migrations`. An older
  /// file is migrated first; [onMigrated] hears what that found (it is not
  /// called for a file already current).
  static List<Entity> load(
    World world,
    Map<String, dynamic> json, {
    ComponentDefinitionRegistry? codecs,
    MigrationHooks? hooks,
    void Function(MigrationResult result)? onMigrated,
  }) {
    final registry = codecs ?? world.context.definitions;
    // Older files are brought to the current format in memory first.
    final migration = SceneFormat.migrateWithReport(
      json,
      hooks: hooks ?? world.context.migrations,
    );
    if (migration.migrated) onMigrated?.call(migration);
    final scene = migration.scene;
    final list = scene['entities'] ?? const <Object?>[];
    if (list is! List) {
      throw FormatException('Scene: "entities" is $list, not a list.');
    }
    final entries = <Map<String, dynamic>>[
      for (var i = 0; i < list.length; i++)
        if (list[i] case final Map<Object?, Object?> entry)
          entry.cast<String, dynamic>()
        else
          throw FormatException(
            'Scene: entity #$i is ${list[i]}, not an object.',
          ),
    ];

    // Decode everything before creating anything, so a bad component leaves
    // the world untouched instead of half-loaded.
    final decoded = [
      for (var i = 0; i < entries.length; i++)
        _decodeEntry(entries[i], i, registry),
    ];

    // Every entry is an entity — one with no components too (a folder in
    // the tree), or its children would lose their parent.
    final created = <Entity>[
      for (final entry in decoded)
        world.createEntityWithComponents(entry.components, name: entry.name),
    ];
    for (var i = 0; i < decoded.length; i++) {
      // Authored switched off: it is in the world, and the systems pass
      // it by until something turns it on.
      if (!decoded[i].enabled) created[i].isActive = false;
    }

    // Parents are stored by name, because entity ids are not stable across
    // sessions; [parentIndices] turns the names into entries. Each child is
    // the entity made from its own entry — never looked up by its name,
    // which another entity may share.
    final parents = parentIndices(entries);
    for (var i = 0; i < decoded.length; i++) {
      final at = parents[i];
      if (at == null) continue;
      if (_reaches(parents, at, i)) {
        debugPrint(
          'SceneLoader: "${decoded[i].name}" under "${decoded[at].name}" '
          'would make a loop of parents; left at the top.',
        );
        continue;
      }
      final child = created[i];
      final parent = created[at];
      // Both ends of the link, and both made where a file leaves one out.
      //
      // Naming a parent used to give the child nothing when it carried no
      // `ParentComponent` of its own: it went into the parent's list, so
      // it drew in the right place, but it still read as a root — shown at
      // the top of the tree, walked past by anything looking upward, and
      // saved with no parent at all, which lost the hierarchy on the next
      // save. A file that says `parentName` means it.
      final existing = child.getComponent<ParentComponent>();
      if (existing != null) {
        existing.parentId = parent.id;
      } else {
        child.addComponent(ParentComponent(parentId: parent.id));
      }
      if (!parent.hasComponent<ChildrenComponent>()) {
        parent.addComponent(ChildrenComponent());
      }
      parent.getComponent<ChildrenComponent>()!.addChild(child.id);
    }
    return created;
  }

  /// For each of a scene's [entries] (its `entities` list), the index of
  /// the entry its `parentName` names, or null for a root.
  ///
  /// A name that one entry carries is that entry. Names can repeat — two
  /// cars, each with a child called `Wheel` — and then the file's order
  /// decides: a scene is written parents first, each followed by everything
  /// under it, so the parent is the entry of that name on the way down to
  /// this one. Failing that (a file written in another order), it is the
  /// nearest earlier entry of that name, else the last; and a message says
  /// the link was a guess, so the names can be made unique.
  static List<int?> parentIndices(List<Map<String, dynamic>> entries) {
    final names = [for (final e in entries) e['name'] as String?];
    final byName = <String, List<int>>{};
    for (var i = 0; i < names.length; i++) {
      final name = names[i];
      if (name != null) (byName[name] ??= []).add(i);
    }

    final parents = List<int?>.filled(entries.length, null);
    // The entries from a root down to the one just read.
    final path = <int>[];
    for (var i = 0; i < entries.length; i++) {
      final parentName = entries[i]['parentName'] as String?;
      final candidates = parentName == null ? null : byName[parentName];
      int? parent;
      if (candidates != null) {
        if (candidates.length == 1) {
          parent = candidates.single;
        } else {
          for (var k = path.length - 1; k >= 0; k--) {
            if (names[path[k]] == parentName) {
              parent = path[k];
              break;
            }
          }
          if (parent == null) {
            parent = candidates.lastWhere(
              (c) => c < i,
              orElse: () => candidates.last,
            );
            debugPrint(
              'SceneLoader: ${candidates.length} entities are named '
              '"$parentName", and the file does not show which is the parent '
              'of entity #$i (${names[i] ?? 'unnamed'}); linked it to entity '
              '#$parent. Give them different names to make it certain.',
            );
          }
        }
      }
      if (parent == i) parent = null;
      parents[i] = parent;

      final onPath = parent == null ? -1 : path.lastIndexOf(parent);
      if (onPath < 0) {
        path.clear();
      } else {
        path.length = onPath + 1;
      }
      path.add(i);
    }

    // Links that loop — each entry naming the next as its parent, round to
    // the first — would make an entity its own ancestor, which a world
    // refuses. The link that closes the loop is dropped: that entry loads
    // as a root.
    final state = List<int>.filled(parents.length, 0); // 1 walking, 2 done
    for (var i = 0; i < parents.length; i++) {
      if (state[i] != 0) continue;
      final walk = <int>[];
      int? at = i;
      while (at != null && state[at] != 2) {
        if (state[at] == 1) {
          final cut = walk.last;
          debugPrint(
            'SceneLoader: the parents of entity #$cut '
            '(${names[cut] ?? 'unnamed'}) lead back to it; it is loaded '
            'without a parent.',
          );
          parents[cut] = null;
          break;
        }
        state[at] = 1;
        walk.add(at);
        at = parents[at];
      }
      for (final w in walk) {
        state[w] = 2;
      }
    }
    return parents;
  }

  /// Parses [source] and loads it; see [load].
  static List<Entity> loadString(
    World world,
    String source, {
    ComponentDefinitionRegistry? codecs,
    MigrationHooks? hooks,
    void Function(MigrationResult result)? onMigrated,
  }) => load(
    world,
    jsonDecode(source) as Map<String, dynamic>,
    codecs: codecs,
    hooks: hooks,
    onMigrated: onMigrated,
  );

  /// Loads the scene asset at [assetPath]; see [load].
  ///
  /// Reads without caching: a level is loaded once per play session, and a
  /// cached copy is how an edited level ends up still playing the old one.
  /// [bundle] defaults to the world's (`world.context.bundle`).
  static Future<List<Entity>> loadAsset(
    World world,
    String assetPath, {
    AssetBundle? bundle,
    ComponentDefinitionRegistry? codecs,
    MigrationHooks? hooks,
    void Function(MigrationResult result)? onMigrated,
  }) async {
    final source = await (bundle ?? world.context.bundle).loadString(
      assetPath,
      cache: false,
    );
    return loadString(
      world,
      source,
      codecs: codecs,
      hooks: hooks,
      onMigrated: onMigrated,
    );
  }

  /// Reads the scene manifest: every scene name, in play order.
  static Future<List<String>> loadManifest({AssetBundle? bundle}) async {
    final source = await (bundle ?? rootBundle).loadString(
      SceneAssets.manifest,
      cache: false,
    );
    // Text that is not a list of scenes lists none; entries that are not
    // names are skipped.
    return SceneManifest.parse(source);
  }

  /// Entry [index] of a scene's `entities`, decoded, or a
  /// [FormatException] naming it when a value has the wrong type.
  static ({
    String? name,
    String? parentName,
    bool enabled,
    List<Component> components,
  })
  _decodeEntry(
    Map<String, dynamic> entry,
    int index,
    ComponentDefinitionRegistry registry,
  ) {
    final rawName = entry['name'];
    final where = rawName is String
        ? 'Entity #$index "$rawName"'
        : 'Entity #$index';
    try {
      final components = <Component>[];
      final seen = <Type>{};
      final list = entry['components'] ?? const <Object?>[];
      if (list is! List) {
        throw FormatException('"components" is $list, not a list.');
      }
      for (final raw in list) {
        if (raw is! Map) {
          throw FormatException('a component is $raw, not an object.');
        }
        final json = raw.cast<String, dynamic>();
        final component =
            registry.decode(json) ??
            (throw UnknownComponentTypeException(
              json['type']?.toString() ?? '<missing type>',
              entityName: rawName is String ? rawName : null,
            ));
        if (!seen.add(component.runtimeType)) {
          debugPrint(
            'SceneLoader: $where has two ${json['type']}; the later one is '
            'kept.',
          );
        }
        components.add(component);
      }
      return (
        name: entry['name'] as String?,
        parentName: entry['parentName'] as String?,
        // Left out means on, which is what nearly every entity is.
        enabled: entry['enabled'] != false,
        components: components,
      );
    } on FormatException catch (e) {
      throw FormatException('$where: ${e.message}');
    } on TypeError catch (e) {
      throw FormatException('$where: a value has the wrong type ($e).');
    }
  }

  /// Whether following [parents] up from [from] arrives at [target].
  static bool _reaches(List<int?> parents, int from, int target) {
    int? at = from;
    for (var steps = 0; at != null && steps <= parents.length; steps++) {
      if (at == target) return true;
      at = parents[at];
    }
    return false;
  }
}

library;

import 'dart:convert';

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
/// ```dart
/// registerCoreCodecs();
/// PlatformerKit.registerCodecs();      // any genre kit the level uses
/// await SceneLoader.loadAsset(world, SceneAssets.pathFor('level_01'));
/// ```
abstract final class SceneLoader {
  /// Instantiates every entity in [json] into [world] and links parents.
  ///
  /// Throws [UnknownComponentTypeException] if the scene uses a component
  /// type no codec is registered for — naming the type and the entity — rather
  /// than creating the entity without it.
  static List<Entity> load(
    World world,
    Map<String, dynamic> json, {
    ComponentCodecRegistry? codecs,
  }) {
    final registry = codecs ?? ComponentCodecRegistry.instance;
    // Older files are brought to the current format in memory first.
    final scene = SceneFormat.migrate(json);
    final entries = (scene['entities'] as List? ?? const [])
        .cast<Map<String, dynamic>>();

    // Decode everything before creating anything, so a bad component leaves
    // the world untouched instead of half-loaded.
    final decoded = [
      for (final entry in entries)
        (
          name: entry['name'] as String?,
          parentName: entry['parentName'] as String?,
          // Left out means on, which is what nearly every entity is.
          enabled: entry['enabled'] != false,
          components: [
            for (final raw
                in (entry['components'] as List? ?? const [])
                    .cast<Map<String, dynamic>>())
              registry.decode(raw) ??
                  (throw UnknownComponentTypeException(
                    raw['type']?.toString() ?? '<missing type>',
                    entityName: entry['name'] as String?,
                  )),
          ],
        ),
    ];

    final created = <Entity>[];
    final byName = <String, Entity>{};
    for (final entry in decoded) {
      if (entry.components.isEmpty) continue;
      final entity = world.createEntityWithComponents(
        entry.components,
        name: entry.name,
      );
      // Authored switched off: it is in the world, and the systems pass
      // it by until something turns it on.
      if (!entry.enabled) entity.isActive = false;
      created.add(entity);
      if (entry.name != null) byName[entry.name!] = entity;
    }

    // Parents are stored by name, because entity ids are not stable across
    // sessions. Same second pass the editor has always done.
    for (final entry in decoded) {
      final parentName = entry.parentName;
      if (parentName == null || entry.name == null) continue;
      final child = byName[entry.name!];
      final parent = byName[parentName];
      if (child == null || parent == null) continue;
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

  /// Parses [source] and loads it; see [load].
  static List<Entity> loadString(
    World world,
    String source, {
    ComponentCodecRegistry? codecs,
  }) => load(world, jsonDecode(source) as Map<String, dynamic>, codecs: codecs);

  /// Loads the scene asset at [assetPath]; see [load].
  ///
  /// Reads without caching: a level is loaded once per play session, and a
  /// cached copy is how an edited level ends up still playing the old one.
  static Future<List<Entity>> loadAsset(
    World world,
    String assetPath, {
    AssetBundle? bundle,
    ComponentCodecRegistry? codecs,
  }) async {
    final source = await (bundle ?? rootBundle).loadString(
      assetPath,
      cache: false,
    );
    return loadString(world, source, codecs: codecs);
  }

  /// Reads the scene manifest: every scene name, in play order.
  static Future<List<String>> loadManifest({AssetBundle? bundle}) async {
    final source = await (bundle ?? rootBundle).loadString(
      SceneAssets.manifest,
      cache: false,
    );
    final json = jsonDecode(source) as Map<String, dynamic>;
    return (json['scenes'] as List? ?? const []).cast<String>();
  }
}

/// The definition that makes a level map saveable and inspectable.
library;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/painting.dart';
import '../../core/dimensions.dart';

import '../../subsystems/level_map/level_map_data.dart';
import '../components/level_map/level_map_component.dart';
import 'component_definition.dart';
import 'field_type.dart';

abstract final class LevelMapDefinitions {
  static final levelMap = ComponentDefinition<LevelMapComponent>(
    type: 'LevelMapComponent',
    // Saved as a tile map before the rename.
    aliases: const ['TileMapComponent'],
    hints: const ComponentHints(
      dimensions: Dimensions.twoD,
      name: 'Map',
      group: 'Rendering',
      description:
          'The level\'s map: layers of tiles painted from tilesets. Paint '
          'them with the tile tools in the Level Designer.',
      icon: Icons.grid_on_rounded,
      accentColor: Color(0xFF8BC34A),
      fields: {
        'mapPath': FieldHint(
          label: 'Map file',
          description:
              'A .map.json to share one map between scenes, or a Tiled '
              '.tmx / .tmj. Empty keeps the map in this scene.',
          fileExtensions: ['map.json', 'tilemap.json', 'tmx', 'tmj'],
        ),
        'inline': FieldHint(label: 'Map', visible: false),
      },
    ),
    create: LevelMapComponent.new,
    // No extent: the map is painted cell by cell, and a map-sized box would
    // make every entity tool treat the whole level as one obstacle.
    fields: [
      SchemaField(
        name: 'mapPath',
        kind: FieldTypes.assetRef,
        read: (c) => (c as LevelMapComponent).mapPath,
        write: (c, v) => (c as LevelMapComponent).mapPath = v as String? ?? '',
      ),
      SchemaField(
        name: 'inline',
        kind: FieldTypes.map,
        // A new map every time: whoever keeps what this returns — a play
        // snapshot, an undo step — must not see later edits.
        read: (c) => (c as LevelMapComponent).inline?.toJson(),
        write: (c, v) => (c as LevelMapComponent).inline = v is Map
            ? LevelMapData.fromJson(v.cast<String, dynamic>())
            : null,
      ),
    ],
  );

  static List<ComponentDefinition> get all => [levelMap];
}

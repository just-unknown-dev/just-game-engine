import 'package:flutter/material.dart' show Icons;
import 'package:flutter/painting.dart';
import 'package:just_dart/just_dart.dart' show Aabb3;

import '../../ecs/ecs.dart';
import '../../foundation/dimensions.dart';
import 'graphics_components.dart';

/// How the 3-D model components (models, animation players, sockets) are
/// saved and shown in an editor. Lights, materials and shapes have their own
/// (`Lighting3DDefinitions`, `Material3DDefinitions`, `Shape3DDefinitions`).
abstract final class Graphics3DDefinitions {
  /// [ModelComponent].
  static ComponentSchema<ModelComponent> get model =>
      ComponentSchema<ModelComponent>(
        type: 'ModelComponent',
        id: 'model_3d_7c21e4b9',
        create: ModelComponent.new,
        extent: const _ModelExtent(),
        hints: const ComponentHints(
          dimensions: Dimensions.threeD,
          name: 'Model',
          group: '3D',
          description: 'Draws a glTF model (.glb or .gltf).',
          icon: Icons.view_in_ar,
          accentColor: Color(0xFF42A5F5),
          fields: {
            'model': FieldHint(label: 'Model', fileExtensions: ['glb', 'gltf']),
            'materials': FieldHint(
              label: 'Materials',
              description:
                  'Material files drawn instead of its own: by material name, '
                  '#index, or * for every one.',
            ),
            'castShadows': FieldHint(label: 'Casts shadows'),
            'visible': FieldHint(label: 'Visible'),
          },
        ),
        fields: [
          SchemaField(
            name: 'model',
            kind: FieldTypes.assetRef,
            read: (c) => (c as ModelComponent).model,
            write: (c, v) => (c as ModelComponent).model = v as String? ?? '',
          ),
          SchemaField(
            name: 'materials',
            kind: FieldTypes.map,
            read: (c) =>
                Map<Object?, Object?>.of((c as ModelComponent).materials),
            write: (c, v) => (c as ModelComponent).materials = {
              if (v is Map)
                for (final e in v.entries)
                  if (e.value is String && (e.value as String).isNotEmpty)
                    '${e.key}': e.value as String,
            },
          ),
          SchemaField(
            name: 'castShadows',
            kind: FieldTypes.boolean,
            read: (c) => (c as ModelComponent).castShadows,
            write: (c, v) => (c as ModelComponent).castShadows = v as bool,
          ),
          SchemaField(
            name: 'visible',
            kind: FieldTypes.boolean,
            read: (c) => (c as ModelComponent).visible,
            write: (c, v) => (c as ModelComponent).visible = v as bool,
          ),
        ],
      );

  /// [AnimationPlayerComponent].
  static ComponentSchema<AnimationPlayerComponent> get animationPlayer =>
      ComponentSchema<AnimationPlayerComponent>(
        type: 'AnimationPlayerComponent',
        id: 'animation_player_3d_91d6a2c4',
        create: AnimationPlayerComponent.new,
        hints: const ComponentHints(
          dimensions: Dimensions.threeD,
          name: 'Animation Player',
          group: '3D',
          description: "Plays the model's animations (glTF clips).",
          icon: Icons.directions_run,
          accentColor: Color(0xFFAB47BC),
          fields: {
            'clip': FieldHint(label: 'Clip'),
            'speed': FieldHint(
              label: 'Speed',
              scrub: ScrubHint(step: 0.05, fractionDigits: 2),
            ),
            'loop': FieldHint(label: 'Loop'),
            'playing': FieldHint(label: 'Playing'),
            'crossfade': FieldHint(
              label: 'Crossfade',
              scrub: ScrubHint(step: 0.05, fractionDigits: 2, suffix: 's'),
            ),
          },
        ),
        fields: [
          SchemaField(
            name: 'clip',
            kind: FieldTypes.text,
            read: (c) => (c as AnimationPlayerComponent).clip,
            write: (c, v) =>
                (c as AnimationPlayerComponent).clip = v as String? ?? '',
          ),
          _decimal(
            'speed',
            (c) => (c as AnimationPlayerComponent).speed,
            (c, v) => (c as AnimationPlayerComponent).speed = v,
          ),
          SchemaField(
            name: 'loop',
            kind: FieldTypes.boolean,
            read: (c) => (c as AnimationPlayerComponent).loop,
            write: (c, v) => (c as AnimationPlayerComponent).loop = v as bool,
          ),
          SchemaField(
            name: 'playing',
            kind: FieldTypes.boolean,
            read: (c) => (c as AnimationPlayerComponent).playing,
            write: (c, v) =>
                (c as AnimationPlayerComponent).playing = v as bool,
          ),
          _decimal(
            'crossfade',
            (c) => (c as AnimationPlayerComponent).crossfade,
            (c, v) => (c as AnimationPlayerComponent).crossfade = v,
            min: 0,
          ),
        ],
      );

  /// [SocketComponent].
  static ComponentSchema<SocketComponent> get socket =>
      ComponentSchema<SocketComponent>(
        type: 'SocketComponent',
        id: 'socket_3d_5e0b7f13',
        create: SocketComponent.new,
        hints: const ComponentHints(
          dimensions: Dimensions.threeD,
          name: 'Socket',
          group: '3D',
          description: "Pins the entity to a joint of its parent's model.",
          icon: Icons.push_pin_outlined,
          accentColor: Color(0xFF8D6E63),
          fields: {'node': FieldHint(label: 'Joint')},
        ),
        fields: [
          SchemaField(
            name: 'node',
            kind: FieldTypes.text,
            read: (c) => (c as SocketComponent).node,
            write: (c, v) => (c as SocketComponent).node = v as String? ?? '',
          ),
        ],
      );

  /// Every model component.
  static List<ComponentSchema> get all => [model, animationPlayer, socket];

  static SchemaField _decimal(
    String name,
    double Function(Component c) read,
    void Function(Component c, double v) write, {
    double? min,
  }) => SchemaField(
    name: name,
    kind: FieldTypes.decimal,
    read: read,
    write: (c, v) => write(c, (v as num).toDouble()),
    min: min,
  );
}

/// A model's size is its loaded bounds; until it loads, a 1 m cube.
final class _ModelExtent extends ComponentExtent {
  const _ModelExtent();

  @override
  Size? sizeOf(Component component) {
    final b = (component as ModelComponent).bounds;
    return b.isEmpty
        ? const Size(1, 1)
        : Size(b.max.x - b.min.x, b.max.y - b.min.y);
  }

  @override
  bool boundsInto(Component component, Aabb3 out) {
    final b = (component as ModelComponent).bounds;
    if (b.isEmpty) {
      out.setValues(-0.5, -0.5, -0.5, 0.5, 0.5, 0.5);
    } else {
      out.setFrom(b);
    }
    return true;
  }
}

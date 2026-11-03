/// The sprite components: a sprite, and a sprite that plays atlas clips.
library;

import '../ecs/ecs.dart';
import '../ecs/serialization/schema_fields.dart';
import '../foundation/dimensions.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/painting.dart';
import 'sprite_animation_component.dart';
import 'sprite_component.dart';

/// The sprite components: a sprite, and a sprite that plays atlas clips.
abstract final class SpriteDefinitions {
  /// Definition of [SpriteComponent], saved as `SpriteComponent`. 2-D
  /// only.
  static ComponentDefinition<SpriteComponent> get sprite =>
      ComponentDefinition<SpriteComponent>(
        type: 'SpriteComponent',
        hints: const ComponentHints(
          dimensions: Dimensions.twoD,
          name: 'Sprite',
          group: 'Rendering',
          description: 'An image, or one region of a sprite atlas.',
          icon: Icons.image,
          accentColor: Color(0xFF42A5F5),
          fieldGroups: {
            'Sprite': ['spritePath'],
            'From an atlas': ['atlasPath', 'region'],
            'Options': ['flipX', 'flipY', 'tint', 'pixelArt'],
          },
          fields: {
            'spritePath': FieldHint(label: 'Path'),
            'atlasPath': FieldHint(label: 'Atlas', fileExtensions: ['json']),
            'region': FieldHint(
              label: 'Region',
              description: 'Empty shows the first.',
            ),
            'pixelArt': FieldHint(
              label: 'Pixel art',
              description: 'No smoothing when scaled.',
            ),
            'flipX': FieldHint(label: 'Flip X'),
            'flipY': FieldHint(label: 'Flip Y'),
            'tint': FieldHint(label: 'Tint'),
          },
        ),
        create: () => SpriteComponent(spritePath: ''),
        fields: [
          SchemaField(
            name: 'spritePath',
            kind: FieldTypes.assetRef,
            read: (c) => (c as SpriteComponent).spritePath,
            write: (c, v) => (c as SpriteComponent).spritePath = v as String,
          ),
          SchemaField(
            name: 'atlasPath',
            kind: FieldTypes.assetRef,
            read: (c) => (c as SpriteComponent).atlasPath,
            write: (c, v) => (c as SpriteComponent).atlasPath = v as String,
          ),
          SchemaField(
            name: 'region',
            kind: FieldTypes.text,
            read: (c) => (c as SpriteComponent).region,
            write: (c, v) => (c as SpriteComponent).region = v as String,
          ),
          SchemaFields.boolean(
            'flipX',
            (c) => (c as SpriteComponent).flipX,
            (c, v) => (c as SpriteComponent).flipX = v,
          ),
          SchemaFields.boolean(
            'flipY',
            (c) => (c as SpriteComponent).flipY,
            (c, v) => (c as SpriteComponent).flipY = v,
          ),
          SchemaField(
            name: 'tint',
            kind: FieldTypes.color,
            read: (c) => (c as SpriteComponent).tint,
            write: (c, v) => (c as SpriteComponent).tint = v as Color?,
          ),
          SchemaFields.boolean(
            'pixelArt',
            (c) => (c as SpriteComponent).pixelArt,
            (c, v) => (c as SpriteComponent).pixelArt = v,
          ),
        ],
        extent: const _SpriteExtent(),
      );

  /// [SpriteAnimationComponent]: a clip from a sprite atlas.
  static ComponentSchema<SpriteAnimationComponent> get spriteAnimation =>
      ComponentSchema<SpriteAnimationComponent>(
        type: 'SpriteAnimationComponent',
        hints: const ComponentHints(
          dimensions: Dimensions.twoD,
          name: 'Sprite Animation',
          group: 'Rendering',
          description:
              'Plays a clip from a sprite atlas: the sheet and JSON a sprite '
              'tool exports.',
          icon: Icons.movie_filter_rounded,
          accentColor: Color(0xFF7DE6B1),
          fieldGroups: {
            'Atlas': ['atlasPath', 'clip'],
            'Playback': ['playOnStart', 'speed'],
            'Options': ['flipX', 'flipY', 'tint', 'pixelArt'],
          },
          fields: {
            'atlasPath': FieldHint(label: 'Atlas', fileExtensions: ['json']),
            'clip': FieldHint(
              label: 'Clip',
              description: 'A tag in the atlas. Empty plays every frame.',
            ),
            'playOnStart': FieldHint(label: 'Play on start'),
            'speed': FieldHint(
              label: 'Speed',
              scrub: ScrubHint(step: 0.05, fractionDigits: 2),
            ),
            'flipX': FieldHint(label: 'Flip X'),
            'flipY': FieldHint(label: 'Flip Y'),
            'tint': FieldHint(label: 'Tint'),
            'pixelArt': FieldHint(
              label: 'Pixel art',
              description: 'No smoothing when scaled.',
            ),
          },
        ),
        id: 'sprite_animation_7c21d9e4',
        create: SpriteAnimationComponent.new,
        fields: [
          SchemaField(
            name: 'atlasPath',
            kind: FieldTypes.assetRef,
            read: (c) => (c as SpriteAnimationComponent).atlasPath,
            write: (c, v) =>
                (c as SpriteAnimationComponent).atlasPath = v as String,
          ),
          SchemaField(
            name: 'clip',
            kind: FieldTypes.text,
            read: (c) => (c as SpriteAnimationComponent).clip,
            write: (c, v) {
              final animation = c as SpriteAnimationComponent;
              if (animation.clip == v) return;
              animation
                ..clip = v as String
                ..restart();
            },
          ),
          SchemaField(
            name: 'playOnStart',
            kind: FieldTypes.boolean,
            read: (c) => (c as SpriteAnimationComponent).playOnStart,
            write: (c, v) =>
                (c as SpriteAnimationComponent).playOnStart = v as bool,
          ),
          SchemaField(
            name: 'speed',
            kind: FieldTypes.decimal,
            read: (c) => (c as SpriteAnimationComponent).speed,
            write: (c, v) =>
                (c as SpriteAnimationComponent).speed = (v as num).toDouble(),
            min: 0.0,
          ),
          SchemaField(
            name: 'flipX',
            kind: FieldTypes.boolean,
            read: (c) => (c as SpriteAnimationComponent).flipX,
            write: (c, v) => (c as SpriteAnimationComponent).flipX = v as bool,
          ),
          SchemaField(
            name: 'flipY',
            kind: FieldTypes.boolean,
            read: (c) => (c as SpriteAnimationComponent).flipY,
            write: (c, v) => (c as SpriteAnimationComponent).flipY = v as bool,
          ),
          SchemaField(
            name: 'tint',
            kind: FieldTypes.color,
            read: (c) => (c as SpriteAnimationComponent).tint,
            write: (c, v) => (c as SpriteAnimationComponent).tint = v as Color?,
          ),
          SchemaField(
            name: 'pixelArt',
            kind: FieldTypes.boolean,
            read: (c) => (c as SpriteAnimationComponent).pixelArt,
            write: (c, v) =>
                (c as SpriteAnimationComponent).pixelArt = v as bool,
          ),
        ],
      );

  /// Every one of them.
  static List<ComponentCodec> get all => [sprite, spriteAnimation];
}

class _SpriteExtent extends ComponentExtent {
  const _SpriteExtent();
  @override
  Size? sizeOf(Component c) => null;
  @override
  void flip(Component c, {required bool horizontal}) {
    final s = c as SpriteComponent;
    horizontal ? s.flipX = !s.flipX : s.flipY = !s.flipY;
  }
}

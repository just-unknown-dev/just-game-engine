library;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/painting.dart';
import 'package:just_dart/just_dart.dart';

import '../components/components.dart';
import '../ecs.dart';
import 'component_codec.dart';
import 'component_schema.dart';
import 'field_type.dart';

/// Schemas for the core components the editor has always saved in its
/// descriptor shape (`{type, customComponentId, fields}`).
///
/// Transcribed from the editor's descriptors: same ids, same field names,
/// same kinds, same clamping. The editor now serializes these through the
/// schemas below, and a test checks every descriptor field still has a
/// matching schema field — an inspector field that did not persist would
/// look editable and quietly lose its value on save.
abstract final class CoreComponentSchemas {
  /// [LayerComponent], from `layer_editor_component.dart`.
  static final layer = ComponentSchema<LayerComponent>(
    type: 'LayerComponent',
    hints: const ComponentHints(
      name: 'Layer',
      group: 'Rendering',
      icon: Icons.layers,
      accentColor: Color(0xFF78909C),
      fields: {
        'layerId': FieldHint(label: 'Layer'),
        'layer': FieldHint(
          label: 'Order',
          scrub: ScrubHint(step: 10, integer: true),
        ),
        'zOrder': FieldHint(label: 'Z', scrub: ScrubHint(integer: true)),
      },
    ),
    id: 'layer_3ab67e05',
    create: LayerComponent.new,
    fields: [
      SchemaField(
        name: 'layerId',
        kind: FieldTypes.text,
        read: (c) => (c as LayerComponent).layerId,
        write: (c, v) =>
            (c as LayerComponent).layerId = (v as String?) ?? 'main',
      ),
      SchemaField(
        name: 'layer',
        kind: FieldTypes.integer,
        read: (c) => (c as LayerComponent).layer,
        write: (c, v) => (c as LayerComponent).layer = (v as num).toInt(),
        min: -1000,
        max: 1000,
      ),
      SchemaField(
        name: 'zOrder',
        kind: FieldTypes.integer,
        read: (c) => (c as LayerComponent).zOrder,
        write: (c, v) => (c as LayerComponent).zOrder = (v as num).toInt(),
        min: -1000,
        max: 1000,
      ),
    ],
  );

  /// [CheckpointComponent], from `checkpoint_editor_component.dart`.
  static final checkpoint = ComponentSchema<CheckpointComponent>(
    type: 'CheckpointComponent',
    hints: const ComponentHints(
      name: 'Checkpoint',
      group: 'Gameplay',
      icon: Icons.flag_outlined,
      accentColor: Color(0xFF66BB6A),
      fields: {
        'respawnX': FieldHint(label: 'Respawn X'),
        'respawnY': FieldHint(label: 'Respawn Y'),
        'radius': FieldHint(label: 'Radius', scrub: ScrubHint()),
      },
    ),
    id: 'checkpoint_5e2b9d71',
    create: () => CheckpointComponent(respawnPosition: Vector3.zero()),
    fields: [
      SchemaField(
        name: 'respawnX',
        kind: FieldTypes.decimal,
        read: (c) => (c as CheckpointComponent).respawnPosition.x,
        write: (c, v) => (c as CheckpointComponent).respawnPosition.x =
            (v as num).toDouble(),
      ),
      SchemaField(
        name: 'respawnY',
        kind: FieldTypes.decimal,
        read: (c) => (c as CheckpointComponent).respawnPosition.y,
        write: (c, v) => (c as CheckpointComponent).respawnPosition.y =
            (v as num).toDouble(),
      ),
      SchemaField(
        name: 'radius',
        kind: FieldTypes.decimal,
        read: (c) => (c as CheckpointComponent).radius,
        write: (c, v) =>
            (c as CheckpointComponent).radius = (v as num).toDouble(),
        min: 0,
        max: 4096,
      ),
    ],
  );

  /// [TextComponent], from `text_editor_component.dart`.
  static final text = ComponentSchema<TextComponent>(
    type: 'TextComponent',
    hints: const ComponentHints(
      name: 'Text',
      group: 'UI',
      icon: Icons.text_fields,
      accentColor: Color(0xFF5C6BC0),
      fieldGroups: {
        'Size': ['w', 'h'],
        'Content': ['textValue'],
      },
      fields: {
        ..._sizeHints,
        'textValue': FieldHint(label: 'Text'),
      },
    ),
    painter: const TextComponentPainter(),
    id: 'text_effcff19',
    create: () => TextComponent(text: 'Text', size: const Size(200, 40)),
    extent: const _UiExtent(),
    fields: [
      SchemaField(
        name: 'w',
        kind: FieldTypes.decimal,
        read: (c) => (c as TextComponent).size.width,
        write: (c, v) {
          final t = c as TextComponent;
          t.size = Size((v as num).toDouble(), t.size.height);
        },
        min: 0.0,
      ),
      SchemaField(
        name: 'h',
        kind: FieldTypes.decimal,
        read: (c) => (c as TextComponent).size.height,
        write: (c, v) {
          final t = c as TextComponent;
          t.size = Size(t.size.width, (v as num).toDouble());
        },
        min: 0.0,
      ),
      SchemaField(
        name: 'textValue',
        kind: FieldTypes.text,
        read: (c) => (c as TextComponent).text,
        write: (c, v) => (c as TextComponent).text = v as String,
      ),
    ],
  );

  /// [LineComponent], from `line_editor_component.dart`.
  static final line = ComponentSchema<LineComponent>(
    type: 'LineComponent',
    hints: const ComponentHints(
      name: 'Line',
      group: 'Rendering',
      icon: Icons.show_chart,
      accentColor: Color(0xFF42A5F5),
      fieldGroups: {
        'Points': ['startX', 'startY', 'endX', 'endY'],
        'Appearance': ['strokeColor', 'strokeW', 'roundCaps'],
      },
      fields: {
        'startX': FieldHint(
          label: 'Start X',
          scrub: ScrubHint(fractionDigits: 1),
        ),
        'startY': FieldHint(
          label: 'Start Y',
          scrub: ScrubHint(fractionDigits: 1),
        ),
        'endX': FieldHint(label: 'End X', scrub: ScrubHint(fractionDigits: 1)),
        'endY': FieldHint(label: 'End Y', scrub: ScrubHint(fractionDigits: 1)),
        'strokeColor': FieldHint(label: 'Paint'),
        'strokeW': FieldHint(
          label: 'Stroke',
          scrub: ScrubHint(step: 0.5, fractionDigits: 1),
        ),
        'roundCaps': FieldHint(label: 'Round'),
      },
    ),
    id: 'line_5a69b8e2',
    create: () => LineComponent(end: const Offset(100, 0)),
    extent: const _LineExtent(),
    fields: [
      SchemaField(
        name: 'startX',
        kind: FieldTypes.decimal,
        read: (c) => (c as LineComponent).start.dx,
        write: (c, v) {
          final l = c as LineComponent;
          l.start = Offset((v as num).toDouble(), l.start.dy);
        },
      ),
      SchemaField(
        name: 'startY',
        kind: FieldTypes.decimal,
        read: (c) => (c as LineComponent).start.dy,
        write: (c, v) {
          final l = c as LineComponent;
          l.start = Offset(l.start.dx, (v as num).toDouble());
        },
      ),
      SchemaField(
        name: 'endX',
        kind: FieldTypes.decimal,
        read: (c) => (c as LineComponent).end.dx,
        write: (c, v) {
          final l = c as LineComponent;
          l.end = Offset((v as num).toDouble(), l.end.dy);
        },
      ),
      SchemaField(
        name: 'endY',
        kind: FieldTypes.decimal,
        read: (c) => (c as LineComponent).end.dy,
        write: (c, v) {
          final l = c as LineComponent;
          l.end = Offset(l.end.dx, (v as num).toDouble());
        },
      ),
      SchemaField(
        name: 'strokeColor',
        kind: FieldTypes.shapePaintStyle,
        read: (c) => (c as LineComponent).strokeStyle,
        write: (c, v) =>
            (c as LineComponent).strokeStyle = v as ShapePaintStyle,
      ),
      SchemaField(
        name: 'strokeW',
        kind: FieldTypes.decimal,
        read: (c) => (c as LineComponent).strokeWidth,
        write: (c, v) =>
            (c as LineComponent).strokeWidth = (v as num).toDouble(),
        min: 0.0,
      ),
      SchemaField(
        name: 'roundCaps',
        kind: FieldTypes.boolean,
        read: (c) => (c as LineComponent).roundCaps,
        write: (c, v) => (c as LineComponent).roundCaps = v as bool,
      ),
    ],
  );

  /// [PolygonComponent], from `polygon_editor_component.dart`.
  static final polygon = ComponentSchema<PolygonComponent>(
    type: 'PolygonComponent',
    hints: const ComponentHints(
      name: 'Polygon',
      group: 'Rendering',
      icon: Icons.pentagon_outlined,
      accentColor: Color(0xFF42A5F5),
      fieldGroups: {
        'Shape': ['vertCount', 'vertices'],
        'Appearance': ['filled', 'fillColor', 'strokeColor', 'strokeW'],
      },
      fields: {
        'vertCount': FieldHint(label: 'Verts', editable: false),
        'vertices': FieldHint(label: 'Vertices'),
        'filled': FieldHint(label: 'Filled'),
        'fillColor': FieldHint(label: 'Fill'),
        'strokeColor': FieldHint(label: 'Stroke Color'),
        'strokeW': FieldHint(
          label: 'Stroke',
          scrub: ScrubHint(step: 0.5, fractionDigits: 1),
        ),
      },
    ),
    id: 'polygon_671a97e0',
    create: () => PolygonComponent(
      vertices: const [
        Offset(-32, -32),
        Offset(32, -32),
        Offset(32, 32),
        Offset(-32, 32),
      ],
    ),
    extent: const _PolygonExtent(),
    fields: [
      SchemaField(
        name: 'vertCount',
        kind: FieldTypes.integer,
        read: (c) => (c as PolygonComponent).vertices.length,
      ),
      // The shape itself. The descriptor this schema was transcribed from
      // saved only the count, so every polygon reloaded as the default
      // square. A file without this key still loads that way.
      SchemaField(
        name: 'vertices',
        kind: FieldTypes.offsetList,
        read: (c) => (c as PolygonComponent).vertices,
        write: (c, v) => (c as PolygonComponent).vertices = (v as List)
            .cast<Offset>()
            .toList(),
      ),
      SchemaField(
        name: 'filled',
        kind: FieldTypes.boolean,
        read: (c) => (c as PolygonComponent).filled,
        write: (c, v) => (c as PolygonComponent).filled = v as bool,
      ),
      SchemaField(
        name: 'fillColor',
        kind: FieldTypes.shapePaintStyle,
        read: (c) => (c as PolygonComponent).fillStyle,
        write: (c, v) =>
            (c as PolygonComponent).fillStyle = v as ShapePaintStyle,
      ),
      SchemaField(
        name: 'strokeColor',
        kind: FieldTypes.shapePaintStyle,
        read: (c) => (c as PolygonComponent).strokeStyle,
        write: (c, v) =>
            (c as PolygonComponent).strokeStyle = v as ShapePaintStyle,
      ),
      SchemaField(
        name: 'strokeW',
        kind: FieldTypes.decimal,
        read: (c) => (c as PolygonComponent).strokeWidth,
        write: (c, v) =>
            (c as PolygonComponent).strokeWidth = (v as num).toDouble(),
        min: 0.0,
      ),
    ],
  );

  /// [AnimatedSpriteComponent], from `animated_sprite_editor_component.dart`.
  static final animatedSprite = ComponentSchema<AnimatedSpriteComponent>(
    type: 'AnimatedSpriteComponent',
    hints: const ComponentHints(
      name: 'Animated Sprite',
      group: 'Rendering',
      description: 'Sprite-sheet animation with named clips and keyframes.',
      icon: Icons.movie_filter_rounded,
      accentColor: Color(0xFF7DE6B1),
      fieldGroups: {
        'Sprite Sheet': [
          'spritePath',
          'jsonPath',
          'frameWidth',
          'frameHeight',
          'columns',
          'rows',
        ],
        'Playback': ['activeClip', 'defaultFps', 'loop', 'playOnStart'],
      },
      fields: {
        'spritePath': FieldHint(label: 'Sprite'),
        'jsonPath': FieldHint(
          label: 'Animation JSON',
          fileExtensions: ['json'],
        ),
        'frameWidth': FieldHint(
          label: 'Frame W',
          scrub: ScrubHint(integer: true),
        ),
        'frameHeight': FieldHint(
          label: 'Frame H',
          scrub: ScrubHint(integer: true),
        ),
        'columns': FieldHint(label: 'Columns', scrub: ScrubHint(integer: true)),
        'rows': FieldHint(label: 'Rows', scrub: ScrubHint(integer: true)),
        'activeClip': FieldHint(label: 'Active Clip'),
        'defaultFps': FieldHint(label: 'FPS', scrub: ScrubHint(step: 0.5)),
        'loop': FieldHint(label: 'Loop'),
        'playOnStart': FieldHint(label: 'Play on Start'),
        'clips': FieldHint(label: 'Clips', visible: false),
      },
    ),
    id: 'animated_sprite_4f8a2b1c',
    create: () => AnimatedSpriteComponent(),
    fields: [
      SchemaField(
        name: 'spritePath',
        kind: FieldTypes.assetRef,
        read: (c) => (c as AnimatedSpriteComponent).spritePath,
        write: (c, v) =>
            (c as AnimatedSpriteComponent).spritePath = v as String,
      ),
      SchemaField(
        name: 'jsonPath',
        kind: FieldTypes.assetRef,
        read: (c) => (c as AnimatedSpriteComponent).jsonPath,
        write: (c, v) {
          final asc = c as AnimatedSpriteComponent;
          asc.jsonPath = v as String;
          asc.initialized = false;
        },
      ),
      SchemaField(
        name: 'frameWidth',
        kind: FieldTypes.integer,
        read: (c) => (c as AnimatedSpriteComponent).frameWidth,
        write: (c, v) =>
            (c as AnimatedSpriteComponent).frameWidth = (v as num).toInt(),
        min: 1,
      ),
      SchemaField(
        name: 'frameHeight',
        kind: FieldTypes.integer,
        read: (c) => (c as AnimatedSpriteComponent).frameHeight,
        write: (c, v) =>
            (c as AnimatedSpriteComponent).frameHeight = (v as num).toInt(),
        min: 1,
      ),
      SchemaField(
        name: 'columns',
        kind: FieldTypes.integer,
        read: (c) => (c as AnimatedSpriteComponent).columns,
        write: (c, v) =>
            (c as AnimatedSpriteComponent).columns = (v as num).toInt(),
        min: 1,
      ),
      SchemaField(
        name: 'rows',
        kind: FieldTypes.integer,
        read: (c) => (c as AnimatedSpriteComponent).rows,
        write: (c, v) =>
            (c as AnimatedSpriteComponent).rows = (v as num).toInt(),
        min: 1,
      ),
      SchemaField(
        name: 'activeClip',
        kind: FieldTypes.text,
        read: (c) => (c as AnimatedSpriteComponent).activeClip,
        write: (c, v) =>
            (c as AnimatedSpriteComponent).activeClip = v as String,
      ),
      SchemaField(
        name: 'defaultFps',
        kind: FieldTypes.decimal,
        read: (c) => (c as AnimatedSpriteComponent).defaultFps,
        write: (c, v) =>
            (c as AnimatedSpriteComponent).defaultFps = (v as num).toDouble(),
        min: 0.1,
        max: 120,
      ),
      SchemaField(
        name: 'loop',
        kind: FieldTypes.boolean,
        read: (c) => (c as AnimatedSpriteComponent).loop,
        write: (c, v) => (c as AnimatedSpriteComponent).loop = v as bool,
      ),
      SchemaField(
        name: 'playOnStart',
        kind: FieldTypes.boolean,
        read: (c) => (c as AnimatedSpriteComponent).playOnStart,
        write: (c, v) => (c as AnimatedSpriteComponent).playOnStart = v as bool,
      ),
      SchemaField(
        name: 'clips',
        kind: FieldTypes.map,
        read: (c) => (c as AnimatedSpriteComponent).clipsToJson(),
        write: (c, v) => (c as AnimatedSpriteComponent).clipsFromJson(v),
      ),
    ],
  );

  /// [AnimationControllerComponent], from `animation_controller_editor_component.dart`.
  static final animationController =
      ComponentSchema<AnimationControllerComponent>(
        type: 'AnimationControllerComponent',
        hints: const ComponentHints(
          name: 'Animation Controller',
          group: 'Animation',
          icon: Icons.timeline_rounded,
          accentColor: Color(0xFF7DD8E0),
          fieldGroups: {
            'Playback': ['duration', 'loop', 'playOnStart'],
          },
          fields: {
            'duration': FieldHint(
              label: 'Duration (s)',
              scrub: ScrubHint(step: 0.1, fractionDigits: 2),
            ),
            'loop': FieldHint(label: 'Loop'),
            'playOnStart': FieldHint(label: 'Play on Start'),
            'keyframes': FieldHint(label: 'Keyframes', visible: false),
            'events': FieldHint(label: 'Events', visible: false),
          },
        ),
        id: 'animation_controller_8c3f2e91',
        create: () => AnimationControllerComponent(),
        fields: [
          SchemaField(
            name: 'duration',
            kind: FieldTypes.decimal,
            read: (c) => (c as AnimationControllerComponent).duration,
            write: (c, v) => (c as AnimationControllerComponent).duration =
                (v as num).toDouble(),
            min: 0.1,
            max: 600,
          ),
          SchemaField(
            name: 'loop',
            kind: FieldTypes.boolean,
            read: (c) => (c as AnimationControllerComponent).loop,
            write: (c, v) =>
                (c as AnimationControllerComponent).loop = v as bool,
          ),
          SchemaField(
            name: 'playOnStart',
            kind: FieldTypes.boolean,
            read: (c) => (c as AnimationControllerComponent).playOnStart,
            write: (c, v) =>
                (c as AnimationControllerComponent).playOnStart = v as bool,
          ),
          SchemaField(
            name: 'keyframes',
            kind: FieldTypes.list,
            read: (c) => (c as AnimationControllerComponent).keyframes
                .map((k) => k.toJson())
                .toList(),
            write: (c, v) {
              final acc = c as AnimationControllerComponent;
              acc.keyframes.clear();
              if (v is List) {
                for (final item in v) {
                  if (item is Map) {
                    acc.keyframes.add(
                      TransformKeyframe.fromJson(item.cast<String, dynamic>()),
                    );
                  }
                }
              }
            },
          ),
          SchemaField(
            name: 'events',
            kind: FieldTypes.list,
            read: (c) => (c as AnimationControllerComponent).events
                .map((e) => e.toJson())
                .toList(),
            write: (c, v) {
              final acc = c as AnimationControllerComponent;
              acc.events.clear();
              if (v is List) {
                for (final item in v) {
                  if (item is Map) {
                    acc.events.add(
                      AnimationEvent.fromJson(item.cast<String, dynamic>()),
                    );
                  }
                }
              }
            },
          ),
        ],
      );

  /// [AnimationStateComponent], from `animation_state_editor_component.dart`.
  static final animationState = ComponentSchema<AnimationStateComponent>(
    type: 'AnimationStateComponent',
    hints: const ComponentHints(
      name: 'Animation State',
      group: 'Animation',
      icon: Icons.animation,
      accentColor: Color(0xFFFFCA28),
      fieldGroups: {
        'Animation': ['animName', 'frameCount', 'frameDuration'],
        'State': ['loop', 'playing'],
      },
      fields: {
        'animName': FieldHint(label: 'Name'),
        'frameCount': FieldHint(
          label: 'Frames',
          scrub: ScrubHint(integer: true),
        ),
        'frameDuration': FieldHint(
          label: 'Dur(s)',
          scrub: ScrubHint(step: 0.01, fractionDigits: 3),
        ),
        'loop': FieldHint(label: 'Loop'),
        'playing': FieldHint(label: 'Playing'),
      },
    ),
    id: 'animation_state_40e001f0',
    create: () => AnimationStateComponent(
      currentAnimation: 'idle',
      frameCount: 4,
      frameDuration: 0.1,
    ),
    fields: [
      SchemaField(
        name: 'animName',
        kind: FieldTypes.text,
        read: (c) => (c as AnimationStateComponent).currentAnimation,
        write: (c, v) =>
            (c as AnimationStateComponent).currentAnimation = v as String,
      ),
      SchemaField(
        name: 'frameCount',
        kind: FieldTypes.integer,
        read: (c) => (c as AnimationStateComponent).frameCount,
        write: (c, v) =>
            (c as AnimationStateComponent).frameCount = (v as num).toInt(),
        min: 1.0,
      ),
      SchemaField(
        name: 'frameDuration',
        kind: FieldTypes.decimal,
        read: (c) => (c as AnimationStateComponent).frameDuration,
        write: (c, v) => (c as AnimationStateComponent).frameDuration =
            (v as num).toDouble(),
        min: 0.0,
      ),
      SchemaField(
        name: 'loop',
        kind: FieldTypes.boolean,
        read: (c) => (c as AnimationStateComponent).loop,
        write: (c, v) => (c as AnimationStateComponent).loop = v as bool,
      ),
      SchemaField(
        name: 'playing',
        kind: FieldTypes.boolean,
        read: (c) => (c as AnimationStateComponent).isPlaying,
        write: (c, v) => (c as AnimationStateComponent).isPlaying = v as bool,
      ),
    ],
  );

  /// [AudioSourceComponent], from `audio_source_editor_component.dart`.
  static final audioSource = ComponentSchema<AudioSourceComponent>(
    type: 'AudioSourceComponent',
    hints: const ComponentHints(
      name: 'Audio Source',
      group: 'Audio',
      icon: Icons.volume_up,
      accentColor: Color(0xFFAB47BC),
      fieldGroups: {
        'Clip': ['path'],
        'Playback': ['loop', 'playOnAdd', 'volume', 'pitch'],
      },
      fields: {
        'path': FieldHint(label: 'Path', fileExtensions: ['mp3', 'wav', 'ogg']),
        'loop': FieldHint(label: 'Loop'),
        'playOnAdd': FieldHint(label: 'Play on Add'),
        'volume': FieldHint(
          label: 'Volume',
          scrub: ScrubHint(step: 0.05, fractionDigits: 2),
        ),
        'pitch': FieldHint(
          label: 'Pitch',
          scrub: ScrubHint(step: 0.05, fractionDigits: 2),
        ),
      },
    ),
    id: 'audio_source_111e2e48',
    create: () => AudioSourceComponent(clipPath: ''),
    fields: [
      SchemaField(
        name: 'path',
        kind: FieldTypes.assetRef,
        read: (c) => (c as AudioSourceComponent).clipPath,
        write: (c, v) => (c as AudioSourceComponent).clipPath = v as String,
      ),
      SchemaField(
        name: 'loop',
        kind: FieldTypes.boolean,
        read: (c) => (c as AudioSourceComponent).loop,
        write: (c, v) => (c as AudioSourceComponent).loop = v as bool,
      ),
      SchemaField(
        name: 'playOnAdd',
        kind: FieldTypes.boolean,
        read: (c) => (c as AudioSourceComponent).playOnAdd,
        write: (c, v) => (c as AudioSourceComponent).playOnAdd = v as bool,
      ),
      SchemaField(
        name: 'volume',
        kind: FieldTypes.decimal,
        read: (c) => (c as AudioSourceComponent).volume,
        write: (c, v) => (c as AudioSourceComponent).volume = (v as num)
            .toDouble()
            .clamp(0.0, 1.0),
        min: 0.0,
        max: 1.0,
      ),
      SchemaField(
        name: 'pitch',
        kind: FieldTypes.decimal,
        read: (c) => (c as AudioSourceComponent).pitch,
        write: (c, v) =>
            (c as AudioSourceComponent).pitch = (v as num).toDouble(),
        min: 0.0,
      ),
    ],
  );

  /// [AudioStreamComponent], from `audio_stream_editor_component.dart`.
  static final audioStream = ComponentSchema<AudioStreamComponent>(
    type: 'AudioStreamComponent',
    hints: const ComponentHints(
      name: 'Audio Stream',
      group: 'Audio',
      icon: Icons.graphic_eq,
      accentColor: Color(0xFFAB47BC),
      fieldGroups: {
        'Stream': ['streamPath'],
        'Playback': ['loop', 'playOnAdd', 'volume'],
      },
      fields: {
        'streamPath': FieldHint(
          label: 'Path',
          fileExtensions: ['mp3', 'wav', 'ogg'],
        ),
        'loop': FieldHint(label: 'Loop'),
        'playOnAdd': FieldHint(label: 'Play on Add'),
        'volume': FieldHint(
          label: 'Volume',
          scrub: ScrubHint(step: 0.05, fractionDigits: 2),
        ),
      },
    ),
    id: 'audio_stream_91f6500b',
    create: () => AudioStreamComponent(path: ''),
    fields: [
      SchemaField(
        name: 'streamPath',
        kind: FieldTypes.assetRef,
        read: (c) => (c as AudioStreamComponent).path,
        write: (c, v) => (c as AudioStreamComponent).path = v as String,
      ),
      SchemaField(
        name: 'loop',
        kind: FieldTypes.boolean,
        read: (c) => (c as AudioStreamComponent).loop,
        write: (c, v) => (c as AudioStreamComponent).loop = v as bool,
      ),
      SchemaField(
        name: 'playOnAdd',
        kind: FieldTypes.boolean,
        read: (c) => (c as AudioStreamComponent).playOnAdd,
        write: (c, v) => (c as AudioStreamComponent).playOnAdd = v as bool,
      ),
      SchemaField(
        name: 'volume',
        kind: FieldTypes.decimal,
        read: (c) => (c as AudioStreamComponent).volume,
        write: (c, v) => (c as AudioStreamComponent).volume = (v as num)
            .toDouble()
            .clamp(0.0, 1.0),
        min: 0.0,
        max: 1.0,
      ),
    ],
  );

  /// [ButtonComponent], from `button_editor_component.dart`.
  static final button = ComponentSchema<ButtonComponent>(
    type: 'ButtonComponent',
    hints: const ComponentHints(
      name: 'Button',
      group: 'UI',
      icon: Icons.smart_button,
      accentColor: Color(0xFF5C6BC0),
      fieldGroups: {
        'Size': ['w', 'h'],
        'Text': ['label'],
      },
      fields: {
        ..._sizeHints,
        'label': FieldHint(label: 'Label'),
      },
    ),
    painter: const ButtonComponentPainter(),
    id: 'button_388d5c40',
    create: () => ButtonComponent(text: 'Button', size: const Size(120, 40)),
    extent: const _UiExtent(),
    fields: [
      SchemaField(
        name: 'w',
        kind: FieldTypes.decimal,
        read: (c) => (c as ButtonComponent).size.width,
        write: (c, v) {
          final b = c as ButtonComponent;
          b.size = Size((v as num).toDouble(), b.size.height);
        },
        min: 0.0,
      ),
      SchemaField(
        name: 'h',
        kind: FieldTypes.decimal,
        read: (c) => (c as ButtonComponent).size.height,
        write: (c, v) {
          final b = c as ButtonComponent;
          b.size = Size(b.size.width, (v as num).toDouble());
        },
        min: 0.0,
      ),
      SchemaField(
        name: 'label',
        kind: FieldTypes.text,
        read: (c) => (c as ButtonComponent).text,
        write: (c, v) => (c as ButtonComponent).text = v as String,
      ),
    ],
  );

  /// [EllipticalProgressComponent], from `elliptical_progress_editor_component.dart`.
  static final ellipticalProgress =
      ComponentSchema<EllipticalProgressComponent>(
        type: 'EllipticalProgressComponent',
        hints: const ComponentHints(
          name: 'Elliptical Progress',
          group: 'UI',
          icon: Icons.donut_large,
          accentColor: Color(0xFF5C6BC0),
          fieldGroups: {
            'Size': ['radius'],
            'Value': ['progressValue'],
          },
          fields: {
            'radius': FieldHint(
              label: 'Radius',
              scrub: ScrubHint(step: 0.5, fractionDigits: 1),
            ),
            'progressValue': FieldHint(
              label: 'Progress',
              scrub: ScrubHint(step: 0.02, fractionDigits: 2),
            ),
          },
        ),
        painter: const EllipticalProgressPainter(),
        id: 'elliptical_progress_d287c579',
        create: () => EllipticalProgressComponent(radius: 30),
        extent: const _UiExtent(),
        fields: [
          SchemaField(
            name: 'radius',
            kind: FieldTypes.decimal,
            read: (c) => (c as EllipticalProgressComponent).size.width / 2,
            write: (c, v) {
              final progress = c as EllipticalProgressComponent;
              final newRadius = (v as num).toDouble();
              progress.size = Size(newRadius * 2, progress.size.height);
            },
            min: 0.0,
          ),
          SchemaField(
            name: 'progressValue',
            kind: FieldTypes.decimal,
            read: (c) => (c as EllipticalProgressComponent).progress,
            write: (c, v) => (c as EllipticalProgressComponent).setProgress(
              (v as num).toDouble(),
            ),
            min: 0.0,
            max: 1.0,
          ),
        ],
      );

  /// [LinearProgressComponent], from `linear_progress_editor_component.dart`.
  static final linearProgress = ComponentSchema<LinearProgressComponent>(
    type: 'LinearProgressComponent',
    hints: const ComponentHints(
      name: 'Linear Progress',
      group: 'UI',
      icon: Icons.linear_scale,
      accentColor: Color(0xFF5C6BC0),
      fieldGroups: {
        'Size': ['w', 'h'],
        'Value': ['progressValue'],
      },
      fields: {
        ..._sizeHints,
        'progressValue': FieldHint(
          label: 'Progress',
          scrub: ScrubHint(step: 0.02, fractionDigits: 2),
        ),
      },
    ),
    painter: const LinearProgressPainter(),
    id: 'linear_progress_006125a9',
    create: () => LinearProgressComponent(size: const Size(200, 20)),
    extent: const _UiExtent(),
    fields: [
      SchemaField(
        name: 'w',
        kind: FieldTypes.decimal,
        read: (c) => (c as LinearProgressComponent).size.width,
        write: (c, v) {
          final p = c as LinearProgressComponent;
          p.size = Size((v as num).toDouble(), p.size.height);
        },
        min: 0.0,
      ),
      SchemaField(
        name: 'h',
        kind: FieldTypes.decimal,
        read: (c) => (c as LinearProgressComponent).size.height,
        write: (c, v) {
          final p = c as LinearProgressComponent;
          p.size = Size(p.size.width, (v as num).toDouble());
        },
        min: 0.0,
      ),
      SchemaField(
        name: 'progressValue',
        kind: FieldTypes.decimal,
        read: (c) => (c as LinearProgressComponent).progress,
        write: (c, v) =>
            (c as LinearProgressComponent).setProgress((v as num).toDouble()),
        min: 0.0,
        max: 1.0,
      ),
    ],
  );

  /// [UIComponent], from `ui_catalog_editor_component.dart`.
  static final ui = ComponentSchema<UIComponent>(
    type: 'UIComponent',
    hints: const ComponentHints(
      name: 'UI',
      group: 'UI',
      description: 'Base UI layout container.',
      icon: Icons.dashboard_outlined,
      accentColor: Color(0xFF5C6BC0),
      fieldGroups: {
        'Size': ['w', 'h'],
        'State': ['visible', 'enabled'],
      },
      fields: {
        ..._sizeHints,
        'visible': FieldHint(label: 'Visible'),
        'enabled': FieldHint(label: 'Enabled'),
      },
    ),
    id: 'ui_6018ae16',
    create: () => UIComponent(size: const Size(100, 40)),
    extent: const _UiExtent(),
    fields: [
      SchemaField(
        name: 'w',
        kind: FieldTypes.decimal,
        read: (c) => (c as UIComponent).size.width,
        write: (c, v) {
          final ui = c as UIComponent;
          ui.size = Size((v as num).toDouble(), ui.size.height);
        },
        min: 0.0,
      ),
      SchemaField(
        name: 'h',
        kind: FieldTypes.decimal,
        read: (c) => (c as UIComponent).size.height,
        write: (c, v) {
          final ui = c as UIComponent;
          ui.size = Size(ui.size.width, (v as num).toDouble());
        },
        min: 0.0,
      ),
      SchemaField(
        name: 'visible',
        kind: FieldTypes.boolean,
        read: (c) => (c as UIComponent).visible,
        write: (c, v) => (c as UIComponent).visible = v as bool,
      ),
      SchemaField(
        name: 'enabled',
        kind: FieldTypes.boolean,
        read: (c) => (c as UIComponent).enabled,
        write: (c, v) => (c as UIComponent).enabled = v as bool,
      ),
    ],
  );

  /// [JoystickInputComponent], from `joystick_input_editor_component.dart`.
  static final joystickInput = ComponentSchema<JoystickInputComponent>(
    type: 'JoystickInputComponent',
    hints: const ComponentHints(
      name: 'Joystick Input',
      group: 'Input',
      icon: Icons.gamepad,
      accentColor: Color(0xFFEF5350),
    ),
    id: 'joystick_input_ae2e7fcb',
    create: () => JoystickInputComponent(),
    fields: const [],
  );

  /// Every schema above.
  static List<ComponentCodec> get all => [
    layer,
    checkpoint,
    text,
    line,
    polygon,
    animatedSprite,
    animationController,
    animationState,
    audioSource,
    audioStream,
    button,
    ellipticalProgress,
    linearProgress,
    ui,
    joystickInput,
  ];

  /// Presentation shared by the UI components' size fields.
  static const Map<String, FieldHint> _sizeHints = {
    'w': FieldHint(label: 'W', scrub: ScrubHint(fractionDigits: 1)),
    'h': FieldHint(label: 'H', scrub: ScrubHint(fractionDigits: 1)),
  };
}

/// A polygon's size is its vertices' bounds; scaling moves the vertices.
class _PolygonExtent extends ComponentExtent {
  const _PolygonExtent();

  @override
  Size? sizeOf(Component component) {
    final vertices = (component as PolygonComponent).vertices;
    if (vertices.isEmpty) return null;
    var bounds = Rect.fromPoints(vertices.first, vertices.first);
    for (final v in vertices) {
      bounds = bounds.expandToInclude(Rect.fromPoints(v, v));
    }
    return bounds.size;
  }

  @override
  bool scale(Component component, double sx, double sy) {
    final polygon = component as PolygonComponent;
    polygon.vertices = [
      for (final v in polygon.vertices) Offset(v.dx * sx, v.dy * sy),
    ];
    return true;
  }
}

/// A line's size is the box its endpoints span; scaling moves them about
/// their midpoint.
class _LineExtent extends ComponentExtent {
  const _LineExtent();

  @override
  Size? sizeOf(Component component) {
    final line = component as LineComponent;
    return Rect.fromPoints(line.start, line.end).size;
  }

  @override
  bool scale(Component component, double sx, double sy) {
    final line = component as LineComponent;
    final mid = (line.start + line.end) / 2;
    Offset about(Offset p) =>
        Offset(mid.dx + (p.dx - mid.dx) * sx, mid.dy + (p.dy - mid.dy) * sy);
    line
      ..start = about(line.start)
      ..end = about(line.end);
    return true;
  }
}

/// A UI element is its own size.
class _UiExtent extends ComponentExtent {
  const _UiExtent();

  @override
  Size? sizeOf(Component component) => (component as UIComponent).size;

  @override
  bool scale(Component component, double sx, double sy) {
    final ui = component as UIComponent;
    ui.size = Size(ui.size.width * sx, ui.size.height * sy);
    return true;
  }
}

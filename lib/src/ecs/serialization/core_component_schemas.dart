library;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/painting.dart';
import 'package:just_dart/just_dart.dart';

import '../components/components.dart';
import '../../subsystems/timeline/timeline_asset.dart';
import '../../subsystems/ui/ui_actions.dart';
import '../../subsystems/ui/ui_text_style.dart';
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
        // On a map layer these follow the layer: shown only off one.
        'layerId': FieldHint(label: 'Layer', visibleWhen: _offMapLayer),
        'layer': FieldHint(
          label: 'Order',
          scrub: ScrubHint(step: 10, integer: true),
          visibleWhen: _offMapLayer,
        ),
        'zOrder': FieldHint(
          label: 'Z',
          scrub: ScrubHint(integer: true),
          visibleWhen: _offMapLayer,
        ),
        'mapLayer': FieldHint(
          label: 'Map layer',
          description:
              'The layer of its level map it belongs to: it draws and hides '
              'with it. Move it to another in the scene tree.',
          editable: false,
          visibleWhen: _onMapLayer,
        ),
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
      SchemaField(
        name: 'mapLayer',
        kind: FieldTypes.integer,
        read: (c) => (c as LayerComponent).mapLayer,
        write: (c, v) => (c as LayerComponent).mapLayer = (v as num?)?.toInt(),
      ),
    ],
  );

  static bool _onMapLayer(Component c) =>
      (c as LayerComponent).mapLayer != null;
  static bool _offMapLayer(Component c) => !_onMapLayer(c);

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

  /// [TextComponent]: text in the world, and everything about how it looks.
  static final text = ComponentSchema<TextComponent>(
    type: 'TextComponent',
    hints: const ComponentHints(
      name: 'Text',
      group: 'UI',
      description:
          'Text at this entity. It can read the game — "Coins: {coins}" — '
          'be looked up in the current language with @a.key, and carry tags '
          'like [b]bold[/b].',
      icon: Icons.text_fields,
      accentColor: Color(0xFF5C6BC0),
      fieldGroups: {
        'Content': ['textValue', 'styleRole'],
        'Look': ['style'],
        'Layout': ['w', 'h', 'align', 'overflow', 'wrap', 'maxLines'],
        'Reveal': ['revealSpeed'],
      },
      fieldRows: [
        FieldRowHint('Size', {'w': 'W', 'h': 'H'}),
      ],
      fields: {
        'textValue': FieldHint(
          label: 'Text',
          description:
              'Tags: [b] [i] [color=#f80] [size=20] [icon=name] [wave] '
              '[shake]. Bindings: {coins}, {time:mm:ss}, {self.name}.',
        ),
        'styleRole': FieldHint(
          label: 'Role',
          description:
              'What kind of text this is. The theme decides what a role '
              'looks like, so restyling every label in the game is one '
              'file rather than every entity.',
        ),
        'style': FieldHint(
          label: 'Style',
          description:
              'What this text says for itself, over the role. Anything '
              'left unset is the role’s, shown greyed.',
        ),
        'w': FieldHint(
          label: 'Width',
          scrub: ScrubHint(step: 4, fractionDigits: 0),
        ),
        'h': FieldHint(
          label: 'Height',
          scrub: ScrubHint(step: 4, fractionDigits: 0),
        ),
        'align': FieldHint(label: 'Align'),
        'overflow': FieldHint(
          label: 'Overflow',
          description: 'Shrink fits the text to the box.',
        ),
        'wrap': FieldHint(
          label: 'Wrap',
          description: 'Break lines at the width above.',
        ),
        'maxLines': FieldHint(
          label: 'Max lines',
          scrub: ScrubHint(integer: true),
        ),
        'revealSpeed': FieldHint(
          label: 'Type out',
          description: 'Characters a second; 0 shows it all at once.',
          scrub: ScrubHint(step: 1, fractionDigits: 0),
        ),
      },
    ),
    painter: const TextComponentPainter(),
    id: 'text_effcff19',
    create: () => TextComponent(text: 'Text'),
    extent: const _UiExtent(),
    fields: [
      SchemaField(
        name: 'textValue',
        kind: FieldTypes.uiText,
        read: (c) => (c as TextComponent).text,
        write: (c, v) => (c as TextComponent).text = v as String? ?? '',
      ),
      SchemaField(
        name: 'style',
        kind: FieldTypes.uiTextStyle,
        read: (c) => (c as TextComponent).style,
        write: (c, v) => (c as TextComponent).style = v is UiTextStyle
            ? v
            : const UiTextStyle(),
      ),
      SchemaField(
        name: 'styleRole',
        kind: FieldTypes.uiStyleRole,
        read: (c) => (c as TextComponent).styleRole,
        write: (c, v) =>
            (c as TextComponent).styleRole = v as String? ?? 'body',
      ),
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
        name: 'align',
        kind: const EnumFieldType(
          UiTextAlign.values,
          fallback: UiTextAlign.center,
          id: 'enum.uiTextAlign',
        ),
        read: (c) => (c as TextComponent).align,
        write: (c, v) => (c as TextComponent).align = v as UiTextAlign,
      ),
      SchemaField(
        name: 'overflow',
        kind: const EnumFieldType(
          UiTextOverflow.values,
          fallback: UiTextOverflow.visible,
          id: 'enum.uiTextOverflow',
        ),
        read: (c) => (c as TextComponent).overflow,
        write: (c, v) => (c as TextComponent).overflow = v as UiTextOverflow,
      ),
      SchemaField(
        name: 'wrap',
        kind: FieldTypes.boolean,
        read: (c) => (c as TextComponent).wrap,
        write: (c, v) => (c as TextComponent).wrap = v as bool? ?? false,
      ),
      SchemaField(
        name: 'maxLines',
        kind: FieldTypes.integer,
        read: (c) => (c as TextComponent).maxLines,
        write: (c, v) => (c as TextComponent).maxLines = (v as num?)?.toInt(),
        min: 0,
      ),
      SchemaField(
        name: 'revealSpeed',
        kind: FieldTypes.decimal,
        read: (c) => (c as TextComponent).revealSpeed,
        write: (c, v) =>
            (c as TextComponent).revealSpeed = (v as num?)?.toDouble() ?? 0,
        min: 0,
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

  /// [SpriteAnimationComponent]: a clip from a sprite atlas.
  static final spriteAnimation = ComponentSchema<SpriteAnimationComponent>(
    type: 'SpriteAnimationComponent',
    hints: const ComponentHints(
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
        write: (c, v) => (c as SpriteAnimationComponent).pixelArt = v as bool,
      ),
    ],
  );

  /// [AnimatorComponent]: the animation state machine.
  static final animator = ComponentSchema<AnimatorComponent>(
    type: 'AnimatorComponent',
    hints: const ComponentHints(
      name: 'Animator',
      group: 'Animation',
      description:
          'A state machine that picks which clip the Sprite Animation plays.',
      icon: Icons.account_tree_outlined,
      accentColor: Color(0xFFFFCA28),
      fields: {
        'graphPath': FieldHint(
          label: 'Graph',
          fileExtensions: ['animator.json', 'json'],
        ),
        'enabled': FieldHint(label: 'Enabled'),
        'faceVelocity': FieldHint(
          label: 'Face movement',
          description: 'Flip the sprite to face the way it moves.',
        ),
      },
    ),
    id: 'animator_5b0e6a37',
    create: AnimatorComponent.new,
    fields: [
      SchemaField(
        name: 'graphPath',
        kind: FieldTypes.assetRef,
        read: (c) => (c as AnimatorComponent).graphPath,
        write: (c, v) => (c as AnimatorComponent).graphPath = v as String,
      ),
      SchemaField(
        name: 'enabled',
        kind: FieldTypes.boolean,
        read: (c) => (c as AnimatorComponent).enabled,
        write: (c, v) => (c as AnimatorComponent).enabled = v as bool,
      ),
      SchemaField(
        name: 'faceVelocity',
        kind: FieldTypes.boolean,
        read: (c) => (c as AnimatorComponent).faceVelocity,
        write: (c, v) => (c as AnimatorComponent).faceVelocity = v as bool,
      ),
    ],
  );

  /// [TimelinePlayerComponent]: plays a timeline asset, or an inline one.
  static final timelinePlayer = ComponentSchema<TimelinePlayerComponent>(
    type: 'TimelinePlayerComponent',
    hints: const ComponentHints(
      name: 'Timeline Player',
      group: 'Animation',
      description:
          'Plays a timeline: keyed fields, sprite clips, events, camera '
          'shots and sounds on one clock.',
      icon: Icons.timeline_rounded,
      accentColor: Color(0xFF7DD8E0),
      fieldGroups: {
        'Timeline': ['timelinePath'],
        'Playback': ['playOnStart', 'speed', 'wrap', 'listenSignal'],
        'Part of it': ['from', 'to'],
      },
      fields: {
        'timelinePath': FieldHint(
          label: 'Timeline',
          description:
              'A .timeline.json asset. Empty plays the timeline saved '
              'inside this component.',
          fileExtensions: ['timeline.json', 'json'],
        ),
        'inline': FieldHint(label: 'Inline timeline', visible: false),
        'playOnStart': FieldHint(label: 'Play on Start'),
        'speed': FieldHint(
          label: 'Speed',
          description: 'Negative plays backwards.',
          scrub: ScrubHint(step: 0.05, fractionDigits: 2),
        ),
        'wrap': FieldHint(label: 'Wrap'),
        'listenSignal': FieldHint(
          label: 'Play on signal',
          description: 'A timeline signal that starts this player.',
        ),
        'from': FieldHint(
          label: 'Play from',
          description:
              'Seconds. Zero starts at the beginning. With Play to, this '
              'entity runs only part of the timeline — so one file can serve '
              'several entities differently.',
          scrub: ScrubHint(step: 0.05, fractionDigits: 2),
        ),
        'to': FieldHint(
          label: 'Play to',
          description: 'Seconds. Zero plays to the end.',
          scrub: ScrubHint(step: 0.05, fractionDigits: 2),
        ),
      },
    ),
    id: 'timeline_player_3d91c7aa',
    create: TimelinePlayerComponent.new,
    fields: [
      SchemaField(
        name: 'timelinePath',
        kind: FieldTypes.assetRef,
        read: (c) => (c as TimelinePlayerComponent).timelinePath,
        write: (c, v) =>
            (c as TimelinePlayerComponent).timelinePath = v as String? ?? '',
      ),
      SchemaField(
        name: 'inline',
        kind: FieldTypes.map,
        read: (c) => (c as TimelinePlayerComponent).inline?.toJson(),
        write: (c, v) => (c as TimelinePlayerComponent).inline = v is Map
            ? TimelineAsset.fromJson(v.cast<String, dynamic>())
            : null,
      ),
      SchemaField(
        name: 'playOnStart',
        kind: FieldTypes.boolean,
        read: (c) => (c as TimelinePlayerComponent).playOnStart,
        write: (c, v) => (c as TimelinePlayerComponent).playOnStart = v as bool,
      ),
      SchemaField(
        name: 'speed',
        kind: FieldTypes.decimal,
        read: (c) => (c as TimelinePlayerComponent).speed,
        write: (c, v) =>
            (c as TimelinePlayerComponent).speed = (v as num).toDouble(),
        min: -16,
        max: 16,
      ),
      SchemaField(
        name: 'wrap',
        kind: const EnumFieldType(
          TimelineWrapChoice.values,
          fallback: TimelineWrapChoice.fromTimeline,
          id: 'enum.timelineWrapChoice',
        ),
        read: (c) => (c as TimelinePlayerComponent).wrap,
        write: (c, v) =>
            (c as TimelinePlayerComponent).wrap = v as TimelineWrapChoice,
      ),
      SchemaField(
        name: 'listenSignal',
        kind: FieldTypes.text,
        read: (c) => (c as TimelinePlayerComponent).listenSignal,
        write: (c, v) =>
            (c as TimelinePlayerComponent).listenSignal = v as String? ?? '',
      ),
      SchemaField(
        name: 'from',
        kind: FieldTypes.decimal,
        read: (c) => (c as TimelinePlayerComponent).from,
        // A scene saved before these existed has no key for them.
        write: (c, v) =>
            (c as TimelinePlayerComponent).from = (v as num?)?.toDouble() ?? 0,
        min: 0,
      ),
      SchemaField(
        name: 'to',
        kind: FieldTypes.decimal,
        read: (c) => (c as TimelinePlayerComponent).to,
        // A scene saved before these existed has no key for them.
        write: (c, v) =>
            (c as TimelinePlayerComponent).to = (v as num?)?.toDouble() ?? 0,
        min: 0,
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

  /// [ButtonComponent]: a button in the world, and what pressing it does.
  static final button = ComponentSchema<ButtonComponent>(
    type: 'ButtonComponent',
    hints: const ComponentHints(
      name: 'Button',
      group: 'UI',
      description:
          'A button at this entity. What it does is a list of actions the '
          'scene holds by name, so it survives a save.',
      icon: Icons.smart_button,
      accentColor: Color(0xFF7E57C2),
      fieldGroups: {
        'Label': ['label', 'styleRole', 'labelStyle'],
        'Does': ['onPressed'],
        'Look': ['colorRole', 'color', 'borderColor', 'borderRadius'],
        'Size': ['w', 'h'],
      },
      fieldRows: [
        FieldRowHint('Size', {'w': 'W', 'h': 'H'}),
      ],
      fields: {
        'label': FieldHint(
          label: 'Label',
          description: 'Bindings and tags work here as they do in a text.',
        ),
        'styleRole': FieldHint(
          label: 'Role',
          description: 'The theme style the label reads as.',
        ),
        'labelStyle': FieldHint(label: 'Label style'),
        'onPressed': FieldHint(
          label: 'On pressed',
          description: 'What happens when the button is released on.',
        ),
        'colorRole': FieldHint(
          label: 'Colour role',
          description: 'A colour from the theme: primary, danger, surface…',
        ),
        'color': FieldHint(
          label: 'Colour',
          description: 'Its own colour, which wins over the role.',
        ),
        'borderColor': FieldHint(label: 'Border'),
        'borderRadius': FieldHint(
          label: 'Corner',
          scrub: ScrubHint(step: 1, fractionDigits: 0),
        ),
        'w': FieldHint(
          label: 'Width',
          scrub: ScrubHint(step: 4, fractionDigits: 0),
        ),
        'h': FieldHint(
          label: 'Height',
          scrub: ScrubHint(step: 4, fractionDigits: 0),
        ),
      },
    ),
    painter: const ButtonComponentPainter(),
    id: 'button_388d5c40',
    create: () => ButtonComponent(),
    extent: const _UiExtent(),
    fields: [
      SchemaField(
        name: 'label',
        kind: FieldTypes.uiText,
        read: (c) => (c as ButtonComponent).label,
        write: (c, v) => (c as ButtonComponent).label = v as String? ?? '',
      ),
      SchemaField(
        name: 'labelStyle',
        kind: FieldTypes.uiTextStyle,
        read: (c) => (c as ButtonComponent).labelStyle,
        write: (c, v) => (c as ButtonComponent).labelStyle = v is UiTextStyle
            ? v
            : const UiTextStyle(),
      ),
      SchemaField(
        name: 'styleRole',
        kind: FieldTypes.uiStyleRole,
        read: (c) => (c as ButtonComponent).styleRole,
        write: (c, v) =>
            (c as ButtonComponent).styleRole = v as String? ?? 'button',
      ),
      SchemaField(
        name: 'onPressed',
        kind: FieldTypes.uiActions,
        read: (c) => (c as ButtonComponent).onPressed,
        write: (c, v) => (c as ButtonComponent).onPressed = v is UiActionList
            ? v
            : UiActionList.empty,
      ),
      SchemaField(
        name: 'colorRole',
        kind: FieldTypes.uiColorRole,
        read: (c) => (c as ButtonComponent).colorRole,
        write: (c, v) =>
            (c as ButtonComponent).colorRole = v as String? ?? 'primary',
      ),
      SchemaField(
        name: 'color',
        kind: FieldTypes.color,
        read: (c) => (c as ButtonComponent).color,
        write: (c, v) => (c as ButtonComponent).color = v as Color?,
      ),
      SchemaField(
        name: 'borderColor',
        kind: FieldTypes.color,
        read: (c) => (c as ButtonComponent).borderColor,
        write: (c, v) => (c as ButtonComponent).borderColor = v as Color?,
      ),
      SchemaField(
        name: 'borderRadius',
        kind: FieldTypes.decimal,
        read: (c) => (c as ButtonComponent).borderRadius,
        write: (c, v) =>
            (c as ButtonComponent).borderRadius = (v as num?)?.toDouble() ?? 8,
        min: 0,
      ),
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
    spriteAnimation,
    animator,
    timelinePlayer,
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

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/painting.dart';
import 'package:just_dart/just_dart.dart' show Aabb3;

import '../core/core.dart';
import '../ecs/ecs.dart';
import '../ecs/serialization/serialization.dart';
import '../foundation/dimensions.dart';
import 'graphics_components.dart';

/// How the 3-D components are saved and shown in an editor. Every one is a
/// 3-D component (`Dimensions.threeD`).
abstract final class GraphicsSchemas {
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

  /// [LightComponent].
  static ComponentSchema<LightComponent> get light =>
      ComponentSchema<LightComponent>(
        type: 'LightComponent',
        id: 'light_3d_4f9a12d0',
        create: LightComponent.new,
        hints: ComponentHints(
          dimensions: Dimensions.threeD,
          name: 'Light',
          group: '3D',
          description: 'A directional, point or spot light.',
          icon: Icons.lightbulb_outline,
          accentColor: const Color(0xFFFFCA28),
          fields: {
            'kind': const FieldHint(label: 'Kind'),
            'color': const FieldHint(label: 'Colour'),
            'intensity': const FieldHint(
              label: 'Intensity',
              scrub: ScrubHint(step: 0.5, fractionDigits: 1),
            ),
            'range': FieldHint(
              label: 'Range',
              scrub: const ScrubHint(step: 0.5, fractionDigits: 1, suffix: 'm'),
              visibleWhen: (c) =>
                  (c as LightComponent).kind != LightKind.directional,
            ),
            'innerConeAngle': FieldHint(
              label: 'Inner cone',
              unit: AngleUnit.degrees,
              scrub: const ScrubHint(step: 1, fractionDigits: 0, suffix: '°'),
              visibleWhen: (c) => (c as LightComponent).kind == LightKind.spot,
            ),
            'outerConeAngle': FieldHint(
              label: 'Outer cone',
              unit: AngleUnit.degrees,
              scrub: const ScrubHint(step: 1, fractionDigits: 0, suffix: '°'),
              visibleWhen: (c) => (c as LightComponent).kind == LightKind.spot,
            ),
          },
        ),
        fields: [
          SchemaField(
            name: 'kind',
            kind: const EnumFieldType(
              LightKind.values,
              fallback: LightKind.point,
              id: 'graphics.lightKind',
            ),
            read: (c) => (c as LightComponent).kind,
            write: (c, v) => (c as LightComponent).kind = v as LightKind,
          ),
          SchemaField(
            name: 'color',
            kind: FieldTypes.color,
            read: (c) => (c as LightComponent).color,
            write: (c, v) => (c as LightComponent).color = v as Color,
          ),
          _decimal(
            'intensity',
            (c) => (c as LightComponent).intensity,
            (c, v) => (c as LightComponent).intensity = v,
            min: 0,
          ),
          _decimal(
            'range',
            (c) => (c as LightComponent).range,
            (c, v) => (c as LightComponent).range = v,
            min: 0,
          ),
          _decimal(
            'innerConeAngle',
            (c) => (c as LightComponent).innerConeAngle,
            (c, v) => (c as LightComponent).innerConeAngle = v,
            min: 0,
          ),
          _decimal(
            'outerConeAngle',
            (c) => (c as LightComponent).outerConeAngle,
            (c, v) => (c as LightComponent).outerConeAngle = v,
            min: 0,
          ),
        ],
      );

  /// [EnvironmentComponent].
  static ComponentSchema<EnvironmentComponent>
  get environment => ComponentSchema<EnvironmentComponent>(
    type: 'EnvironmentComponent',
    id: 'environment_3d_b38e5c17',
    create: EnvironmentComponent.new,
    hints: ComponentHints(
      dimensions: Dimensions.threeD,
      name: 'Environment',
      group: '3D',
      description: 'The sky and ambient light of a 3D scene.',
      icon: Icons.wb_sunny_outlined,
      accentColor: const Color(0xFF26C6DA),
      fields: {
        'sky': const FieldHint(label: 'Sky'),
        'zenith': FieldHint(
          label: 'Zenith',
          visibleWhen: (c) => (c as EnvironmentComponent).sky,
        ),
        'horizon': FieldHint(
          label: 'Horizon',
          visibleWhen: (c) => (c as EnvironmentComponent).sky,
        ),
        'ground': FieldHint(
          label: 'Ground',
          visibleWhen: (c) => (c as EnvironmentComponent).sky,
        ),
        'background': FieldHint(
          label: 'Background',
          visibleWhen: (c) => !(c as EnvironmentComponent).sky,
        ),
        'ambientSky': const FieldHint(label: 'Ambient above'),
        'ambientGround': const FieldHint(label: 'Ambient below'),
        'exposure': const FieldHint(
          label: 'Exposure',
          scrub: ScrubHint(step: 0.05, fractionDigits: 2),
        ),
        'fog': const FieldHint(label: 'Fog'),
        'fogColor': FieldHint(
          label: 'Fog colour',
          visibleWhen: (c) => (c as EnvironmentComponent).fog,
        ),
        'fogDensity': FieldHint(
          label: 'Fog density',
          scrub: const ScrubHint(step: 0.001, fractionDigits: 3),
          visibleWhen: (c) => (c as EnvironmentComponent).fog,
        ),
        'fogStart': FieldHint(
          label: 'Fog starts',
          scrub: const ScrubHint(step: 0.5, fractionDigits: 1, suffix: 'm'),
          visibleWhen: (c) => (c as EnvironmentComponent).fog,
        ),
        'reflections': const FieldHint(
          label: 'Reflections',
          description:
              'Light and reflections from the skybox or the sky, not the two ambient colours.',
        ),
        'reflectionStrength': FieldHint(
          label: 'Strength',
          scrub: const ScrubHint(step: 0.05, fractionDigits: 2),
          visibleWhen: (c) => (c as EnvironmentComponent).reflections,
        ),
        'skybox': const FieldHint(
          label: 'Skybox',
          description:
              'A panorama (.hdr) for the sky and its light; empty for the gradient.',
          fileExtensions: ['hdr'],
        ),
        'skyboxBlur': FieldHint(
          label: 'Skybox blur',
          scrub: const ScrubHint(step: 0.05, fractionDigits: 2),
          visibleWhen: (c) => (c as EnvironmentComponent).skybox.isNotEmpty,
        ),
      },
    ),
    fields: [
      SchemaField(
        name: 'sky',
        kind: FieldTypes.boolean,
        read: (c) => (c as EnvironmentComponent).sky,
        write: (c, v) => (c as EnvironmentComponent).sky = v as bool,
      ),
      _color('zenith', (c) => c.zenith, (c, v) => c.zenith = v),
      _color('horizon', (c) => c.horizon, (c, v) => c.horizon = v),
      _color('ground', (c) => c.ground, (c, v) => c.ground = v),
      _color('background', (c) => c.background, (c, v) => c.background = v),
      _color('ambientSky', (c) => c.ambientSky, (c, v) => c.ambientSky = v),
      _color(
        'ambientGround',
        (c) => c.ambientGround,
        (c, v) => c.ambientGround = v,
      ),
      _decimal(
        'exposure',
        (c) => (c as EnvironmentComponent).exposure,
        (c, v) => (c as EnvironmentComponent).exposure = v,
        min: 0,
      ),
      SchemaField(
        name: 'fog',
        kind: FieldTypes.boolean,
        read: (c) => (c as EnvironmentComponent).fog,
        write: (c, v) => (c as EnvironmentComponent).fog = v as bool,
      ),
      _color('fogColor', (c) => c.fogColor, (c, v) => c.fogColor = v),
      _decimal(
        'fogDensity',
        (c) => (c as EnvironmentComponent).fogDensity,
        (c, v) => (c as EnvironmentComponent).fogDensity = v,
        min: 0,
      ),
      _decimal(
        'fogStart',
        (c) => (c as EnvironmentComponent).fogStart,
        (c, v) => (c as EnvironmentComponent).fogStart = v,
        min: 0,
      ),
      SchemaField(
        name: 'reflections',
        kind: FieldTypes.boolean,
        read: (c) => (c as EnvironmentComponent).reflections,
        write: (c, v) => (c as EnvironmentComponent).reflections = v as bool,
      ),
      _decimal(
        'reflectionStrength',
        (c) => (c as EnvironmentComponent).reflectionStrength,
        (c, v) => (c as EnvironmentComponent).reflectionStrength = v,
        min: 0,
      ),
      SchemaField(
        name: 'skybox',
        kind: FieldTypes.assetRef,
        read: (c) => (c as EnvironmentComponent).skybox,
        write: (c, v) =>
            (c as EnvironmentComponent).skybox = v as String? ?? '',
      ),
      _decimal(
        'skyboxBlur',
        (c) => (c as EnvironmentComponent).skyboxBlur,
        (c, v) => (c as EnvironmentComponent).skyboxBlur = v.clamp(0.0, 1.0),
        min: 0,
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

  /// Every 3-D component.
  static List<ComponentSchema> get all => [
    model,
    light,
    environment,
    animationPlayer,
    socket,
  ];

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

  static SchemaField _color(
    String name,
    Color Function(EnvironmentComponent c) read,
    void Function(EnvironmentComponent c, Color v) write,
  ) => SchemaField(
    name: name,
    kind: FieldTypes.color,
    read: (c) => read(c as EnvironmentComponent),
    write: (c, v) => write(c as EnvironmentComponent, v as Color),
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

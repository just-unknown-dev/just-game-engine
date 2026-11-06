import 'package:flutter/material.dart' show Icons;
import 'package:flutter/painting.dart';
import 'package:just_graphics_engine/assets.dart' show Light3DKind;

import '../../../ecs/ecs.dart';
import '../../../foundation/dimensions.dart';
import 'environment_component.dart';
import 'light_3d_component.dart';

/// How the 3-D lights and the environment are saved and shown in an editor.
/// Every one is a 3-D component (`Dimensions.threeD`).
abstract final class Lighting3DDefinitions {
  /// [Light3DComponent].
  static ComponentDefinition<Light3DComponent> get light3D =>
      ComponentDefinition<Light3DComponent>(
        type: 'Light3DComponent',
        id: 'light_3d_4f9a12d0',
        create: Light3DComponent.new,
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
                  (c as Light3DComponent).kind != Light3DKind.directional,
            ),
            'innerConeAngle': FieldHint(
              label: 'Inner cone',
              unit: AngleUnit.degrees,
              scrub: const ScrubHint(step: 1, fractionDigits: 0, suffix: '°'),
              visibleWhen: (c) =>
                  (c as Light3DComponent).kind == Light3DKind.spot,
            ),
            'outerConeAngle': FieldHint(
              label: 'Outer cone',
              unit: AngleUnit.degrees,
              scrub: const ScrubHint(step: 1, fractionDigits: 0, suffix: '°'),
              visibleWhen: (c) =>
                  (c as Light3DComponent).kind == Light3DKind.spot,
            ),
          },
        ),
        fields: [
          FieldDefinition(
            name: 'kind',
            kind: const EnumFieldType(
              Light3DKind.values,
              fallback: Light3DKind.point,
              id: 'graphics.lightKind',
            ),
            read: (c) => (c as Light3DComponent).kind,
            write: (c, v) => (c as Light3DComponent).kind = v as Light3DKind,
          ),
          FieldDefinition(
            name: 'color',
            kind: FieldTypes.color,
            read: (c) => (c as Light3DComponent).color,
            write: (c, v) => (c as Light3DComponent).color = v as Color,
          ),
          _decimal(
            'intensity',
            (c) => (c as Light3DComponent).intensity,
            (c, v) => (c as Light3DComponent).intensity = v,
            min: 0,
          ),
          _decimal(
            'range',
            (c) => (c as Light3DComponent).range,
            (c, v) => (c as Light3DComponent).range = v,
            min: 0,
          ),
          _decimal(
            'innerConeAngle',
            (c) => (c as Light3DComponent).innerConeAngle,
            (c, v) => (c as Light3DComponent).innerConeAngle = v,
            min: 0,
          ),
          _decimal(
            'outerConeAngle',
            (c) => (c as Light3DComponent).outerConeAngle,
            (c, v) => (c as Light3DComponent).outerConeAngle = v,
            min: 0,
          ),
        ],
      );

  /// [EnvironmentComponent].
  static ComponentDefinition<EnvironmentComponent>
  get environment => ComponentDefinition<EnvironmentComponent>(
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
      FieldDefinition(
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
      FieldDefinition(
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
      FieldDefinition(
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
      FieldDefinition(
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
        max: 1,
      ),
    ],
  );

  /// Every lighting component.
  static List<ComponentDefinition> get all => [light3D, environment];

  static FieldDefinition _decimal(
    String name,
    double Function(Component c) read,
    void Function(Component c, double v) write, {
    double? min,
    double? max,
  }) => FieldDefinition(
    name: name,
    kind: FieldTypes.decimal,
    read: read,
    write: (c, v) => write(c, (v as num).toDouble()),
    min: min,
    max: max,
  );

  static FieldDefinition _color(
    String name,
    Color Function(EnvironmentComponent c) read,
    void Function(EnvironmentComponent c, Color v) write,
  ) => FieldDefinition(
    name: name,
    kind: FieldTypes.color,
    read: (c) => read(c as EnvironmentComponent),
    write: (c, v) => write(c as EnvironmentComponent, v as Color),
  );
}

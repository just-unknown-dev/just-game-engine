/// The camera components' definitions: the virtual camera's here, each
/// family of the stages that shape its shot in a part of its own
/// (framing, noise, targets, managers, 3-D rigs).
library;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/painting.dart';
import 'package:just_dart/just_dart.dart' show Vector3;
import '../foundation/dimensions.dart';

import '../ecs/ecs.dart';
import '../interfaces/camera_lens.dart';
import 'camera_noise_profiles.dart';
import 'camera_confiner_components.dart';
import 'camera_framing_component.dart';
import 'camera_manager_components.dart';
import 'camera_noise_components.dart';
import 'camera_rig_3d_components.dart';
import 'camera_target_components.dart';
import 'virtual_camera_component.dart';

part 'camera_framing_definitions.dart';
part 'camera_noise_definitions.dart';
part 'camera_target_definitions.dart';
part 'camera_manager_definitions.dart';
part 'camera_rig_3d_definitions.dart';

const Color _accent = Color(0xFF26C6DA);
const String _group = 'Camera';

FieldDefinition _d<T extends Component>(
  String name,
  double Function(T) read,
  void Function(T, double) write, {
  double? min,
  double? max,
}) => FieldDefinition(
  name: name,
  kind: FieldTypes.decimal,
  read: (c) => read(c as T),
  write: (c, v) => write(c as T, (v as num).toDouble()),
  min: min,
  max: max,
);

FieldDefinition _b<T extends Component>(
  String name,
  bool Function(T) read,
  void Function(T, bool) write,
) => FieldDefinition(
  name: name,
  kind: FieldTypes.boolean,
  read: (c) => read(c as T),
  write: (c, v) => write(c as T, v as bool),
);

FieldDefinition _i<T extends Component>(
  String name,
  int Function(T) read,
  void Function(T, int) write,
) => FieldDefinition(
  name: name,
  kind: FieldTypes.integer,
  read: (c) => read(c as T),
  write: (c, v) => write(c as T, (v as num).toInt()),
);

FieldDefinition _s<T extends Component>(
  String name,
  String Function(T) read,
  void Function(T, String) write, {
  FieldType kind = FieldTypes.text,
}) => FieldDefinition(
  name: name,
  kind: kind,
  read: (c) => read(c as T),
  write: (c, v) => write(c as T, v as String? ?? ''),
);

FieldDefinition _t<T extends Component>(
  String name,
  EntityTarget Function(T) read,
  void Function(T, EntityTarget) write,
) => FieldDefinition(
  name: name,
  kind: FieldTypes.target,
  read: (c) => read(c as T),
  write: (c, v) => write(c as T, v as EntityTarget? ?? EntityTarget.none),
);

const _fraction = ScrubHint(step: 0.01, fractionDigits: 2);
const _seconds = ScrubHint(step: 0.05, fractionDigits: 2);

FieldDefinition _v<T extends Component>(
  String name,
  Vector3 Function(T) read,
  void Function(T, Vector3) write,
) => FieldDefinition(
  name: name,
  kind: FieldTypes.vector3,
  read: (c) => Vector3.copy(read(c as T)),
  write: (c, v) => write(c as T, Vector3.copy(v as Vector3)),
);

const _metres = ScrubHint(step: 0.05, fractionDigits: 2, suffix: 'm');
const _degrees = ScrubHint(step: 1, fractionDigits: 1, suffix: '°');

/// Definitions for the camera components: a virtual camera and the stages
/// that shape its shot. One per component, so each is saved, inspected and
/// added from the picker like any other; the stages' are by family in
/// [CameraFramingDefinitions], [CameraNoiseDefinitions],
/// [CameraTargetDefinitions], [CameraManagerDefinitions] and
/// [CameraRig3DDefinitions].
abstract final class CameraDefinitions {
  /// Definition of [VirtualCameraComponent] (one shot the brain can show),
  /// saved as `VirtualCameraComponent`.
  static ComponentDefinition<VirtualCameraComponent>
  get virtualCamera => ComponentDefinition<VirtualCameraComponent>(
    type: 'VirtualCameraComponent',
    hints: const ComponentHints(
      name: 'Virtual Camera',
      group: _group,
      description:
          'A shot. The brain shows the enabled one with the highest priority.',
      icon: Icons.videocam_rounded,
      accentColor: _accent,
      fieldGroups: {
        'Shot': ['priority', 'enabled', 'standbyUpdate'],
        'Follow': ['follow'],
        'Lens': [
          'zoom',
          'dutch',
          'projection',
          'fieldOfView',
          'nearClip',
          'farClip',
        ],
      },
      fields: {
        'priority': FieldHint(
          label: 'Priority',
          scrub: ScrubHint(integer: true),
        ),
        'enabled': FieldHint(label: 'Enabled'),
        'standbyUpdate': FieldHint(label: 'Standby'),
        'follow': FieldHint(
          label: 'Follow',
          description: 'An entity by name, or the first entity with a tag.',
        ),
        'zoom': FieldHint(
          label: 'Zoom',
          scrub: ScrubHint(step: 0.05, fractionDigits: 2),
        ),
        'dutch': FieldHint(
          label: 'Dutch',
          unit: AngleUnit.degrees,
          scrub: ScrubHint(step: 1, fractionDigits: 1),
        ),
        // A 2-D shot is orthographic and sized by its zoom; the rest of the
        // lens only matters in 3-D.
        'projection': FieldHint(
          label: 'Projection',
          dimensions: Dimensions.threeD,
        ),
        'fieldOfView': FieldHint(
          label: 'Field of view',
          unit: AngleUnit.degrees,
          scrub: ScrubHint(step: 1, fractionDigits: 1),
          dimensions: Dimensions.threeD,
        ),
        'nearClip': FieldHint(
          label: 'Near',
          scrub: ScrubHint(fractionDigits: 1),
          dimensions: Dimensions.threeD,
        ),
        'farClip': FieldHint(
          label: 'Far',
          scrub: ScrubHint(fractionDigits: 1),
          dimensions: Dimensions.threeD,
        ),
      },
    ),
    create: VirtualCameraComponent.new,
    fields: [
      _i<VirtualCameraComponent>(
        'priority',
        (c) => c.priority,
        (c, v) => c.priority = v,
      ),
      _b<VirtualCameraComponent>(
        'enabled',
        (c) => c.enabled,
        (c, v) => c.enabled = v,
      ),
      FieldDefinition(
        name: 'standbyUpdate',
        kind: const EnumFieldType(
          CameraStandbyUpdate.values,
          fallback: CameraStandbyUpdate.never,
          id: 'camera.standbyUpdate',
        ),
        read: (c) => (c as VirtualCameraComponent).standbyUpdate,
        write: (c, v) => (c as VirtualCameraComponent).standbyUpdate =
            v as CameraStandbyUpdate,
      ),
      _t<VirtualCameraComponent>(
        'follow',
        (c) => c.follow,
        (c, v) => c.follow = v,
      ),
      _d<VirtualCameraComponent>(
        'zoom',
        (c) => c.zoom,
        (c, v) => c.zoom = v,
        min: 0.01,
      ),
      _d<VirtualCameraComponent>(
        'dutch',
        (c) => c.dutch,
        (c, v) => c.dutch = v,
      ),
      FieldDefinition(
        name: 'projection',
        kind: const EnumFieldType(
          CameraProjection.values,
          fallback: CameraProjection.orthographic,
          id: 'camera.projection',
        ),
        read: (c) => (c as VirtualCameraComponent).projection,
        write: (c, v) =>
            (c as VirtualCameraComponent).projection = v as CameraProjection,
      ),
      _d<VirtualCameraComponent>(
        'fieldOfView',
        (c) => c.fieldOfView,
        (c, v) => c.fieldOfView = v,
        min: 0.01,
        max: 3.1,
      ),
      _d<VirtualCameraComponent>(
        'nearClip',
        (c) => c.nearClip,
        (c, v) => c.nearClip = v,
      ),
      _d<VirtualCameraComponent>(
        'farClip',
        (c) => c.farClip,
        (c, v) => c.farClip = v,
      ),
    ],
  );

  /// Every camera definition, in picker order.
  static List<ComponentDefinition> get all => [
    virtualCamera,
    ...CameraFramingDefinitions.all,
    ...CameraNoiseDefinitions.all,
    ...CameraTargetDefinitions.all,
    ...CameraManagerDefinitions.all,
    ...CameraRig3DDefinitions.all,
  ];
}

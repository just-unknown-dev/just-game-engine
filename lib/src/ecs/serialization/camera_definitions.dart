library;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/painting.dart';

import '../components/components.dart';
import '../ecs.dart';
import 'component_definition.dart';
import '../../subsystems/camera/camera_noise.dart';
import 'field_type.dart';

/// Definitions for the camera components: a virtual camera and the stages
/// that shape its shot. One per component, so each is saved, inspected and
/// added from the picker like any other.
abstract final class CameraDefinitions {
  static const Color _accent = Color(0xFF26C6DA);
  static const String _group = 'Camera';

  static SchemaField _d<T extends Component>(
    String name,
    double Function(T) read,
    void Function(T, double) write, {
    double? min,
    double? max,
  }) => SchemaField(
    name: name,
    kind: FieldTypes.decimal,
    read: (c) => read(c as T),
    write: (c, v) => write(c as T, (v as num).toDouble()),
    min: min,
    max: max,
  );

  static SchemaField _b<T extends Component>(
    String name,
    bool Function(T) read,
    void Function(T, bool) write,
  ) => SchemaField(
    name: name,
    kind: FieldTypes.boolean,
    read: (c) => read(c as T),
    write: (c, v) => write(c as T, v as bool),
  );

  static SchemaField _i<T extends Component>(
    String name,
    int Function(T) read,
    void Function(T, int) write,
  ) => SchemaField(
    name: name,
    kind: FieldTypes.integer,
    read: (c) => read(c as T),
    write: (c, v) => write(c as T, (v as num).toInt()),
  );

  static SchemaField _s<T extends Component>(
    String name,
    String Function(T) read,
    void Function(T, String) write, {
    FieldType kind = FieldTypes.text,
  }) => SchemaField(
    name: name,
    kind: kind,
    read: (c) => read(c as T),
    write: (c, v) => write(c as T, v as String? ?? ''),
  );

  static const _fraction = ScrubHint(step: 0.01, fractionDigits: 2);
  static const _seconds = ScrubHint(step: 0.05, fractionDigits: 2);

  static final virtualCamera = ComponentDefinition<VirtualCameraComponent>(
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
        'Follow': ['followName', 'followTag'],
        'Lens': ['zoom', 'dutch'],
      },
      fields: {
        'priority': FieldHint(
          label: 'Priority',
          scrub: ScrubHint(integer: true),
        ),
        'enabled': FieldHint(label: 'Enabled'),
        'standbyUpdate': FieldHint(label: 'Standby'),
        'followName': FieldHint(label: 'Follow'),
        'followTag': FieldHint(label: 'Follow tag'),
        'zoom': FieldHint(
          label: 'Zoom',
          scrub: ScrubHint(step: 0.05, fractionDigits: 2),
        ),
        'dutch': FieldHint(
          label: 'Dutch',
          unit: AngleUnit.degrees,
          scrub: ScrubHint(step: 1, fractionDigits: 1),
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
      SchemaField(
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
      _s<VirtualCameraComponent>(
        'followName',
        (c) => c.followName,
        (c, v) => c.followName = v,
        kind: FieldTypes.entityRef,
      ),
      _s<VirtualCameraComponent>(
        'followTag',
        (c) => c.followTag,
        (c, v) => c.followTag = v,
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
    ],
  );

  static final framing = ComponentDefinition<CameraFramingComponent>(
    type: 'CameraFramingComponent',
    hints: const ComponentHints(
      name: 'Camera Framing',
      group: _group,
      description:
          'Keeps the followed entity inside a dead zone on screen, easing '
          'when it leaves.',
      icon: Icons.center_focus_strong,
      accentColor: _accent,
      fieldGroups: {
        'Composition': [
          'screenX',
          'screenY',
          'deadZoneWidth',
          'deadZoneHeight',
          'softZoneWidth',
          'softZoneHeight',
        ],
        'Easing': ['dampingX', 'dampingY'],
        'Lookahead': ['lookaheadTime', 'lookaheadSmoothing'],
        'Axes': ['followX', 'followY'],
      },
      fieldRows: [
        FieldRowHint('Screen position', {'screenX': 'X', 'screenY': 'Y'}),
        FieldRowHint('Dead zone', {
          'deadZoneWidth': 'W',
          'deadZoneHeight': 'H',
        }),
        FieldRowHint('Soft zone', {
          'softZoneWidth': 'W',
          'softZoneHeight': 'H',
        }),
        FieldRowHint('Damping (s)', {'dampingX': 'X', 'dampingY': 'Y'}),
      ],
      fields: {
        'screenX': FieldHint(label: 'X', scrub: _fraction),
        'screenY': FieldHint(label: 'Y', scrub: _fraction),
        'deadZoneWidth': FieldHint(label: 'Width', scrub: _fraction),
        'deadZoneHeight': FieldHint(label: 'Height', scrub: _fraction),
        'softZoneWidth': FieldHint(label: 'Width', scrub: _fraction),
        'softZoneHeight': FieldHint(label: 'Height', scrub: _fraction),
        'dampingX': FieldHint(label: 'X (s)', scrub: _seconds),
        'dampingY': FieldHint(label: 'Y (s)', scrub: _seconds),
        'lookaheadTime': FieldHint(label: 'Time (s)', scrub: _seconds),
        'lookaheadSmoothing': FieldHint(
          label: 'Smoothing (s)',
          scrub: _seconds,
        ),
        'followX': FieldHint(label: 'Follow X'),
        'followY': FieldHint(label: 'Follow Y'),
      },
    ),
    create: CameraFramingComponent.new,
    fields: [
      _d<CameraFramingComponent>(
        'screenX',
        (c) => c.screenX,
        (c, v) => c.screenX = v,
        min: -0.5,
        max: 0.5,
      ),
      _d<CameraFramingComponent>(
        'screenY',
        (c) => c.screenY,
        (c, v) => c.screenY = v,
        min: -0.5,
        max: 0.5,
      ),
      _d<CameraFramingComponent>(
        'deadZoneWidth',
        (c) => c.deadZoneWidth,
        (c, v) => c.deadZoneWidth = v,
        min: 0,
        max: 2,
      ),
      _d<CameraFramingComponent>(
        'deadZoneHeight',
        (c) => c.deadZoneHeight,
        (c, v) => c.deadZoneHeight = v,
        min: 0,
        max: 2,
      ),
      _d<CameraFramingComponent>(
        'softZoneWidth',
        (c) => c.softZoneWidth,
        (c, v) => c.softZoneWidth = v,
        min: 0,
        max: 2,
      ),
      _d<CameraFramingComponent>(
        'softZoneHeight',
        (c) => c.softZoneHeight,
        (c, v) => c.softZoneHeight = v,
        min: 0,
        max: 2,
      ),
      _d<CameraFramingComponent>(
        'dampingX',
        (c) => c.dampingX,
        (c, v) => c.dampingX = v,
        min: 0,
      ),
      _d<CameraFramingComponent>(
        'dampingY',
        (c) => c.dampingY,
        (c, v) => c.dampingY = v,
        min: 0,
      ),
      _d<CameraFramingComponent>(
        'lookaheadTime',
        (c) => c.lookaheadTime,
        (c, v) => c.lookaheadTime = v,
        min: 0,
      ),
      _d<CameraFramingComponent>(
        'lookaheadSmoothing',
        (c) => c.lookaheadSmoothing,
        (c, v) => c.lookaheadSmoothing = v,
        min: 0,
      ),
      _b<CameraFramingComponent>(
        'followX',
        (c) => c.followX,
        (c, v) => c.followX = v,
      ),
      _b<CameraFramingComponent>(
        'followY',
        (c) => c.followY,
        (c, v) => c.followY = v,
      ),
    ],
  );

  static final confiner = ComponentDefinition<CameraConfinerComponent>(
    type: 'CameraConfinerComponent',
    hints: const ComponentHints(
      name: 'Camera Confiner',
      group: _group,
      description:
          'Keeps the whole view inside the bounds of the entity it names.',
      icon: Icons.crop_free,
      accentColor: _accent,
      fields: {
        'boundsName': FieldHint(label: 'Bounds'),
        'damping': FieldHint(label: 'Damping (s)', scrub: _seconds),
      },
    ),
    create: CameraConfinerComponent.new,
    fields: [
      _s<CameraConfinerComponent>(
        'boundsName',
        (c) => c.boundsName,
        (c, v) => c.boundsName = v,
        kind: FieldTypes.entityRef,
      ),
      _d<CameraConfinerComponent>(
        'damping',
        (c) => c.damping,
        (c, v) => c.damping = v,
        min: 0,
      ),
    ],
  );

  static final bounds = ComponentDefinition<CameraBoundsComponent>(
    type: 'CameraBoundsComponent',
    hints: const ComponentHints(
      name: 'Camera Bounds',
      group: _group,
      description:
          'A rectangle, centred on this entity, that a confiner can name.',
      icon: Icons.border_outer,
      accentColor: _accent,
      fieldRows: [
        FieldRowHint('Size', {'width': 'W', 'height': 'H'}),
      ],
      fields: {
        'width': FieldHint(
          label: 'Width',
          scrub: ScrubHint(step: 32, fractionDigits: 0),
        ),
        'height': FieldHint(
          label: 'Height',
          scrub: ScrubHint(step: 32, fractionDigits: 0),
        ),
      },
    ),
    create: CameraBoundsComponent.new,
    extent: const _BoundsExtent(),
    fields: [
      _d<CameraBoundsComponent>(
        'width',
        (c) => c.width,
        (c, v) => c.width = v,
        min: 1,
      ),
      _d<CameraBoundsComponent>(
        'height',
        (c) => c.height,
        (c, v) => c.height = v,
        min: 1,
      ),
    ],
  );

  static final noise = ComponentDefinition<CameraNoiseComponent>(
    type: 'CameraNoiseComponent',
    hints: const ComponentHints(
      name: 'Camera Noise',
      group: _group,
      description: 'Continuous handheld motion over the settled shot.',
      icon: Icons.waves,
      accentColor: _accent,
      fields: {
        'preset': FieldHint(label: 'Profile'),
        'amplitudeGain': FieldHint(label: 'Amplitude', scrub: _fraction),
        'frequencyGain': FieldHint(label: 'Frequency', scrub: _fraction),
      },
    ),
    create: CameraNoiseComponent.new,
    fields: [
      SchemaField(
        name: 'preset',
        kind: const EnumFieldType(
          CameraNoisePreset.values,
          fallback: CameraNoisePreset.handheldNormal,
          id: 'camera.noisePreset',
        ),
        read: (c) => (c as CameraNoiseComponent).preset,
        write: (c, v) =>
            (c as CameraNoiseComponent).preset = v as CameraNoisePreset,
      ),
      _d<CameraNoiseComponent>(
        'amplitudeGain',
        (c) => c.amplitudeGain,
        (c, v) => c.amplitudeGain = v,
        min: 0,
      ),
      _d<CameraNoiseComponent>(
        'frequencyGain',
        (c) => c.frequencyGain,
        (c, v) => c.frequencyGain = v,
        min: 0,
      ),
    ],
  );

  static final impulseListener =
      ComponentDefinition<CameraImpulseListenerComponent>(
        type: 'CameraImpulseListenerComponent',
        hints: const ComponentHints(
          name: 'Camera Impulse Listener',
          group: _group,
          description: 'Lets this shot feel the impulses emitted near it.',
          icon: Icons.hearing,
          accentColor: _accent,
          fields: {
            'gain': FieldHint(label: 'Gain', scrub: _fraction),
            'channels': FieldHint(
              label: 'Channels',
              scrub: ScrubHint(integer: true),
            ),
          },
        ),
        create: CameraImpulseListenerComponent.new,
        fields: [
          _d<CameraImpulseListenerComponent>(
            'gain',
            (c) => c.gain,
            (c, v) => c.gain = v,
            min: 0,
          ),
          _i<CameraImpulseListenerComponent>(
            'channels',
            (c) => c.channels,
            (c, v) => c.channels = v,
          ),
        ],
      );

  static final impulseSource = ComponentDefinition<CameraImpulseSourceComponent>(
    type: 'CameraImpulseSourceComponent',
    hints: const ComponentHints(
      name: 'Camera Impulse Source',
      group: _group,
      description:
          'An authored impulse the game emits from here: a landing, a blast.',
      icon: Icons.flash_on,
      accentColor: _accent,
      fields: {
        'amplitude': FieldHint(
          label: 'Amplitude',
          scrub: ScrubHint(step: 1, fractionDigits: 1),
        ),
        'duration': FieldHint(label: 'Duration (s)', scrub: _seconds),
        'radius': FieldHint(
          label: 'Radius',
          scrub: ScrubHint(step: 16, fractionDigits: 0),
        ),
        'channel': FieldHint(label: 'Channel', scrub: ScrubHint(integer: true)),
      },
    ),
    create: CameraImpulseSourceComponent.new,
    fields: [
      _d<CameraImpulseSourceComponent>(
        'amplitude',
        (c) => c.amplitude,
        (c, v) => c.amplitude = v,
      ),
      _d<CameraImpulseSourceComponent>(
        'duration',
        (c) => c.duration,
        (c, v) => c.duration = v,
        min: 0,
      ),
      _d<CameraImpulseSourceComponent>(
        'radius',
        (c) => c.radius,
        (c, v) => c.radius = v,
        min: 0,
      ),
      _i<CameraImpulseSourceComponent>(
        'channel',
        (c) => c.channel,
        (c, v) => c.channel = v,
      ),
    ],
  );

  static final targetGroup = ComponentDefinition<CameraTargetGroupComponent>(
    type: 'CameraTargetGroupComponent',
    hints: const ComponentHints(
      name: 'Camera Target Group',
      group: _group,
      description:
          'Moves this entity to the weighted centre of its members, so a '
          'camera that follows it frames them all.',
      icon: Icons.group_work_outlined,
      accentColor: _accent,
      fields: {
        'members': FieldHint(
          label: 'Members',
          description: 'Who the group keeps in shot, by entity name or tag.',
          itemTemplate: {'name': '', 'tag': '', 'weight': 1.0, 'radius': 0.0},
        ),
      },
    ),
    create: CameraTargetGroupComponent.new,
    fields: [
      SchemaField(
        name: 'members',
        kind: FieldTypes.list,
        read: (c) => [
          for (final m in (c as CameraTargetGroupComponent).members) m.toJson(),
        ],
        write: (c, v) => (c as CameraTargetGroupComponent).members = [
          for (final m in (v as List?) ?? const [])
            if (m is Map) CameraGroupMember.fromJson(m),
        ],
      ),
    ],
  );

  static final groupFraming = ComponentDefinition<CameraGroupFramingComponent>(
    type: 'CameraGroupFramingComponent',
    hints: const ComponentHints(
      name: 'Camera Group Framing',
      group: _group,
      description:
          'Sets the lens so the target group this camera follows fits the view.',
      icon: Icons.zoom_out_map,
      accentColor: _accent,
      fieldRows: [
        FieldRowHint('Zoom', {'minZoom': 'Min', 'maxZoom': 'Max'}),
      ],
      fields: {
        'padding': FieldHint(label: 'Padding', scrub: _fraction),
        'minZoom': FieldHint(label: 'Min zoom', scrub: _fraction),
        'maxZoom': FieldHint(label: 'Max zoom', scrub: _fraction),
        'zoomDamping': FieldHint(label: 'Damping (s)', scrub: _seconds),
      },
    ),
    create: CameraGroupFramingComponent.new,
    fields: [
      _d<CameraGroupFramingComponent>(
        'padding',
        (c) => c.padding,
        (c, v) => c.padding = v,
        min: 0,
      ),
      _d<CameraGroupFramingComponent>(
        'minZoom',
        (c) => c.minZoom,
        (c, v) => c.minZoom = v,
        min: 0.01,
      ),
      _d<CameraGroupFramingComponent>(
        'maxZoom',
        (c) => c.maxZoom,
        (c, v) => c.maxZoom = v,
        min: 0.01,
      ),
      _d<CameraGroupFramingComponent>(
        'zoomDamping',
        (c) => c.zoomDamping,
        (c, v) => c.zoomDamping = v,
        min: 0,
      ),
    ],
  );

  static final trigger = ComponentDefinition<CameraTriggerComponent>(
    type: 'CameraTriggerComponent',
    hints: ComponentHints(
      name: 'Camera Trigger',
      group: _group,
      description:
          'A rectangle that switches a virtual camera while a target is inside.',
      icon: Icons.sensors,
      accentColor: _accent,
      fieldGroups: const {
        'Area': ['width', 'height'],
        'Set off by': ['targetName', 'targetTag'],
        'Switches': ['cameraName', 'mode', 'amount', 'oneShot'],
      },
      fieldRows: const [
        FieldRowHint('Size', {'width': 'W', 'height': 'H'}),
      ],
      fields: {
        'width': const FieldHint(
          label: 'Width',
          scrub: ScrubHint(step: 32, fractionDigits: 0),
        ),
        'height': const FieldHint(
          label: 'Height',
          scrub: ScrubHint(step: 32, fractionDigits: 0),
        ),
        'targetName': const FieldHint(label: 'Entity'),
        'targetTag': const FieldHint(label: 'Tag'),
        'cameraName': const FieldHint(
          label: 'Camera',
          description: 'Empty: the virtual camera on this entity.',
        ),
        'mode': const FieldHint(label: 'Mode'),
        // Only a boost has an amount.
        'amount': FieldHint(
          label: 'Boost',
          scrub: const ScrubHint(integer: true),
          visibleWhen: (c) =>
              (c as CameraTriggerComponent).mode ==
              CameraTriggerMode.boostPriority,
        ),
        'oneShot': const FieldHint(label: 'One shot'),
      },
    ),
    create: CameraTriggerComponent.new,
    extent: const _TriggerExtent(),
    fields: [
      _d<CameraTriggerComponent>(
        'width',
        (c) => c.width,
        (c, v) => c.width = v,
        min: 1,
      ),
      _d<CameraTriggerComponent>(
        'height',
        (c) => c.height,
        (c, v) => c.height = v,
        min: 1,
      ),
      _s<CameraTriggerComponent>(
        'targetName',
        (c) => c.targetName,
        (c, v) => c.targetName = v,
        kind: FieldTypes.entityRef,
      ),
      _s<CameraTriggerComponent>(
        'targetTag',
        (c) => c.targetTag,
        (c, v) => c.targetTag = v,
      ),
      _s<CameraTriggerComponent>(
        'cameraName',
        (c) => c.cameraName,
        (c, v) => c.cameraName = v,
        kind: FieldTypes.entityRef,
      ),
      SchemaField(
        name: 'mode',
        kind: const EnumFieldType(
          CameraTriggerMode.values,
          fallback: CameraTriggerMode.enableWhileInside,
          id: 'camera.triggerMode',
        ),
        read: (c) => (c as CameraTriggerComponent).mode,
        write: (c, v) =>
            (c as CameraTriggerComponent).mode = v as CameraTriggerMode,
      ),
      _i<CameraTriggerComponent>(
        'amount',
        (c) => c.amount,
        (c, v) => c.amount = v,
      ),
      _b<CameraTriggerComponent>(
        'oneShot',
        (c) => c.oneShot,
        (c, v) => c.oneShot = v,
      ),
    ],
  );

  static final dolly = ComponentDefinition<CameraDollyComponent>(
    type: 'CameraDollyComponent',
    hints: ComponentHints(
      name: 'Camera Dolly',
      group: _group,
      description:
          'Rides a track: to the point nearest the followed entity, or '
          'wherever Position says.',
      icon: Icons.timeline,
      accentColor: _accent,
      fields: {
        'waypoints': const FieldHint(label: 'Track'),
        'closed': const FieldHint(label: 'Closed'),
        'autoDolly': const FieldHint(label: 'Auto dolly'),
        // A position is only read when the target is not choosing it.
        'pathPosition': FieldHint(
          label: 'Position',
          scrub: _fraction,
          visibleWhen: (c) => !(c as CameraDollyComponent).autoDolly,
        ),
        'damping': const FieldHint(label: 'Damping (s)', scrub: _seconds),
      },
    ),
    create: CameraDollyComponent.new,
    fields: [
      SchemaField(
        name: 'waypoints',
        kind: FieldTypes.offsetList,
        read: (c) => (c as CameraDollyComponent).waypoints,
        write: (c, v) => (c as CameraDollyComponent).waypoints = [
          ...?(v as List?)?.cast<Offset>(),
        ],
      ),
      _b<CameraDollyComponent>(
        'closed',
        (c) => c.closed,
        (c, v) => c.closed = v,
      ),
      _b<CameraDollyComponent>(
        'autoDolly',
        (c) => c.autoDolly,
        (c, v) => c.autoDolly = v,
      ),
      _d<CameraDollyComponent>(
        'pathPosition',
        (c) => c.pathPosition,
        (c, v) => c.pathPosition = v,
        min: 0,
        max: 1,
      ),
      _d<CameraDollyComponent>(
        'damping',
        (c) => c.damping,
        (c, v) => c.damping = v,
        min: 0,
      ),
    ],
  );

  static final stateDriven = ComponentDefinition<CameraStateDrivenComponent>(
    type: 'CameraStateDrivenComponent',
    hints: const ComponentHints(
      name: 'Camera State-Driven',
      group: _group,
      description:
          "Manager: shows the child camera mapped to another entity's state.",
      icon: Icons.account_tree_outlined,
      accentColor: _accent,
      fields: {
        'sourceName': FieldHint(label: 'State of'),
        'sourceTag': FieldHint(label: 'State of tag'),
        'states': FieldHint(
          label: 'States',
          description: 'State → the child camera to show for it.',
          itemTemplate: '',
        ),
        'defaultChild': FieldHint(label: 'Default child'),
        'blend': FieldHint(label: 'Blend (s)', scrub: _seconds),
      },
    ),
    create: CameraStateDrivenComponent.new,
    fields: [
      _s<CameraStateDrivenComponent>(
        'sourceName',
        (c) => c.sourceName,
        (c, v) => c.sourceName = v,
        kind: FieldTypes.entityRef,
      ),
      _s<CameraStateDrivenComponent>(
        'sourceTag',
        (c) => c.sourceTag,
        (c, v) => c.sourceTag = v,
      ),
      SchemaField(
        name: 'states',
        kind: FieldTypes.map,
        read: (c) =>
            Map<Object?, Object?>.of((c as CameraStateDrivenComponent).states),
        write: (c, v) => (c as CameraStateDrivenComponent).states = {
          for (final e in ((v as Map?) ?? const {}).entries)
            '${e.key}': '${e.value}',
        },
      ),
      _s<CameraStateDrivenComponent>(
        'defaultChild',
        (c) => c.defaultChild,
        (c, v) => c.defaultChild = v,
      ),
      _d<CameraStateDrivenComponent>(
        'blend',
        (c) => c.blend,
        (c, v) => c.blend = v,
        min: 0,
      ),
    ],
  );

  static final cameraState = ComponentDefinition<CameraStateComponent>(
    type: 'CameraStateComponent',
    hints: const ComponentHints(
      name: 'Camera State',
      group: _group,
      description:
          'A named state the game sets, for a state-driven camera to read.',
      icon: Icons.label_outline,
      accentColor: _accent,
      fields: {'state': FieldHint(label: 'State')},
    ),
    create: CameraStateComponent.new,
    fields: [
      _s<CameraStateComponent>('state', (c) => c.state, (c, v) => c.state = v),
    ],
  );

  static final blendList = ComponentDefinition<CameraBlendListComponent>(
    type: 'CameraBlendListComponent',
    hints: const ComponentHints(
      name: 'Camera Blend List',
      group: _group,
      description:
          'Manager: plays its child cameras as a sequence of held shots, '
          'starting over each time it goes live.',
      icon: Icons.playlist_play,
      accentColor: _accent,
      fields: {
        'steps': FieldHint(
          label: 'Steps',
          description:
              'The shots, in order: a child camera, how long it is '
              'held, and the blend into it.',
          itemTemplate: {'child': '', 'hold': 1.0, 'blend': 0.5},
        ),
        'loop': FieldHint(label: 'Loop'),
      },
    ),
    create: CameraBlendListComponent.new,
    fields: [
      SchemaField(
        name: 'steps',
        kind: FieldTypes.list,
        read: (c) => [
          for (final s in (c as CameraBlendListComponent).steps) s.toJson(),
        ],
        write: (c, v) => (c as CameraBlendListComponent).steps = [
          for (final s in (v as List?) ?? const [])
            if (s is Map) CameraBlendStep.fromJson(s),
        ],
      ),
      _b<CameraBlendListComponent>('loop', (c) => c.loop, (c, v) => c.loop = v),
    ],
  );

  static final mixer = ComponentDefinition<CameraMixerComponent>(
    type: 'CameraMixerComponent',
    hints: const ComponentHints(
      name: 'Camera Mixer',
      group: _group,
      description: 'Manager: a weighted mix of its child cameras.',
      icon: Icons.tune,
      accentColor: _accent,
      fields: {
        'weights': FieldHint(
          label: 'Weights',
          description: 'Child camera → how much of it is in the mix.',
          itemTemplate: 1.0,
        ),
      },
    ),
    create: CameraMixerComponent.new,
    fields: [
      SchemaField(
        name: 'weights',
        kind: FieldTypes.map,
        read: (c) =>
            Map<Object?, Object?>.of((c as CameraMixerComponent).weights),
        write: (c, v) => (c as CameraMixerComponent).weights = {
          for (final e in ((v as Map?) ?? const {}).entries)
            if (e.value is num) '${e.key}': (e.value as num).toDouble(),
        },
      ),
    ],
  );

  /// Every camera definition, in picker order.
  static List<ComponentDefinition> get all => [
    virtualCamera,
    framing,
    confiner,
    bounds,
    noise,
    impulseListener,
    impulseSource,
    targetGroup,
    groupFraming,
    trigger,
    dolly,
    stateDriven,
    cameraState,
    blendList,
    mixer,
  ];
}

class _BoundsExtent extends ComponentExtent {
  const _BoundsExtent();

  @override
  Size? sizeOf(Component component) {
    final b = component as CameraBoundsComponent;
    return Size(b.width, b.height);
  }

  @override
  bool scale(Component component, double sx, double sy) {
    final b = component as CameraBoundsComponent;
    b
      ..width = b.width * sx.abs()
      ..height = b.height * sy.abs();
    return true;
  }
}

class _TriggerExtent extends ComponentExtent {
  const _TriggerExtent();

  @override
  Size? sizeOf(Component component) {
    final t = component as CameraTriggerComponent;
    return Size(t.width, t.height);
  }

  @override
  bool scale(Component component, double sx, double sy) {
    final t = component as CameraTriggerComponent;
    t
      ..width = t.width * sx.abs()
      ..height = t.height * sy.abs();
    return true;
  }
}

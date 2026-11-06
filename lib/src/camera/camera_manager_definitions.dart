part of 'camera_definitions.dart';

/// How the camera managers — the dolly, the state-driven camera and its
/// state, the blend list and the mixer — are saved and shown in an
/// editor.
abstract final class CameraManagerDefinitions {
  /// Definition of [CameraDollyComponent] (a camera on a track), saved as
  /// `CameraDollyComponent`. 2-D only.
  static ComponentDefinition<CameraDollyComponent> get dolly =>
      ComponentDefinition<CameraDollyComponent>(
        type: 'CameraDollyComponent',
        hints: ComponentHints(
          dimensions: Dimensions.twoD,
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
          FieldDefinition(
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

  /// Definition of [CameraStateDrivenComponent] (a manager camera picking a
  /// child by state), saved as `CameraStateDrivenComponent`.
  static ComponentDefinition<CameraStateDrivenComponent>
  get stateDriven => ComponentDefinition<CameraStateDrivenComponent>(
    type: 'CameraStateDrivenComponent',
    hints: const ComponentHints(
      name: 'Camera State-Driven',
      group: _group,
      description:
          "Manager: shows the child camera mapped to another entity's state.",
      icon: Icons.account_tree_outlined,
      accentColor: _accent,
      fields: {
        'source': FieldHint(
          label: 'State of',
          description: 'An entity by name, or the first entity with a tag.',
        ),
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
      _t<CameraStateDrivenComponent>(
        'source',
        (c) => c.source,
        (c, v) => c.source = v,
      ),
      FieldDefinition(
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

  /// Definition of [CameraStateComponent] (the state a state-driven camera
  /// reads), saved as `CameraStateComponent`.
  static ComponentDefinition<CameraStateComponent> get cameraState =>
      ComponentDefinition<CameraStateComponent>(
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
          _s<CameraStateComponent>(
            'state',
            (c) => c.state,
            (c, v) => c.state = v,
          ),
        ],
      );

  /// Definition of [CameraBlendListComponent] (a manager camera playing
  /// its children in sequence), saved as `CameraBlendListComponent`.
  static ComponentDefinition<CameraBlendListComponent> get blendList =>
      ComponentDefinition<CameraBlendListComponent>(
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
          FieldDefinition(
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
          _b<CameraBlendListComponent>(
            'loop',
            (c) => c.loop,
            (c, v) => c.loop = v,
          ),
        ],
      );

  /// Definition of [CameraMixerComponent] (a weighted mix of its child
  /// cameras), saved as `CameraMixerComponent`.
  static ComponentDefinition<CameraMixerComponent> get mixer =>
      ComponentDefinition<CameraMixerComponent>(
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
          FieldDefinition(
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

  /// Every one of them, in picker order.
  static List<ComponentDefinition> get all => [
    dolly,
    stateDriven,
    cameraState,
    blendList,
    mixer,
  ];
}

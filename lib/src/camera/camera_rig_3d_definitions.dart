part of 'camera_definitions.dart';

/// How the 3-D camera rigs — orbit follow, first person and look-at —
/// are saved and shown in an editor.
abstract final class CameraRig3DDefinitions {
  /// Definition of [OrbitFollowComponent] (a third-person camera circling
  /// its target), saved as `OrbitFollowComponent`. 3-D only.
  static ComponentDefinition<OrbitFollowComponent> get orbitFollow =>
      ComponentDefinition<OrbitFollowComponent>(
        type: 'OrbitFollowComponent',
        hints: const ComponentHints(
          dimensions: Dimensions.threeD,
          name: 'Orbit Follow',
          group: _group,
          description:
              'Circles the followed entity at a distance; gameplay turns it '
              'with yaw and pitch.',
          icon: Icons.threesixty,
          accentColor: _accent,
          fieldGroups: {
            'Distance': ['distance', 'minDistance', 'maxDistance'],
            'Angles': ['yaw', 'pitch', 'minPitch', 'maxPitch'],
            'Framing': ['pivot', 'shoulder', 'damping'],
          },
          fields: {
            'distance': FieldHint(label: 'Distance', scrub: _metres),
            'minDistance': FieldHint(label: 'Closest', scrub: _metres),
            'maxDistance': FieldHint(label: 'Furthest', scrub: _metres),
            'yaw': FieldHint(
              label: 'Yaw',
              unit: AngleUnit.degrees,
              scrub: _degrees,
            ),
            'pitch': FieldHint(
              label: 'Pitch',
              unit: AngleUnit.degrees,
              scrub: _degrees,
            ),
            'minPitch': FieldHint(
              label: 'Lowest pitch',
              unit: AngleUnit.degrees,
              scrub: _degrees,
            ),
            'maxPitch': FieldHint(
              label: 'Highest pitch',
              unit: AngleUnit.degrees,
              scrub: _degrees,
            ),
            'pivot': FieldHint(
              label: 'Pivot',
              description: 'Where it circles, from the target (-Y is up).',
            ),
            'shoulder': FieldHint(label: 'Shoulder', scrub: _metres),
            'damping': FieldHint(label: 'Damping (s)', scrub: _seconds),
          },
        ),
        create: OrbitFollowComponent.new,
        fields: [
          _d<OrbitFollowComponent>(
            'distance',
            (c) => c.distance,
            (c, v) => c.distance = v,
            min: 0,
          ),
          _d<OrbitFollowComponent>(
            'minDistance',
            (c) => c.minDistance,
            (c, v) => c.minDistance = v,
            min: 0,
          ),
          _d<OrbitFollowComponent>(
            'maxDistance',
            (c) => c.maxDistance,
            (c, v) => c.maxDistance = v,
            min: 0,
          ),
          _d<OrbitFollowComponent>('yaw', (c) => c.yaw, (c, v) => c.yaw = v),
          _d<OrbitFollowComponent>(
            'pitch',
            (c) => c.pitch,
            (c, v) => c.pitch = v,
          ),
          _d<OrbitFollowComponent>(
            'minPitch',
            (c) => c.minPitch,
            (c, v) => c.minPitch = v,
          ),
          _d<OrbitFollowComponent>(
            'maxPitch',
            (c) => c.maxPitch,
            (c, v) => c.maxPitch = v,
          ),
          _v<OrbitFollowComponent>(
            'pivot',
            (c) => c.pivot,
            (c, v) => c.pivot = v,
          ),
          _d<OrbitFollowComponent>(
            'shoulder',
            (c) => c.shoulder,
            (c, v) => c.shoulder = v,
          ),
          _d<OrbitFollowComponent>(
            'damping',
            (c) => c.damping,
            (c, v) => c.damping = v,
            min: 0,
          ),
        ],
      );

  /// Definition of [FirstPersonComponent] (the camera at the target's
  /// eyes), saved as `FirstPersonComponent`. 3-D only.
  static ComponentDefinition<FirstPersonComponent> get firstPerson =>
      ComponentDefinition<FirstPersonComponent>(
        type: 'FirstPersonComponent',
        hints: const ComponentHints(
          dimensions: Dimensions.threeD,
          name: 'First Person',
          group: _group,
          description: "Looks out of the followed entity's eyes.",
          icon: Icons.visibility_outlined,
          accentColor: _accent,
          fields: {
            'eye': FieldHint(
              label: 'Eyes',
              description: 'From the target (-Y is up).',
            ),
            'yaw': FieldHint(
              label: 'Yaw',
              unit: AngleUnit.degrees,
              scrub: _degrees,
            ),
            'pitch': FieldHint(
              label: 'Pitch',
              unit: AngleUnit.degrees,
              scrub: _degrees,
            ),
            'minPitch': FieldHint(
              label: 'Lowest pitch',
              unit: AngleUnit.degrees,
              scrub: _degrees,
            ),
            'maxPitch': FieldHint(
              label: 'Highest pitch',
              unit: AngleUnit.degrees,
              scrub: _degrees,
            ),
          },
        ),
        create: FirstPersonComponent.new,
        fields: [
          _v<FirstPersonComponent>('eye', (c) => c.eye, (c, v) => c.eye = v),
          _d<FirstPersonComponent>('yaw', (c) => c.yaw, (c, v) => c.yaw = v),
          _d<FirstPersonComponent>(
            'pitch',
            (c) => c.pitch,
            (c, v) => c.pitch = v,
          ),
          _d<FirstPersonComponent>(
            'minPitch',
            (c) => c.minPitch,
            (c, v) => c.minPitch = v,
          ),
          _d<FirstPersonComponent>(
            'maxPitch',
            (c) => c.maxPitch,
            (c, v) => c.maxPitch = v,
          ),
        ],
      );

  /// Definition of [LookAtComponent] (aims the camera at its target),
  /// saved as `LookAtComponent`. 3-D only.
  static ComponentDefinition<LookAtComponent> get lookAt =>
      ComponentDefinition<LookAtComponent>(
        type: 'LookAtComponent',
        hints: const ComponentHints(
          dimensions: Dimensions.threeD,
          name: 'Look At',
          group: _group,
          description: 'Turns the camera to look at the followed entity.',
          icon: Icons.center_focus_weak,
          accentColor: _accent,
          fields: {
            'offset': FieldHint(
              label: 'Aim at',
              description: 'From the target (-Y is up).',
            ),
            'damping': FieldHint(label: 'Damping (s)', scrub: _seconds),
          },
        ),
        create: LookAtComponent.new,
        fields: [
          _v<LookAtComponent>(
            'offset',
            (c) => c.offset,
            (c, v) => c.offset = v,
          ),
          _d<LookAtComponent>(
            'damping',
            (c) => c.damping,
            (c, v) => c.damping = v,
            min: 0,
          ),
        ],
      );

  /// Every one of them, in picker order.
  static List<ComponentDefinition> get all => [
    orbitFollow,
    firstPerson,
    lookAt,
  ];
}

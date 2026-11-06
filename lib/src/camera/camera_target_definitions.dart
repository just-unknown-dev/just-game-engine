part of 'camera_definitions.dart';

/// How the target group, group framing and trigger components are
/// saved and shown in an editor: what a shot follows, and where it
/// switches.
abstract final class CameraTargetDefinitions {
  /// Definition of [CameraTargetGroupComponent], saved as
  /// `CameraTargetGroupComponent`.
  static ComponentDefinition<CameraTargetGroupComponent> get targetGroup =>
      ComponentDefinition<CameraTargetGroupComponent>(
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
              description:
                  'Who the group keeps in shot: an entity by name, or every '
                  'entity with a tag.',
              itemTemplate: {
                'target': {'tag': 'player'},
                'weight': 1.0,
                'radius': 0.0,
              },
              itemKinds: {'target': FieldTypes.target},
            ),
          },
        ),
        create: CameraTargetGroupComponent.new,
        fields: [
          FieldDefinition(
            name: 'members',
            kind: FieldTypes.list,
            read: (c) => [
              for (final m in (c as CameraTargetGroupComponent).members)
                m.toJson(),
            ],
            write: (c, v) => (c as CameraTargetGroupComponent).members = [
              for (final m in (v as List?) ?? const [])
                if (m is Map) CameraGroupMember.fromJson(m),
            ],
          ),
        ],
      );

  /// Definition of [CameraGroupFramingComponent], saved as
  /// `CameraGroupFramingComponent`. 2-D only.
  static ComponentDefinition<CameraGroupFramingComponent>
  get groupFraming => ComponentDefinition<CameraGroupFramingComponent>(
    type: 'CameraGroupFramingComponent',
    hints: const ComponentHints(
      dimensions: Dimensions.twoD,
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

  /// Definition of [CameraTriggerComponent], saved as
  /// `CameraTriggerComponent`. 2-D only.
  static ComponentDefinition<CameraTriggerComponent>
  get trigger => ComponentDefinition<CameraTriggerComponent>(
    type: 'CameraTriggerComponent',
    hints: ComponentHints(
      dimensions: Dimensions.twoD,
      name: 'Camera Trigger',
      group: _group,
      description:
          'A rectangle that switches a virtual camera while a target is inside.',
      icon: Icons.sensors,
      accentColor: _accent,
      fieldGroups: const {
        'Area': ['width', 'height'],
        'Set off by': ['target'],
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
        'target': const FieldHint(
          label: 'Target',
          description: 'An entity by name, or any entity with a tag.',
        ),
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
      _t<CameraTriggerComponent>(
        'target',
        (c) => c.target,
        (c, v) => c.target = v,
      ),
      _s<CameraTriggerComponent>(
        'cameraName',
        (c) => c.cameraName,
        (c, v) => c.cameraName = v,
        kind: FieldTypes.entityRef,
      ),
      FieldDefinition(
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

  /// Every one of them, in picker order.
  static List<ComponentDefinition> get all => [
    targetGroup,
    groupFraming,
    trigger,
  ];
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

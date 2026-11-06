part of 'camera_definitions.dart';

/// How the framing, confiner and bounds components are saved and shown
/// in an editor: what keeps the shot composed, and inside the level.
abstract final class CameraFramingDefinitions {
  /// Definition of [CameraFramingComponent] (dead-zone framing), saved as
  /// `CameraFramingComponent`. 2-D only.
  static ComponentDefinition<CameraFramingComponent> get framing =>
      ComponentDefinition<CameraFramingComponent>(
        type: 'CameraFramingComponent',
        hints: const ComponentHints(
          dimensions: Dimensions.twoD,
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

  /// Definition of [CameraConfinerComponent], saved as
  /// `CameraConfinerComponent`. 2-D only.
  static ComponentDefinition<CameraConfinerComponent> get confiner =>
      ComponentDefinition<CameraConfinerComponent>(
        type: 'CameraConfinerComponent',
        hints: const ComponentHints(
          dimensions: Dimensions.twoD,
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

  /// Definition of [CameraBoundsComponent] (the rectangle a confiner
  /// names), saved as `CameraBoundsComponent`. 2-D only.
  static ComponentDefinition<CameraBoundsComponent> get bounds =>
      ComponentDefinition<CameraBoundsComponent>(
        type: 'CameraBoundsComponent',
        hints: const ComponentHints(
          dimensions: Dimensions.twoD,
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

  /// Every one of them, in picker order.
  static List<ComponentDefinition> get all => [framing, confiner, bounds];
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

part of 'camera_definitions.dart';

/// How the noise and impulse components are saved and shown in an
/// editor: a shot's handheld shake, and the kicks it takes.
abstract final class CameraNoiseDefinitions {
  /// Definition of [CameraNoiseComponent] (handheld shake), saved as
  /// `CameraNoiseComponent`. 2-D only.
  static ComponentDefinition<CameraNoiseComponent> get noise =>
      ComponentDefinition<CameraNoiseComponent>(
        type: 'CameraNoiseComponent',
        hints: const ComponentHints(
          dimensions: Dimensions.twoD,
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
          FieldDefinition(
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

  /// Definition of [CameraImpulseListenerComponent], saved as
  /// `CameraImpulseListenerComponent`. 2-D only.
  static ComponentDefinition<CameraImpulseListenerComponent>
  get impulseListener => ComponentDefinition<CameraImpulseListenerComponent>(
    type: 'CameraImpulseListenerComponent',
    hints: const ComponentHints(
      dimensions: Dimensions.twoD,
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

  /// Definition of [CameraImpulseSourceComponent], saved as
  /// `CameraImpulseSourceComponent`. 2-D only.
  static ComponentDefinition<CameraImpulseSourceComponent>
  get impulseSource => ComponentDefinition<CameraImpulseSourceComponent>(
    type: 'CameraImpulseSourceComponent',
    hints: const ComponentHints(
      dimensions: Dimensions.twoD,
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

  /// Every one of them, in picker order.
  static List<ComponentDefinition> get all => [
    noise,
    impulseListener,
    impulseSource,
  ];
}

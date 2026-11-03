/// The audio components: sound sources, the listener and music streams.
library;

import '../ecs/ecs.dart';
import 'audio.dart' show AudioChannel, AudioRolloff;
import 'audio_components.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/painting.dart';

/// The audio components: sound sources, the listener and music streams.
abstract final class AudioDefinitions {
  static bool _is3d(Component c) => (c as AudioSourceComponent).is3d;

  /// [AudioSourceComponent], from `audio_source_editor_component.dart`.
  static ComponentSchema<AudioSourceComponent>
  get audioSource => ComponentSchema<AudioSourceComponent>(
    type: 'AudioSourceComponent',
    hints: ComponentHints(
      name: 'Audio Source',
      group: 'Audio',
      description: 'Plays a sound — flat, or in 3-D from where the entity is.',
      icon: Icons.volume_up,
      accentColor: const Color(0xFFAB47BC),
      fieldGroups: const {
        'Clip': ['path'],
        'Playback': ['loop', 'playOnAdd', 'volume', 'pitch', 'pan', 'channel'],
        '3D': [
          'is3d',
          'minDistance',
          'maxDistance',
          'rolloff',
          'dopplerLevel',
          'farCutoff',
        ],
      },
      fields: {
        'path': const FieldHint(
          label: 'Path',
          fileExtensions: ['mp3', 'wav', 'ogg', 'flac', 'm4a'],
        ),
        'loop': const FieldHint(label: 'Loop'),
        'playOnAdd': const FieldHint(label: 'Play on Add'),
        'volume': const FieldHint(
          label: 'Volume',
          scrub: ScrubHint(step: 0.05, fractionDigits: 2),
        ),
        'pitch': const FieldHint(
          label: 'Pitch',
          scrub: ScrubHint(step: 0.05, fractionDigits: 2),
        ),
        'pan': FieldHint(
          label: 'Pan',
          scrub: const ScrubHint(step: 0.05, fractionDigits: 2),
          visibleWhen: (c) => !(c as AudioSourceComponent).is3d,
        ),
        'channel': const FieldHint(label: 'Channel'),
        'is3d': const FieldHint(label: '3D'),
        'minDistance': FieldHint(
          label: 'Full within',
          scrub: const ScrubHint(step: 0.25, fractionDigits: 2),
          visibleWhen: _is3d,
        ),
        'maxDistance': FieldHint(
          label: 'Silent beyond',
          scrub: const ScrubHint(step: 0.5, fractionDigits: 1),
          visibleWhen: _is3d,
        ),
        'rolloff': FieldHint(label: 'Fade', visibleWhen: _is3d),
        'dopplerLevel': FieldHint(
          label: 'Doppler',
          scrub: const ScrubHint(step: 0.1, fractionDigits: 2),
          visibleWhen: _is3d,
        ),
        'farCutoff': FieldHint(
          label: 'Muffle to',
          scrub: const ScrubHint(step: 100, fractionDigits: 0, suffix: 'Hz'),
          visibleWhen: _is3d,
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
      SchemaField(
        name: 'pan',
        kind: FieldTypes.decimal,
        read: (c) => (c as AudioSourceComponent).pan,
        write: (c, v) => (c as AudioSourceComponent).pan = (v as num)
            .toDouble()
            .clamp(-1.0, 1.0),
        min: -1.0,
        max: 1.0,
      ),
      SchemaField(
        name: 'channel',
        kind: const EnumFieldType(
          AudioChannel.values,
          fallback: AudioChannel.sfx,
          id: 'audio.channel',
        ),
        read: (c) => (c as AudioSourceComponent).channel,
        write: (c, v) =>
            (c as AudioSourceComponent).channel = v as AudioChannel,
      ),
      SchemaField(
        name: 'is3d',
        kind: FieldTypes.boolean,
        read: (c) => (c as AudioSourceComponent).is3d,
        write: (c, v) => (c as AudioSourceComponent).is3d = v as bool,
      ),
      SchemaField(
        name: 'minDistance',
        kind: FieldTypes.decimal,
        read: (c) => (c as AudioSourceComponent).minDistance,
        write: (c, v) =>
            (c as AudioSourceComponent).minDistance = (v as num).toDouble(),
        min: 0.01,
      ),
      SchemaField(
        name: 'maxDistance',
        kind: FieldTypes.decimal,
        read: (c) => (c as AudioSourceComponent).maxDistance,
        write: (c, v) =>
            (c as AudioSourceComponent).maxDistance = (v as num).toDouble(),
        min: 0.01,
      ),
      SchemaField(
        name: 'rolloff',
        kind: const EnumFieldType(
          AudioRolloff.values,
          fallback: AudioRolloff.inverse,
          id: 'audio.rolloff',
        ),
        read: (c) => (c as AudioSourceComponent).rolloff,
        write: (c, v) =>
            (c as AudioSourceComponent).rolloff = v as AudioRolloff,
      ),
      SchemaField(
        name: 'dopplerLevel',
        kind: FieldTypes.decimal,
        read: (c) => (c as AudioSourceComponent).dopplerLevel,
        write: (c, v) =>
            (c as AudioSourceComponent).dopplerLevel = (v as num).toDouble(),
        min: 0.0,
      ),
      SchemaField(
        name: 'farCutoff',
        kind: FieldTypes.decimal,
        read: (c) => (c as AudioSourceComponent).farCutoff,
        write: (c, v) =>
            (c as AudioSourceComponent).farCutoff = (v as num).toDouble(),
        min: 0.0,
      ),
    ],
  );

  /// [AudioListenerComponent].
  static ComponentSchema<AudioListenerComponent> get audioListener =>
      ComponentSchema<AudioListenerComponent>(
        type: 'AudioListenerComponent',
        hints: const ComponentHints(
          name: 'Audio Listener',
          group: 'Audio',
          description:
              'Where 3-D sounds are heard from. Without one, the camera hears.',
          icon: Icons.hearing,
          accentColor: Color(0xFFAB47BC),
          fields: {
            'atCamera': FieldHint(label: 'At the camera'),
            'faceCamera': FieldHint(label: 'Face like the camera'),
          },
        ),
        id: 'audio_listener_5d2c81f3',
        create: AudioListenerComponent.new,
        fields: [
          SchemaField(
            name: 'atCamera',
            kind: FieldTypes.boolean,
            read: (c) => (c as AudioListenerComponent).atCamera,
            write: (c, v) => (c as AudioListenerComponent).atCamera = v as bool,
          ),
          SchemaField(
            name: 'faceCamera',
            kind: FieldTypes.boolean,
            read: (c) => (c as AudioListenerComponent).faceCamera,
            write: (c, v) =>
                (c as AudioListenerComponent).faceCamera = v as bool,
          ),
        ],
      );

  /// [AudioStreamComponent], from `audio_stream_editor_component.dart`.
  static ComponentSchema<AudioStreamComponent> get audioStream =>
      ComponentSchema<AudioStreamComponent>(
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

  /// Every one of them.
  static List<ComponentCodec> get all => [
    audioSource,
    audioListener,
    audioStream,
  ];
}

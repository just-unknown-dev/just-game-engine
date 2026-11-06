/// The audio components: sound sources, the listener and music streams.
library;

import 'dart:math' as math;

import '../ecs/ecs.dart';
import 'audio_components.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/painting.dart';
import 'package:just_audio_engine/just_audio_engine.dart'
    show Audio3DRolloff, AudioChannel;

/// The audio components: sound sources, the listener and music streams.
abstract final class AudioDefinitions {
  static bool _is3D(Component c) => (c as AudioSourceComponent).is3D;

  /// [AudioSourceComponent], from `audio_source_editor_component.dart`.
  static ComponentDefinition<AudioSourceComponent>
  get audioSource => ComponentDefinition<AudioSourceComponent>(
    type: 'AudioSourceComponent',
    hints: ComponentHints(
      name: 'Audio Source',
      group: 'Audio',
      description: 'Plays a sound — flat, or in 3-D from where the entity is.',
      icon: Icons.volume_up,
      accentColor: const Color(0xFFAB47BC),
      fieldGroups: const {
        'Clip': ['path'],
        'Playback': [
          'loop',
          'playOnAdd',
          'volume',
          'pitch',
          'speed',
          'pan',
          'channel',
        ],
        '3D': [
          'is3D',
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
        'speed': const FieldHint(
          label: 'Speed',
          scrub: ScrubHint(step: 0.05, fractionDigits: 2),
        ),
        'pan': FieldHint(
          label: 'Pan',
          scrub: const ScrubHint(step: 0.05, fractionDigits: 2),
          visibleWhen: (c) => !(c as AudioSourceComponent).is3D,
        ),
        'channel': const FieldHint(label: 'Channel'),
        'is3D': const FieldHint(label: '3D'),
        'minDistance': FieldHint(
          label: 'Full within',
          scrub: const ScrubHint(step: 0.25, fractionDigits: 2),
          visibleWhen: _is3D,
        ),
        'maxDistance': FieldHint(
          label: 'Silent beyond',
          scrub: const ScrubHint(step: 0.5, fractionDigits: 1),
          visibleWhen: _is3D,
        ),
        'rolloff': FieldHint(label: 'Fade', visibleWhen: _is3D),
        'dopplerLevel': FieldHint(
          label: 'Doppler',
          scrub: const ScrubHint(step: 0.1, fractionDigits: 2),
          visibleWhen: _is3D,
        ),
        'farCutoff': FieldHint(
          label: 'Muffle to',
          scrub: const ScrubHint(step: 100, fractionDigits: 0, suffix: 'Hz'),
          visibleWhen: _is3D,
        ),
      },
    ),
    id: 'audio_source_111e2e48',
    create: () => AudioSourceComponent(clipPath: ''),
    fields: [
      FieldDefinition(
        name: 'path',
        kind: FieldTypes.assetRef,
        read: (c) => (c as AudioSourceComponent).clipPath,
        write: (c, v) => (c as AudioSourceComponent).clipPath = v as String,
      ),
      FieldDefinition(
        name: 'loop',
        kind: FieldTypes.boolean,
        read: (c) => (c as AudioSourceComponent).loop,
        write: (c, v) => (c as AudioSourceComponent).loop = v as bool,
      ),
      FieldDefinition(
        name: 'playOnAdd',
        kind: FieldTypes.boolean,
        read: (c) => (c as AudioSourceComponent).playOnAdd,
        write: (c, v) => (c as AudioSourceComponent).playOnAdd = v as bool,
      ),
      FieldDefinition(
        name: 'volume',
        kind: FieldTypes.decimal,
        read: (c) => (c as AudioSourceComponent).volume,
        write: (c, v) => (c as AudioSourceComponent).volume = (v as num)
            .toDouble()
            .clamp(0.0, 1.0),
        min: 0.0,
        max: 1.0,
      ),
      FieldDefinition(
        name: 'pitch',
        kind: FieldTypes.decimal,
        read: (c) => (c as AudioSourceComponent).pitch,
        write: (c, v) =>
            (c as AudioSourceComponent).pitch = (v as num).toDouble(),
        min: 0.0,
      ),
      FieldDefinition(
        name: 'speed',
        kind: FieldTypes.decimal,
        read: (c) => (c as AudioSourceComponent).speed,
        write: (c, v) => (c as AudioSourceComponent).speed = math.max(
          (v as num).toDouble(),
          0.0,
        ),
        min: 0.0,
      ),
      FieldDefinition(
        name: 'pan',
        kind: FieldTypes.decimal,
        read: (c) => (c as AudioSourceComponent).pan,
        write: (c, v) => (c as AudioSourceComponent).pan = (v as num)
            .toDouble()
            .clamp(-1.0, 1.0),
        min: -1.0,
        max: 1.0,
      ),
      FieldDefinition(
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
      FieldDefinition(
        name: 'is3D',
        kind: FieldTypes.boolean,
        read: (c) => (c as AudioSourceComponent).is3D,
        write: (c, v) => (c as AudioSourceComponent).is3D = v as bool,
      ),
      FieldDefinition(
        name: 'minDistance',
        kind: FieldTypes.decimal,
        read: (c) => (c as AudioSourceComponent).minDistance,
        write: (c, v) =>
            (c as AudioSourceComponent).minDistance = (v as num).toDouble(),
        min: 0.01,
      ),
      FieldDefinition(
        name: 'maxDistance',
        kind: FieldTypes.decimal,
        read: (c) => (c as AudioSourceComponent).maxDistance,
        write: (c, v) =>
            (c as AudioSourceComponent).maxDistance = (v as num).toDouble(),
        min: 0.01,
      ),
      FieldDefinition(
        name: 'rolloff',
        kind: const EnumFieldType(
          Audio3DRolloff.values,
          fallback: Audio3DRolloff.inverse,
          id: 'audio.rolloff',
        ),
        read: (c) => (c as AudioSourceComponent).rolloff,
        write: (c, v) =>
            (c as AudioSourceComponent).rolloff = v as Audio3DRolloff,
      ),
      FieldDefinition(
        name: 'dopplerLevel',
        kind: FieldTypes.decimal,
        read: (c) => (c as AudioSourceComponent).dopplerLevel,
        write: (c, v) =>
            (c as AudioSourceComponent).dopplerLevel = (v as num).toDouble(),
        min: 0.0,
      ),
      FieldDefinition(
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
  static ComponentDefinition<AudioListenerComponent> get audioListener =>
      ComponentDefinition<AudioListenerComponent>(
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
          FieldDefinition(
            name: 'atCamera',
            kind: FieldTypes.boolean,
            read: (c) => (c as AudioListenerComponent).atCamera,
            write: (c, v) => (c as AudioListenerComponent).atCamera = v as bool,
          ),
          FieldDefinition(
            name: 'faceCamera',
            kind: FieldTypes.boolean,
            read: (c) => (c as AudioListenerComponent).faceCamera,
            write: (c, v) =>
                (c as AudioListenerComponent).faceCamera = v as bool,
          ),
        ],
      );

  /// [AudioStreamComponent], from `audio_stream_editor_component.dart`.
  static ComponentDefinition<AudioStreamComponent> get audioStream =>
      ComponentDefinition<AudioStreamComponent>(
        type: 'AudioStreamComponent',
        hints: const ComponentHints(
          name: 'Audio Stream',
          group: 'Audio',
          icon: Icons.graphic_eq,
          accentColor: Color(0xFFAB47BC),
          fieldGroups: {
            'Stream': ['streamPath'],
            'Playback': ['loop', 'playOnAdd', 'volume', 'channel', 'fadeIn'],
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
            'channel': FieldHint(label: 'Channel'),
            'fadeIn': FieldHint(
              label: 'Fade in',
              description: 'Seconds from silence to the volume; 0 for none.',
              scrub: ScrubHint(step: 0.1, fractionDigits: 2, suffix: 's'),
            ),
          },
        ),
        id: 'audio_stream_91f6500b',
        create: () => AudioStreamComponent(path: ''),
        fields: [
          FieldDefinition(
            name: 'streamPath',
            kind: FieldTypes.assetRef,
            read: (c) => (c as AudioStreamComponent).path,
            write: (c, v) => (c as AudioStreamComponent).path = v as String,
          ),
          FieldDefinition(
            name: 'loop',
            kind: FieldTypes.boolean,
            read: (c) => (c as AudioStreamComponent).loop,
            write: (c, v) => (c as AudioStreamComponent).loop = v as bool,
          ),
          FieldDefinition(
            name: 'playOnAdd',
            kind: FieldTypes.boolean,
            read: (c) => (c as AudioStreamComponent).playOnAdd,
            write: (c, v) => (c as AudioStreamComponent).playOnAdd = v as bool,
          ),
          FieldDefinition(
            name: 'volume',
            kind: FieldTypes.decimal,
            read: (c) => (c as AudioStreamComponent).volume,
            write: (c, v) => (c as AudioStreamComponent).volume = (v as num)
                .toDouble()
                .clamp(0.0, 1.0),
            min: 0.0,
            max: 1.0,
          ),
          FieldDefinition(
            name: 'channel',
            kind: const EnumFieldType(
              AudioChannel.values,
              fallback: AudioChannel.music,
              id: 'audio.channel',
            ),
            read: (c) => (c as AudioStreamComponent).channel,
            write: (c, v) =>
                (c as AudioStreamComponent).channel = v as AudioChannel,
          ),
          // Seconds; 0 is no fade.
          FieldDefinition(
            name: 'fadeIn',
            kind: FieldTypes.decimal,
            read: (c) {
              final fade = (c as AudioStreamComponent).fadeInDuration;
              return fade == null ? 0.0 : fade.inMicroseconds / 1e6;
            },
            write: (c, v) {
              final seconds = (v as num).toDouble();
              (c as AudioStreamComponent).fadeInDuration = seconds > 0
                  ? Duration(microseconds: (seconds * 1e6).round())
                  : null;
            },
            min: 0.0,
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

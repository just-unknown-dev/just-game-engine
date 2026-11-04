/// Definitions for the timeline components that are not plain field lists.
library;

import 'timeline_player_component.dart';
import 'timeline_asset.dart';

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/painting.dart';
import '../foundation/dimensions.dart';

import '../ecs/ecs.dart';
import 'timeline_trigger_component.dart';

/// Definitions for the timeline components that need more than a plain
/// field list: [TimelineTriggerComponent], whose rectangle the editor sizes and
/// scales.
abstract final class TimelineDefinitions {
  static const Color _accent = Color(0xFF7DD8E0);

  static const _actions = EnumFieldType(
    TimelineTriggerAction.values,
    fallback: TimelineTriggerAction.nothing,
    id: 'enum.timelineTriggerAction',
  );

  /// Definition of [TimelineTriggerComponent], saved as
  /// `TimelineTriggerComponent`.
  static ComponentDefinition<TimelineTriggerComponent> get trigger =>
      ComponentDefinition<TimelineTriggerComponent>(
        type: 'TimelineTriggerComponent',
        hints: const ComponentHints(
          dimensions: Dimensions.twoD,
          name: 'Timeline Trigger',
          group: 'Animation',
          description:
              'A rectangle that plays a timeline when a target walks into it.',
          icon: Icons.sensors,
          accentColor: _accent,
          fieldGroups: {
            'Area': ['width', 'height'],
            'Set off by': ['target'],
            'Does': ['playerName', 'enterAction', 'exitAction', 'oneShot'],
          },
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
            'target': FieldHint(
              label: 'Target',
              description: 'An entity by name, or any entity with a tag.',
            ),
            'playerName': FieldHint(
              label: 'Player',
              description: 'Empty: the Timeline Player on this entity.',
            ),
            'enterAction': FieldHint(label: 'On enter'),
            'exitAction': FieldHint(label: 'On exit'),
            'oneShot': FieldHint(label: 'One shot'),
          },
        ),
        create: TimelineTriggerComponent.new,
        extent: const _TriggerExtent(),
        fields: [
          FieldDefinition(
            name: 'width',
            kind: FieldTypes.decimal,
            read: (c) => (c as TimelineTriggerComponent).width,
            write: (c, v) =>
                (c as TimelineTriggerComponent).width = (v as num).toDouble(),
            min: 1,
          ),
          FieldDefinition(
            name: 'height',
            kind: FieldTypes.decimal,
            read: (c) => (c as TimelineTriggerComponent).height,
            write: (c, v) =>
                (c as TimelineTriggerComponent).height = (v as num).toDouble(),
            min: 1,
          ),
          FieldDefinition(
            name: 'target',
            kind: FieldTypes.target,
            read: (c) => (c as TimelineTriggerComponent).target,
            write: (c, v) => (c as TimelineTriggerComponent).target =
                v as EntityTarget? ?? EntityTarget.none,
          ),
          FieldDefinition(
            name: 'playerName',
            kind: FieldTypes.entityRef,
            read: (c) => (c as TimelineTriggerComponent).playerName,
            write: (c, v) =>
                (c as TimelineTriggerComponent).playerName = v as String? ?? '',
          ),
          FieldDefinition(
            name: 'enterAction',
            kind: _actions,
            read: (c) => (c as TimelineTriggerComponent).enterAction,
            write: (c, v) => (c as TimelineTriggerComponent).enterAction =
                v as TimelineTriggerAction,
          ),
          FieldDefinition(
            name: 'exitAction',
            kind: _actions,
            read: (c) => (c as TimelineTriggerComponent).exitAction,
            write: (c, v) => (c as TimelineTriggerComponent).exitAction =
                v as TimelineTriggerAction,
          ),
          FieldDefinition(
            name: 'oneShot',
            kind: FieldTypes.boolean,
            read: (c) => (c as TimelineTriggerComponent).oneShot,
            write: (c, v) =>
                (c as TimelineTriggerComponent).oneShot = v as bool,
          ),
        ],
      );

  /// Definition of [TimelinePlayerComponent], saved as
  /// `TimelinePlayerComponent`: plays a timeline asset, or an inline one.
  static ComponentDefinition<TimelinePlayerComponent>
  get timelinePlayer => ComponentDefinition<TimelinePlayerComponent>(
    type: 'TimelinePlayerComponent',
    hints: const ComponentHints(
      name: 'Timeline Player',
      group: 'Animation',
      description:
          'Plays a timeline: keyed fields, sprite clips, events, camera '
          'shots and sounds on one clock.',
      icon: Icons.timeline_rounded,
      accentColor: Color(0xFF7DD8E0),
      fieldGroups: {
        'Timeline': ['timelinePath'],
        'Playback': ['playOnStart', 'speed', 'wrap', 'listenSignal'],
        'Part of it': ['from', 'to'],
      },
      fields: {
        'timelinePath': FieldHint(
          label: 'Timeline',
          description:
              'A .timeline.json asset. Empty plays the timeline saved '
              'inside this component.',
          fileExtensions: ['timeline.json', 'json'],
        ),
        'inline': FieldHint(label: 'Inline timeline', visible: false),
        'playOnStart': FieldHint(label: 'Play on Start'),
        'speed': FieldHint(
          label: 'Speed',
          description: 'Negative plays backwards.',
          scrub: ScrubHint(step: 0.05, fractionDigits: 2),
        ),
        'wrap': FieldHint(label: 'Wrap'),
        'listenSignal': FieldHint(
          label: 'Play on signal',
          description: 'A timeline signal that starts this player.',
        ),
        'from': FieldHint(
          label: 'Play from',
          description:
              'Seconds. Zero starts at the beginning. With Play to, this '
              'entity runs only part of the timeline — so one file can serve '
              'several entities differently.',
          scrub: ScrubHint(step: 0.05, fractionDigits: 2),
        ),
        'to': FieldHint(
          label: 'Play to',
          description: 'Seconds. Zero plays to the end.',
          scrub: ScrubHint(step: 0.05, fractionDigits: 2),
        ),
      },
    ),
    id: 'timeline_player_3d91c7aa',
    create: TimelinePlayerComponent.new,
    fields: [
      FieldDefinition(
        name: 'timelinePath',
        kind: FieldTypes.assetRef,
        read: (c) => (c as TimelinePlayerComponent).timelinePath,
        write: (c, v) =>
            (c as TimelinePlayerComponent).timelinePath = v as String? ?? '',
      ),
      FieldDefinition(
        name: 'inline',
        kind: FieldTypes.map,
        read: (c) => (c as TimelinePlayerComponent).inline?.toJson(),
        write: (c, v) => (c as TimelinePlayerComponent).inline = v is Map
            ? TimelineAsset.fromJson(v.cast<String, dynamic>())
            : null,
      ),
      FieldDefinition(
        name: 'playOnStart',
        kind: FieldTypes.boolean,
        read: (c) => (c as TimelinePlayerComponent).playOnStart,
        write: (c, v) => (c as TimelinePlayerComponent).playOnStart = v as bool,
      ),
      FieldDefinition(
        name: 'speed',
        kind: FieldTypes.decimal,
        read: (c) => (c as TimelinePlayerComponent).speed,
        write: (c, v) =>
            (c as TimelinePlayerComponent).speed = (v as num).toDouble(),
        min: -16,
        max: 16,
      ),
      FieldDefinition(
        name: 'wrap',
        kind: const EnumFieldType(
          TimelineWrapChoice.values,
          fallback: TimelineWrapChoice.fromTimeline,
          id: 'enum.timelineWrapChoice',
        ),
        read: (c) => (c as TimelinePlayerComponent).wrap,
        write: (c, v) =>
            (c as TimelinePlayerComponent).wrap = v as TimelineWrapChoice,
      ),
      FieldDefinition(
        name: 'listenSignal',
        kind: FieldTypes.text,
        read: (c) => (c as TimelinePlayerComponent).listenSignal,
        write: (c, v) =>
            (c as TimelinePlayerComponent).listenSignal = v as String? ?? '',
      ),
      FieldDefinition(
        name: 'from',
        kind: FieldTypes.decimal,
        read: (c) => (c as TimelinePlayerComponent).from,
        // A scene saved before these existed has no key for them.
        write: (c, v) =>
            (c as TimelinePlayerComponent).from = (v as num?)?.toDouble() ?? 0,
        min: 0,
      ),
      FieldDefinition(
        name: 'to',
        kind: FieldTypes.decimal,
        read: (c) => (c as TimelinePlayerComponent).to,
        // A scene saved before these existed has no key for them.
        write: (c, v) =>
            (c as TimelinePlayerComponent).to = (v as num?)?.toDouble() ?? 0,
        min: 0,
      ),
    ],
  );

  /// Every definition above — a new list on each call.
  static List<ComponentDefinition> get all => [trigger, timelinePlayer];
}

class _TriggerExtent extends ComponentExtent {
  const _TriggerExtent();

  @override
  Size? sizeOf(Component component) {
    final t = component as TimelineTriggerComponent;
    return Size(t.width, t.height);
  }

  @override
  bool scale(Component component, double sx, double sy) {
    final t = component as TimelineTriggerComponent;
    t
      ..width = t.width * sx.abs()
      ..height = t.height * sy.abs();
    return true;
  }
}

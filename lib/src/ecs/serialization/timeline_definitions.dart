/// Definitions for the timeline components that are not plain schemas.
library;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/painting.dart';

import '../components/components.dart';
import '../ecs.dart';
import 'component_definition.dart';
import 'field_type.dart';

abstract final class TimelineDefinitions {
  static const Color _accent = Color(0xFF7DD8E0);

  static const _actions = EnumFieldType(
    TimelineTriggerAction.values,
    fallback: TimelineTriggerAction.nothing,
    id: 'enum.timelineTriggerAction',
  );

  static final trigger = ComponentDefinition<TimelineTriggerComponent>(
    type: 'TimelineTriggerComponent',
    hints: const ComponentHints(
      name: 'Timeline Trigger',
      group: 'Animation',
      description:
          'A rectangle that plays a timeline when a target walks into it.',
      icon: Icons.sensors,
      accentColor: _accent,
      fieldGroups: {
        'Area': ['width', 'height'],
        'Set off by': ['targetName', 'targetTag'],
        'Does': ['playerName', 'onEnter', 'onExit', 'oneShot'],
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
        'targetName': FieldHint(label: 'Entity'),
        'targetTag': FieldHint(label: 'Tag'),
        'playerName': FieldHint(
          label: 'Player',
          description: 'Empty: the Timeline Player on this entity.',
        ),
        'onEnter': FieldHint(label: 'On enter'),
        'onExit': FieldHint(label: 'On exit'),
        'oneShot': FieldHint(label: 'One shot'),
      },
    ),
    create: TimelineTriggerComponent.new,
    extent: const _TriggerExtent(),
    fields: [
      SchemaField(
        name: 'width',
        kind: FieldTypes.decimal,
        read: (c) => (c as TimelineTriggerComponent).width,
        write: (c, v) =>
            (c as TimelineTriggerComponent).width = (v as num).toDouble(),
        min: 1,
      ),
      SchemaField(
        name: 'height',
        kind: FieldTypes.decimal,
        read: (c) => (c as TimelineTriggerComponent).height,
        write: (c, v) =>
            (c as TimelineTriggerComponent).height = (v as num).toDouble(),
        min: 1,
      ),
      SchemaField(
        name: 'targetName',
        kind: FieldTypes.entityRef,
        read: (c) => (c as TimelineTriggerComponent).targetName,
        write: (c, v) =>
            (c as TimelineTriggerComponent).targetName = v as String? ?? '',
      ),
      SchemaField(
        name: 'targetTag',
        kind: FieldTypes.text,
        read: (c) => (c as TimelineTriggerComponent).targetTag,
        write: (c, v) =>
            (c as TimelineTriggerComponent).targetTag = v as String? ?? '',
      ),
      SchemaField(
        name: 'playerName',
        kind: FieldTypes.entityRef,
        read: (c) => (c as TimelineTriggerComponent).playerName,
        write: (c, v) =>
            (c as TimelineTriggerComponent).playerName = v as String? ?? '',
      ),
      SchemaField(
        name: 'onEnter',
        kind: _actions,
        read: (c) => (c as TimelineTriggerComponent).onEnter,
        write: (c, v) => (c as TimelineTriggerComponent).onEnter =
            v as TimelineTriggerAction,
      ),
      SchemaField(
        name: 'onExit',
        kind: _actions,
        read: (c) => (c as TimelineTriggerComponent).onExit,
        write: (c, v) =>
            (c as TimelineTriggerComponent).onExit = v as TimelineTriggerAction,
      ),
      SchemaField(
        name: 'oneShot',
        kind: FieldTypes.boolean,
        read: (c) => (c as TimelineTriggerComponent).oneShot,
        write: (c, v) => (c as TimelineTriggerComponent).oneShot = v as bool,
      ),
    ],
  );

  static List<ComponentDefinition> get all => [trigger];
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

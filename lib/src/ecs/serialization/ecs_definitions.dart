/// The ECS core's own components: the transform, the parent and children

/// links, and tags. Every `EngineContext` has them.
library;

import '../ecs.dart';
import 'component_codec.dart';
import 'component_definition.dart';
import 'field_type.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/painting.dart';
import 'package:just_dart/just_dart.dart';

/// The ECS core's own components: the transform, the parent and children
/// links, and tags. Every `EngineContext` has them.
abstract final class EcsDefinitions {
  /// Definition of [TransformComponent], saved as `TransformComponent`:
  /// `position`, `rotation` (Euler angles in radians) and `scale`. It
  /// cannot be removed in the inspector.
  static ComponentDefinition<TransformComponent> get transform =>
      ComponentDefinition<TransformComponent>(
        type: 'TransformComponent',
        hints: const ComponentHints(
          name: 'Transform',
          group: 'Core',
          description: 'Position, rotation, and scale.',
          icon: Icons.open_with,
          accentColor: Color(0xFF607D8B),
          deletable: false,
          fieldGroups: {
            'Position': ['position'],
            'Rotation': ['rotation'],
            'Scale': ['scale'],
          },
          fields: {
            'position': FieldHint(
              label: 'Position',
              scrub: ScrubHint(fractionDigits: 1),
            ),
            // Three angles; a 2-D scene shows only the one about Z.
            'rotation': FieldHint(
              label: 'Rotation',
              unit: AngleUnit.degrees,
              scrub: ScrubHint(fractionDigits: 1),
            ),
            'scale': FieldHint(
              label: 'Scale',
              scrub: ScrubHint(step: 0.05, fractionDigits: 3),
            ),
          },
        ),
        create: TransformComponent.new,
        // A loaded transform has not moved yet: its previous pose is the one
        // just read. Left at the origin, render interpolation would draw a
        // physics body sliding in from (0, 0) until its first physics step.
        afterDecode: (c) => (c as TransformComponent).capturePrevious(),
        fields: [
          SchemaField(
            name: 'position',
            kind: FieldTypes.vector3,
            read: (c) => Vector3.copy((c as TransformComponent).position),
            write: (c, v) =>
                (c as TransformComponent).position.setFrom(v as Vector3),
          ),
          SchemaField(
            name: 'rotation',
            kind: FieldTypes.euler,
            read: (c) {
              final t = c as TransformComponent;
              return Vector3(t.eulerX, t.eulerY, t.angle);
            },
            write: (c, v) {
              final e = v as Vector3;
              (c as TransformComponent).setEuler(e.x, e.y, e.z);
            },
          ),
          SchemaField(
            name: 'scale',
            kind: FieldTypes.vector3,
            read: (c) => (c as TransformComponent).scale,
            write: (c, v) =>
                (c as TransformComponent).scale.setFrom(v as Vector3),
          ),
        ],
      );

  /// Definition of [TagComponent], saved as `TagComponent` with its tags as
  /// a `tags` list.
  static ComponentDefinition<TagComponent> get tag =>
      ComponentDefinition<TagComponent>(
        type: 'TagComponent',
        hints: const ComponentHints(
          name: 'Tag',
          group: 'Gameplay',
          description:
              'Labels cameras, triggers and systems find this entity by. An '
              'entity can carry several.',
          icon: Icons.label,
          accentColor: Color(0xFF66BB6A),
          fields: {'tags': FieldHint(label: 'Tags')},
        ),
        create: TagComponent.new,
        // Saved as one `tag` until scene format 7.
        fields: [
          SchemaField(
            name: 'tags',
            kind: FieldTypes.tagList,
            read: (c) => (c as TagComponent).tags.toList(),
            write: (c, v) => (c as TagComponent).tags = [
              for (final t in v as List? ?? const []) '$t',
            ],
          ),
        ],
      );

  /// Definition of [ChildrenComponent], saved as `ChildrenComponent`. Its
  /// `childIds` are saved for reference only and never read back.
  static ComponentDefinition<ChildrenComponent>
  get children => ComponentDefinition<ChildrenComponent>(
    type: 'ChildrenComponent',
    hints: const ComponentHints(
      name: 'Children',
      group: 'Hierarchy',
      description: 'The entities parented to this one.',
      icon: Icons.account_tree,
      accentColor: Color(0xFF26A69A),
      fields: {'childIds': FieldHint(label: 'Children', editable: false)},
    ),
    create: ChildrenComponent.new,
    fields: [
      // Saved for reference only: ids are not stable across sessions, so the
      // loader re-links children by their parent's name instead.
      SchemaField(
        name: 'childIds',
        kind: FieldTypes.list,
        read: (c) => List<int>.of((c as ChildrenComponent).childIds),
      ),
    ],
  );

  /// Definition of [ParentComponent], saved as `ParentComponent`. Its
  /// `parentId` is saved for reference only; no local transform is saved.
  static ComponentDefinition<ParentComponent> get parent =>
      ComponentDefinition<ParentComponent>(
        type: 'ParentComponent',
        hints: const ComponentHints(
          name: 'Parent',
          group: 'Hierarchy',
          description:
              'Hangs this entity under another: it moves, turns and scales '
              'with it. The local values are worked out from where things are.',
          icon: Icons.link,
          accentColor: Color(0xFF26A69A),
          fields: {'parentId': FieldHint(label: 'Parent', editable: false)},
        ),
        create: ParentComponent.new,
        fields: [
          // Re-linked by name on load; see childIds.
          SchemaField(
            name: 'parentId',
            kind: FieldTypes.integer,
            read: (c) => (c as ParentComponent).parentId,
          ),
          // Nothing local is saved: the offset from the parent follows from
          // the world transforms, which are what the file means.
        ],
      );

  /// Every one of them.
  static List<ComponentCodec> get all => [transform, tag, children, parent];
}

/// The animation components: the animator.
library;

import '../ecs/serialization/component_codec.dart';
import '../ecs/serialization/component_definition.dart';
import '../ecs/serialization/field_type.dart';
import 'animator_component.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/painting.dart';

/// The animation components: the animator.
abstract final class AnimationDefinitions {
  /// [AnimatorComponent]: the animation state machine.
  static ComponentDefinition<AnimatorComponent>
  get animator => ComponentDefinition<AnimatorComponent>(
    type: 'AnimatorComponent',
    hints: const ComponentHints(
      name: 'Animator',
      group: 'Animation',
      description:
          'A state machine that picks which clip the Sprite Animation plays.',
      icon: Icons.account_tree_outlined,
      accentColor: Color(0xFFFFCA28),
      fields: {
        'graphPath': FieldHint(
          label: 'Graph',
          fileExtensions: ['animator.json', 'json'],
        ),
        'enabled': FieldHint(label: 'Enabled'),
        'faceVelocity': FieldHint(
          label: 'Face movement',
          description: 'Flip the sprite to face the way it moves.',
        ),
      },
    ),
    id: 'animator_5b0e6a37',
    create: AnimatorComponent.new,
    fields: [
      FieldDefinition(
        name: 'graphPath',
        kind: FieldTypes.assetRef,
        read: (c) => (c as AnimatorComponent).graphPath,
        write: (c, v) => (c as AnimatorComponent).graphPath = v as String,
      ),
      FieldDefinition(
        name: 'enabled',
        kind: FieldTypes.boolean,
        read: (c) => (c as AnimatorComponent).enabled,
        write: (c, v) => (c as AnimatorComponent).enabled = v as bool,
      ),
      FieldDefinition(
        name: 'faceVelocity',
        kind: FieldTypes.boolean,
        read: (c) => (c as AnimatorComponent).faceVelocity,
        write: (c, v) => (c as AnimatorComponent).faceVelocity = v as bool,
      ),
    ],
  );

  /// Every one of them.
  static List<ComponentCodec> get all => [animator];
}

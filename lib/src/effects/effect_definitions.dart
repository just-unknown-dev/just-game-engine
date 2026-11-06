/// The deterministic effects component.
library;

import '../ecs/serialization/component_codec.dart';
import '../ecs/serialization/component_definition.dart';
import 'effect_component.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/painting.dart';

/// The deterministic effects component.
abstract final class EffectDefinitions {
  /// Definition of [EffectComponent], saved as `EffectComponent` with no
  /// fields: its effect queue is not saved, so a loaded one starts empty.
  static ComponentDefinition<EffectComponent> get effect =>
      ComponentDefinition<EffectComponent>(
        type: 'EffectComponent',
        hints: const ComponentHints(
          name: 'Effects',
          group: 'Effects',
          icon: Icons.auto_awesome,
          accentColor: Color(0xFFFF4081),
        ),
        create: EffectComponent.new,
        fields: const [],
      );

  /// Every one of them.
  static List<ComponentCodec> get all => [effect];
}

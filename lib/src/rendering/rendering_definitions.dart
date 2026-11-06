/// The rendering components: the layer an entity draws on.
library;

import '../ecs/ecs.dart';
import '../foundation/dimensions.dart';
import 'layer_component.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/painting.dart';

/// The rendering components: the layer an entity draws on.
abstract final class RenderingDefinitions {
  static bool _onMapLayer(Component c) =>
      (c as LayerComponent).mapLayer != null;
  static bool _offMapLayer(Component c) => !_onMapLayer(c);

  /// [LayerComponent], from `layer_editor_component.dart`.
  static ComponentDefinition<LayerComponent>
  get layer => ComponentDefinition<LayerComponent>(
    type: 'LayerComponent',
    hints: const ComponentHints(
      dimensions: Dimensions.twoD,
      name: 'Layer',
      group: 'Rendering',
      icon: Icons.layers,
      accentColor: Color(0xFF78909C),
      fields: {
        // On a map layer these follow the layer: shown only off one.
        'layerId': FieldHint(label: 'Layer', visibleWhen: _offMapLayer),
        'layer': FieldHint(
          label: 'Order',
          scrub: ScrubHint(step: 10, integer: true),
          visibleWhen: _offMapLayer,
        ),
        'zOrder': FieldHint(
          label: 'Z',
          scrub: ScrubHint(integer: true),
          visibleWhen: _offMapLayer,
        ),
        'mapLayer': FieldHint(
          label: 'Map layer',
          description:
              'The layer of its level map it belongs to: it draws and hides '
              'with it. Move it to another in the scene tree.',
          editable: false,
          visibleWhen: _onMapLayer,
        ),
      },
    ),
    id: 'layer_3ab67e05',
    create: LayerComponent.new,
    fields: [
      FieldDefinition(
        name: 'layerId',
        kind: FieldTypes.text,
        read: (c) => (c as LayerComponent).layerId,
        write: (c, v) =>
            (c as LayerComponent).layerId = (v as String?) ?? 'main',
      ),
      FieldDefinition(
        name: 'layer',
        kind: FieldTypes.integer,
        read: (c) => (c as LayerComponent).layer,
        write: (c, v) => (c as LayerComponent).layer = (v as num).toInt(),
        min: -1000,
        max: 1000,
      ),
      FieldDefinition(
        name: 'zOrder',
        kind: FieldTypes.integer,
        read: (c) => (c as LayerComponent).zOrder,
        write: (c, v) => (c as LayerComponent).zOrder = (v as num).toInt(),
        min: -1000,
        max: 1000,
      ),
      FieldDefinition(
        name: 'mapLayer',
        kind: FieldTypes.integer,
        read: (c) => (c as LayerComponent).mapLayer,
        write: (c, v) => (c as LayerComponent).mapLayer = (v as num?)?.toInt(),
      ),
    ],
  );

  /// Every one of them.
  static List<ComponentCodec> get all => [layer];
}

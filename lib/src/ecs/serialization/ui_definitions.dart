/// What the screen-space UI components save, and how the inspector shows
/// them.
library;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/painting.dart';

import '../../subsystems/ui/ui_actions.dart';
import '../components/components.dart';
import '../ecs.dart';
import 'component_definition.dart';
import 'field_type.dart';

abstract final class UiDefinitions {
  static const String _group = 'UI';
  static const Color _accent = Color(0xFF5C6BC0);

  // ── Helpers, so a field of each kind is one line ────────────────────────

  static SchemaField _d<T extends Component>(
    String name,
    double Function(T c) read,
    void Function(T c, double v) write, {
    double? min,
    double? max,
  }) => SchemaField(
    name: name,
    kind: FieldTypes.decimal,
    read: (c) => read(c as T),
    write: (c, v) => write(c as T, (v as num?)?.toDouble() ?? 0),
    min: min,
    max: max,
  );

  static SchemaField _i<T extends Component>(
    String name,
    int Function(T c) read,
    void Function(T c, int v) write, {
    double? min,
  }) => SchemaField(
    name: name,
    kind: FieldTypes.integer,
    read: (c) => read(c as T),
    write: (c, v) => write(c as T, (v as num?)?.toInt() ?? 0),
    min: min,
  );

  static SchemaField _b<T extends Component>(
    String name,
    bool Function(T c) read,
    void Function(T c, bool v) write,
  ) => SchemaField(
    name: name,
    kind: FieldTypes.boolean,
    read: (c) => read(c as T),
    write: (c, v) => write(c as T, v as bool? ?? false),
  );

  static SchemaField _s<T extends Component>(
    String name,
    String Function(T c) read,
    void Function(T c, String v) write, {
    FieldType kind = FieldTypes.text,
  }) => SchemaField(
    name: name,
    kind: kind,
    read: (c) => read(c as T),
    write: (c, v) => write(c as T, v as String? ?? ''),
  );

  static SchemaField _color<T extends Component>(
    String name,
    Color? Function(T c) read,
    void Function(T c, Color? v) write,
  ) => SchemaField(
    name: name,
    kind: FieldTypes.color,
    read: (c) => read(c as T),
    write: (c, v) => write(c as T, v as Color?),
  );

  static SchemaField _insets<T extends Component>(
    String name,
    EdgeInsets Function(T c) read,
    void Function(T c, EdgeInsets v) write,
  ) => SchemaField(
    name: name,
    kind: FieldTypes.edgeInsets,
    read: (c) => read(c as T),
    write: (c, v) => write(c as T, v is EdgeInsets ? v : EdgeInsets.zero),
  );

  static SchemaField _actions<T extends Component>(
    String name,
    UiActionList Function(T c) read,
    void Function(T c, UiActionList v) write,
  ) => SchemaField(
    name: name,
    kind: FieldTypes.uiActions,
    read: (c) => read(c as T),
    write: (c, v) => write(c as T, v is UiActionList ? v : UiActionList.empty),
  );

  // ── The canvas ──────────────────────────────────────────────────────────

  static final canvas = ComponentDefinition<UiCanvasComponent>(
    type: 'UiCanvasComponent',
    hints: const ComponentHints(
      name: 'UI Canvas',
      group: _group,
      description:
          'The root of a screen: everything under it is laid out by real '
          'Flutter widgets.',
      icon: Icons.web_asset,
      accentColor: _accent,
      fieldGroups: {
        'Design': ['designW', 'designH', 'scaleMode', 'safeArea'],
        'Behaviour': ['visible', 'isScreen', 'modal', 'transition'],
        'Style': ['theme', 'sortOrder', 'initialFocus'],
      },
      fieldRows: [
        FieldRowHint('Design size', {'designW': 'W', 'designH': 'H'}),
      ],
      fields: {
        'designW': FieldHint(label: 'Width'),
        'designH': FieldHint(label: 'Height'),
        'scaleMode': FieldHint(
          label: 'Scale',
          description: 'How this answers a screen it was not drawn for.',
        ),
        'safeArea': FieldHint(label: 'Safe area'),
        'visible': FieldHint(label: 'Visible'),
        'isScreen': FieldHint(
          label: 'Is a screen',
          description:
              'Pushed and popped like a page, rather than a layer '
              'that stays.',
        ),
        'modal': FieldHint(label: 'Modal'),
        'transition': FieldHint(label: 'Transition'),
        'theme': FieldHint(label: 'Theme', fileExtensions: ['uitheme.json']),
        'sortOrder': FieldHint(label: 'Order'),
        'initialFocus': FieldHint(label: 'First focus'),
      },
    ),
    create: UiCanvasComponent.new,
    fields: [
      _d<UiCanvasComponent>(
        'designW',
        (c) => c.designSize.width,
        (c, v) => c.designSize = Size(v, c.designSize.height),
        min: 1,
      ),
      _d<UiCanvasComponent>(
        'designH',
        (c) => c.designSize.height,
        (c, v) => c.designSize = Size(c.designSize.width, v),
        min: 1,
      ),
      SchemaField(
        name: 'scaleMode',
        kind: const EnumFieldType(
          UiScaleMode.values,
          fallback: UiScaleMode.fit,
          id: 'enum.uiScaleMode',
        ),
        read: (c) => (c as UiCanvasComponent).scaleMode,
        write: (c, v) => (c as UiCanvasComponent).scaleMode = v as UiScaleMode,
      ),
      _b<UiCanvasComponent>(
        'safeArea',
        (c) => c.safeArea,
        (c, v) => c.safeArea = v,
      ),
      _b<UiCanvasComponent>(
        'visible',
        (c) => c.visible,
        (c, v) => c.visible = v,
      ),
      _b<UiCanvasComponent>(
        'isScreen',
        (c) => c.isScreen,
        (c, v) => c.isScreen = v,
      ),
      _b<UiCanvasComponent>('modal', (c) => c.modal, (c, v) => c.modal = v),
      SchemaField(
        name: 'transition',
        kind: const EnumFieldType(
          UiTransition.values,
          fallback: UiTransition.fade,
          id: 'enum.uiTransition',
        ),
        read: (c) => (c as UiCanvasComponent).transition,
        write: (c, v) =>
            (c as UiCanvasComponent).transition = v as UiTransition,
      ),
      _s<UiCanvasComponent>(
        'theme',
        (c) => c.theme,
        (c, v) => c.theme = v,
        kind: FieldTypes.assetRef,
      ),
      _i<UiCanvasComponent>(
        'sortOrder',
        (c) => c.sortOrder,
        (c, v) => c.sortOrder = v,
      ),
      _s<UiCanvasComponent>(
        'initialFocus',
        (c) => c.initialFocus,
        (c, v) => c.initialFocus = v,
        kind: FieldTypes.entityRef,
      ),
    ],
  );

  // ── How a child sits ────────────────────────────────────────────────────

  static final slot = ComponentDefinition<UiSlotComponent>(
    type: 'UiSlotComponent',
    hints: const ComponentHints(
      name: 'UI Slot',
      group: _group,
      description: 'Where this sits in its parent.',
      icon: Icons.control_camera,
      accentColor: _accent,
      fieldGroups: {
        'Placing': ['mode', 'anchor', 'pivotX', 'pivotY'],
        'Box': ['offsetX', 'offsetY', 'w', 'h', 'margin'],
        'In a row or column': ['flex', 'alignSelf'],
        'Appearance': ['opacity', 'visible', 'ignorePointer', 'heroTag'],
      },
      fieldRows: [
        FieldRowHint('Offset', {'offsetX': 'X', 'offsetY': 'Y'}),
        FieldRowHint('Size', {'w': 'W', 'h': 'H'}),
        FieldRowHint('Pivot', {'pivotX': 'X', 'pivotY': 'Y'}),
      ],
      fields: {
        'mode': FieldHint(label: 'Mode'),
        'anchor': FieldHint(
          label: 'Anchor',
          description: 'Where in the parent this is pinned.',
        ),
        'offsetX': FieldHint(label: 'X'),
        'offsetY': FieldHint(label: 'Y'),
        'w': FieldHint(label: 'Width'),
        'h': FieldHint(label: 'Height'),
        'pivotX': FieldHint(label: 'Pivot X'),
        'pivotY': FieldHint(label: 'Pivot Y'),
        'margin': FieldHint(label: 'Margin'),
        'flex': FieldHint(
          label: 'Flex',
          description: '0 takes what it needs; more shares what is left.',
        ),
        'alignSelf': FieldHint(label: 'Align self'),
        'opacity': FieldHint(label: 'Opacity'),
        'visible': FieldHint(label: 'Visible'),
        'ignorePointer': FieldHint(label: 'Click through'),
        'heroTag': FieldHint(
          label: 'Hero tag',
          description: 'Matched between screens to fly from one to the other.',
        ),
      },
    ),
    create: UiSlotComponent.new,
    fields: [
      SchemaField(
        name: 'mode',
        kind: const EnumFieldType(
          UiSlotMode.values,
          fallback: UiSlotMode.flow,
          id: 'enum.uiSlotMode',
        ),
        read: (c) => (c as UiSlotComponent).mode,
        write: (c, v) => (c as UiSlotComponent).mode = v as UiSlotMode,
      ),
      SchemaField(
        name: 'anchor',
        kind: FieldTypes.uiAnchor,
        read: (c) => (c as UiSlotComponent).anchor,
        write: (c, v) => (c as UiSlotComponent).anchor = v is UiAnchor
            ? v
            : UiAnchor.topLeft,
      ),
      _d<UiSlotComponent>(
        'pivotX',
        (c) => c.pivot.dx,
        (c, v) => c.pivot = Offset(v, c.pivot.dy),
      ),
      _d<UiSlotComponent>(
        'pivotY',
        (c) => c.pivot.dy,
        (c, v) => c.pivot = Offset(c.pivot.dx, v),
      ),
      _d<UiSlotComponent>(
        'offsetX',
        (c) => c.offset.dx,
        (c, v) => c.offset = Offset(v, c.offset.dy),
      ),
      _d<UiSlotComponent>(
        'offsetY',
        (c) => c.offset.dy,
        (c, v) => c.offset = Offset(c.offset.dx, v),
      ),
      _d<UiSlotComponent>(
        'w',
        (c) => c.size.width,
        (c, v) => c.size = Size(v, c.size.height),
        min: 0,
      ),
      _d<UiSlotComponent>(
        'h',
        (c) => c.size.height,
        (c, v) => c.size = Size(c.size.width, v),
        min: 0,
      ),
      _insets<UiSlotComponent>(
        'margin',
        (c) => c.margin,
        (c, v) => c.margin = v,
      ),
      _i<UiSlotComponent>('flex', (c) => c.flex, (c, v) => c.flex = v, min: 0),
      _s<UiSlotComponent>(
        'alignSelf',
        (c) => c.alignSelf,
        (c, v) => c.alignSelf = v,
      ),
      _d<UiSlotComponent>(
        'opacity',
        (c) => c.opacity,
        (c, v) => c.opacity = v,
        min: 0,
        max: 1,
      ),
      _b<UiSlotComponent>('visible', (c) => c.visible, (c, v) => c.visible = v),
      _b<UiSlotComponent>(
        'ignorePointer',
        (c) => c.ignorePointer,
        (c, v) => c.ignorePointer = v,
      ),
      _s<UiSlotComponent>('heroTag', (c) => c.heroTag, (c, v) => c.heroTag = v),
    ],
  );

  // ── Containers and the rest ─────────────────────────────────────────────

  static final layout = ComponentDefinition<UiLayoutComponent>(
    type: 'UiLayoutComponent',
    hints: const ComponentHints(
      name: 'UI Layout',
      group: _group,
      description: 'Lays the entities under this one out.',
      icon: Icons.view_column,
      accentColor: _accent,
      fieldGroups: {
        'Kind': ['kind', 'columns'],
        'Alignment': ['mainAxis', 'crossAxis', 'spacing', 'tight'],
        'Space': ['padding'],
      },
      fields: {
        'kind': FieldHint(label: 'Kind'),
        'mainAxis': FieldHint(label: 'Along'),
        'crossAxis': FieldHint(label: 'Across'),
        'spacing': FieldHint(label: 'Gap'),
        'padding': FieldHint(label: 'Padding'),
        'columns': FieldHint(label: 'Columns'),
        'tight': FieldHint(
          label: 'Hug contents',
          description: 'Take only the room the children need.',
        ),
      },
    ),
    create: UiLayoutComponent.new,
    fields: [
      SchemaField(
        name: 'kind',
        kind: const EnumFieldType(
          UiLayoutKind.values,
          fallback: UiLayoutKind.column,
          id: 'enum.uiLayoutKind',
        ),
        read: (c) => (c as UiLayoutComponent).kind,
        write: (c, v) => (c as UiLayoutComponent).kind = v as UiLayoutKind,
      ),
      SchemaField(
        name: 'mainAxis',
        kind: const EnumFieldType(
          UiAlign.values,
          fallback: UiAlign.start,
          id: 'enum.uiAlign',
        ),
        read: (c) => (c as UiLayoutComponent).mainAxis,
        write: (c, v) => (c as UiLayoutComponent).mainAxis = v as UiAlign,
      ),
      SchemaField(
        name: 'crossAxis',
        kind: const EnumFieldType(
          UiAlign.values,
          fallback: UiAlign.center,
          id: 'enum.uiAlign',
        ),
        read: (c) => (c as UiLayoutComponent).crossAxis,
        write: (c, v) => (c as UiLayoutComponent).crossAxis = v as UiAlign,
      ),
      _d<UiLayoutComponent>(
        'spacing',
        (c) => c.spacing,
        (c, v) => c.spacing = v,
        min: 0,
      ),
      _insets<UiLayoutComponent>(
        'padding',
        (c) => c.padding,
        (c, v) => c.padding = v,
      ),
      _i<UiLayoutComponent>(
        'columns',
        (c) => c.columns,
        (c, v) => c.columns = v,
        min: 1,
      ),
      _b<UiLayoutComponent>('tight', (c) => c.tight, (c, v) => c.tight = v),
    ],
  );

  static final panel = ComponentDefinition<UiPanelComponent>(
    type: 'UiPanelComponent',
    hints: const ComponentHints(
      name: 'UI Panel',
      group: _group,
      description: 'A background behind this element and its children.',
      icon: Icons.rectangle_outlined,
      accentColor: _accent,
      fieldGroups: {
        'Fill': ['colorRole', 'color', 'image'],
        'Edge': ['borderColor', 'borderWidth', 'radius'],
        'Depth': ['shadowBlur', 'blur'],
        'Nine-slice': ['nineSlice'],
      },
      fields: {
        'colorRole': FieldHint(
          label: 'Colour role',
          description:
              'A colour from the theme. The Colour below overrides it; '
              'clear that and this decides.',
        ),
        'color': FieldHint(label: 'Colour'),
        'image': FieldHint(
          label: 'Image',
          fileExtensions: ['png', 'jpg', 'jpeg', 'webp'],
        ),
        'borderColor': FieldHint(label: 'Border'),
        'borderWidth': FieldHint(label: 'Border width'),
        'radius': FieldHint(label: 'Corner'),
        'shadowBlur': FieldHint(label: 'Shadow'),
        'blur': FieldHint(label: 'Frost'),
        'nineSlice': FieldHint(
          label: 'Slices',
          description: 'Which parts of the image stretch.',
        ),
      },
    ),
    create: UiPanelComponent.new,
    fields: [
      _s<UiPanelComponent>(
        'colorRole',
        (c) => c.colorRole,
        (c, v) => c.colorRole = v,
        kind: FieldTypes.uiColorRole,
      ),
      _color<UiPanelComponent>('color', (c) => c.color, (c, v) => c.color = v),
      _color<UiPanelComponent>(
        'borderColor',
        (c) => c.borderColor,
        (c, v) => c.borderColor = v,
      ),
      _d<UiPanelComponent>(
        'borderWidth',
        (c) => c.borderWidth,
        (c, v) => c.borderWidth = v,
        min: 0,
      ),
      _d<UiPanelComponent>(
        'radius',
        (c) => c.radius,
        (c, v) => c.radius = v,
        min: 0,
      ),
      _d<UiPanelComponent>(
        'shadowBlur',
        (c) => c.shadowBlur,
        (c, v) => c.shadowBlur = v,
        min: 0,
      ),
      _d<UiPanelComponent>('blur', (c) => c.blur, (c, v) => c.blur = v, min: 0),
      _s<UiPanelComponent>(
        'image',
        (c) => c.image,
        (c, v) => c.image = v,
        kind: FieldTypes.assetRef,
      ),
      _insets<UiPanelComponent>(
        'nineSlice',
        (c) => c.nineSlice,
        (c, v) => c.nineSlice = v,
      ),
    ],
  );

  static final image = ComponentDefinition<UiImageComponent>(
    type: 'UiImageComponent',
    hints: const ComponentHints(
      name: 'UI Image',
      group: _group,
      description: 'A picture in the interface.',
      icon: Icons.image_outlined,
      accentColor: _accent,
      fields: {
        'path': FieldHint(
          label: 'Image',
          fileExtensions: ['png', 'jpg', 'jpeg', 'webp'],
        ),
        'atlasRegion': FieldHint(label: 'Region'),
        'fit': FieldHint(label: 'Fit'),
        'tint': FieldHint(label: 'Tint'),
        'opacity': FieldHint(label: 'Opacity'),
      },
    ),
    create: UiImageComponent.new,
    fields: [
      _s<UiImageComponent>(
        'path',
        (c) => c.path,
        (c, v) => c.path = v,
        kind: FieldTypes.assetRef,
      ),
      _s<UiImageComponent>(
        'atlasRegion',
        (c) => c.atlasRegion,
        (c, v) => c.atlasRegion = v,
      ),
      SchemaField(
        name: 'fit',
        kind: const EnumFieldType(
          BoxFit.values,
          fallback: BoxFit.contain,
          id: 'enum.boxFit',
        ),
        read: (c) => (c as UiImageComponent).fit,
        write: (c, v) => (c as UiImageComponent).fit = v as BoxFit,
      ),
      _color<UiImageComponent>('tint', (c) => c.tint, (c, v) => c.tint = v),
      _d<UiImageComponent>(
        'opacity',
        (c) => c.opacity,
        (c, v) => c.opacity = v,
        min: 0,
        max: 1,
      ),
    ],
  );

  static final progress = ComponentDefinition<UiProgressComponent>(
    type: 'UiProgressComponent',
    hints: const ComponentHints(
      name: 'UI Progress',
      group: _group,
      description: 'A bar or ring that fills — health, loading, a timer.',
      icon: Icons.linear_scale,
      accentColor: _accent,
      fieldGroups: {
        'Value': ['value', 'binding', 'maxBinding'],
        'Look': [
          'colorRole',
          'color',
          'trackColor',
          'radius',
          'radial',
          'thickness',
        ],
      },
      fields: {
        'value': FieldHint(label: 'Value'),
        'binding': FieldHint(
          label: 'Reads',
          description: 'A game value to follow instead — "health".',
        ),
        'maxBinding': FieldHint(label: 'Out of'),
        'colorRole': FieldHint(
          label: 'Colour role',
          description:
              'A colour from the theme. The Colour below overrides it; '
              'clear that and this decides.',
        ),
        'color': FieldHint(label: 'Colour'),
        'trackColor': FieldHint(label: 'Track'),
        'radius': FieldHint(label: 'Corner'),
        'radial': FieldHint(label: 'Ring'),
        'thickness': FieldHint(label: 'Thickness'),
      },
    ),
    create: UiProgressComponent.new,
    fields: [
      _d<UiProgressComponent>(
        'value',
        (c) => c.value,
        (c, v) => c.value = v,
        min: 0,
        max: 1,
      ),
      _s<UiProgressComponent>(
        'binding',
        (c) => c.binding,
        (c, v) => c.binding = v,
      ),
      _s<UiProgressComponent>(
        'maxBinding',
        (c) => c.maxBinding,
        (c, v) => c.maxBinding = v,
      ),
      _s<UiProgressComponent>(
        'colorRole',
        (c) => c.colorRole,
        (c, v) => c.colorRole = v,
        kind: FieldTypes.uiColorRole,
      ),
      _color<UiProgressComponent>(
        'color',
        (c) => c.color,
        (c, v) => c.color = v,
      ),
      _color<UiProgressComponent>(
        'trackColor',
        (c) => c.trackColor,
        (c, v) => c.trackColor = v,
      ),
      _d<UiProgressComponent>(
        'radius',
        (c) => c.radius,
        (c, v) => c.radius = v,
        min: 0,
      ),
      _b<UiProgressComponent>(
        'radial',
        (c) => c.radial,
        (c, v) => c.radial = v,
      ),
      _d<UiProgressComponent>(
        'thickness',
        (c) => c.thickness,
        (c, v) => c.thickness = v,
        min: 1,
      ),
    ],
  );

  static final toggle = ComponentDefinition<UiToggleComponent>(
    type: 'UiToggleComponent',
    hints: const ComponentHints(
      name: 'UI Toggle',
      group: _group,
      icon: Icons.toggle_on_outlined,
      accentColor: _accent,
      fields: {
        'value': FieldHint(label: 'On'),
        'label': FieldHint(label: 'Label'),
        'binding': FieldHint(label: 'Reads'),
        'onChanged': FieldHint(label: 'On change'),
      },
    ),
    create: UiToggleComponent.new,
    fields: [
      _b<UiToggleComponent>('value', (c) => c.value, (c, v) => c.value = v),
      _s<UiToggleComponent>(
        'label',
        (c) => c.label,
        (c, v) => c.label = v,
        kind: FieldTypes.uiText,
      ),
      _s<UiToggleComponent>(
        'binding',
        (c) => c.binding,
        (c, v) => c.binding = v,
      ),
      _actions<UiToggleComponent>(
        'onChanged',
        (c) => c.onChanged,
        (c, v) => c.onChanged = v,
      ),
    ],
  );

  static final slider = ComponentDefinition<UiSliderComponent>(
    type: 'UiSliderComponent',
    hints: const ComponentHints(
      name: 'UI Slider',
      group: _group,
      icon: Icons.tune,
      accentColor: _accent,
      fields: {
        'value': FieldHint(label: 'Value'),
        'min': FieldHint(label: 'Least'),
        'max': FieldHint(label: 'Most'),
        'steps': FieldHint(label: 'Notches'),
        'label': FieldHint(label: 'Label'),
        'binding': FieldHint(label: 'Reads'),
        'onChanged': FieldHint(label: 'On change'),
      },
    ),
    create: UiSliderComponent.new,
    fields: [
      _d<UiSliderComponent>('value', (c) => c.value, (c, v) => c.value = v),
      _d<UiSliderComponent>('min', (c) => c.min, (c, v) => c.min = v),
      _d<UiSliderComponent>('max', (c) => c.max, (c, v) => c.max = v),
      _i<UiSliderComponent>(
        'steps',
        (c) => c.steps,
        (c, v) => c.steps = v,
        min: 0,
      ),
      _s<UiSliderComponent>(
        'label',
        (c) => c.label,
        (c, v) => c.label = v,
        kind: FieldTypes.uiText,
      ),
      _s<UiSliderComponent>(
        'binding',
        (c) => c.binding,
        (c, v) => c.binding = v,
      ),
      _actions<UiSliderComponent>(
        'onChanged',
        (c) => c.onChanged,
        (c, v) => c.onChanged = v,
      ),
    ],
  );

  static final textField = ComponentDefinition<UiTextFieldComponent>(
    type: 'UiTextFieldComponent',
    hints: const ComponentHints(
      name: 'UI Text Field',
      group: _group,
      description: 'A real text field, with the platform’s keyboard.',
      icon: Icons.keyboard_alt_outlined,
      accentColor: _accent,
      fields: {
        'value': FieldHint(label: 'Text'),
        'hint': FieldHint(label: 'Hint'),
        'maxLength': FieldHint(label: 'Max length'),
        'obscure': FieldHint(label: 'Hide typing'),
        'onSubmitted': FieldHint(label: 'On submit'),
        'onChanged': FieldHint(label: 'On change'),
      },
    ),
    create: UiTextFieldComponent.new,
    fields: [
      _s<UiTextFieldComponent>('value', (c) => c.value, (c, v) => c.value = v),
      _s<UiTextFieldComponent>(
        'hint',
        (c) => c.hint,
        (c, v) => c.hint = v,
        kind: FieldTypes.uiText,
      ),
      _i<UiTextFieldComponent>(
        'maxLength',
        (c) => c.maxLength,
        (c, v) => c.maxLength = v,
        min: 0,
      ),
      _b<UiTextFieldComponent>(
        'obscure',
        (c) => c.obscure,
        (c, v) => c.obscure = v,
      ),
      _actions<UiTextFieldComponent>(
        'onSubmitted',
        (c) => c.onSubmitted,
        (c, v) => c.onSubmitted = v,
      ),
      _actions<UiTextFieldComponent>(
        'onChanged',
        (c) => c.onChanged,
        (c, v) => c.onChanged = v,
      ),
    ],
  );

  static final dropdown = ComponentDefinition<UiDropdownComponent>(
    type: 'UiDropdownComponent',
    hints: const ComponentHints(
      name: 'UI Dropdown',
      group: _group,
      icon: Icons.arrow_drop_down_circle_outlined,
      accentColor: _accent,
      fields: {
        'value': FieldHint(label: 'Chosen'),
        'options': FieldHint(label: 'Choices'),
        'label': FieldHint(label: 'Label'),
        'onChanged': FieldHint(label: 'On change'),
      },
    ),
    create: UiDropdownComponent.new,
    fields: [
      _s<UiDropdownComponent>('value', (c) => c.value, (c, v) => c.value = v),
      SchemaField(
        name: 'options',
        kind: FieldTypes.list,
        read: (c) => (c as UiDropdownComponent).options,
        write: (c, v) {
          final d = c as UiDropdownComponent;
          d.options
            ..clear()
            ..addAll([
              if (v is List)
                for (final o in v) '$o',
            ]);
        },
      ),
      _s<UiDropdownComponent>(
        'label',
        (c) => c.label,
        (c, v) => c.label = v,
        kind: FieldTypes.uiText,
      ),
      _actions<UiDropdownComponent>(
        'onChanged',
        (c) => c.onChanged,
        (c, v) => c.onChanged = v,
      ),
    ],
  );

  static final custom = ComponentDefinition<UiCustomComponent>(
    type: 'UiCustomComponent',
    hints: const ComponentHints(
      name: 'UI Custom',
      group: _group,
      description:
          'A widget this game registered. Anything Flutter can do, a scene '
          'can hold.',
      icon: Icons.extension_outlined,
      accentColor: _accent,
      fields: {
        'widgetId': FieldHint(label: 'Widget'),
        'props': FieldHint(label: 'Properties'),
      },
    ),
    create: UiCustomComponent.new,
    fields: [
      _s<UiCustomComponent>(
        'widgetId',
        (c) => c.widgetId,
        (c, v) => c.widgetId = v,
      ),
      SchemaField(
        name: 'props',
        kind: FieldTypes.map,
        read: (c) => (c as UiCustomComponent).props,
        write: (c, v) {
          final custom = c as UiCustomComponent;
          custom.props
            ..clear()
            ..addAll({
              if (v is Map)
                for (final e in v.entries) '${e.key}': '${e.value}',
            });
        },
      ),
    ],
  );

  static final spacer = ComponentDefinition<UiSpacerComponent>(
    type: 'UiSpacerComponent',
    hints: const ComponentHints(
      name: 'UI Spacer',
      group: _group,
      description: 'Empty room in a row or a column.',
      icon: Icons.space_bar,
      accentColor: _accent,
      fields: {
        'size': FieldHint(label: 'Size'),
        'expand': FieldHint(label: 'Take what is left'),
      },
    ),
    create: UiSpacerComponent.new,
    fields: [
      _d<UiSpacerComponent>(
        'size',
        (c) => c.size,
        (c, v) => c.size = v,
        min: 0,
      ),
      _b<UiSpacerComponent>('expand', (c) => c.expand, (c, v) => c.expand = v),
    ],
  );

  static List<ComponentDefinition> get all => [
    canvas,
    slot,
    layout,
    panel,
    image,
    progress,
    toggle,
    slider,
    textField,
    dropdown,
    custom,
    spacer,
  ];
}

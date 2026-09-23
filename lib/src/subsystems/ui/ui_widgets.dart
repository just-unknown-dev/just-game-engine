/// What a UI entity becomes on screen, and how a game adds its own.
///
/// Every element is built through this registry, built-ins included, so a
/// widget a game writes is placed, saved and edited exactly like one that
/// came with the engine:
///
/// ```dart
/// UiWidgets.register(UiWidgetDefinition(
///   id: 'inventory_grid',
///   label: 'Inventory',
///   build: (context) => InventoryGrid(columns: context.number('columns') ?? 4),
///   props: [UiWidgetProp('columns', 'Columns', UiPropKind.number)],
/// ));
/// ```
library;

import 'package:flutter/widgets.dart';

import '../../ecs/components/components.dart';
import '../../ecs/ecs.dart';
import 'ui_actions.dart';
import 'ui_bindings.dart';
import 'ui_theme.dart';

/// What kind of value a custom widget's property holds, so the inspector
/// can offer the right control.
enum UiPropKind { text, number, flag, color, asset }

/// One thing a custom widget lets the scene set.
class UiWidgetProp {
  const UiWidgetProp(
    this.name,
    this.label,
    this.kind, {
    this.defaultValue = '',
    this.description = '',
  });

  final String name;
  final String label;
  final UiPropKind kind;
  final String defaultValue;
  final String description;
}

/// What a widget is given when it is built.
class UiBuildContext {
  const UiBuildContext({
    required this.entity,
    required this.world,
    required this.theme,
    required this.children,
    this.props = const {},
    this.localise,
  });

  /// The entity this widget is.
  final Entity entity;
  final World world;

  /// The theme its canvas is drawn with.
  final UiTheme theme;

  /// What the entities under it became.
  final List<Widget> children;

  /// What the scene set on it, for a custom widget.
  final Map<String, String> props;

  /// How a `@key` becomes words.
  final String Function(String key)? localise;

  /// A property, with its bindings filled in.
  String text(String name) =>
      UiBindings.interpolate(props[name] ?? '', self: entity);

  double? number(String name) => double.tryParse(props[name] ?? '');

  bool flag(String name) => props[name] == 'true';

  /// Runs [actions] as if this entity had done it.
  void run(UiActionList actions, {Object? value}) =>
      actions.run(UiActionContext(world: world, entity: entity, value: value));

  /// The words behind a string that may be a key, a binding, or both.
  String resolve(String source) {
    var text = source;
    if (text.startsWith('@') && text.length > 1) {
      final key = text.substring(1);
      text = localise?.call(key) ?? key;
    }
    return UiBindings.interpolate(text, self: entity);
  }
}

/// How an entity becomes a widget.
typedef UiWidgetBuilder = Widget Function(UiBuildContext context);

/// A kind of UI element: what it is called, what it builds, what it lets a
/// scene set.
class UiWidgetDefinition {
  const UiWidgetDefinition({
    required this.id,
    required this.label,
    required this.build,
    this.props = const [],
    this.takesChildren = false,
    this.icon,
    this.description = '',
  });

  /// What a scene saves — `inventory_grid`.
  final String id;

  /// What the editor calls it in its menu.
  final String label;

  final UiWidgetBuilder build;

  /// What the inspector offers for it.
  final List<UiWidgetProp> props;

  /// Whether entities under it are built and handed over as children.
  final bool takesChildren;

  final IconData? icon;
  final String description;
}

abstract final class UiWidgets {
  static final Map<String, UiWidgetDefinition> _widgets = {};

  /// Makes [definition] placeable. Registering the same id again replaces
  /// it, so a game may override a built-in with its own.
  static void register(UiWidgetDefinition definition) =>
      _widgets[definition.id] = definition;

  static void registerAll(Iterable<UiWidgetDefinition> definitions) {
    for (final definition in definitions) {
      register(definition);
    }
  }

  static void unregister(String id) => _widgets.remove(id);

  static UiWidgetDefinition? of(String id) => _widgets[id];

  static bool has(String id) => _widgets.containsKey(id);

  /// Everything a game has offered, for the editor's menu.
  static List<UiWidgetDefinition> get all =>
      _widgets.values.toList()..sort((a, b) => a.label.compareTo(b.label));

  static void clear() => _widgets.clear();

  /// What [entity] builds, or null when nothing here knows how.
  static Widget? build(UiBuildContext context) {
    final custom = context.entity.getComponent<UiCustomComponent>();
    if (custom == null) return null;
    final definition = _widgets[custom.widgetId];
    if (definition == null) {
      // A scene naming a widget this game does not have: better an empty
      // space than a crash, and the Problems dock says which.
      return const SizedBox.shrink();
    }
    return definition.build(
      UiBuildContext(
        entity: context.entity,
        world: context.world,
        theme: context.theme,
        children: context.children,
        props: {
          for (final prop in definition.props)
            prop.name: custom.props[prop.name] ?? prop.defaultValue,
          ...custom.props,
        },
        localise: context.localise,
      ),
    );
  }
}

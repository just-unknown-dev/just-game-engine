import 'dart:collection' show UnmodifiableMapView;

import '../../../ecs/ecs.dart';

// Plain data with no GPU imports, so scenes that hold it load everywhere,
// the web included (where it simply draws nothing).

/// An entity's own values for the material files it is drawn with — its
/// shape's (`Primitive3DComponent.material`) or its model's
/// (`ModelComponent.materials`): a glow pulsing, a colour fading, a
/// texture sliding. By [key] from `Material3DFile.animatableKeys`, shaped as
/// a material file saves them (`color` an ARGB number, `tiling` `[x, y]`).
///
/// Change them with [set] and [remove] (or give [values] a new map), so the
/// renderer sees the change; values for a shape drawn with its own look,
/// without a material file, do nothing.
class MaterialOverrides3DComponent extends Component {
  /// Overrides holding [values].
  MaterialOverrides3DComponent({Map<String, Object>? values})
    : _values = {...?values};

  Map<String, Object> _values;
  UnmodifiableMapView<String, Object>? _view;
  int _revision = 0;

  /// The values, by key: a read-only view that follows [set] and [remove]
  /// (nothing is copied). Copy it to keep the values as they are now.
  Map<String, Object> get values => _view ??= UnmodifiableMapView(_values);

  set values(Map<String, Object> next) {
    _values = {...next};
    _view = null;
    _revision++;
  }

  /// Goes up with every change.
  int get revision => _revision;

  /// [key]'s value, or null when the material file's own shows.
  Object? operator [](String key) => _values[key];

  /// Draws with [value] for [key].
  void set(String key, Object value) {
    if (_values[key] == value) return;
    _values[key] = value;
    _revision++;
  }

  /// The material file's own value for [key] again.
  void remove(String key) {
    if (_values.remove(key) != null) _revision++;
  }
}

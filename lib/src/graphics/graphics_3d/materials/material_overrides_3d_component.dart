import '../../../ecs/ecs.dart';

// Plain data with no GPU imports, so scenes that hold it load everywhere,
// the web included (where it simply draws nothing).

/// An entity's own values for the material files it is drawn with — its
/// shape's (`Primitive3DComponent.material`) or its model's
/// (`ModelComponent.materials`): a glow pulsing, a colour fading, a
/// texture sliding. By [key] from `MaterialFile.animatableKeys`, shaped as
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
  int _revision = 0;

  /// The values, by key. Read-only: change them with [set] and [remove].
  Map<String, Object> get values => Map.unmodifiable(_values);

  set values(Map<String, Object> next) {
    _values = {...next};
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

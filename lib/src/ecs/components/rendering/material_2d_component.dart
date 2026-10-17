library;

import '../../ecs.dart';

/// Draws an entity's sprite through a 2-D material file
/// (`*.material2d.json`): an outline, a flash, a dissolve, a wave — the
/// effects the file switches on (`Material2DEffects`).
///
/// Every sprite sharing a material is drawn together, in one draw, in the
/// order the layers say. Until the file has been read — or where it cannot
/// be — the sprite is drawn as it is.
///
/// [overrides] are this entity's own values for what the game changes as it
/// runs — a hit flash, a dissolve as it dies — by key (`flash.amount`), in
/// the shape a material file saves them: a number, an ARGB colour, `[x, y]`.
/// Only values a game may change are used (`Material2DParam.animatable`);
/// change them with [set] and [remove] (or give [overrides] a new map), so
/// the renderer sees the change.
class Material2D extends Component {
  /// A material from the file at [material], with [overrides].
  Material2D({this.material = '', Map<String, Object>? overrides})
    : _overrides = {...?overrides};

  /// The 2-D material file, by project path. Empty draws without one.
  String material;

  Map<String, Object> _overrides;
  int _revision = 0;

  /// This entity's own values, by key. Read-only: change them with [set]
  /// and [remove].
  Map<String, Object> get overrides => Map.unmodifiable(_overrides);

  set overrides(Map<String, Object> next) {
    _overrides = {...next};
    _revision++;
  }

  /// Goes up with every change to [overrides].
  int get revision => _revision;

  /// [key]'s own value, or null when the material's shows.
  Object? operator [](String key) => _overrides[key];

  /// Draws with [value] for [key] (`effect.name`, as `flash.amount`).
  void set(String key, Object value) {
    if (_overrides[key] == value) return;
    _overrides[key] = value;
    _revision++;
  }

  /// The material's own value for [key] again.
  void remove(String key) {
    if (_overrides.remove(key) != null) _revision++;
  }
}

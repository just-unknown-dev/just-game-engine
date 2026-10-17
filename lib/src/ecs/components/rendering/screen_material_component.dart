library;

import '../../ecs.dart';

/// Draws the whole view through a 2-D material of the `screen` kind
/// (`*.material2d.json`): a vignette, a colour grade, scanlines, a CRT
/// bulge, big pixels — the effects the file switches on.
///
/// Put it on the camera, or on any entity: of those [enabled] on active
/// entities, the one with the highest [order] (the last found, on a tie) is
/// drawn. The game's drawing goes under it; an editor's gizmos and the
/// interface's widgets do not.
///
/// [overrides] are this entity's own values for what changes as the game
/// runs — a vignette closing in, the colour draining — by key
/// (`vignette.amount`), as a material file saves them. Change them with
/// [set] and [remove] (or give [overrides] a new map).
class ScreenMaterial extends Component {
  /// A screen material from the file at [material].
  ScreenMaterial({
    this.material = '',
    this.enabled = true,
    this.order = 0,
    Map<String, Object>? overrides,
  }) : _overrides = {...?overrides};

  /// The 2-D material file, by project path. Empty draws without one.
  String material;

  /// Whether it is drawn.
  bool enabled;

  /// Which wins when several are on: the highest.
  int order;

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

  /// Draws with [value] for [key] (`effect.name`, as `vignette.amount`).
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

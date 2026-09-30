/// Whether a scene — and a component, prefab or tool — is 2-D, 3-D or both.
library;

/// How a scene is authored.
///
/// Every entity has a 3-D transform either way; a 2-D scene is a 3-D scene
/// seen straight on by an orthographic camera. The mode only picks what an
/// editor shows and offers: its view, gizmos, tools and which fields and
/// axes appear. Saved in the scene file as `mode`.
enum SceneMode {
  /// Authored flat: x/y and a turn about Z. The default.
  twoD('2d'),

  /// Authored in space.
  threeD('3d');

  const SceneMode(this.id);

  /// How the mode is written in a scene file.
  final String id;

  /// The mode written as [id], or [twoD] for anything unknown or missing.
  static SceneMode fromId(Object? id) {
    for (final mode in values) {
      if (mode.id == id) return mode;
    }
    return twoD;
  }
}

/// Which scene modes something belongs in — a component, a field, a prefab,
/// a tool. An editor offers it only where it belongs.
///
/// Not called "depth": that already means draw order here.
enum Dimensions {
  /// 2-D scenes only — a tile map, a 2-D physics body.
  twoD,

  /// 3-D scenes only.
  threeD,

  /// Either.
  both;

  /// Whether this belongs in a scene authored as [mode].
  bool allows(SceneMode mode) => switch (this) {
    Dimensions.both => true,
    Dimensions.twoD => mode == SceneMode.twoD,
    Dimensions.threeD => mode == SceneMode.threeD,
  };
}

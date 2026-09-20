library;

import 'scene_migrations.dart';

/// The saved scene format's version, and how older files are brought up to
/// date.
///
/// A file without a `version` key is v0: the original format, where the
/// core components were stored flat (`{type, width, height, ...}`) and the
/// rest under `fields` with a `customComponentId`. v1 stores every component
/// as `{type, fields}`.
///
/// Migration happens in memory on every load — the engine's scene loader
/// and the editor's — and never rewrites a file by itself. A migrated scene
/// is written in the current format the next time it is saved.
abstract final class SceneFormat {
  /// The version this engine writes.
  static const int current = 2;

  /// The version [json] declares; 0 when it declares none.
  static int versionOf(Map<String, dynamic> json) =>
      (json['version'] as num?)?.toInt() ?? 0;

  /// [json] brought up to [current], applying each [SceneMigration] in turn.
  /// Returns the input unchanged if it is already current. Never mutates the
  /// input.
  static Map<String, dynamic> migrate(Map<String, dynamic> json) {
    var version = versionOf(json);
    if (version >= current) return json;
    var out = json;
    for (final step in SceneMigrations.chain) {
      if (step.from != version) continue;
      out = step.apply(_deepCopy(out));
      version = step.from + 1;
      out['version'] = version;
    }
    if (version != current) {
      throw StateError('No migration from scene format v$version to v$current');
    }
    return out;
  }

  // Typed as a JSON decoder would type them, so a migrated scene casts the
  // same way a freshly decoded one does.
  static Map<String, dynamic> _deepCopy(Map m) => <String, dynamic>{
    for (final e in m.entries) e.key as String: _copyValue(e.value),
  };

  static Object? _copyValue(Object? v) => switch (v) {
    Map() => _deepCopy(v),
    List() => <dynamic>[for (final x in v) _copyValue(x)],
    _ => v,
  };
}

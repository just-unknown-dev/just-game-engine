/// What a package adds to the format migrations, and what one migration
/// found.
library;

import '../../subsystems/timeline/timeline_format.dart';
import 'scene_migrations.dart';

/// Rewrites a component's `fields` map in place.
typedef FieldMigration = void Function(Map<String, dynamic> fields);

/// The rules a package adds to the scene and timeline migrations, on top of
/// the engine's own — its old component shapes brought forward.
///
/// Each engine has its own (`engine.context.migrations`), filled by the
/// packages' extensions as they are installed; the engine's scene loader and
/// timeline loader pass it to every migration. [none] adds nothing.
///
/// ```dart
/// context.migrations.perEntity(1).add((entity, scene) { ... });
/// context.migrations.perType(5)['KitComponent'] = (fields) { ... };
/// ```
final class MigrationHooks {
  /// Empty hooks to add to.
  MigrationHooks() : _frozen = false;

  MigrationHooks._frozen() : _frozen = true;

  /// No rules: only the engine's own migrations run. Cannot be added to.
  static final MigrationHooks none = MigrationHooks._frozen();

  final bool _frozen;
  final Map<String, ComponentMigration> _v0Components = {};
  final Map<int, List<EntityMigration>> _perEntity = {};
  final Map<int, Map<String, FieldMigration>> _perType = {};
  final Map<String, (String, String, String)> _targetPairs = {};
  final List<TrackMigration> _perTrack = [];

  /// v0 → v1: per component type, a rewrite of the component (already
  /// `{type, fields}`) — run instead of the engine's own rule for that type.
  Map<String, ComponentMigration> get v0Components =>
      _frozen ? const {} : _v0Components;

  /// Entity-level rules for the step from version [from] to [from] + 1
  /// (1 to 7): one component becoming several, or moving to another entity.
  /// Run after the engine's own.
  List<EntityMigration> perEntity(int from) {
    if (from < 1 || from >= 8) {
      throw RangeError.range(from, 1, 7, 'from', 'No such scene migration');
    }
    return _frozen ? const [] : _perEntity.putIfAbsent(from, () => []);
  }

  /// Per component type, a rewrite of its `fields` for the step from [from]
  /// (5, 6 or 7), run after the engine's own.
  Map<String, FieldMigration> perType(int from) {
    if (from < 5 || from > 7) {
      throw ArgumentError.value(from, 'from', 'Only steps 5 to 7 take these');
    }
    return _frozen ? const {} : _perType.putIfAbsent(from, () => {});
  }

  /// v6 → v7: component type → (name field, tag field, target field), for a
  /// package's own name-else-tag pairs; added to the engine's four.
  Map<String, (String, String, String)> get targetPairs =>
      _frozen ? const {} : _targetPairs;

  /// Timeline v1 → v2: track-level rules, run after the engine's own.
  List<TrackMigration> get perTrack => _frozen ? const [] : _perTrack;
}

/// Something one migration step noticed that a person may want to know.
final class MigrationNote {
  /// A note from the step that starts at [fromVersion].
  const MigrationNote(this.fromVersion, this.message);

  /// The step: from this version to the next.
  final int fromVersion;

  /// What was noticed, as a sentence for a person to read.
  final String message;

  @override
  String toString() => 'v$fromVersion→v${fromVersion + 1}: $message';
}

/// One migration in progress: the hooks it runs with and what it finds.
/// Handed to every step, so two migrations never share what they found.
final class MigrationRun {
  /// A run with [hooks] and nothing found yet.
  MigrationRun(this.hooks);

  /// The package rules this run applies on top of the engine's own.
  final MigrationHooks hooks;

  /// Entities whose old animated sprite had no atlas to point at (v2 → v3);
  /// their sheet needs exporting as an atlas before they animate again.
  final List<String> needsAtlas = [];

  /// What the steps noticed.
  final List<MigrationNote> notes = [];
}

/// A scene brought up to the current format, and what was found on the way.
final class MigrationResult {
  /// The migrated [scene], read at [fromVersion], and what the run found.
  const MigrationResult({
    required this.scene,
    required this.fromVersion,
    this.needsAtlas = const [],
    this.notes = const [],
  });

  /// The scene in the current format — the input itself when it already
  /// was.
  final Map<String, dynamic> scene;

  /// The version the input declared.
  final int fromVersion;

  /// Whether anything was migrated.
  bool get migrated => fromVersion != (scene['version'] as num?)?.toInt();

  /// See [MigrationRun.needsAtlas].
  final List<String> needsAtlas;

  /// See [MigrationRun.notes].
  final List<MigrationNote> notes;
}

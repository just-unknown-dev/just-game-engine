library;

import 'package:meta/meta.dart';

/// Whether an achievement requires a single action or cumulative progress.
enum AchievementType { boolean, progress }

/// A single achievement definition with mutable runtime state.
///
/// Immutable definition fields ([id], [name], [description], [type], [goal])
/// are set at construction time. Mutable state ([progress], [isUnlocked]) is
/// updated by [AchievementManager] and persisted across sessions.
class Achievement {
  final String id;
  final String name;
  final String description;
  final AchievementType type;

  /// Target value for [AchievementType.progress] achievements.
  /// Ignored for [AchievementType.boolean].
  final double goal;

  double _progress = 0.0;
  bool _isUnlocked = false;

  Achievement({
    required this.id,
    required this.name,
    required this.description,
    this.type = AchievementType.boolean,
    this.goal = 1.0,
  });

  bool get isUnlocked => _isUnlocked;
  double get progress => _progress;

  /// Completion percentage in [0.0, 100.0].
  double get percentComplete {
    if (_isUnlocked) return 100.0;
    if (type == AchievementType.boolean) return 0.0;
    return (_progress / goal * 100.0).clamp(0.0, 100.0);
  }

  /// Serializes mutable runtime state for persistence.
  /// Called by [AchievementManager] — not part of the public API.
  @internal
  Map<String, dynamic> toStateJson() => {
    'unlocked': _isUnlocked,
    if (type == AchievementType.progress) 'progress': _progress,
  };

  /// Restores mutable runtime state from a previously persisted snapshot.
  /// Called by [AchievementManager] — not part of the public API.
  @internal
  void applyState(Map<String, dynamic> json) {
    _isUnlocked = (json['unlocked'] as bool?) ?? false;
    _progress = (json['progress'] as num?)?.toDouble() ?? 0.0;
  }

  /// Sets the unlocked flag directly. Called by [AchievementManager].
  @internal
  set isUnlockedInternal(bool value) => _isUnlocked = value;

  /// Sets the progress value directly. Called by [AchievementManager].
  @internal
  set progressInternal(double value) => _progress = value;
}

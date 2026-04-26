library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:just_storage/just_storage.dart';

import '../../ecs/ecs.dart';
import 'achievement.dart';
import 'achievement_events.dart';
import 'achievement_provider.dart';

/// Manages achievement definitions, tracks progress, persists state,
/// and delegates to a platform [AchievementProvider].
///
/// Typical setup:
/// ```dart
/// // In game bootstrap — define achievements:
/// engine.achievements.define(Achievement(
///   id: 'first_win',
///   name: 'First Win',
///   description: 'Complete level 1.',
/// ));
///
/// // Register a platform provider:
/// engine.achievements.registerProvider(MyPlayGamesProvider());
///
/// // During gameplay:
/// engine.achievements.unlock('first_win');
/// engine.achievements.incrementProgress('total_coins', 5);
/// ```
class AchievementManager {
  static const String _kStateKey = 'jge_achievement_state';

  final Map<String, Achievement> _achievements = {};
  AchievementProvider _provider = NoOpAchievementProvider();
  JustStandardStorage? _storage;
  World? _world;

  // ── Setup ─────────────────────────────────────────────────────────────────

  /// Binds the ECS world so unlock/progress events are fired on its event bus.
  /// Called by [Engine] during subsystem initialization.
  void bindWorld(World world) => _world = world;

  /// Registers an achievement definition.
  ///
  /// Call before [AchievementManager] is initialized so persisted progress
  /// can be restored into the correct definition. Safe to call after
  /// initialization too — previously persisted state is applied immediately.
  void define(Achievement achievement) {
    _achievements[achievement.id] = achievement;
    if (_storage != null) {
      // Manager already initialized — restore any saved state right away.
      unawaited(_restoreOne(achievement));
    }
  }

  /// Replaces the current platform provider.
  ///
  /// The previous provider is disposed and the new one is initialized
  /// immediately. Safe to call at any point after engine initialization.
  void registerProvider(AchievementProvider provider) {
    unawaited(_provider.dispose());
    _provider = provider;
    unawaited(_provider.initialize());
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  Future<void> initialize() async {
    try {
      _storage = await JustStorage.standard();
      await _loadState();
    } catch (e) {
      debugPrint('AchievementManager: storage unavailable ($e)');
    }
    try {
      await _provider.initialize();
    } catch (e) {
      debugPrint('AchievementManager: provider init failed ($e)');
    }
  }

  void dispose() {
    unawaited(_provider.dispose());
  }

  // ── Progress API ──────────────────────────────────────────────────────────

  /// Unlocks a boolean achievement. No-op if already unlocked or not defined.
  void unlock(String id) {
    final a = _achievements[id];
    if (a == null || a.isUnlocked) return;

    a.isUnlockedInternal = true;
    _notifyUnlocked(a);
    unawaited(_save());
  }

  /// Adds [amount] to a progress achievement's counter.
  ///
  /// When the counter reaches [Achievement.goal] the achievement is
  /// automatically unlocked. No-op if already unlocked or not defined.
  void incrementProgress(String id, double amount) {
    final a = _achievements[id];
    if (a == null || a.isUnlocked) return;
    if (a.type != AchievementType.progress) return;

    a.progressInternal = (a.progress + amount).clamp(0.0, a.goal);
    _notifyProgress(a);
    if (a.progress >= a.goal) {
      a.isUnlockedInternal = true;
      _notifyUnlocked(a);
    }
    unawaited(_save());
  }

  /// Sets the absolute progress value for a progress achievement.
  ///
  /// Useful when syncing from an external source. No-op if already unlocked.
  void setProgress(String id, double value) {
    final a = _achievements[id];
    if (a == null || a.isUnlocked) return;
    if (a.type != AchievementType.progress) return;

    a.progressInternal = value.clamp(0.0, a.goal);
    _notifyProgress(a);
    if (a.progress >= a.goal) {
      a.isUnlockedInternal = true;
      _notifyUnlocked(a);
    }
    unawaited(_save());
  }

  // ── Query ─────────────────────────────────────────────────────────────────

  Achievement? getAchievement(String id) => _achievements[id];
  List<Achievement> get all => _achievements.values.toList();
  List<Achievement> get unlocked =>
      _achievements.values.where((a) => a.isUnlocked).toList();

  // ── Notification helpers ──────────────────────────────────────────────────

  void _notifyUnlocked(Achievement a) {
    debugPrint('Achievement unlocked: ${a.name}');
    unawaited(_provider.unlockAchievement(a.id));
    _world?.events.fire(AchievementUnlockedEvent(id: a.id, name: a.name));
  }

  void _notifyProgress(Achievement a) {
    unawaited(_provider.reportProgress(a.id, a.percentComplete));
    _world?.events.fire(
      AchievementProgressUpdatedEvent(
        id: a.id,
        percentComplete: a.percentComplete,
      ),
    );
  }

  // ── Persistence ───────────────────────────────────────────────────────────

  Future<void> _save() async {
    final storage = _storage;
    if (storage == null) return;
    try {
      final state = {
        for (final entry in _achievements.entries)
          entry.key: entry.value.toStateJson(),
      };
      await storage.write(_kStateKey, jsonEncode(state));
    } catch (e) {
      debugPrint('AchievementManager: save failed ($e)');
    }
  }

  Future<void> _loadState() async {
    final storage = _storage;
    if (storage == null) return;
    try {
      final raw = await storage.read(_kStateKey);
      if (raw == null) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      for (final entry in map.entries) {
        _achievements[entry.key]
            ?.applyState(entry.value as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('AchievementManager: load failed ($e)');
    }
  }

  Future<void> _restoreOne(Achievement achievement) async {
    final storage = _storage;
    if (storage == null) return;
    try {
      final raw = await storage.read(_kStateKey);
      if (raw == null) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final saved = map[achievement.id] as Map<String, dynamic>?;
      if (saved != null) achievement.applyState(saved);
    } catch (_) {}
  }
}

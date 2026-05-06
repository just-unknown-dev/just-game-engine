library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_database/just_database.dart';

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
  static const String _kTable = 'jge_achievements';

  final Map<String, Achievement> _achievements = {};
  AchievementProvider _provider = NoOpAchievementProvider();
  JustDatabase? _db;
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
    if (_db != null) {
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
      _db = await DatabaseManager.open('jge_engine', persist: true);
      await _db!.execute(
        'CREATE TABLE IF NOT EXISTS $_kTable '
        '(id TEXT PRIMARY KEY NOT NULL, '
        'unlocked INTEGER NOT NULL DEFAULT 0, '
        'progress REAL NOT NULL DEFAULT 0.0)',
      );
      await _loadState();
    } catch (e) {
      debugPrint('AchievementManager: database unavailable ($e)');
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
    _persist(a);
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
    _persist(a);
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
    _persist(a);
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

  /// Persists a single achievement. Null-safe — no-op when the DB is
  /// unavailable (e.g. initialization failed).
  void _persist(Achievement a) {
    final db = _db;
    if (db == null) return;
    unawaited(_saveOne(a, db));
  }

  Future<void> _saveOne(Achievement a, JustDatabase db) async {
    try {
      final id = _esc(a.id);
      final unlocked = a.isUnlocked ? 1 : 0;
      final progress = a.progress;
      final upd = await db.execute(
        'UPDATE $_kTable SET unlocked = $unlocked, progress = $progress '
        'WHERE id = $id',
      );
      if (upd.affectedRows == 0) {
        await db.execute(
          'INSERT INTO $_kTable (id, unlocked, progress) '
          'VALUES ($id, $unlocked, $progress)',
        );
      }
    } catch (e) {
      debugPrint('AchievementManager: save failed for ${a.id} ($e)');
    }
  }

  Future<void> _loadState() async {
    final db = _db;
    if (db == null) return;
    try {
      final result = await db.execute(
        'SELECT id, unlocked, progress FROM $_kTable',
      );
      for (final row in result.rows) {
        final id = row['id'] as String?;
        if (id == null) continue;
        _achievements[id]?.applyState({
          'unlocked': ((row['unlocked'] as num?)?.toInt() ?? 0) != 0,
          'progress': (row['progress'] as num?)?.toDouble() ?? 0.0,
        });
      }
    } catch (e) {
      debugPrint('AchievementManager: load failed ($e)');
    }
  }

  Future<void> _restoreOne(Achievement achievement) async {
    final db = _db;
    if (db == null) return;
    try {
      final id = _esc(achievement.id);
      final result = await db.execute(
        'SELECT unlocked, progress FROM $_kTable WHERE id = $id',
      );
      if (result.rows.isEmpty) return;
      final row = result.rows.first;
      achievement.applyState({
        'unlocked': ((row['unlocked'] as num?)?.toInt() ?? 0) != 0,
        'progress': (row['progress'] as num?)?.toDouble() ?? 0.0,
      });
    } catch (_) {}
  }

  /// Wraps [value] in single quotes, escaping any embedded quotes.
  static String _esc(String value) => "'${value.replaceAll("'", "''")}'";
}

library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../ecs/ecs.dart';
import 'leaderboard_definition.dart';
import 'leaderboard_entry.dart';
import 'leaderboard_events.dart';
import 'leaderboard_provider.dart';

/// Manages leaderboard definitions, submission, and platform delegation.
///
/// Typical setup:
/// ```dart
/// // Define leaderboards and register a provider after engine initialization:
/// engine.leaderboard.define(const LeaderboardDefinition(
///   id: 'high_score',
///   androidLeaderboardId: 'CgkI_your_android_id',
///   iosLeaderboardId: 'your_ios_id',
/// ));
/// engine.leaderboard.registerProvider(PlayGamesLeaderboardProvider());
///
/// // Submit a score during gameplay:
/// engine.leaderboard.submitScore('high_score', playerScore);
///
/// // Open the platform native leaderboard UI:
/// engine.leaderboard.showLeaderboard('high_score');
/// ```
class LeaderboardManager {
  final Map<String, LeaderboardDefinition> _leaderboards = {};
  LeaderboardProvider _provider = NoOpLeaderboardProvider();
  World? _world;

  // ── Setup ─────────────────────────────────────────────────────────────────

  /// Binds the ECS world so submission events are fired on its event bus.
  /// Called by [Engine] during subsystem initialization.
  void bindWorld(World world) => _world = world;

  /// Registers a leaderboard definition.
  ///
  /// Call before gameplay begins so the manager knows the platform-specific
  /// IDs to use when submitting or displaying the leaderboard.
  void define(LeaderboardDefinition leaderboard) {
    _leaderboards[leaderboard.id] = leaderboard;
  }

  /// Replaces the current platform provider.
  ///
  /// The previous provider is disposed and the new one is initialized
  /// immediately. Safe to call at any point after engine initialization.
  void registerProvider(LeaderboardProvider provider) {
    unawaited(_provider.dispose());
    _provider = provider;
    unawaited(_provider.initialize());
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  Future<void> initialize() async {
    try {
      await _provider.initialize();
    } catch (e) {
      debugPrint('LeaderboardManager: provider init failed ($e)');
    }
  }

  void dispose() {
    unawaited(_provider.dispose());
  }

  // ── Leaderboard API ───────────────────────────────────────────────────────

  /// Submits [score] to the leaderboard identified by [leaderboardId].
  ///
  /// No-op if [leaderboardId] has not been defined via [define].
  /// Fires [LeaderboardScoreSubmittedEvent] on success.
  Future<void> submitScore(String leaderboardId, int score) async {
    final def = _leaderboards[leaderboardId];
    if (def == null) {
      debugPrint('LeaderboardManager: unknown leaderboard "$leaderboardId"');
      return;
    }
    try {
      await _provider.submitScore(def, score);
      debugPrint('LeaderboardManager: submitted score $score to "$leaderboardId"');
      _world?.events.fire(
        LeaderboardScoreSubmittedEvent(leaderboardId: leaderboardId, score: score),
      );
    } catch (e) {
      debugPrint('LeaderboardManager: submitScore "$leaderboardId" failed ($e)');
    }
  }

  /// Returns the top [limit] entries for [leaderboardId].
  ///
  /// Returns an empty list if [leaderboardId] is not defined or the provider
  /// does not support programmatic reads.
  Future<List<LeaderboardEntry>> getTopScores(
    String leaderboardId, {
    int limit = 10,
  }) async {
    final def = _leaderboards[leaderboardId];
    if (def == null) {
      debugPrint('LeaderboardManager: unknown leaderboard "$leaderboardId"');
      return [];
    }
    try {
      return await _provider.getTopScores(def, limit: limit);
    } catch (e) {
      debugPrint('LeaderboardManager: getTopScores "$leaderboardId" failed ($e)');
      return [];
    }
  }

  /// Opens the platform's native leaderboard UI for [leaderboardId].
  ///
  /// No-op if [leaderboardId] has not been defined via [define].
  Future<void> showLeaderboard(String leaderboardId) async {
    final def = _leaderboards[leaderboardId];
    if (def == null) {
      debugPrint('LeaderboardManager: unknown leaderboard "$leaderboardId"');
      return;
    }
    try {
      await _provider.showLeaderboard(def);
    } catch (e) {
      debugPrint('LeaderboardManager: showLeaderboard "$leaderboardId" failed ($e)');
    }
  }

  // ── Query ─────────────────────────────────────────────────────────────────

  /// Returns the [LeaderboardDefinition] for [id], or `null` if not defined.
  LeaderboardDefinition? getDefinition(String id) => _leaderboards[id];

  /// All registered leaderboard definitions.
  List<LeaderboardDefinition> get all => _leaderboards.values.toList();
}

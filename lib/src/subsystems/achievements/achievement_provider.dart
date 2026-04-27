library;

/// Contract for platform achievement backends (Play Games, Game Center, Steam, etc.).
///
/// Implement this interface and pass an instance to
/// [AchievementManager.registerProvider] to connect achievements to a
/// platform service. The engine calls [unlockAchievement] and
/// [reportProgress] automatically when achievements change state.
abstract class AchievementProvider {
  Future<void> initialize();

  /// Called the first time a boolean achievement is unlocked.
  Future<void> unlockAchievement(String id);

  /// Called whenever a progress achievement advances.
  /// [percentComplete] is in the range [0.0, 100.0].
  Future<void> reportProgress(String id, double percentComplete);

  Future<void> dispose();
}

/// Default provider — persists achievements locally only, no platform calls.
///
/// Used when no platform provider has been registered, or in environments
/// where platform services are unavailable (desktop, test, web).
class NoOpAchievementProvider implements AchievementProvider {
  @override
  Future<void> initialize() async {}

  @override
  Future<void> unlockAchievement(String id) async {}

  @override
  Future<void> reportProgress(String id, double percentComplete) async {}

  @override
  Future<void> dispose() async {}
}

library;

import 'package:flutter/material.dart';
import 'package:just_debugger/just_debugger.dart';
import 'package:just_memory/just_memory.dart';

import '../core/engine.dart';

class EngineDebuggerPanel extends StatelessWidget {
  const EngineDebuggerPanel({super.key, required this.controller});

  final JustDebuggerController controller;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          TabBar(
            isScrollable: true,
            tabs: const [
              Tab(text: 'ECS'),
              Tab(text: 'Performance'),
              Tab(text: 'Memory'),
              Tab(text: 'Logs'),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: TabBarView(
              children: [
                EcsDebuggerPanel(controller: controller),
                PerformanceDebuggerPanel(controller: controller),
                MemoryDebuggerPanel(controller: controller),
                DebuggerLogConsole(controller: controller),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

extension JustGameEngineDebuggerIntegration on Engine {
  JustDebuggerController createDebuggerController({
    bool overlayVisible = true,
    Duration interval = const Duration(milliseconds: 250),
    EcsComponentUsageProvider? componentUsageProvider,
    EcsSystemTimesProvider? systemTimesProvider,
    PerformanceStatsProvider? performanceStatsProvider,
    MemoryStatsProvider? memoryStatsProvider,
    bool attachImmediately = true,
  }) {
    final controller = JustDebuggerController(overlayVisible: overlayVisible);

    if (attachImmediately) {
      attachDebugger(
        controller,
        interval: interval,
        componentUsageProvider: componentUsageProvider,
        systemTimesProvider: systemTimesProvider,
        performanceStatsProvider: performanceStatsProvider,
        memoryStatsProvider: memoryStatsProvider,
      );
    }

    return controller;
  }

  void attachDebugger(
    JustDebuggerController controller, {
    Duration interval = const Duration(milliseconds: 250),
    EcsComponentUsageProvider? componentUsageProvider,
    EcsSystemTimesProvider? systemTimesProvider,
    PerformanceStatsProvider? performanceStatsProvider,
    MemoryStatsProvider? memoryStatsProvider,
    bool fireImmediately = true,
  }) {
    controller.bindToSources(
      statsProvider: () {
        final worldStats = _safeWorldStats();
        final perfStats = _safePerformanceStats();
        return <String, dynamic>{
          ...worldStats,
          'frame': perfStats['frame'] ?? 0,
          'deltaTime': perfStats['deltaTime'] ?? 0.0,
          'engineLastUpdateMs': perfStats['lastUpdateMs'] ?? 0.0,
          'budgetRemainingMs': perfStats['budgetRemainingMs'] ?? 0.0,
          'isOverBudget': perfStats['isOverBudget'] ?? false,
        };
      },
      componentUsageProvider: componentUsageProvider ?? _componentUsageSummary,
      systemTimesProvider: systemTimesProvider ?? _mergedSystemTimes,
      performanceStatsProvider:
          performanceStatsProvider ??
          () => <String, dynamic>{
            ..._safePerformanceStats(),
            'currentFPS': gameLoop.currentFPS,
            'systemTimesMs': _mergedSystemTimes(),
          },
      memoryStatsProvider: memoryStatsProvider ?? _buildMemoryStats,
      memoryCleanupAction: () async {
        final cleanup = MemoryProfiler.cleanupGlobalResources(
          clearReleasedObjects: true,
        );

        try {
          await cache.clearAll();
        } catch (_) {}

        controller.log(
          'Released ${cleanup.releasedPools} pools and '
          '${cleanup.clearedArenas} arenas.',
          category: 'memory',
        );

        final stats = _buildMemoryStats();
        final counters = Map<String, int>.from(
          stats['counters'] as Map<String, int>? ?? const <String, int>{},
        );
        counters['releasedPools'] = cleanup.releasedPools;
        counters['clearedArenas'] = cleanup.clearedArenas;
        counters['clearedCaches'] = cleanup.clearedCaches + 1;
        stats['counters'] = counters;
        return stats;
      },
      interval: interval,
      fireImmediately: fireImmediately,
    );

    controller.log(
      'Just Debugger attached to Just Game Engine.',
      category: 'runtime',
    );
  }

  Map<String, dynamic> _safeWorldStats() {
    try {
      return Map<String, dynamic>.from(world.stats);
    } catch (_) {
      return const <String, dynamic>{};
    }
  }

  Map<String, dynamic> _safePerformanceStats() {
    try {
      return Map<String, dynamic>.from(performanceStats);
    } catch (_) {
      return const <String, dynamic>{};
    }
  }

  Map<String, int> _componentUsageSummary() {
    final usage = <String, int>{};

    try {
      for (final entity in world.activeEntities) {
        for (final component in entity.components) {
          final key = component.runtimeType.toString();
          usage[key] = (usage[key] ?? 0) + 1;
        }
      }
    } catch (_) {
      return const <String, int>{};
    }

    return usage;
  }

  Map<String, dynamic> _buildMemoryStats() {
    final worldStats = _safeWorldStats();
    final componentUsage = _componentUsageSummary();
    final systemMemory = MemoryProfiler.captureSystemMemory();

    return <String, dynamic>{
      'entityCount': worldStats['activeEntities'] ?? 0,
      'componentCount': componentUsage.values.fold<int>(
        0,
        (sum, value) => sum + value,
      ),
      'usingCacheFallback': cache.isUsingMemoryFallback,
      'cleanupAvailable': true,
      'totalPhysicalMemoryBytes': systemMemory.totalPhysicalMemoryBytes,
      'freePhysicalMemoryBytes': systemMemory.freePhysicalMemoryBytes,
      'rssBytes': systemMemory.rssBytes,
      'counters': <String, int>{
        'systems': (worldStats['systems'] as num?)?.toInt() ?? 0,
        'archetypes': (worldStats['archetypes'] as num?)?.toInt() ?? 0,
        'pools': _poolCount(),
        'arenas': _arenaCount(),
      },
    };
  }

  int _poolCount() {
    try {
      return PoolManager.instance.getPoolStats().length;
    } catch (_) {
      return 0;
    }
  }

  int _arenaCount() {
    try {
      return PoolManager.instance.getArenaStats().length;
    } catch (_) {
      return 0;
    }
  }

  Map<String, double> _mergedSystemTimes() {
    final worldTimes = _readDoubleMap(_safeWorldStats()['systemTimesMs']);
    final perfTimes = _readDoubleMap(_safePerformanceStats()['systemTimesMs']);
    return <String, double>{...perfTimes, ...worldTimes};
  }

  Map<String, double> _readDoubleMap(Object? source) {
    if (source is! Map) {
      return const <String, double>{};
    }

    final output = <String, double>{};
    source.forEach((key, value) {
      if (value is num) {
        output[key.toString()] = value.toDouble();
      }
    });
    return output;
  }
}

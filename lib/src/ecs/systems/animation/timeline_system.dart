library;

import 'dart:async';

import '../../../subsystems/timeline/timeline_asset.dart';
import '../../../subsystems/timeline/timeline_player.dart';
import '../../../subsystems/timeline/timeline_signals.dart';
import '../../components/animation/timeline_player_component.dart';
import '../../ecs.dart';
import '../system_priorities.dart';

class _Source {
  _Source(this.path, this.inline);

  final String path;
  final TimelineAsset? inline;
  bool failed = false;
  bool loading = false;
}

/// Runs every [TimelinePlayerComponent]: loads its timeline, plays it, and
/// says which events fired.
class TimelineSystem extends System {
  TimelineSystem({Future<TimelineAsset> Function(String path)? loader})
    : _loader = loader;

  final Future<TimelineAsset> Function(String path)? _loader;
  final Map<String, Future<TimelineAsset>> _assets = {};
  final Map<Entity, _Source> _sources = {};
  final StreamController<TimelineEventFired> _events =
      StreamController<TimelineEventFired>.broadcast(sync: true);

  StreamSubscription<String>? _signals;

  @override
  void onAddedToWorld() {
    super.onAddedToWorld();
    _signals ??= TimelineSignals.stream.listen(_onSignal);
  }

  // A signal starts every player listening for it, from the start.
  void _onSignal(String name) {
    if (!isActive) return;
    for (final entity in entities) {
      final player = entity.getComponent<TimelinePlayerComponent>()!;
      if (player.listenSignal == name && !player.suspended) player.restart();
    }
  }

  /// Every event any timeline fires.
  Stream<TimelineEventFired> get events => _events.stream;

  // Before the animator and the sprites, so a clip a timeline picks plays
  // the same frame; after movement, so a timeline has the last word on a
  // transform it animates.
  @override
  int get priority => SystemPriorities.animation + 2;

  @override
  List<Type> get requiredComponents => [TimelinePlayerComponent];

  /// The timeline [entity] is playing, once loaded.
  TimelineAsset? assetOf(Entity entity) =>
      entity.getComponent<TimelinePlayerComponent>()?.playback?.asset;

  /// Reads [path] again — it changed on disk. Players of it start over.
  /// Without a path, every timeline.
  void reload([String? path]) {
    if (path == null) {
      _assets.clear();
    } else {
      _assets.remove(path);
    }
    _sources.removeWhere((entity, source) {
      if (path != null && source.path != path) return false;
      entity.getComponent<TimelinePlayerComponent>()?.reset();
      return true;
    });
  }

  @override
  void update(double deltaTime) {
    final live = entities.toSet();
    _sources.removeWhere((e, _) => !live.contains(e));

    forEach((entity) {
      final player = entity.getComponent<TimelinePlayerComponent>()!;
      if (player.suspended) return;
      final path = player.timelinePath.trim();
      var source = _sources[entity];
      if (source == null ||
          source.path != path ||
          !identical(source.inline, player.inline) ||
          (player.playback == null && !source.failed && !source.loading)) {
        // Not reset(): what was asked of the player while it had no
        // timeline is still owed.
        player.playback?.dispose();
        player.playback = null;
        source = _sources[entity] = _Source(path, player.inline);
        if (path.isNotEmpty) {
          _load(entity, player, source);
        } else if (player.inline != null) {
          _start(entity, player, player.inline!);
        } else {
          source.failed = true;
        }
      }
      final playback = player.playback;
      if (playback == null) return;
      playback
        ..speed = player.speed
        ..wrap = player.wrap.wrap
        ..range = player.playRange
        ..update(deltaTime);
    });
  }

  void _load(Entity entity, TimelinePlayerComponent player, _Source source) {
    source.loading = true;
    final future = _read(source.path);
    future.then(
      (asset) {
        // The player may have moved on to another timeline while this one
        // was loading.
        source.loading = false;
        if (!identical(_sources[entity], source)) return;
        _start(entity, player, asset);
      },
      onError: (Object _) {
        // Remembered, so a missing file is not asked for every frame.
        source.loading = false;
        source.failed = true;
      },
    );
  }

  // One read per file, shared by every player and nested track that asks.
  Future<TimelineAsset> _read(String path) =>
      _assets.putIfAbsent(path, () => (_loader ?? TimelineAssets.loader)(path));

  void _start(
    Entity entity,
    TimelinePlayerComponent player,
    TimelineAsset asset,
  ) {
    final playback =
        TimelinePlayback(
            asset,
            world: world,
            owner: entity,
            onEvent: _events.add,
            loader: _read,
          )
          ..speed = player.speed
          ..range = player.playRange;
    player.playback = playback;
    if (!player.initialized) {
      player.initialized = true;
      if (player.playOnStart) playback.play();
    }
    player.flushPending();
  }

  @override
  void dispose() {
    for (final entity in _sources.keys) {
      entity.getComponent<TimelinePlayerComponent>()?.playback?.dispose();
    }
    _sources.clear();
    _signals?.cancel();
    _events.close();
    super.dispose();
  }
}

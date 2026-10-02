library;

import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

import '../../../subsystems/timeline/timeline_asset.dart';
import '../../../subsystems/timeline/timeline_player.dart';
import '../../components/animation/timeline_player_component.dart';
import '../../ecs.dart';
import '../../base/system_priorities.dart';

class _Source {
  _Source(this.player, this.path, this.inline);

  /// The component this source was made for — kept, so its playback can be
  /// ended even after the component or its entity is gone.
  final TimelinePlayerComponent player;
  final String path;
  final TimelineAsset? inline;
  bool failed = false;
  bool loading = false;
}

/// Runs every [TimelinePlayerComponent]: loads its timeline, plays it, and
/// says which events fired.
class TimelineSystem extends System {
  /// A system that reads each timeline with [loader] — the world context's
  /// `timelines` when null — once per path, shared by every player and
  /// nested track that names it.
  TimelineSystem({Future<TimelineAsset> Function(String path)? loader})
    : _loader = loader;

  final Future<TimelineAsset> Function(String path)? _loader;
  final Map<String, Future<TimelineAsset>> _assets = {};
  final Map<Entity, _Source> _sources = {};

  // Paths whose failure to load has been said.
  final Set<String> _reported = {};
  final StreamController<TimelineEventFired> _events =
      StreamController<TimelineEventFired>.broadcast(sync: true);

  StreamSubscription<String>? _signals;

  // The world's structure when [_sources] was last pruned.
  int _prunedAt = -1;

  @override
  void onAddedToWorld() {
    super.onAddedToWorld();
    // The engine's bus: a signal from any world on this context — a
    // button on an interface screen — starts players here.
    _signals ??= world.context.signals.stream.listen(_onSignal);
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
      _reported.clear();
    } else {
      _assets.remove(path);
      _reported.remove(path);
    }
    _sources.removeWhere((entity, source) {
      if (path != null && source.path != path) return false;
      source.player.reset();
      return true;
    });
  }

  @override
  void update(double deltaTime) {
    // Only a structural change can take a player away; a player whose
    // entity is merely switched off keeps its playback, and carries on
    // where it was when it is switched back on.
    if (world.structureVersion != _prunedAt) {
      _prunedAt = world.structureVersion;
      _prune();
    }

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
        source = _sources[entity] = _Source(player, path, player.inline);
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

  /// Ends the playback of every player whose entity was destroyed or which
  /// was taken off its entity (or replaced): what only lasts while a
  /// timeline runs — a camera shot's raised priority — is undone.
  void _prune() {
    _sources.removeWhere((entity, source) {
      if (entity.isAlive &&
          identical(
            entity.getComponent<TimelinePlayerComponent>(),
            source.player,
          )) {
        return false;
      }
      final player = source.player;
      player.playback?.dispose();
      player.playback = null;
      return true;
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
      onError: (Object error) {
        // Remembered, so a missing file is not asked for every frame — and
        // said once, so a player that never moves is not a mystery.
        source.loading = false;
        source.failed = true;
        if (_reported.add(source.path)) {
          debugPrint(
            'TimelineSystem: "${source.path}" could not be loaded; its '
            'players will not play. $error',
          );
        }
      },
    );
  }

  // One read per file, shared by every player and nested track that asks.
  Future<TimelineAsset> _read(String path) => _assets.putIfAbsent(
    path,
    () => (_loader ?? world.context.timelines)(path),
  );

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
    for (final source in _sources.values) {
      source.player.playback?.dispose();
    }
    _sources.clear();
    _signals?.cancel();
    _events.close();
    super.dispose();
  }
}

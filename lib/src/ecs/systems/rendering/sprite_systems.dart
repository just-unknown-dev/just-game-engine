library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show debugPrint;

import '../../../subsystems/rendering/impl/sprite.dart';
import '../../../subsystems/sprite_atlas/sprite_atlas.dart';
import '../../components/components.dart';
import '../../ecs.dart';
import '../../base/system_priorities.dart';

/// Shows a [SpriteComponent]: loads its image — or its region of an atlas —
/// into a [RenderableComponent], and keeps flip, tint and filtering current.
class SpriteLoadSystem extends System {
  /// A system loading through [loader]; the world's loader when null.
  SpriteLoadSystem({SpriteAssetLoader? loader}) : _loader = loader;

  final SpriteAssetLoader? _loader;

  /// The loader given, else the world's (`world.context.sprites`).
  SpriteAssetLoader get loader => _loader ?? world.context.sprites;

  final Map<Entity, _Shown> _shown = {};
  final Set<Entity> _loading = {};
  final Map<Entity, Sprite> _sprites = {};

  // What could not be shown, said once each.
  final Set<String> _reported = {};

  // The world's structure when the maps above were last pruned.
  int _prunedAt = -1;

  @override
  int get priority => SystemPriorities.animation - 1;

  @override
  List<Type> get requiredComponents => [TransformComponent, SpriteComponent];

  /// Loads everything again on the next frame: a file changed on disk.
  void reload() {
    _shown.clear();
    _reported.clear();
  }

  static String _keyOf(SpriteComponent c) =>
      '${c.spritePath.trim()}|${c.atlasPath.trim()}|${c.region.trim()}';

  @override
  void update(double deltaTime) {
    // Only a structural change can take a sprite away; one switched off
    // keeps what it showed.
    if (world.structureVersion != _prunedAt) {
      _prunedAt = world.structureVersion;
      bool gone(Entity e) =>
          !e.isAlive ||
          !e.hasComponent<SpriteComponent>() ||
          !e.hasComponent<TransformComponent>();
      _shown.removeWhere((e, _) => gone(e));
      _loading.removeWhere(gone);
      _sprites.removeWhere((e, _) => gone(e));
    }

    forEach((entity) {
      final c = entity.getComponent<SpriteComponent>()!;
      final sprite = _sprites[entity];
      if (sprite != null) {
        sprite
          ..flipX = c.flipX
          ..flipY = c.flipY
          ..tint = c.tint
          ..filterQuality = c.pixelArt
              ? ui.FilterQuality.none
              : ui.FilterQuality.medium;
      }
      if (_loading.contains(entity)) return;
      // The three paths as they were: nothing to build or compare beyond
      // them while they stay put.
      final shown = _shown[entity];
      if (shown != null && shown.matches(c)) return;
      final key = _keyOf(c);
      _shown[entity] = _Shown(c, key);
      if (shown?.key == key) return;

      if (c.spritePath.trim().isEmpty && c.atlasPath.trim().isEmpty) {
        if (_sprites.remove(entity) != null) {
          entity.removeComponent<RenderableComponent>();
        }
        return;
      }
      _loading.add(entity);
      _load(entity, key);
    });
  }

  Future<void> _load(Entity entity, String key) async {
    try {
      final asked = entity.getComponent<SpriteComponent>();
      if (asked == null) return;
      final Sprite sprite;
      final atlasPath = asked.atlasPath.trim();
      if (atlasPath.isNotEmpty) {
        final atlas = await loader.loadAtlas(atlasPath);
        final region = asked.region.trim().isEmpty
            ? atlas.regionNames.first
            : asked.region.trim();
        sprite = atlas.createSprite(region);
      } else {
        sprite = Sprite(image: await loader.loadImage(asked.spritePath.trim()));
      }

      // The entity may be gone, or asking for something else by now.
      final c = entity.getComponent<SpriteComponent>();
      if (c == null || _keyOf(c) != key) {
        _shown.remove(entity);
        return;
      }
      _sprites[entity] = sprite;
      final existing = entity.getComponent<RenderableComponent>();
      if (existing != null) {
        existing.renderable = sprite;
      } else {
        entity.addComponent(
          RenderableComponent(renderable: sprite, syncTransform: true),
        );
      }
    } catch (error) {
      // A wrong path stays remembered, so it is not tried again every
      // frame; correcting it changes the key, and that is tried. Said once,
      // so a sprite that never shows is not a mystery.
      if (_reported.add(key)) {
        debugPrint(
          'SpriteLoadSystem: could not show ${_describe(key)}: $error',
        );
      }
    } finally {
      _loading.remove(entity);
    }
  }

  /// "image.png", or "region r of atlas.json", from a [_keyOf] key.
  static String _describe(String key) {
    final parts = key.split('|');
    final atlas = parts.length > 1 ? parts[1] : '';
    if (atlas.isEmpty) return '"${parts[0]}"';
    final region = parts.length > 2 ? parts[2] : '';
    return region.isEmpty ? '"$atlas"' : 'region "$region" of "$atlas"';
  }
}

/// The paths a [SpriteComponent] had when its sprite was last worked out.
class _Shown {
  _Shown(SpriteComponent c, this.key)
    : sprite = c.spritePath,
      atlas = c.atlasPath,
      region = c.region;

  final String sprite;
  final String atlas;
  final String region;
  final String key;

  bool matches(SpriteComponent c) =>
      c.spritePath == sprite && c.atlasPath == atlas && c.region == region;
}

/// Something a playing sprite said: a frame event the artist placed, or
/// [SpriteAnimationSignal.completed] when a clip that does not loop ends.
class SpriteAnimationSignal {
  /// Signal [name] from [entity], playing [clip].
  const SpriteAnimationSignal(this.entity, this.clip, this.name);

  /// The [name] of the signal sent when a clip that does not loop ends.
  static const String completed = 'completed';

  /// The entity whose sprite sent it.
  final Entity entity;

  /// The clip playing when it was sent; empty when the component names no
  /// clip.
  final String clip;

  /// The frame event's name, as the artist placed it, or [completed].
  final String name;
}

class _Playing {
  _Playing(this.path);

  final String path;
  SpriteAtlas? atlas;
  AtlasRegionSprite? sprite;

  // Where this system left the clip last frame. A component that says
  // otherwise was switched or restarted since, and starts afresh.
  String? clip;
  double elapsed = double.nan;
}

/// Plays [SpriteAnimationComponent]s: loads the atlas, advances the clip by
/// each frame's own duration, shows the frame, and reports events.
///
/// A negative [SpriteAnimationComponent.speed] plays the clip backwards,
/// from its last frame. Frame events fire as time passes them either way —
/// one at the very start of a clip as it begins, one at its very end as a
/// clip played backwards begins.
class SpriteAnimationSystem extends System {
  /// A system loading atlases through [loader]; the world's loader when
  /// null.
  SpriteAnimationSystem({SpriteAssetLoader? loader}) : _loader = loader;

  final SpriteAssetLoader? _loader;

  /// The loader given, else the world's (`world.context.sprites`).
  SpriteAssetLoader get loader => _loader ?? world.context.sprites;

  final Map<Entity, _Playing> _playing = {};
  final Map<SpriteAtlas, AtlasAnimationClip> _everyFrame = {};
  final StreamController<SpriteAnimationSignal> _signals =
      StreamController<SpriteAnimationSignal>.broadcast(sync: true);

  // A clip's frame events, read from its atlas once rather than every
  // frame: by atlas, then clip name.
  Expando<Map<String, List<AnimationEvent>>> _events = Expando();

  // Atlases that could not be loaded, said once each.
  final Set<String> _reported = {};

  // The world's structure when [_playing] was last pruned.
  int _prunedAt = -1;

  /// Frame events and clip completions, as they happen.
  Stream<SpriteAnimationSignal> get signals => _signals.stream;

  // After whatever chooses the clip (an animator), before the renderer.
  @override
  int get priority => SystemPriorities.animation - 2;

  @override
  List<Type> get requiredComponents => [
    TransformComponent,
    SpriteAnimationComponent,
  ];

  /// The atlas [entity] is playing from, once loaded — for a tool that lists
  /// its clips.
  SpriteAtlas? atlasOf(Entity entity) => _playing[entity]?.atlas;

  /// Reads [atlasPath] again on the next frame — it changed on disk. With no
  /// path, everything.
  void reload([String? atlasPath]) {
    if (atlasPath != null) loader.evict(atlasPath);
    _playing.removeWhere((_, p) => atlasPath == null || p.path == atlasPath);
    _everyFrame.clear();
    _events = Expando();
    if (atlasPath == null) {
      _reported.clear();
    } else {
      _reported.remove(atlasPath);
    }
  }

  /// The clip [c] names, or every frame in order when it names none the
  /// atlas has.
  AtlasAnimationClip clipOf(SpriteAtlas atlas, SpriteAnimationComponent c) {
    final named = atlas.getClip(c.clip);
    if (named != null) return named;
    return _everyFrame[atlas] ??= AtlasAnimationClip(
      name: '',
      frames: [
        for (final name in atlas.regionNames)
          AtlasFrame(regionName: name, duration: 0.1),
      ],
    );
  }

  @override
  void update(double deltaTime) {
    // Only a structural change can take a player away; one switched off
    // keeps its atlas and carries on when it is switched back on.
    if (world.structureVersion != _prunedAt) {
      _prunedAt = world.structureVersion;
      _playing.removeWhere(
        (e, _) =>
            !e.isAlive ||
            !e.hasComponent<SpriteAnimationComponent>() ||
            !e.hasComponent<TransformComponent>(),
      );
    }

    forEach((entity) {
      final c = entity.getComponent<SpriteAnimationComponent>()!;
      final path = c.atlasPath.trim();
      var state = _playing[entity];
      if (state == null || state.path != path) {
        if (state?.sprite != null) {
          entity.removeComponent<RenderableComponent>();
        }
        state = _playing[entity] = _Playing(path);
        if (path.isNotEmpty) _load(entity, state);
      }
      final atlas = state.atlas;
      if (atlas == null) return;

      final clip = clipOf(atlas, c);
      if (clip.frames.isEmpty) return;
      if (!c.initialized) {
        c.initialized = true;
        if (c.playOnStart) c.isPlaying = true;
      }
      if (c.isPlaying && !c.isComplete) {
        _advance(entity, state, atlas, c, clip, deltaTime);
      }
      _show(entity, state, atlas, c, clip);
    });
  }

  Future<void> _load(Entity entity, _Playing state) async {
    try {
      final atlas = await loader.loadAtlas(state.path);
      if (_playing[entity] != state) return;
      state.atlas = atlas;
    } catch (error) {
      // Not tried again for this entity; said once per file.
      if (_reported.add(state.path)) {
        debugPrint(
          'SpriteAnimationSystem: the atlas "${state.path}" could not be '
          'loaded; sprites playing it stay hidden. $error',
        );
      }
    }
  }

  void _advance(
    Entity entity,
    _Playing state,
    SpriteAtlas atlas,
    SpriteAnimationComponent c,
    AtlasAnimationClip clip,
    double dt,
  ) {
    final total = clip.totalDuration;
    if (total <= 0) return;
    final loops = c.loopOverride ?? clip.loop;
    // Switched to, or restarted, since this system last moved it.
    final fresh = state.clip != c.clip || c.elapsed != state.elapsed;

    double now;
    if (c.speed >= 0) {
      final before = c.elapsed;
      // What sits on the very start happens as the clip begins.
      final starting = fresh && before <= 0;
      now = before + dt * c.speed;
      if (now >= total) {
        _fire(entity, atlas, c, before, total, fromStart: starting);
        if (loops) {
          now %= total;
          _fire(entity, atlas, c, 0, now, fromStart: true);
        } else {
          now = total;
          _complete(entity, c);
        }
      } else {
        _fire(entity, atlas, c, before, now, fromStart: starting);
      }
    } else {
      // Backwards a clip starts at its end, and 0 is where it stops — or
      // wraps round to the end again.
      final starting = fresh && c.elapsed <= 0;
      final before = starting ? total : c.elapsed;
      now = before + dt * c.speed;
      if (now <= 0) {
        _fireBack(entity, atlas, c, 0, before, atEnd: starting);
        if (loops) {
          now = total - (-now) % total;
          _fireBack(entity, atlas, c, now, total, atEnd: true);
        } else {
          now = 0;
          _complete(entity, c);
        }
      } else {
        _fireBack(entity, atlas, c, now, before, atEnd: starting);
      }
    }
    c
      ..elapsed = now
      ..frameIndex = clip.frameIndexAt(now);
    state
      ..clip = c.clip
      ..elapsed = now;
  }

  void _complete(Entity entity, SpriteAnimationComponent c) {
    c
      ..isComplete = true
      ..isPlaying = false;
    _signals.add(
      SpriteAnimationSignal(entity, c.clip, SpriteAnimationSignal.completed),
    );
  }

  /// Events in (after, upTo] — [after] itself too when [fromStart] —
  /// earliest first.
  void _fire(
    Entity entity,
    SpriteAtlas atlas,
    SpriteAnimationComponent c,
    double after,
    double upTo, {
    bool fromStart = false,
  }) {
    if (!_signals.hasListener) return;
    for (final event in _eventsOf(atlas, c.clip)) {
      final t = event.time;
      if ((t > after || (fromStart && t == after)) && t <= upTo) {
        _signals.add(SpriteAnimationSignal(entity, c.clip, event.name));
      }
    }
  }

  /// Events in [from, before) — [before] itself too when [atEnd] — latest
  /// first, the order time meets them going backwards.
  void _fireBack(
    Entity entity,
    SpriteAtlas atlas,
    SpriteAnimationComponent c,
    double from,
    double before, {
    bool atEnd = false,
  }) {
    if (!_signals.hasListener) return;
    final events = _eventsOf(atlas, c.clip);
    for (var i = events.length - 1; i >= 0; i--) {
      final t = events[i].time;
      if (t >= from && (t < before || (atEnd && t == before))) {
        _signals.add(SpriteAnimationSignal(entity, c.clip, events[i].name));
      }
    }
  }

  /// [clip]'s frame events in [atlas], earliest first, read once.
  List<AnimationEvent> _eventsOf(SpriteAtlas atlas, String clip) {
    final byClip = _events[atlas] ??= {};
    return byClip[clip] ??= _readEvents(atlas, clip);
  }

  static List<AnimationEvent> _readEvents(SpriteAtlas atlas, String clip) {
    final all = atlas.userData['events'];
    final forClip = all is Map ? all[clip] : null;
    if (forClip is! List) return const [];
    final events = [
      for (final raw in forClip)
        if (raw is Map) AnimationEvent.fromJson(raw.cast<String, dynamic>()),
    ]..sort((a, b) => a.time.compareTo(b.time));
    return List.unmodifiable(events);
  }

  void _show(
    Entity entity,
    _Playing state,
    SpriteAtlas atlas,
    SpriteAnimationComponent c,
    AtlasAnimationClip clip,
  ) {
    final frame = clip.frames[c.frameIndex.clamp(0, clip.frames.length - 1)];
    final region = atlas.getRegion(frame.regionName);
    if (region == null) return;
    var sprite = state.sprite;
    if (sprite == null) {
      sprite = state.sprite = AtlasRegionSprite();
      final existing = entity.getComponent<RenderableComponent>();
      if (existing != null) {
        existing.renderable = sprite;
      } else {
        entity.addComponent(
          RenderableComponent(renderable: sprite, syncTransform: true),
        );
      }
    }
    // A trimmed frame is drawn at its place in the untrimmed box and a
    // rotated one turned back upright: see [AtlasRegionSprite].
    sprite
      ..image = atlas.pages[region.pageIndex].image
      ..region = region
      ..flipX = c.flipX
      ..flipY = c.flipY
      ..tint = c.tint
      ..filterQuality = c.pixelArt
          ? ui.FilterQuality.none
          : ui.FilterQuality.medium;
  }

  @override
  void dispose() {
    _signals.close();
    super.dispose();
  }
}

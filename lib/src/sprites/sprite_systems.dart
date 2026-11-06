library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show debugPrint;

import '../rendering/sprite.dart';
import 'atlas/atlas.dart';
import 'atlas/sprite_asset_loader.dart';
import '../ecs/ecs.dart';
import 'animation_event.dart';
import '../rendering/renderable_component.dart';
import 'sprite_animation_component.dart';
import 'sprite_component.dart';
import 'sprites_context.dart';

/// Shows a [SpriteComponent]: loads its image — or its region of an atlas —
/// into a [RenderableComponent], and keeps flip, tint and filtering current.
///
/// What it shows it holds through its loader ([SpriteAssetLoader.acquireImage],
/// [SpriteAssetLoader.acquireAtlas]) and gives back once nothing shows it:
/// the sprite replaced, its paths cleared, its component or entity gone, or
/// the system removed. An image of its own (from a loader whose images are
/// the caller's, [SpriteAssetLoader.callerDisposesImages]) is disposed then.
/// When the sprite stops showing on an entity that is still there, the
/// [RenderableComponent] the system added is taken off it, so nothing draws
/// an image that was let go. An atlas unloaded under a sprite is loaded
/// again.
class SpriteLoadSystem extends System {
  /// A system loading through [loader]; the world's loader when null.
  SpriteLoadSystem({SpriteAssetLoader? loader}) : _loader = loader;

  final SpriteAssetLoader? _loader;

  /// The loader given, else the world's (`world.context.sprites`).
  SpriteAssetLoader get loader => _loader ?? world.context.sprites;

  // Per entity: the paths last worked out, whether a load is under way, and
  // the sprite shown — one lookup a frame.
  final Map<Entity, _SpriteEntry> _entries = {};

  // What could not be shown, said once each.
  final Set<String> _reported = {};

  // The world's structure when the maps above were last pruned.
  int _prunedAt = -1;

  @override
  int get priority => SystemPriorities.animation - 1;

  @override
  List<Type> get requiredComponents => const [
    TransformComponent,
    SpriteComponent,
  ];

  /// Loads everything again on the next frame: a file changed on disk.
  void reload() {
    for (final entry in _entries.values) {
      entry.shown = null;
    }
    _reported.clear();
  }

  static String _keyOf(SpriteComponent c) =>
      '${c.spritePath.trim()}|${c.atlasPath.trim()}|${c.region.trim()}';

  @override
  void update(double deltaTime) {
    // Only a structural change can take a sprite away; one switched off
    // keeps what it showed.
    final version = world.queryVersion(requiredComponents);
    if (version != _prunedAt) {
      _prunedAt = version;
      bool gone(Entity e) =>
          !e.isAlive ||
          !e.hasComponent<SpriteComponent>() ||
          !e.hasComponent<TransformComponent>();
      _entries.removeWhere((e, entry) {
        if (!gone(e)) return false;
        _forget(e, entry);
        return true;
      });
    }

    for (final entity in entities) {
      final c = entity.getComponent<SpriteComponent>()!;
      final entry = _entries[entity] ??= _SpriteEntry();
      final sprite = entry.sprite;
      if (sprite != null) {
        // An atlas unloaded under it (its pages disposed): drawn as nothing
        // until it is loaded again. What was held went with it.
        final page = entry.page;
        if (page != null && !identical(page.image, sprite.image)) {
          sprite.image = null;
          entry
            ..page = null
            ..dropHold();
          if (!entry.loading) entry.shown = null;
        }
        sprite
          ..flipX = c.flipX
          ..flipY = c.flipY
          ..tint = c.tint
          ..filterQuality = c.pixelArt
              ? ui.FilterQuality.none
              : ui.FilterQuality.medium;
      }
      if (entry.loading) continue;
      // The three paths as they were: nothing to build or compare beyond
      // them while they stay put.
      final shown = entry.shown;
      if (shown != null && shown.matches(c)) continue;
      final key = _keyOf(c);
      entry.shown = _Shown(c, key);
      if (shown?.key == key) continue;

      if (c.spritePath.trim().isEmpty && c.atlasPath.trim().isEmpty) {
        if (entry.sprite != null) {
          entity.removeComponent<RenderableComponent>();
          entry.show(null);
        }
        continue;
      }
      entry.loading = true;
      _load(entity, entry, key);
    }
  }

  /// Lets go of what [entry] showed on [entity], which no longer shows a
  /// sprite: the renderable the system added comes off the entity when it is
  /// still there, then the image is disposed and the hold given back.
  void _forget(Entity entity, _SpriteEntry entry) {
    final sprite = entry.sprite;
    if (sprite != null && entity.isAlive) {
      final renderable = entity.getComponent<RenderableComponent>();
      if (identical(renderable?.renderable, sprite)) {
        entity.removeComponent<RenderableComponent>();
      }
    }
    entry.show(null);
  }

  @override
  void dispose() {
    for (final MapEntry(key: entity, value: entry) in _entries.entries) {
      _forget(entity, entry);
    }
    _entries.clear();
    super.dispose();
  }

  Future<void> _load(Entity entity, _SpriteEntry entry, String key) async {
    final loading = loader;
    ui.Image? own;
    _Hold? held;
    try {
      final asked = entity.getComponent<SpriteComponent>();
      if (asked == null) return;
      final Sprite sprite;
      SpriteAtlasPage? page;
      final atlasPath = asked.atlasPath.trim();
      if (atlasPath.isNotEmpty) {
        final atlas = await loading.acquireAtlas(atlasPath);
        held = _Hold(loading, atlasPath, atlas: true);
        final region = asked.region.trim().isEmpty
            ? atlas.regionNames.first
            : asked.region.trim();
        sprite = atlas.createSprite(region);
        page = atlas.pages[atlas.requireRegion(region).pageIndex];
      } else {
        final path = asked.spritePath.trim();
        final image = await loading.acquireImage(path);
        held = _Hold(loading, path, atlas: false);
        if (loading.callerDisposesImages) own = image;
        sprite = Sprite(image: image);
      }

      // The entity may be gone, asking for something else by now, or the
      // system forgotten it.
      final c = entity.getComponent<SpriteComponent>();
      if (!identical(_entries[entity], entry) ||
          c == null ||
          _keyOf(c) != key) {
        entry.shown = null;
        return;
      }
      final existing = entity.getComponent<RenderableComponent>();
      if (existing != null) {
        existing.renderable = sprite;
      } else {
        entity.addComponent(
          RenderableComponent(renderable: sprite, syncTransform: true),
        );
      }
      // Shown now, the one before let go.
      entry.show(sprite, own: own, held: held, page: page);
      own = null;
      held = null;
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
      // Loaded and not shown: not needed.
      own?.dispose();
      held?.release();
      entry.loading = false;
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

/// What a sprite system holds through a [SpriteAssetLoader] — an atlas or
/// an image — to give back when it stops showing it.
final class _Hold {
  _Hold(this.loader, this.path, {required this.atlas});

  final SpriteAssetLoader loader;
  final String path;
  final bool atlas;

  void release() {
    if (atlas) {
      loader.releaseAtlas(path);
    } else {
      loader.releaseImage(path);
    }
  }
}

/// What [SpriteLoadSystem] knows of one entity.
class _SpriteEntry {
  /// The paths its sprite was last worked out from; null to work it out
  /// again.
  _Shown? shown;

  /// Whether its sprite is being loaded.
  bool loading = false;

  /// The sprite it shows, the image of it the system owns, and what it
  /// holds through the loader.
  Sprite? sprite;
  ui.Image? _own;
  _Hold? _held;

  /// The atlas page [sprite] draws, when it is from an atlas: when the page
  /// no longer has that image, the atlas was unloaded under it.
  SpriteAtlasPage? page;

  /// Shows [next] (its image the system's own when [own], held through the
  /// loader by [held], from atlas [page]), disposing the image of the one
  /// before and giving back what that held.
  void show(Sprite? next, {ui.Image? own, _Hold? held, SpriteAtlasPage? page}) {
    final old = _own;
    final oldHeld = _held;
    sprite = next;
    _own = own;
    _held = held;
    this.page = page;
    if (old != null && !identical(old, own)) old.dispose();
    oldHeld?.release();
  }

  /// Forgets the hold without giving it back: what it held was unloaded,
  /// and its counts with it.
  void dropHold() => _held = null;
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

  /// What [atlas] is held by, given back when this goes.
  _Hold? held;

  /// What the player before this one (of the same path, read again) held,
  /// kept while its sprite still shows: given back once this one shows, or
  /// when this goes.
  final List<_Hold> retired = [];

  // Where this system left the clip last frame. A component that says
  // otherwise was switched or restarted since, and starts afresh.
  String? clip;
  int restarts = -1;
  double elapsed = double.nan;

  // The frame shown last, of which atlas, and its region.
  AtlasFrame? frame;
  SpriteAtlas? frameAtlas;
  SpriteRegion? region;

  /// Gives back everything held.
  void release() {
    held?.release();
    held = null;
    releaseRetired();
  }

  void releaseRetired() {
    for (final hold in retired) {
      hold.release();
    }
    retired.clear();
  }
}

/// Plays [SpriteAnimationComponent]s: loads the atlas, advances the clip by
/// each frame's own duration, shows the frame, and reports events.
///
/// It plays what the component plays now — its `playingClip`, at its
/// `playingSpeed`, facing as its `playingFlipX` says — and writes nothing
/// the component saves.
///
/// A negative playing speed plays the clip backwards, from its last frame.
/// Frame events fire as time passes them either way —
/// one at the very start of a clip as it begins, one at its very end as a
/// clip played backwards begins. A step long enough to go round a looping
/// clip several times fires the events of each pass (of up to
/// [maxPassesPerStep] passes).
///
/// Signals are sent while the clip advances. A listener that switches or
/// restarts the clip ([SpriteAnimationComponent.switchClip],
/// [SpriteAnimationComponent.restart]) gets what it asked for: what was left
/// of the step is dropped, and the new clip starts afresh on the next frame.
///
/// The atlas is held through the loader ([SpriteAssetLoader.acquireAtlas])
/// while something plays it, and given back when the component, its entity
/// or the system goes — taking the [RenderableComponent] it added off an
/// entity that is still there. An atlas unloaded under a player is loaded
/// again.
class SpriteAnimationSystem extends System {
  /// A system loading atlases through [loader]; the world's loader when
  /// null.
  SpriteAnimationSystem({SpriteAssetLoader? loader}) : _loader = loader;

  /// The most loop passes one step fires the events of: a long hitch on a
  /// short clip does not fire its events without end.
  static const int maxPassesPerStep = 8;

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
  List<Type> get requiredComponents => const [
    TransformComponent,
    SpriteAnimationComponent,
  ];

  /// The atlas [entity] is playing from, once loaded — for a tool that lists
  /// its clips.
  SpriteAtlas? atlasOf(Entity entity) => _playing[entity]?.atlas;

  /// Reads [atlasPath] again on the next frame — it changed on disk. With no
  /// path, everything.
  ///
  /// What shows now keeps showing until what is read again replaces it.
  void reload([String? atlasPath]) {
    if (atlasPath != null) loader.evict(atlasPath);
    for (final MapEntry(key: entity, value: state)
        in _playing.entries.toList()) {
      if (atlasPath != null && state.path != atlasPath) continue;
      final next = _playing[entity] = _Playing(state.path)
        ..sprite = state.sprite;
      final held = state.held;
      if (held != null) next.retired.add(held);
      next.retired.addAll(state.retired);
      if (next.path.isNotEmpty) _load(entity, next);
    }
    _everyFrame.clear();
    _events = Expando();
    if (atlasPath == null) {
      _reported.clear();
    } else {
      _reported.remove(atlasPath);
    }
  }

  /// The clip [c] plays ([SpriteAnimationComponent.playingClip]), or every
  /// frame in order when it names none the atlas has.
  AtlasAnimationClip clipOf(SpriteAtlas atlas, SpriteAnimationComponent c) {
    final named = atlas.getClip(c.playingClip);
    if (named != null) return named;
    return _everyFrame[atlas] ??= AtlasAnimationClip(
      name: '',
      frames: [
        for (final name in atlas.regionNames)
          AtlasFrame(regionName: name, duration: 0.1),
      ],
    );
  }

  /// Lets go of [state], [entity]'s player: the renderable it added comes
  /// off the entity when that is still there, then what it held is given
  /// back.
  void _drop(Entity entity, _Playing state) {
    final sprite = state.sprite;
    if (sprite != null && entity.isAlive) {
      final renderable = entity.getComponent<RenderableComponent>();
      if (identical(renderable?.renderable, sprite)) {
        entity.removeComponent<RenderableComponent>();
      }
    }
    state.release();
  }

  /// Whether every page of [atlas] still has its image: an atlas unloaded
  /// (its pages disposed) is not.
  static bool _intact(SpriteAtlas atlas) {
    for (final page in atlas.pages) {
      if (!page.isLoaded) return false;
    }
    return true;
  }

  @override
  void update(double deltaTime) {
    // Only a structural change can take a player away; one switched off
    // keeps its atlas and carries on when it is switched back on.
    final version = world.queryVersion(requiredComponents);
    if (version != _prunedAt) {
      _prunedAt = version;
      _playing.removeWhere((e, state) {
        final gone =
            !e.isAlive ||
            !e.hasComponent<SpriteAnimationComponent>() ||
            !e.hasComponent<TransformComponent>();
        if (gone) _drop(e, state);
        return gone;
      });
    }

    for (final entity in entities) {
      final c = entity.getComponent<SpriteAnimationComponent>()!;
      final path = c.atlasPath.trim();
      var state = _playing[entity];
      if (state == null || state.path != path) {
        if (state != null) _drop(entity, state);
        state = _playing[entity] = _Playing(path);
        if (path.isNotEmpty) _load(entity, state);
      }
      var atlas = state.atlas;
      if (atlas != null && !_intact(atlas)) {
        // Unloaded under it: what it held went with it. Nothing is drawn
        // from the disposed pages; the atlas is loaded again.
        state.sprite?.image = null;
        state.held = null;
        _everyFrame.remove(atlas);
        final next = _playing[entity] = _Playing(path)..sprite = state.sprite;
        next.retired.addAll(state.retired);
        state = next;
        atlas = null;
        _load(entity, state);
      }
      if (atlas == null) continue;

      var clip = clipOf(atlas, c);
      if (clip.frames.isEmpty) continue;
      if (!c.isInitialized) {
        c.isInitialized = true;
        if (c.playOnStart) c.isPlaying = true;
      }
      if (c.isPlaying && !c.isComplete) {
        final playing = c.playingClip;
        _advance(entity, state, atlas, c, clip, deltaTime);
        // A listener may have switched the clip meanwhile.
        if (c.playingClip != playing) clip = clipOf(atlas, c);
        if (clip.frames.isEmpty) continue;
      }
      _show(entity, state, atlas, c, clip);
    }
  }

  Future<void> _load(Entity entity, _Playing state) async {
    final loading = loader;
    try {
      final atlas = await loading.acquireAtlas(state.path);
      final hold = _Hold(loading, state.path, atlas: true);
      if (!identical(_playing[entity], state)) {
        hold.release();
        return;
      }
      state
        ..atlas = atlas
        ..held = hold;
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
    final speed = c.playingSpeed;
    // Switched to, or restarted, since this system last moved it — or its
    // place set from outside.
    final playing = c.playingClip;
    final restarts = c.restarts;
    final fresh =
        state.clip != playing ||
        state.restarts != restarts ||
        c.elapsed != state.elapsed;
    // Whether a listener switched or restarted the clip while it was told
    // something: then what is left of this step is not this clip's.
    bool taken() => c.playingClip != playing || c.restarts != restarts;

    double now;
    if (speed >= 0) {
      final before = c.elapsed;
      // What sits on the very start happens as the clip begins.
      final starting = fresh && before <= 0;
      now = before + dt * speed;
      if (now >= total) {
        _fire(entity, atlas, c, before, total, fromStart: starting);
        if (taken()) return _handOver(state);
        if (loops) {
          // Whole passes inside the step tell their events too.
          final passes = math.min((now / total).floor() - 1, maxPassesPerStep);
          now %= total;
          for (var i = 0; i < passes; i++) {
            _fire(entity, atlas, c, 0, total, fromStart: true);
            if (taken()) return _handOver(state);
          }
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
      now = before + dt * speed;
      if (now <= 0) {
        _fireBack(entity, atlas, c, 0, before, atEnd: starting);
        if (taken()) return _handOver(state);
        if (loops) {
          final passes = math.min((-now / total).floor(), maxPassesPerStep);
          now = total - (-now) % total;
          for (var i = 0; i < passes; i++) {
            _fireBack(entity, atlas, c, 0, total, atEnd: true);
            if (taken()) return _handOver(state);
          }
          _fireBack(entity, atlas, c, now, total, atEnd: true);
        } else {
          now = 0;
          _complete(entity, c);
        }
      } else {
        _fireBack(entity, atlas, c, now, before, atEnd: starting);
      }
    }
    // What a listener asked for stands: the rest of this step is dropped.
    if (taken()) return _handOver(state);
    c
      ..elapsed = now
      ..frameIndex = clip.frameIndexAt(now);
    state
      ..clip = playing
      ..restarts = restarts
      ..elapsed = now;
  }

  /// A listener switched or restarted the clip mid-step: it starts afresh
  /// next frame, from where the listener left it.
  void _handOver(_Playing state) {
    state
      ..clip = null
      ..elapsed = double.nan;
  }

  void _complete(Entity entity, SpriteAnimationComponent c) {
    c
      ..isComplete = true
      ..isPlaying = false;
    _signals.add(
      SpriteAnimationSignal(
        entity,
        c.playingClip,
        SpriteAnimationSignal.completed,
      ),
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
    final clip = c.playingClip;
    final restarts = c.restarts;
    for (final event in _eventsOf(atlas, clip)) {
      final t = event.time;
      if ((t > after || (fromStart && t == after)) && t <= upTo) {
        _signals.add(SpriteAnimationSignal(entity, clip, event.name));
        // A listener switched or restarted the clip: the rest are not due.
        if (c.playingClip != clip || c.restarts != restarts) return;
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
    final clip = c.playingClip;
    final restarts = c.restarts;
    final events = _eventsOf(atlas, clip);
    for (var i = events.length - 1; i >= 0; i--) {
      final t = events[i].time;
      if (t >= from && (t < before || (atEnd && t == before))) {
        _signals.add(SpriteAnimationSignal(entity, clip, events[i].name));
        if (c.playingClip != clip || c.restarts != restarts) return;
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
    // The frame's region, looked up again only when the frame changes.
    if (!identical(frame, state.frame) || !identical(atlas, state.frameAtlas)) {
      state
        ..frame = frame
        ..frameAtlas = atlas
        ..region = atlas.getRegion(frame.regionName);
    }
    final region = state.region;
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
      ..flipX = c.playingFlipX
      ..flipY = c.flipY
      ..tint = c.tint
      ..filterQuality = c.pixelArt
          ? ui.FilterQuality.none
          : ui.FilterQuality.medium;
    // Read again, it shows what was read: what the one before held can go.
    if (state.retired.isNotEmpty) state.releaseRetired();
  }

  @override
  void dispose() {
    for (final MapEntry(key: entity, value: state) in _playing.entries) {
      _drop(entity, state);
    }
    _playing.clear();
    _signals.close();
    super.dispose();
  }
}

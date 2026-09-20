library;

import 'dart:async';
import 'dart:ui' as ui;

import '../../../subsystems/rendering/impl/sprite.dart';
import '../../../subsystems/sprite_atlas/sprite_atlas.dart';
import '../../components/components.dart';
import '../../ecs.dart';
import '../system_priorities.dart';

/// Where sprite images and atlases come from.
///
/// The game reads the asset bundle ([BundleSpriteAssetLoader]). An authoring
/// tool replaces [SpriteAssets.loader] with one that reads the project's
/// files, because a sheet saved a second ago is not in the bundle yet.
abstract class SpriteAssetLoader {
  Future<ui.Image> loadImage(String path);
  Future<SpriteAtlas> loadAtlas(String path);

  /// Forgets [path], so the next load reads it again. A loader that does not
  /// cache has nothing to do.
  void evict(String path) {}
}

/// Loads through the engine's asset manager, which caches by path.
class BundleSpriteAssetLoader extends SpriteAssetLoader {
  @override
  Future<ui.Image> loadImage(String path) => Sprite.loadImageFromAsset(path);

  @override
  Future<SpriteAtlas> loadAtlas(String path) => SpriteAtlas.fromAsset(path);
}

/// The loader the sprite systems use unless given their own.
abstract final class SpriteAssets {
  static SpriteAssetLoader loader = BundleSpriteAssetLoader();
}

/// Shows a [SpriteComponent]: loads its image — or its region of an atlas —
/// into a [RenderableComponent], and keeps flip, tint and filtering current.
class SpriteLoadSystem extends System {
  SpriteLoadSystem({SpriteAssetLoader? loader}) : _loader = loader;

  final SpriteAssetLoader? _loader;
  SpriteAssetLoader get loader => _loader ?? SpriteAssets.loader;

  final Map<Entity, String> _shown = {};
  final Set<Entity> _loading = {};
  final Map<Entity, Sprite> _sprites = {};

  @override
  int get priority => SystemPriorities.animation - 1;

  @override
  List<Type> get requiredComponents => [TransformComponent, SpriteComponent];

  /// Loads everything again on the next frame: a file changed on disk.
  void reload() => _shown.clear();

  static String _keyOf(SpriteComponent c) =>
      '${c.spritePath.trim()}|${c.atlasPath.trim()}|${c.region.trim()}';

  @override
  void update(double deltaTime) {
    final live = entities.toSet();
    _shown.removeWhere((e, _) => !live.contains(e));
    _loading.removeWhere((e) => !live.contains(e));
    _sprites.removeWhere((e, _) => !live.contains(e));

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
      final key = _keyOf(c);
      if (_shown[entity] == key) return;
      _shown[entity] = key;

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
    } catch (_) {
      // A wrong path stays remembered, so it is not tried again every
      // frame; correcting it changes the key, and that is tried.
    } finally {
      _loading.remove(entity);
    }
  }
}

/// Something a playing sprite said: a frame event the artist placed, or
/// [SpriteAnimationSignal.completed] when a clip that does not loop ends.
class SpriteAnimationSignal {
  const SpriteAnimationSignal(this.entity, this.clip, this.name);

  static const String completed = 'completed';

  final Entity entity;
  final String clip;
  final String name;
}

class _Playing {
  _Playing(this.path);

  final String path;
  SpriteAtlas? atlas;
  Sprite? sprite;
  bool failed = false;
}

/// Plays [SpriteAnimationComponent]s: loads the atlas, advances the clip by
/// each frame's own duration, shows the frame, and reports events.
class SpriteAnimationSystem extends System {
  SpriteAnimationSystem({SpriteAssetLoader? loader}) : _loader = loader;

  final SpriteAssetLoader? _loader;
  SpriteAssetLoader get loader => _loader ?? SpriteAssets.loader;

  final Map<Entity, _Playing> _playing = {};
  final Map<SpriteAtlas, AtlasAnimationClip> _everyFrame = {};
  final StreamController<SpriteAnimationSignal> _signals =
      StreamController<SpriteAnimationSignal>.broadcast(sync: true);

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
    final live = entities.toSet();
    _playing.removeWhere((e, _) => !live.contains(e));

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
        _advance(entity, atlas, c, clip, deltaTime);
      }
      _show(entity, state, atlas, c, clip);
    });
  }

  Future<void> _load(Entity entity, _Playing state) async {
    try {
      final atlas = await loader.loadAtlas(state.path);
      if (_playing[entity] != state) return;
      state.atlas = atlas;
    } catch (_) {
      state.failed = true;
    }
  }

  void _advance(
    Entity entity,
    SpriteAtlas atlas,
    SpriteAnimationComponent c,
    AtlasAnimationClip clip,
    double dt,
  ) {
    final total = clip.totalDuration;
    if (total <= 0) return;
    final loops = c.loopOverride ?? clip.loop;
    final before = c.elapsed;
    var now = before + dt * c.speed;

    if (now >= total) {
      if (loops) {
        _fire(entity, atlas, c, before, total);
        now %= total;
        _fire(entity, atlas, c, -1, now);
      } else {
        _fire(entity, atlas, c, before, total);
        now = total;
        c
          ..isComplete = true
          ..isPlaying = false;
        _signals.add(
          SpriteAnimationSignal(
            entity,
            c.clip,
            SpriteAnimationSignal.completed,
          ),
        );
      }
    } else {
      _fire(entity, atlas, c, before, now);
    }
    c.elapsed = now;

    var t = 0.0;
    var index = clip.frames.length - 1;
    for (var i = 0; i < clip.frames.length; i++) {
      t += clip.frames[i].duration;
      if (now < t) {
        index = i;
        break;
      }
    }
    c.frameIndex = index;
  }

  /// Events in (after, upTo]; pass -1 for [after] to include time zero.
  void _fire(
    Entity entity,
    SpriteAtlas atlas,
    SpriteAnimationComponent c,
    double after,
    double upTo,
  ) {
    if (!_signals.hasListener) return;
    final all = atlas.userData['events'];
    final forClip = all is Map ? all[c.clip] : null;
    if (forClip is! List) return;
    for (final raw in forClip) {
      if (raw is! Map) continue;
      final event = AnimationEvent.fromJson(raw.cast<String, dynamic>());
      if (event.time > after && event.time <= upTo) {
        _signals.add(SpriteAnimationSignal(entity, c.clip, event.name));
      }
    }
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
      sprite = state.sprite = Sprite();
      final existing = entity.getComponent<RenderableComponent>();
      if (existing != null) {
        existing.renderable = sprite;
      } else {
        entity.addComponent(
          RenderableComponent(renderable: sprite, syncTransform: true),
        );
      }
    }
    sprite
      ..image = atlas.pages[region.pageIndex].image
      ..sourceRect = region.frame
      ..renderSize = region.sourceSize
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

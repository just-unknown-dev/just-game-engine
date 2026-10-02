/// What one engine knows: its registries, loaders, caches and buses.
library;

import 'dart:convert' show jsonDecode;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart'
    show AssetBundle, AssetManifest, rootBundle;

import '../serialization/component_definition_registry.dart';
import '../serialization/core_codecs.dart';
import '../serialization/field_type.dart';
import '../serialization/migration_hooks.dart';
import '../components/animation/animator_bindings.dart';
import '../../subsystems/sprite_atlas/sprite_asset_loader.dart';
import '../../subsystems/animation/animator/animator_graph.dart';
import '../../subsystems/assets/asset_management.dart';
import '../../subsystems/effects/effect_system.dart';
import '../../subsystems/level_map/collision/map_collision_kinds.dart';
import '../../subsystems/level_map/tile_assets.dart';
import '../../subsystems/localization/localization_manager.dart';
import '../../subsystems/physics/physics_layers.dart';
import '../../subsystems/timeline/timeline_asset.dart';
import '../../subsystems/timeline/timeline_keys.dart';
import '../../subsystems/timeline/timeline_signals.dart';
import '../../subsystems/timeline/timeline_track.dart';
import '../../subsystems/timeline/tracks/block_tracks.dart';

export '../../subsystems/level_map/tile_assets.dart' show TextReader;

/// Loads an animator graph by path.
typedef AnimatorGraphLoader = Future<AnimatorGraph> Function(String path);

/// Loads a timeline by path.
typedef TimelineLoader = Future<TimelineAsset> Function(String path);

/// What a package teaches an engine: its component definitions, migrations,
/// animator bindings, timeline track kinds, collision kinds and easings.
///
/// Installed once per [EngineContext], by [id]: installing the same
/// extension twice does nothing the second time.
///
/// ```dart
/// final class MyKitExtension implements ContextExtension {
///   const MyKitExtension();
///   @override
///   String get id => 'my_kit';
///   @override
///   void install(EngineContext context) {
///     context.definitions.registerAll(MyKitDefinitions.all);
///   }
/// }
///
/// final engine = Engine(
///   config: const EngineConfig(extensions: [MyKitExtension()]),
/// );
/// ```
abstract interface class ContextExtension {
  /// Names the extension; one install per context.
  String get id;

  /// Registers what the package brings into [context].
  void install(EngineContext context);
}

/// State a package keeps per context (see [EngineContext.slot]) that must
/// be released with it.
abstract interface class ContextResource {
  /// Releases the state; called once, from [EngineContext.dispose].
  void dispose();
}

/// Everything one engine knows that is not a subsystem: the component
/// definitions and field types scenes are read with, and the per-package
/// state packages hang on it.
///
/// Each [Engine] owns one, made in its constructor, and gives it to its
/// [World]; worlds it makes later — the interface's screens, an editor's
/// previews — are given the same context, so they read the same components.
/// A bare `World()` makes a fresh context of its own, with the engine's
/// core definitions already registered, and disposes it with itself.
///
/// Nothing in here is process-wide: two engines, or two tests, never see
/// each other's registrations.
final class EngineContext {
  /// A context with the engine's own definitions and field types registered
  /// (unless [withBuiltIns] is false — only for tests that check a registry
  /// precisely), then [extensions] installed, in order.
  ///
  /// Files are read from [bundle] — the app's `rootBundle` when null; a test
  /// passes a fake.
  EngineContext({
    Iterable<ContextExtension> extensions = const [],
    AssetBundle? bundle,
    bool withBuiltIns = true,
  }) : definitions = ComponentDefinitionRegistry(),
       fieldTypes = FieldTypeRegistry(withBuiltIns: withBuiltIns),
       trackKinds = TimelineTrackKinds(withBuiltIns: withBuiltIns),
       easings = KeyEasings(withBuiltIns: withBuiltIns),
       animatorBindings = AnimatorBindings(withBuiltIns: withBuiltIns),
       collisionKinds = MapCollisionKinds(withBuiltIns: withBuiltIns),
       effectTypes = EffectTypes(withBuiltIns: withBuiltIns),
       bundle = bundle ?? rootBundle,
       assets = AssetManager(bundle: bundle) {
    sprites = _bundleSprites = BundleSpriteAssetLoader(assets);
    animatorGraphs = _bundleGraph;
    timelines = _bundleTimeline;
    tiles = TileAssets(readText: _bundleText, collisionKinds: collisionKinds);
    if (withBuiltIns) registerCoreCodecs(definitions);
    installAll(extensions);
  }

  /// Every component this context can save, load, inspect and draw. Core
  /// components are registered from the start; a package adds its own
  /// through a [ContextExtension].
  final ComponentDefinitionRegistry definitions;

  /// The kinds of field component definitions are made of.
  final FieldTypeRegistry fieldTypes;

  /// What packages add to the scene and timeline migrations; the scene
  /// loader and the timeline loader migrate older files with them.
  final MigrationHooks migrations = MigrationHooks();

  /// The kinds of timeline track this engine reads and plays; the engine's
  /// seven are always there.
  final TimelineTrackKinds trackKinds;

  /// The easings a timeline key can name.
  final KeyEasings easings;

  /// What an animator graph's parameters can be bound to.
  final AnimatorBindings animatorBindings;

  /// The collision kinds a tile can have; `solid` and `oneWay` are always
  /// there.
  final MapCollisionKinds collisionKinds;

  /// The deterministic effects a snapshot can hold.
  final EffectTypes effectTypes;

  /// The project's collision layers: their names and which collide. Every
  /// `PhysicsSystem` on this context filters its bodies by it, and refilters
  /// them when it is replaced — so an editor changing the grid changes a
  /// running game.
  ///
  /// [PhysicsLayers.defaults] until [loadPhysicsLayers] reads the project's
  /// file, which `Engine.initialize` does.
  PhysicsLayers physicsLayers = PhysicsLayers.defaults;

  /// Reads [path] from [bundle] into [physicsLayers]. A project without the
  /// file keeps the defaults; one whose file cannot be read keeps them too,
  /// and says why in the log.
  Future<void> loadPhysicsLayers([
    String path = PhysicsLayers.defaultPath,
  ]) async {
    // The manifest first, where there is one: on the web, asking for a
    // file the app does not bundle is a failed request the browser reports.
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(bundle);
      if (!manifest.listAssets().contains(path)) return;
    } catch (_) {
      // No manifest (a bundle of a test's own): ask for the file itself.
    }
    final String text;
    try {
      text = await bundle.loadString(path, cache: false);
    } catch (_) {
      return; // Not bundled: the project has not set any up.
    }
    try {
      physicsLayers = PhysicsLayers.fromJson(jsonDecode(text));
    } catch (e) {
      debugPrint('Could not read the physics layers in $path: $e');
    }
  }

  /// How a timeline's audio track makes a sound. By default an
  /// `AudioPlayComponent` for the engine's audio system
  /// ([TimelineAudio.viaComponent]); a game with its own audio replaces it.
  TimelineAudioPlayer timelineAudio = TimelineAudio.viaComponent;

  /// Named signals, for every world on this context: a timeline event or an
  /// interface button emits one, and timeline players listening for it
  /// start. Closed with the context.
  final TimelineSignals signals = TimelineSignals();

  /// The game's strings, when it has them. A `GameWidget` showing this
  /// engine provides it to everything drawn over the game through a
  /// `LocalizationScope`; set it before building the widget.
  LocalizationManager? localization;

  /// Where this context's files come from.
  final AssetBundle bundle;

  /// Loads, caches and releases images, audio, text, JSON and atlases from
  /// [bundle]; what `engine.assets` is.
  final AssetManager assets;

  // ── Where files come from ────────────────────────────────────────────────
  //
  // Four seams, each read by the systems of every world on this context. The
  // game leaves them on the bundle; an authoring tool points them at the
  // project's files (see [overrideLoaders]) — for this engine only.

  late final BundleSpriteAssetLoader _bundleSprites;

  /// Loads sprite images and atlases for the sprite systems and the level
  /// maps' tileset images. The bundle, through [assets], by default.
  late SpriteAssetLoader sprites;

  /// Loads animator graphs for the `AnimatorSystem`. The bundle by default.
  late AnimatorGraphLoader animatorGraphs;

  /// Loads timelines for the `TimelineSystem` and nested timeline tracks.
  /// The bundle by default.
  late TimelineLoader timelines;

  /// Tilesets and map files, and what was loaded of them; its
  /// [TileAssets.readText] is the fourth seam.
  late final TileAssets tiles;

  Future<String> _bundleText(String path) =>
      bundle.loadString(path, cache: false);

  Future<AnimatorGraph> _bundleGraph(String path) async =>
      AnimatorGraph.parse(await bundle.loadString(path));

  Future<TimelineAsset> _bundleTimeline(String path) async =>
      TimelineAsset.parse(
        await bundle.loadString(path),
        kinds: trackKinds,
        migrations: migrations,
      );

  /// Points the file-reading seams given at other loaders, together — an
  /// editor reading the project's files, say. Returns what puts them back:
  /// [LoaderOverride.restore] restores each seam only if it still holds
  /// what this override set, so a later override is not undone.
  LoaderOverride overrideLoaders({
    SpriteAssetLoader? sprites,
    AnimatorGraphLoader? animatorGraphs,
    TimelineLoader? timelines,
    TextReader? tileText,
  }) {
    final override = LoaderOverride._(
      this,
      sprites: (this.sprites, sprites),
      animatorGraphs: (this.animatorGraphs, animatorGraphs),
      timelines: (this.timelines, timelines),
      tileText: (tiles.readText, tileText),
    );
    if (sprites != null) this.sprites = sprites;
    if (animatorGraphs != null) this.animatorGraphs = animatorGraphs;
    if (timelines != null) this.timelines = timelines;
    if (tileText != null) tiles.readText = tileText;
    return override;
  }

  /// Every seam back on [bundle], and the tile caches cleared.
  void useBundle() {
    sprites = _bundleSprites;
    animatorGraphs = _bundleGraph;
    timelines = _bundleTimeline;
    tiles
      ..readText = _bundleText
      ..clear();
  }

  final Map<String, ContextExtension> _installed = {};
  final Map<Object, Object> _slots = {};
  bool _disposed = false;

  /// Installs [extension] — once: a second install of the same [ContextExtension.id]
  /// is ignored.
  void install(ContextExtension extension) {
    if (_installed.containsKey(extension.id)) return;
    _installed[extension.id] = extension;
    extension.install(this);
  }

  /// Installs each of [extensions], in order.
  void installAll(Iterable<ContextExtension> extensions) {
    for (final extension in extensions) {
      install(extension);
    }
  }

  /// Whether an extension with [id] was installed.
  bool isInstalled(String id) => _installed.containsKey(id);

  /// The ids of the extensions installed, in install order.
  Iterable<String> get installed => _installed.keys;

  /// The state a package keeps in this context under [key], made by
  /// [create] the first time it is asked for.
  ///
  /// The way for a package to keep a registry or a cache per engine rather
  /// than in a static: use a private object (or the package's own type) as
  /// the key. A value that is a [ContextResource] is disposed with the
  /// context.
  T slot<T extends Object>(Object key, T Function() create) {
    final existing = _slots[key];
    if (existing != null) return existing as T;
    final made = create();
    _slots[key] = made;
    return made;
  }

  /// Whether [dispose] has run.
  bool get isDisposed => _disposed;

  /// Releases what the context holds: its loaded assets and the
  /// per-package slots that are [ContextResource]s. Registrations stay
  /// readable; a disposed context is not meant to be used again.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    signals.dispose();
    tiles.dispose();
    assets.dispose();
    for (final value in _slots.values) {
      if (value is ContextResource) value.dispose();
    }
    _slots.clear();
  }
}

/// What [EngineContext.overrideLoaders] changed, and how to put it back.
final class LoaderOverride {
  LoaderOverride._(
    this._context, {
    required (SpriteAssetLoader, SpriteAssetLoader?) sprites,
    required (AnimatorGraphLoader, AnimatorGraphLoader?) animatorGraphs,
    required (TimelineLoader, TimelineLoader?) timelines,
    required (TextReader, TextReader?) tileText,
  }) : _sprites = sprites,
       _animatorGraphs = animatorGraphs,
       _timelines = timelines,
       _tileText = tileText;

  final EngineContext _context;
  final (SpriteAssetLoader, SpriteAssetLoader?) _sprites;
  final (AnimatorGraphLoader, AnimatorGraphLoader?) _animatorGraphs;
  final (TimelineLoader, TimelineLoader?) _timelines;
  final (TextReader, TextReader?) _tileText;
  bool _restored = false;

  /// Puts back each seam this override set, if it still holds what it set.
  /// Once only.
  void restore() {
    if (_restored) return;
    _restored = true;
    final c = _context;
    if (_sprites.$2 case final set? when identical(c.sprites, set)) {
      c.sprites = _sprites.$1;
    }
    if (_animatorGraphs.$2 case final set?
        when identical(c.animatorGraphs, set)) {
      c.animatorGraphs = _animatorGraphs.$1;
    }
    if (_timelines.$2 case final set? when identical(c.timelines, set)) {
      c.timelines = _timelines.$1;
    }
    if (_tileText.$2 case final set? when identical(c.tiles.readText, set)) {
      c.tiles.readText = _tileText.$1;
    }
  }
}

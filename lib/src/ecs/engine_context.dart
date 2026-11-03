/// What one engine knows: its component definitions, field types,
/// migrations and files, and the state each feature keeps per engine.
library;

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import '../assets/asset_manager.dart';
import 'serialization/component_definition_registry.dart';
import 'serialization/ecs_definitions.dart';
import 'serialization/field_type.dart';
import 'package:just_game_engine_formats/just_game_engine_formats.dart';

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

/// A [ContextExtension] that can put its definitions in place again, as
/// the code now makes them, after a hot reload — so an editor shows a field
/// just added to one of its components. See
/// [EngineContext.refreshDefinitions].
///
/// [refresh] must be safe to call any number of times: register with
/// [ComponentDefinitionRegistry.refresh] and other replace-by-key calls,
/// never anything that appends (a migration, a listener).
abstract interface class RefreshableExtension implements ContextExtension {
  /// Puts what [install] registered in place again, from the code as it
  /// now is.
  void refresh(EngineContext context);
}

/// State a package keeps per context (see [EngineContext.slot]) that must
/// be released with it.
abstract interface class ContextResource {
  /// Releases the state; called once, from [EngineContext.dispose].
  void dispose();
}

/// Everything one engine knows that is not a subsystem: the component
/// definitions and field types scenes are read with, the migrations older
/// files are brought forward with, where files come from, and the state
/// each feature keeps per engine.
///
/// The ECS core's own components (the transform, the parent and children
/// links, tags) are always registered. Everything else is taught by
/// [ContextExtension]s: an `Engine` installs `BuiltInComponents.extension`
/// (the engine's own features) and the game's extensions, so its scenes
/// load. A feature keeps its own state here through [slot] — the timeline
/// its track kinds, the level map its tiles — and offers it as an extension
/// on this class (`context.trackKinds`, `context.tiles`).
///
/// Each [Engine] owns one, made in its constructor, and gives it to its
/// [World]; worlds it makes later — the interface's screens, an editor's
/// previews — are given the same context, so they read the same components.
/// A bare `World()` makes a fresh context of its own and disposes it with
/// itself.
///
/// Nothing in here is process-wide: two engines, or two tests, never see
/// each other's registrations.
final class EngineContext {
  /// A context with the ECS core's own definitions and the field types
  /// registered (unless [withBuiltIns] is false — only for tests that check
  /// a registry precisely), then [extensions] installed, in order.
  ///
  /// Files are read from [bundle] — the app's `rootBundle` when null; a test
  /// passes a fake.
  EngineContext({
    Iterable<ContextExtension> extensions = const [],
    AssetBundle? bundle,
    this.withBuiltIns = true,
  }) : definitions = ComponentDefinitionRegistry(),
       fieldTypes = FieldTypeRegistry(withBuiltIns: withBuiltIns),
       bundle = bundle ?? rootBundle,
       assets = AssetManager(bundle: bundle) {
    if (withBuiltIns) {
      definitions.registerAll(EcsDefinitions.all, ifAbsent: true);
    }
    installAll(extensions);
  }

  /// Whether the context started with what is built in: the ECS core's
  /// components and field types, and each feature's own kinds (track
  /// kinds, easings, collision kinds, …) as a feature makes its state.
  final bool withBuiltIns;

  /// Every component this context can save, load, inspect and draw. The ECS
  /// core's own are registered from the start; a package adds its own
  /// through a [ContextExtension].
  final ComponentDefinitionRegistry definitions;

  /// The kinds of field component definitions are made of.
  final FieldTypeRegistry fieldTypes;

  /// What packages add to the scene and timeline migrations; the scene
  /// loader and the timeline loader migrate older files with them.
  final MigrationHooks migrations = MigrationHooks();

  /// Where this context's files come from.
  final AssetBundle bundle;

  /// Loads, caches and releases images, audio, text, JSON and atlases from
  /// [bundle]; what `engine.assets` is.
  final AssetManager assets;

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

  /// Puts every component definition in place again as the code now makes
  /// it: the ECS core's own, then each installed [RefreshableExtension]'s,
  /// in install order. A project's deliberate replacement of a definition
  /// stays (see [ComponentDefinitionRegistry.refresh]).
  ///
  /// For an editor, after a hot reload: definitions are built once at boot,
  /// so without this a field added to a component would not be seen until
  /// a restart. An extension that is not refreshable is left as installed.
  /// A game never calls this.
  void refreshDefinitions() {
    if (withBuiltIns) definitions.refresh(EcsDefinitions.all);
    for (final extension in _installed.values) {
      if (extension is RefreshableExtension) extension.refresh(this);
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

  /// Releases what the context holds: the per-package slots that are
  /// [ContextResource]s, then its loaded assets. Registrations stay
  /// readable, and so do the slots — released, not made again; a disposed
  /// context is not meant to be used again.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final value in _slots.values) {
      if (value is ContextResource) value.dispose();
    }
    assets.dispose();
  }
}

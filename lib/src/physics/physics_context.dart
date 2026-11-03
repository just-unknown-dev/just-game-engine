/// What physics keeps per engine: the project's collision layers.
library;

import 'dart:convert' show jsonDecode;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show AssetManifest;

import '../ecs/engine_context.dart';
import 'physics_layers.dart';

/// The physics state of one [EngineContext]; read it through
/// [ContextPhysics].
final class PhysicsContextState {
  PhysicsContextState._();

  /// [context]'s state, made the first time it is asked for.
  static PhysicsContextState of(EngineContext context) =>
      context.slot(_key, PhysicsContextState._);

  static final Object _key = Object();

  /// See [ContextPhysics.physicsLayers].
  PhysicsLayers layers = PhysicsLayers.defaults;
}

/// An engine's collision layers, on its [EngineContext].
extension ContextPhysics on EngineContext {
  /// The project's collision layers: their names and which collide. Every
  /// `PhysicsSystem` on this context filters its bodies by it, and refilters
  /// them when it is replaced — so an editor changing the grid changes a
  /// running game.
  ///
  /// [PhysicsLayers.defaults] until [loadPhysicsLayers] reads the project's
  /// file, which `Engine.initialize` does.
  PhysicsLayers get physicsLayers => PhysicsContextState.of(this).layers;
  set physicsLayers(PhysicsLayers value) =>
      PhysicsContextState.of(this).layers = value;

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
}

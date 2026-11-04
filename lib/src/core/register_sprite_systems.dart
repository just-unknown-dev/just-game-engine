library;

import 'package:just_game_engine_formats/just_game_engine_formats.dart';
import '../sprites/atlas/sprite_asset_loader.dart';
import '../timeline/timeline_asset.dart';
import '../ecs/ecs.dart';
import '../sprites/sprite_systems.dart';
import '../animation/animator_system.dart';
import '../timeline/timeline_system.dart';
import '../timeline/timeline_trigger_system.dart';

/// Registers what shows and animates sprites: still sprites and clip
/// playback — and, unless [animators] or [timelines] is false, the
/// animator state machine ([registerAnimatorSystems]) and timelines
/// ([registerTimelineSystems]). A game that places sprites calls this once
/// at boot; without it a sprite component is only data. Systems already in
/// [world] are left alone.
void registerSpriteSystems(
  World world, {
  SpriteAssetLoader? loader,
  Future<AnimatorGraph> Function(String path)? graphLoader,
  Future<TimelineAsset> Function(String path)? timelineLoader,
  bool animators = true,
  bool timelines = true,
}) {
  if (!world.hasSystem<SpriteLoadSystem>()) {
    world.addSystem(SpriteLoadSystem(loader: loader));
  }
  if (animators) registerAnimatorSystems(world, graphLoader: graphLoader);
  if (!world.hasSystem<SpriteAnimationSystem>()) {
    world.addSystem(SpriteAnimationSystem(loader: loader));
  }
  if (timelines) registerTimelineSystems(world, loader: timelineLoader);
}

/// Registers the animator state machine (`AnimatorSystem`), reading graphs
/// through [graphLoader] (the context's when null). Left alone when [world]
/// has one.
void registerAnimatorSystems(
  World world, {
  Future<AnimatorGraph> Function(String path)? graphLoader,
}) {
  if (!world.hasSystem<AnimatorSystem>()) {
    world.addSystem(AnimatorSystem(loader: graphLoader));
  }
}

/// Registers timelines: `TimelineTriggerSystem`, which starts them, and
/// `TimelineSystem`, which plays them — over sprites, 3-D models or any
/// field — reading timeline files through [loader] (the context's when
/// null). Systems already in [world] are left alone.
void registerTimelineSystems(
  World world, {
  Future<TimelineAsset> Function(String path)? loader,
}) {
  if (!world.hasSystem<TimelineTriggerSystem>()) {
    world.addSystem(TimelineTriggerSystem());
  }
  if (!world.hasSystem<TimelineSystem>()) {
    world.addSystem(TimelineSystem(loader: loader));
  }
}

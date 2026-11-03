library;

import 'package:just_game_engine_formats/just_game_engine_formats.dart';
import '../sprites/atlas/sprite_asset_loader.dart';
import '../timeline/timeline_asset.dart';
import '../ecs/ecs.dart';
import '../sprites/sprite_systems.dart';
import '../animation/animator_system.dart';
import '../timeline/timeline_system.dart';
import '../timeline/timeline_trigger_system.dart';

/// Registers what shows and animates sprites: still sprites, the animator
/// state machine, clip playback and timelines. A game that
/// places sprites calls this once at boot; without it a sprite component is
/// only data. Systems already in [world] are left alone.
void registerSpriteSystems(
  World world, {
  SpriteAssetLoader? loader,
  Future<AnimatorGraph> Function(String path)? graphLoader,
  Future<TimelineAsset> Function(String path)? timelineLoader,
}) {
  bool has<T extends System>() => world.systems.any((s) => s is T);
  if (!has<SpriteLoadSystem>()) {
    world.addSystem(SpriteLoadSystem(loader: loader));
  }
  if (!has<AnimatorSystem>()) {
    world.addSystem(AnimatorSystem(loader: graphLoader));
  }
  if (!has<SpriteAnimationSystem>()) {
    world.addSystem(SpriteAnimationSystem(loader: loader));
  }
  if (!has<TimelineTriggerSystem>()) {
    world.addSystem(TimelineTriggerSystem());
  }
  if (!has<TimelineSystem>()) {
    world.addSystem(TimelineSystem(loader: timelineLoader));
  }
}

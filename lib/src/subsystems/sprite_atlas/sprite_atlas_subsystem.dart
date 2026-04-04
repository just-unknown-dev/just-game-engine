/// Sprite Atlas Subsystem
///
/// Provides sprite-sheet parsing, frame region management, named animation
/// clips, and an [AtlasSpriteAnimation] that drives a [Sprite] through
/// variable-duration frames — optimising 2-D games by packing many sprites
/// onto a single GPU texture and reducing per-frame draw calls.
///
/// ## Supported atlas formats
/// | Format | Notes |
/// |--------|-------|
/// | **TexturePacker JSON Array** | `frames` is a JSON array |
/// | **TexturePacker JSON Hash**  | `frames` is a JSON object |
/// | **TexturePacker multi-page** | top-level `"textures"` list |
/// | **Aseprite JSON export**     | detected via `meta.app` = `"aseprite"` |
///
/// Format is **auto-detected** by [AtlasParser.detect] — no manual selection
/// is required.
///
/// ## Quick start
/// ```dart
/// // Load once (result cached by AssetManager)
/// final atlas = await SpriteAtlas.fromAsset('assets/data/heroes.json');
///
/// // Create a sprite from a named region
/// final sprite = atlas.createSprite('hero_idle_0',
///     position: Offset(100, 200));
///
/// // Animate through a named clip
/// final anim = atlas.createAnimation('run', sprite);
/// engine.animation.add(anim);
///
/// // Register a runtime clip (code-driven)
/// atlas.registerClip(AtlasAnimationClip(
///   name: 'attack',
///   frames: [
///     AtlasFrame(regionName: 'hero_attack_0', duration: 0.05),
///     AtlasFrame(regionName: 'hero_attack_1', duration: 0.10),
///   ],
/// ));
/// ```
library;

import 'dart:ui' as ui;
// Hide Flutter's Animation to avoid ambiguity with the engine's Animation
// base class that is exported from animation_system.dart.
import 'package:flutter/material.dart' hide Animation;
import '../../core/engine.dart';
import '../rendering/impl/sprite.dart';
import '../animation/animation_system.dart';
import '../assets/asset_management.dart';

part 'impl/sprite_region.dart';
part 'impl/atlas_animation_clip.dart';
part 'impl/sprite_atlas_page.dart';
part 'impl/sprite_atlas.dart';
part 'impl/atlas_parser.dart';
part 'impl/texture_packer_parser.dart';
part 'impl/aseprite_parser.dart';
part 'impl/atlas_sprite_animation.dart';
part 'impl/atlas_asset.dart';

/// Sprite atlases: sprite-sheet parsing, regions and clips, and the sprite
/// loader seam.
///
/// Provides sprite-sheet parsing, frame region management and named
/// animation clips with variable-duration frames — optimising 2-D games by
/// packing many sprites onto a single GPU texture and reducing per-frame
/// draw calls. An entity plays a clip with a `SpriteAnimationComponent`.
///
/// ## Supported atlas formats
/// | Format | Notes |
/// |--------|-------|
/// | **TexturePacker JSON Array** | `frames` is a JSON array |
/// | **TexturePacker JSON Hash**  | `frames` is a JSON object |
/// | **TexturePacker multi-page** | top-level `"textures"` list |
/// | **Aseprite JSON export**     | detected via `meta.app` = `"aseprite"` |
/// | **Grid sheet** (legacy)      | `meta.frameWidth/Height`, no `frames` |
///
/// Format is **auto-detected** by [AtlasParser.detect] — no manual selection
/// is required.
///
/// ## Quick start
/// ```dart
/// // Load once (result cached by AssetManager)
/// final atlas = await SpriteAtlas.fromAsset(
///   'assets/data/heroes.json',
///   assets: engine.assets,
/// );
///
/// // Create a sprite from a named region
/// final sprite = atlas.createSprite('hero_idle_0',
///     position: Vector3(100, 200, 0));
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

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../rendering/sprite.dart';
import '../../assets/asset_manager.dart';
import 'package:just_dart/just_dart.dart';

part 'sprite_region.dart';
part 'atlas_animation_clip.dart';
part 'sprite_atlas_page.dart';
part 'sprite_atlas.dart';
part 'atlas_parser.dart';
part 'texture_packer_atlas_parser.dart';
part 'aseprite_atlas_parser.dart';
part 'grid_sheet_atlas_parser.dart';
part 'atlas_asset.dart';
part 'atlas_region_sprite.dart';

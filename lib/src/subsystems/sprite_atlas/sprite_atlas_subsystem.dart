/// Sprite Atlas Subsystem
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
///     position: Offset(100, 200));
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

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../rendering/impl/sprite.dart';
import '../assets/asset_management.dart';
import 'package:just_dart/just_dart.dart';

part 'impl/sprite_region.dart';
part 'impl/atlas_animation_clip.dart';
part 'impl/sprite_atlas_page.dart';
part 'impl/sprite_atlas.dart';
part 'impl/atlas_parser.dart';
part 'impl/texture_packer_parser.dart';
part 'impl/aseprite_parser.dart';
part 'impl/grid_sheet_parser.dart';
part 'impl/atlas_asset.dart';
part 'impl/atlas_region_sprite.dart';

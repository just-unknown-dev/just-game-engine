/// How a `RenderSystem` batches what it draws: sprites, plain shapes, and
/// what is drawn through a 2-D material.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:just_game_engine_formats/just_game_engine_formats.dart'
    show Material2DKind;
import 'package:meta/meta.dart' show internal;

import '../../ecs/ecs.dart';
import 'materials/material_2d_batch.dart';
import 'materials/material_2d_component.dart';
import 'materials/material_2d_library.dart';
import 'materials/material_2d_shapes.dart';
import 'shapes/circle_2d_component.dart';
import 'shapes/rectangle_2d_component.dart';
import 'shapes/shape_2d_look.dart';
import '../../interfaces/rendering_interfaces.dart';
import '../../rendering/renderable.dart';
import '../../rendering/renderable_component.dart';
import '../../rendering/sprite.dart';
import '../../rendering/sprite_batch.dart';
import '../../rendering/sprite_batching.dart';
import 'render_queue.dart';
import 'shape_batch.dart';

/// What a frame of a `RenderSystem` drew, counted as it draws.
@internal
final class RenderCounts {
  /// Canvas draws, a batch as one.
  int drawCalls = 0;

  /// Things drawn — renderables, render items, particle emitters; a batched
  /// sprite or shape as one.
  int rendered = 0;

  /// Renderables skipped as hidden or off screen.
  int culled = 0;

  /// Sprites drawn in batches.
  int batchedSprites = 0;

  /// Back to nothing, for a new frame.
  void reset() => drawCalls = rendered = culled = batchedSprites = 0;
}

/// The batches a `RenderSystem` queues what it draws into, in draw order:
/// sprites by image, plain rectangles and circles, and what is drawn
/// through a 2-D material.
///
/// At most one kind is queued at a time, and only under one draw key
/// (layer, zOrder, sub-order): anything else draws what is queued first,
/// so batching never reorders what the layers say — a sprite on the
/// background still draws under a tile layer in front of it.
@internal
final class RenderBatcher {
  /// Batches counted into [counts]; sprite batches made by [factory], or the
  /// built-in [SpriteBatch] when null.
  RenderBatcher(this.counts, SpriteBatchFactory? factory)
    : _spriteBatches = SpriteBatchCache(factory);

  /// Where what is drawn is counted.
  final RenderCounts counts;

  /// Sprite batches by atlas image — the image object itself, not a hash of
  /// it — then by filter quality. A batch not used in a frame is dropped at
  /// its end, so an image the level no longer shows is not held.
  final SpriteBatchCache _spriteBatches;

  /// The batch holding sprites not drawn yet — at most one: a sprite from
  /// another image draws what is queued first, so batching never reorders.
  final List<SpriteBatchRenderer> _pendingSprites = [];

  /// Reused to work out how each sprite is batched.
  final SpriteBatchPlan _plan = SpriteBatchPlan();

  final ShapeBatch _shapeBatch = ShapeBatch();

  /// Sprites drawn through a 2-D material ([Material2DComponent]), queued;
  /// made with the world's library the first time one is drawn.
  Material2DBatch? _materialBatch;

  /// Shapes drawn through a 2-D material, each drawn into an image.
  final ShapeSheets shapeSheets = ShapeSheets();

  /// How big a world unit is on screen this frame (the camera's zoom): what
  /// a shape drawn into an image is drawn at.
  double? _canvasScale;

  /// Seconds into the game this frame, for what moves in a 2-D material.
  double _time = 0;

  /// Counts frames, for [lookOf].
  int _frame = 0;

  /// The draw key of what the pending batches hold.
  int _batchLayer = 0, _batchZ = 0, _batchSub = 0;

  /// How many sprite batches are kept — one per image and filter quality
  /// drawn in the last frame.
  int get spriteBatchCount => _spriteBatches.length;

  /// Starts a frame drawn [time] seconds into the game.
  void beginFrame(double time) {
    _time = time;
    _frame++;
    _spriteBatches.beginFrame();
    _materialBatch?.beginFrame();
    shapeSheets.beginFrame();
    _canvasScale = null;
  }

  /// Ends the frame: what it did not draw with is let go.
  void endFrame() => _spriteBatches.endFrame();

  /// Drops every batch and sheet.
  void clear() {
    _spriteBatches.clear();
    _pendingSprites.clear();
    _shapeBatch.clear();
    _materialBatch?.dispose();
    _materialBatch = null;
    shapeSheets.clear();
  }

  /// How big a world unit is on [canvas] this frame — its transform's
  /// scale, read once a frame, when a shape needs it (a canvas that cannot
  /// say is taken as unscaled).
  double scaleOf(Canvas canvas) {
    final known = _canvasScale;
    if (known != null) return known;
    double scale;
    try {
      final m = canvas.getTransform();
      scale = math.sqrt(m[0] * m[0] + m[1] * m[1]);
    } on Object {
      scale = 1;
    }
    return _canvasScale = scale > 0 ? scale : 1;
  }

  /// What [entry]'s component looks like: a shape drawn into an image is
  /// drawn again when it changes. A built-in shape says so cheaply
  /// ([Shape2DLook]); anything else is compared as saved by [definitions],
  /// worked out once a frame — one with no definition is drawn again every
  /// frame.
  Object lookOf(RenderEntry entry, ComponentDefinitionRegistry definitions) {
    final component = entry.renderComp!;
    if (component case final Shape2DLook shape) return shape.look;
    if (entry.lookFrame == _frame) return entry.look!;
    Object look;
    try {
      final saved = definitions.encode(component);
      look = saved != null ? jsonEncode(saved) : Object();
    } on Object {
      look = Object();
    }
    entry
      ..look = look
      ..lookFrame = _frame;
    return look;
  }

  /// [renderable] — a shape — drawn into an image at [canvas]'s scale times
  /// its own (see [ShapeSheets]); null when it cannot be.
  ShapeSheet? sheetOf(
    Canvas canvas,
    RenderEntry entry,
    Renderable renderable,
    Object look,
  ) {
    final scale = math.max(renderable.scale.x.abs(), renderable.scale.y.abs());
    return shapeSheets.sheetOf(
      entry.entity,
      renderable,
      look,
      scaleOf(canvas) * scale,
    );
  }

  bool _sameKey(RenderEntry e) =>
      e.layerKey == _batchLayer && e.zKey == _batchZ && e.sub == _batchSub;

  void _setKey(RenderEntry e) {
    _batchLayer = e.layerKey;
    _batchZ = e.zKey;
    _batchSub = e.sub;
  }

  /// Draws every sprite batched so far.
  ///
  /// Called before anything that is not batched and whenever the draw key
  /// changes, so batching never reorders what the layers say.
  void flushSprites(Canvas canvas) {
    if (_pendingSprites.isEmpty) return;
    for (final batch in _pendingSprites) {
      batch.flush(canvas);
      counts.drawCalls++;
    }
    _pendingSprites.clear();
  }

  void _flushShapes(Canvas canvas) {
    if (_shapeBatch.isEmpty) return;
    _shapeBatch.flush(canvas);
    counts.drawCalls++;
  }

  /// Draws the sprites queued through a 2-D material.
  void _flushMaterial(Canvas canvas) {
    final batch = _materialBatch;
    if (batch == null || batch.isEmpty) return;
    batch.flush(canvas, _time);
    counts.drawCalls++;
  }

  /// Draws everything batched.
  void flush(Canvas canvas) {
    flushSprites(canvas);
    _flushMaterial(canvas);
    _flushShapes(canvas);
  }

  /// Queues [renderable] — of an entity with a [Material2DComponent] — to be
  /// drawn through its material with the others sharing it; false when it
  /// must be drawn as it is: its material not read yet (or broken, or for
  /// the screen), the shader not loaded, nothing to draw it from.
  ///
  /// A sprite is drawn from its sheet; anything else that draws itself
  /// around its origin — a shape — is drawn once into an image first
  /// ([ShapeSheets]), kept while it looks the same ([lookOf]), and its
  /// material's lengths are measured in the world, whatever resolution the
  /// image was drawn at.
  bool addMaterial(
    Canvas canvas,
    RenderEntry entry,
    Renderable renderable,
    Material2DComponent material,
    Material2DLibrary library,
    ComponentDefinitionRegistry definitions,
  ) {
    final file = library.fileOf(material.material);
    if (library.program == null ||
        file == null ||
        file.kind != Material2DKind.sprite) {
      return false;
    }
    final ui.Image image;
    final FilterQuality quality;
    ShapeSheet? sheet;
    if (renderable is Sprite) {
      final own = renderable.image;
      if (own == null) return false;
      image = own;
      quality = renderable.filterQuality;
    } else {
      sheet = sheetOf(canvas, entry, renderable, lookOf(entry, definitions));
      if (sheet == null) return false;
      image = sheet.image;
      quality = FilterQuality.medium;
    }
    final unitScale = sheet?.resolution ?? 1.0;
    final batch = _materialBatch ??= Material2DBatch(library);
    // Plain sprites and shapes queued before it draw first, and so do
    // material sprites under another key or of another material or sheet.
    flushSprites(canvas);
    _flushShapes(canvas);
    if (!batch.isEmpty &&
        (!_sameKey(entry) ||
            !batch.accepts(
              material.material,
              image,
              quality,
              unitScale: unitScale,
            ))) {
      _flushMaterial(canvas);
    }
    final seed = entry.entity.id;
    bool add() {
      if (batch.isEmpty) {
        batch.begin(
          material.material,
          file,
          image,
          quality,
          unitScale: unitScale,
        );
      }
      if (sheet == null) {
        return batch.addSprite(
          renderable as Sprite,
          seed: seed,
          overrides: material.overrides,
        );
      }
      return batch.addBox(
        sheet.frame,
        sheet.bounds,
        x: renderable.position.x,
        y: renderable.position.y,
        rotation: renderable.rotation,
        scaleX: renderable.scale.x,
        scaleY: renderable.scale.y,
        tint: renderable.tint,
        opacity: renderable.opacity,
        seed: seed,
        overrides: material.overrides,
      );
    }

    if (!add()) {
      if (batch.isEmpty) return false;
      _flushMaterial(canvas);
      if (!add()) return false;
    }
    _setKey(entry);
    counts.rendered++;
    return true;
  }

  /// Queues [renderable] into a sprite batch; false when it must be drawn
  /// by itself. See [SpriteBatchPlan.plan] for which sprites batch.
  bool addSprite(Canvas canvas, RenderEntry entry, Renderable renderable) {
    final plan = _plan;
    if (!plan.plan(renderable, mirrors: _spriteBatches.mirrors)) return false;
    if (!_shapeBatch.isEmpty ||
        !(_materialBatch?.isEmpty ?? true) ||
        !_sameKey(entry)) {
      flush(canvas);
    }
    _setKey(entry);
    final batch = _spriteBatches.batchFor(plan.image!, plan.quality);
    // Only the newest batch takes more: joining an older one would draw
    // this sprite under what another image's batch queued since.
    if (_pendingSprites.isEmpty || !identical(_pendingSprites.last, batch)) {
      flushSprites(canvas);
      _pendingSprites.add(batch);
    }
    plan.addTo(batch);
    counts
      ..rendered += 1
      ..batchedSprites += 1;
    return true;
  }

  /// Queues the shape [comp] draws into the shape batch; false when it must
  /// be drawn by itself.
  bool addShape(
    Canvas canvas,
    RenderEntry entry,
    RenderableComponent comp,
    Renderable renderable,
  ) {
    if (comp is! Rectangle2DComponent && comp is! Circle2DComponent) {
      return false;
    }
    // Sprites queued before this shape, or shapes under another key, draw
    // first: a batch never moves anything ahead of what came before it.
    if (_pendingSprites.isNotEmpty ||
        !(_materialBatch?.isEmpty ?? true) ||
        (!_shapeBatch.isEmpty && !_sameKey(entry))) {
      flush(canvas);
    }
    if (!_shapeBatch.tryAdd(comp, renderable)) return false;
    _setKey(entry);
    counts.rendered++;
    return true;
  }
}

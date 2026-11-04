/// Adding up what drawing a frame cost, across everything that draws it.
library;

/// Something that adds up what a frame's drawing cost: `RenderingEngine`,
/// whose `stats` then count the ECS world's drawing along with its own.
///
/// A drawer that is not the rendering engine itself — the ECS
/// `RenderSystem` — reports what it drew each time it draws, and the
/// engine folds that into the frame it is drawing. What is reported
/// outside a frame of the engine's is dropped when its next frame starts.
abstract interface class RenderStatsSink {
  /// Adds one draw's counts to the frame being drawn: [drawCalls] canvas
  /// draws (a batch is one), [renderedObjects] things drawn (a batched
  /// sprite is one), [culledObjects] skipped as hidden or off screen, of
  /// which none were drawn, and [batchedSprites] sprites drawn in batches.
  void addFrameStats({
    int drawCalls = 0,
    int renderedObjects = 0,
    int culledObjects = 0,
    int batchedSprites = 0,
  });
}

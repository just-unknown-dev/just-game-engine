/// Game Camera Controls widget
///
/// A Flutter widget that overlays zoom controls on top of any child widget
/// (typically a [GameWidget]) and wires them to a [Camera].
///
/// **Performance design**
///
/// Camera mutations are applied directly to [camera] — no [State.setState] is
/// ever called on the game child.  [GameWidget] already repaints itself every
/// vsync frame through its own [Ticker] + `_repaintNotifier` mechanism, so it
/// picks up the updated [Camera.zoom] automatically.
///
/// Only the small button-column overlay is rebuilt, and only when the zoom
/// value actually changes, via a scoped [ValueListenableBuilder].
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'camera_system.dart';

/// A widget that wraps [child] with scroll-wheel and on-screen +/− zoom
/// controls that operate a [Camera] without rebuilding the child.
///
/// ```dart
/// GameCameraControls(
///   camera: engine.rendering.camera,
///   child: GameWidget(engine: engine),
/// )
/// ```
class GameCameraControls extends StatefulWidget {
  const GameCameraControls({
    super.key,
    required this.camera,
    required this.child,
    this.zoomStep = 0.1,
    this.scrollZoomFactor = 0.1,
    this.showZoomLevel = false,
  });

  /// The [Camera] whose [Camera.zoom] is controlled.
  final Camera camera;

  /// Child widget — never rebuilt when zoom changes.
  final Widget child;

  /// Zoom delta applied each time the +/− buttons are tapped.
  final double zoomStep;

  /// Zoom delta applied per scroll unit (mouse-wheel / trackpad).
  final double scrollZoomFactor;

  /// When `true`, displays the current zoom level between the +/− buttons.
  final bool showZoomLevel;

  @override
  State<GameCameraControls> createState() => _GameCameraControlsState();
}

class _GameCameraControlsState extends State<GameCameraControls> {
  /// Notifier scoped to the button overlay only.
  ///
  /// The game canvas is [Positioned.fill] and located **outside** the
  /// [ValueListenableBuilder], so it is never involved in button repaints.
  late final ValueNotifier<double> _zoomNotifier;

  /// Unique `heroTag` objects per widget instance to prevent Hero transition
  /// conflicts when multiple [GameCameraControls] widgets exist in the tree.
  final Object _heroIn = Object();
  final Object _heroOut = Object();

  @override
  void initState() {
    super.initState();
    _zoomNotifier = ValueNotifier<double>(widget.camera.zoom);
  }

  @override
  void dispose() {
    _zoomNotifier.dispose();
    super.dispose();
  }

  /// Applies [newZoom] to the camera and notifies the button overlay.
  ///
  /// Does **not** call [setState]; the game canvas picks up the change on its
  /// next Ticker frame without any Flutter rebuild.
  void _applyZoom(double newZoom) {
    widget.camera.setZoom(newZoom);
    // camera.setZoom clamps to [minZoom, maxZoom] — read back the clamped value.
    _zoomNotifier.value = widget.camera.zoom;
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final dy = event.scrollDelta.dy;
    if (dy == 0) return;
    _applyZoom(
      widget.camera.zoom + widget.scrollZoomFactor * (dy > 0 ? -1.0 : 1.0),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: _handlePointerSignal,
      child: Stack(
        children: [
          // ── Game content ──────────────────────────────────────────────
          // Placed at top of Stack so it is laid out / painted first.
          // Zoom changes never touch this subtree.
          Positioned.fill(child: widget.child),

          // ── Zoom button overlay ───────────────────────────────────────
          // Only this tiny Column rebuilds when zoom changes.
          Positioned(
            right: 16,
            bottom: 16,
            child: ValueListenableBuilder<double>(
              valueListenable: _zoomNotifier,
              builder: (_, zoom, __) => _ZoomButtons(
                zoom: zoom,
                minZoom: widget.camera.minZoom,
                maxZoom: widget.camera.maxZoom,
                showZoomLevel: widget.showZoomLevel,
                heroIn: _heroIn,
                heroOut: _heroOut,
                onZoomIn: () => _applyZoom(zoom + widget.zoomStep),
                onZoomOut: () => _applyZoom(zoom - widget.zoomStep),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Stateless button column — rebuilt only via [ValueListenableBuilder].
class _ZoomButtons extends StatelessWidget {
  const _ZoomButtons({
    required this.zoom,
    required this.minZoom,
    required this.maxZoom,
    required this.showZoomLevel,
    required this.heroIn,
    required this.heroOut,
    required this.onZoomIn,
    required this.onZoomOut,
  });

  final double zoom;
  final double minZoom;
  final double maxZoom;
  final bool showZoomLevel;
  final Object heroIn;
  final Object heroOut;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  @override
  Widget build(BuildContext context) {
    final atMax = zoom >= maxZoom;
    final atMin = zoom <= minZoom;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton.small(
          heroTag: heroIn,
          onPressed: atMax ? null : onZoomIn,
          tooltip: 'Zoom in',
          child: const Icon(Icons.add),
        ),
        if (showZoomLevel) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${zoom.toStringAsFixed(1)}x',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
        const SizedBox(height: 10),
        FloatingActionButton.small(
          heroTag: heroOut,
          onPressed: atMin ? null : onZoomOut,
          tooltip: 'Zoom out',
          child: const Icon(Icons.remove),
        ),
      ],
    );
  }
}

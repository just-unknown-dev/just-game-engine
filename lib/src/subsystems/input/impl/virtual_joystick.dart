part of '../input_management.dart';

/// Joystick placement behavior.
enum JoystickVariant {
  /// Base stays visible at a fixed anchor.
  fixed,

  /// Base appears where the user starts dragging.
  floating,
}

/// Axis constraint mode.
enum JoystickAxis {
  /// Two-dimensional movement.
  both,

  /// Only horizontal movement.
  horizontal,

  /// Only vertical movement.
  vertical,
}

/// A reusable virtual joystick widget for touch controls.
///
/// Emits normalized direction values in the range [-1, 1] on each axis.
class VirtualJoystick extends StatefulWidget {
  const VirtualJoystick({
    super.key,
    required this.onDirectionChanged,
    this.variant = JoystickVariant.floating,
    this.axis = JoystickAxis.both,
    this.radius = 64,
    this.deadZone = 8,
    this.fixedAlignment = const Alignment(-0.75, 0.70),
    this.activeOpacity = 1.0,
    this.inactiveOpacity = 0.0,
    this.showWhenInactive = false,
    this.baseColor = Colors.white,
    this.thumbColor = const Color(0xFFEA80FC),
  });

  /// Callback for joystick direction changes.
  final ValueChanged<Offset> onDirectionChanged;

  /// Fixed base or floating base behavior.
  final JoystickVariant variant;

  /// Axis lock mode.
  final JoystickAxis axis;

  /// Radius of the joystick base in logical pixels.
  final double radius;

  /// Dead zone radius in logical pixels around the center.
  final double deadZone;

  /// Fixed-base anchor alignment when [variant] is [JoystickVariant.fixed].
  final Alignment fixedAlignment;

  /// Opacity when actively dragging.
  final double activeOpacity;

  /// Opacity when not dragging.
  final double inactiveOpacity;

  /// Whether fixed joystick should remain visible when inactive.
  final bool showWhenInactive;

  /// Base ring color.
  final Color baseColor;

  /// Thumb color.
  final Color thumbColor;

  @override
  State<VirtualJoystick> createState() => _VirtualJoystickState();
}

class _VirtualJoystickState extends State<VirtualJoystick> {
  int? _pointerId;
  Offset _base = Offset.zero;
  Offset _thumb = Offset.zero;
  bool _active = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.variant == JoystickVariant.fixed) {
      _syncFixedBase();
    }
  }

  @override
  void didUpdateWidget(covariant VirtualJoystick oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.variant == JoystickVariant.fixed && !_active) {
      _syncFixedBase();
    }
  }

  void _syncFixedBase() {
    final size = context.size;
    if (size == null || size == Size.zero) return;

    final center = widget.fixedAlignment.alongSize(size);
    _base = center;
    _thumb = center;
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_pointerId != null) return;

    _pointerId = event.pointer;
    if (widget.variant == JoystickVariant.floating) {
      _base = event.localPosition;
      _thumb = event.localPosition;
    } else {
      _syncFixedBase();
      _thumb = _base;
      _updateDirection(event.localPosition - _base);
    }

    _active = true;
    setState(() {});
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _pointerId) return;

    final delta = event.localPosition - _base;
    final distance = delta.distance;
    final clamped = distance > widget.radius
        ? delta / distance * widget.radius
        : delta;

    _thumb = _base + clamped;
    _updateDirection(delta);
    setState(() {});
  }

  void _onPointerUp(PointerEvent event) {
    if (event.pointer != _pointerId) return;

    _pointerId = null;
    _active = false;
    widget.onDirectionChanged(Offset.zero);

    if (widget.variant == JoystickVariant.fixed) {
      _syncFixedBase();
      _thumb = _base;
    }

    setState(() {});
  }

  void _updateDirection(Offset delta) {
    if (delta.distance <= widget.deadZone) {
      widget.onDirectionChanged(Offset.zero);
      return;
    }

    final normalized = Offset(
      (delta.dx / widget.radius).clamp(-1.0, 1.0),
      (delta.dy / widget.radius).clamp(-1.0, 1.0),
    );

    switch (widget.axis) {
      case JoystickAxis.both:
        widget.onDirectionChanged(normalized);
      case JoystickAxis.horizontal:
        widget.onDirectionChanged(Offset(normalized.dx, 0));
      case JoystickAxis.vertical:
        widget.onDirectionChanged(Offset(0, normalized.dy));
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible =
        _active ||
        (widget.variant == JoystickVariant.fixed && widget.showWhenInactive);

    final opacity = _active ? widget.activeOpacity : widget.inactiveOpacity;
    final paintOpacity = visible ? opacity : 0.0;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerUp,
      child: IgnorePointer(
        child: CustomPaint(
          painter: _VirtualJoystickPainter(
            base: _base,
            thumb: _thumb,
            radius: widget.radius,
            opacity: paintOpacity,
            baseColor: widget.baseColor,
            thumbColor: widget.thumbColor,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _VirtualJoystickPainter extends CustomPainter {
  const _VirtualJoystickPainter({
    required this.base,
    required this.thumb,
    required this.radius,
    required this.opacity,
    required this.baseColor,
    required this.thumbColor,
  });

  final Offset base;
  final Offset thumb;
  final double radius;
  final double opacity;
  final Color baseColor;
  final Color thumbColor;

  // Cached paints — static because the class is recreated each build.
  static final Paint _baseFillPaint = Paint();
  static final Paint _baseStrokePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;
  static final Paint _thumbPaint = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0) return;

    final safeOpacity = opacity.clamp(0.0, 1.0);

    _baseFillPaint.color = baseColor.withValues(alpha: 0.12 * safeOpacity);
    canvas.drawCircle(base, radius, _baseFillPaint);

    _baseStrokePaint.color = baseColor.withValues(alpha: 0.30 * safeOpacity);
    canvas.drawCircle(base, radius, _baseStrokePaint);

    final maxThumbDistance = radius;
    final delta = thumb - base;
    final clampedThumb = delta.distance > maxThumbDistance
        ? base + delta / delta.distance * maxThumbDistance
        : thumb;

    _thumbPaint.color = thumbColor.withValues(alpha: 0.88 * safeOpacity);
    canvas.drawCircle(clampedThumb, radius * 0.38, _thumbPaint);
  }

  @override
  bool shouldRepaint(covariant _VirtualJoystickPainter oldDelegate) {
    return oldDelegate.base != base ||
        oldDelegate.thumb != thumb ||
        oldDelegate.radius != radius ||
        oldDelegate.opacity != opacity ||
        oldDelegate.baseColor != baseColor ||
        oldDelegate.thumbColor != thumbColor;
  }
}

/// Default dialogue box widget.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/dialogue_line.dart';
import '../runtime/dialogue_runner.dart';

// ---------------------------------------------------------------------------
// DialogueBoxWidget
// ---------------------------------------------------------------------------

/// A ready-to-use dialogue box that renders the current [DialogueLine] from
/// a [DialogueRunner] with an optional typewriter animation.
///
/// Place this in a `Stack`, `Overlay`, or `Positioned` widget above your
/// game canvas:
///
/// ```dart
/// Stack(
///   children: [
///     GameWidget(game: myGame),
///     Positioned(
///       left: 16, right: 16, bottom: 16,
///       child: DialogueBoxWidget(
///         runner: runner,
///         onTap: runner.advance,
///         portraitBuilder: (char) => CharacterPortrait(name: char),
///       ),
///     ),
///   ],
/// )
/// ```
///
/// **Tapping behaviour**
/// * First tap while typewriter is running → instantly reveals the full text.
/// * Second tap (or first tap when typewriter is done) → calls [onTap]
///   (typically `runner.advance`).
class DialogueBoxWidget extends StatefulWidget {
  /// A box showing [runner]'s current line, 160 px high with 16 px of
  /// padding, typing it out at 40 characters a second, over a translucent
  /// black rounded box unless [boxDecoration] is given.
  const DialogueBoxWidget({
    super.key,
    required this.runner,
    this.onTap,
    this.boxDecoration,
    this.characterNameStyle,
    this.textStyle,
    this.typewriterSpeed = 40.0,
    this.showContinueIndicator = true,
    this.portraitBuilder,
    this.padding = const EdgeInsets.all(16),
    this.height = 160,
    this.continueIndicator,
  });

  /// The runner whose lines are shown. The box starts listening when it is
  /// first built, so it shows the lines presented after that. A different
  /// runner passed in on a rebuild takes over at once: the box stops
  /// listening to the old one and shows the new one's current line.
  final DialogueRunner runner;

  /// Callback invoked when the player taps to advance (after typewriter
  /// finishes).  Typically `runner.advance`.
  final VoidCallback? onTap;

  /// Background / border decoration for the dialogue box.
  final BoxDecoration? boxDecoration;

  /// Style for the character name heading.
  final TextStyle? characterNameStyle;

  /// Style for the body text.
  final TextStyle? textStyle;

  /// Characters per second for the typewriter effect.  Set to `0` to disable.
  final double typewriterSpeed;

  /// Whether to show a blinking arrow / indicator when typewriter is done.
  final bool showContinueIndicator;

  /// Optional portrait widget factory.  Receives the current speaker name.
  final Widget Function(String character)? portraitBuilder;

  /// Space between the box's edge and its contents; 16 px all round by
  /// default.
  final EdgeInsets padding;

  /// Fixed height of the dialogue box.
  final double height;

  /// Replace the default blinking-arrow indicator with your own widget.
  final Widget? continueIndicator;

  @override
  State<DialogueBoxWidget> createState() => _DialogueBoxWidgetState();
}

class _DialogueBoxWidgetState extends State<DialogueBoxWidget> {
  DialogueLine? _line;
  String _displayText = '';
  bool _typewriterDone = true;

  Timer? _timer;
  int _charIndex = 0;

  late final VoidCallback _lineSub;

  @override
  void initState() {
    super.initState();
    _lineSub = () => _onLineChanged(widget.runner.signals.currentLine.value);
    widget.runner.signals.currentLine.addListener(_lineSub);
  }

  @override
  void didUpdateWidget(DialogueBoxWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.runner, widget.runner)) return;
    oldWidget.runner.signals.currentLine.removeListener(_lineSub);
    widget.runner.signals.currentLine.addListener(_lineSub);
    _onLineChanged(widget.runner.signals.currentLine.value);
  }

  @override
  void dispose() {
    widget.runner.signals.currentLine.removeListener(_lineSub);
    _timer?.cancel();
    super.dispose();
  }

  void _onLineChanged(DialogueLine? line) {
    if (!mounted) return;
    _timer?.cancel();
    setState(() {
      _line = line;
      _displayText = '';
      _charIndex = 0;
      _typewriterDone = line == null;
    });

    if (line == null) return;

    if (widget.typewriterSpeed > 0) {
      _startTypewriter(line.text);
    } else {
      setState(() {
        _displayText = line.text;
        _typewriterDone = true;
      });
    }
  }

  void _startTypewriter(String text) {
    // Where each character the reader sees ends — an emoji or an accented
    // letter can be several UTF-16 units, never to be cut in two.
    final ends = <int>[];
    var offset = 0;
    for (final character in text.characters) {
      offset += character.length;
      ends.add(offset);
    }
    final intervalMs = (1000.0 / widget.typewriterSpeed).round();
    _timer = Timer.periodic(Duration(milliseconds: intervalMs), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      _charIndex++;
      if (_charIndex >= ends.length) {
        t.cancel();
        setState(() {
          _displayText = text;
          _typewriterDone = true;
        });
      } else {
        setState(() => _displayText = text.substring(0, ends[_charIndex - 1]));
      }
    });
  }

  void _handleTap() {
    if (!_typewriterDone) {
      // Skip typewriter → reveal full text immediately
      _timer?.cancel();
      setState(() {
        _displayText = _line?.text ?? '';
        _typewriterDone = true;
      });
    } else {
      widget.onTap?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Hide completely when there is no active line
    return ValueListenableBuilder<bool>(
      valueListenable: widget.runner.signals.isDialogueActive,
      builder: (context, active, _) {
        if (!active || _line == null) return const SizedBox.shrink();
        return _buildBox(context);
      },
    );
  }

  Widget _buildBox(BuildContext context) {
    final decoration =
        widget.boxDecoration ??
        BoxDecoration(
          color: Colors.black.withAlpha(217),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white24),
        );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _handleTap,
      child: Container(
        height: widget.height,
        decoration: decoration,
        padding: widget.padding,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Portrait
            if (_line!.character != null && widget.portraitBuilder != null) ...[
              widget.portraitBuilder!(_line!.character!),
              const SizedBox(width: 12),
            ],
            // Text column
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Character name
                  if (_line!.character != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        _line!.character!,
                        style:
                            widget.characterNameStyle ??
                            const TextStyle(
                              color: Colors.amber,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                      ),
                    ),
                  // Body text
                  Expanded(
                    child: Text(
                      _displayText,
                      style:
                          widget.textStyle ??
                          const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            height: 1.4,
                          ),
                    ),
                  ),
                  // Continue indicator
                  if (widget.showContinueIndicator && _typewriterDone)
                    Align(
                      alignment: Alignment.bottomRight,
                      child: widget.continueIndicator ?? const _BlinkingArrow(),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _BlinkingArrow  (default continue indicator)
// ---------------------------------------------------------------------------

class _BlinkingArrow extends StatefulWidget {
  const _BlinkingArrow();

  @override
  State<_BlinkingArrow> createState() => _BlinkingArrowState();
}

class _BlinkingArrowState extends State<_BlinkingArrow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    _fade = Tween<double>(begin: 0.25, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: const Icon(
        Icons.keyboard_arrow_down_rounded,
        color: Colors.white70,
        size: 20,
      ),
    );
  }
}

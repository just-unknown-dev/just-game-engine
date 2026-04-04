/// Player choice list widget for the dialogue system.
library;

import 'package:flutter/material.dart';

import '../core/dialogue_choice.dart';
import '../runtime/dialogue_runner.dart';

// ---------------------------------------------------------------------------
// DialogueChoicesWidget
// ---------------------------------------------------------------------------

/// Displays the current set of [DialogueChoice]s and calls
/// [DialogueRunner.selectChoice] when the player taps one.
///
/// Place this above [DialogueBoxWidget] in your stack:
///
/// ```dart
/// Stack(
///   children: [
///     GameWidget(...),
///     Positioned(
///       left: 16, right: 16, bottom: 180,
///       child: DialogueChoicesWidget(runner: runner),
///     ),
///     Positioned(
///       left: 16, right: 16, bottom: 16,
///       child: DialogueBoxWidget(runner: runner, onTap: runner.advance),
///     ),
///   ],
/// )
/// ```
///
/// Unavailable choices ([DialogueChoice.isAvailable] == `false`) are shown
/// greyed-out and are not tappable.  Override [unavailableStyle] to change
/// this.
class DialogueChoicesWidget extends StatelessWidget {
  const DialogueChoicesWidget({
    super.key,
    required this.runner,
    this.choiceStyle,
    this.unavailableStyle,
    this.backgroundColor = Colors.black54,
    this.selectedColor = const Color(0xFF1E3A5F),
    this.borderRadius = 6.0,
    this.spacing = 6.0,
    this.showUnavailable = true,
  });

  final DialogueRunner runner;

  /// Text style for available choices.
  final TextStyle? choiceStyle;

  /// Text style for unavailable choices (greyed-out by default).
  final TextStyle? unavailableStyle;

  final Color backgroundColor;

  /// Background highlight when hovered / tapped.
  final Color selectedColor;

  final double borderRadius;

  /// Vertical gap between choice buttons.
  final double spacing;

  /// Whether to show (greyed-out) unavailable choices at all.
  final bool showUnavailable;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<DialogueChoice>>(
      valueListenable: runner.signals.choices,
      builder: (context, choices, _) {
        final visible = showUnavailable
            ? choices
            : choices.where((c) => c.isAvailable).toList();

        if (visible.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: visible
              .map(
                (choice) => Padding(
                  padding: EdgeInsets.only(bottom: spacing),
                  child: _ChoiceButton(
                    choice: choice,
                    onSelect: () => runner.selectChoice(choice.index),
                    choiceStyle: choiceStyle,
                    unavailableStyle: unavailableStyle,
                    backgroundColor: backgroundColor,
                    selectedColor: selectedColor,
                    borderRadius: borderRadius,
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// _ChoiceButton
// ---------------------------------------------------------------------------

class _ChoiceButton extends StatefulWidget {
  const _ChoiceButton({
    required this.choice,
    required this.onSelect,
    required this.backgroundColor,
    required this.selectedColor,
    required this.borderRadius,
    this.choiceStyle,
    this.unavailableStyle,
  });

  final DialogueChoice choice;
  final VoidCallback onSelect;
  final TextStyle? choiceStyle;
  final TextStyle? unavailableStyle;
  final Color backgroundColor;
  final Color selectedColor;
  final double borderRadius;

  @override
  State<_ChoiceButton> createState() => _ChoiceButtonState();
}

class _ChoiceButtonState extends State<_ChoiceButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressCtrl;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
    );
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final available = widget.choice.isAvailable;

    final defaultStyle = TextStyle(
      color: available ? Colors.white : Colors.white38,
      fontSize: 15,
    );
    final textStyle = available
        ? (widget.choiceStyle ?? defaultStyle)
        : (widget.unavailableStyle ??
              defaultStyle.copyWith(color: Colors.white38));

    return GestureDetector(
      onTapDown: available ? (_) => _pressCtrl.forward() : null,
      onTapUp: available
          ? (_) {
              _pressCtrl.reverse();
              widget.onSelect();
            }
          : null,
      onTapCancel: available ? () => _pressCtrl.reverse() : null,
      child: AnimatedBuilder(
        animation: _pressCtrl,
        builder: (context, child) {
          final bg = Color.lerp(
            widget.backgroundColor,
            widget.selectedColor,
            _pressCtrl.value,
          )!;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(widget.borderRadius),
              border: Border.all(
                color: available ? Colors.white24 : Colors.white12,
              ),
            ),
            child: child,
          );
        },
        child: Row(
          children: [
            Text('▸ ', style: textStyle),
            Expanded(child: Text(widget.choice.text, style: textStyle)),
          ],
        ),
      ),
    );
  }
}

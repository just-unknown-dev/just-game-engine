import 'package:flutter/material.dart';
import 'package:just_signals/just_signals.dart';

import 'subtitle_controller.dart';

/// Wraps [child] and overlays a subtitle panel driven by [controller].
///
/// The subtitle appears at the bottom of the stack and animates in/out
/// via [AnimatedSwitcher].  Only rebuilds when the active cue changes,
/// so frame-rate is unaffected during cue-stable periods.
class SubtitleOverlay extends StatelessWidget {
  const SubtitleOverlay({
    super.key,
    required this.controller,
    required this.child,
  });

  final SubtitleController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned(
          left: 24,
          right: 24,
          bottom: 48,
          child: SignalBuilder<String?>(
            signal: controller.currentText,
            builder: (context, text, _) {
              return AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: text != null && text.isNotEmpty
                    ? _SubtitlePill(key: ValueKey(text), text: text)
                    : const SizedBox.shrink(),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SubtitlePill extends StatelessWidget {
  const _SubtitlePill({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          height: 1.4,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.2,
          shadows: [Shadow(blurRadius: 4, color: Colors.black)],
        ),
      ),
    );
  }
}

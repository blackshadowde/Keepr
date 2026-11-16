// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:vibe/l10n/l10n.dart';
import 'package:vibe/vibe/buddy/vibe_buddy.dart';
import 'package:vibe/vibe/screens/chat/recording_view_model.dart';
import 'package:vibe/vibe/vibe_motion.dart';
import 'package:flutter/material.dart';

/// Recording a voice note: a pane over the text box in your colour theme.
/// A little stage shows the time, a mic and your voice as bars (Bujji
/// listens in its headphones); below, Cancel, pause or go on, and Send.
class RecordingInputRow extends StatelessWidget {
  final RecordingViewModelState state;
  final Future<void> Function(String, int, List<int>, String) onSend;
  const RecordingInputRow({
    required this.state,
    required this.onSend,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = L10n.of(context);
    final d = state.duration;
    final time = '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
    final live = !state.isPaused;
    Widget pill({
      required String tip,
      required Color bg,
      required VoidCallback onTap,
      required Widget child,
      bool glow = false,
    }) => Expanded(
      child: VibePressable(
        scale: 0.94,
        child: Tooltip(
          message: tip,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            height: 58,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(29),
              boxShadow: glow
                  ? [BoxShadow(color: bg.withValues(alpha: 0.28), spreadRadius: 5)]
                  : const [],
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: onTap,
                child: Center(child: child),
              ),
            ),
          ),
        ),
      ),
    );
    Widget label(IconData icon, String text, Color c) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: c, size: 22),
        const SizedBox(width: 8),
        Text(text, style: TextStyle(color: c, fontSize: 15.5, fontWeight: FontWeight.w700)),
      ],
    );
    // the pane rises in with a little spring
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutBack,
      builder: (context, v, child) => Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform.translate(offset: Offset(0, 28 * (1 - v)), child: child),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 150,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: RadialGradient(
                  center: const Alignment(0, 1.4),
                  radius: 1.3,
                  colors: [
                    Color.lerp(cs.primary, cs.surfaceContainerHigh, 0.8)!,
                    cs.surfaceContainerHigh,
                  ],
                ),
              ),
              child: Stack(
                children: [
                  // how long, with a dot that breathes while it records
                  Positioned(
                    top: 12,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        height: 30,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: cs.surface.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _Breathing(color: live ? cs.error : cs.outline, on: live),
                            const SizedBox(width: 8),
                            Text(
                              live ? time : 'Paused · $time',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: cs.onSurface,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // the mic, your voice as bars, Bujji listening
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 18,
                    child: Row(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: cs.surface,
                            shape: BoxShape.circle,
                            boxShadow: live
                                ? [BoxShadow(color: cs.primary.withValues(alpha: 0.18), spreadRadius: 8)]
                                : const [],
                          ),
                          child: Icon(Icons.mic_rounded, color: cs.onSurface, size: 28),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: LayoutBuilder(
                              builder: (context, box) {
                                const w = 4.0, gap = 3.0;
                                final n = (box.maxWidth / (w + gap)).floor();
                                final amps = state.amplitudeTimeline.reversed.take(n).toList().reversed.toList();
                                return Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    for (final a in amps)
                                      AnimatedContainer(
                                        duration: const Duration(milliseconds: 140),
                                        margin: const EdgeInsets.only(left: gap),
                                        width: w,
                                        height: 6 + 40 * (a / 100).clamp(0.0, 1.0),
                                        decoration: BoxDecoration(
                                          color: live ? cs.primary : cs.outline,
                                          borderRadius: BorderRadius.circular(w / 2),
                                        ),
                                      ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                        if (VibeBuddy.on) ...[
                          const SizedBox(width: 10),
                          VibeBuddyFace(
                            size: 50,
                            color: cs.primary,
                            mood: BuddyMood.happy,
                            prop: BuddyProp.headphones,
                            outfit: VibeBuddy.outfit,
                            gaze: -0.8,
                            look: 0.3,
                            floating: true,
                            groove: live ? 1 : 0,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                pill(
                  tip: l10n.cancel,
                  bg: cs.secondaryContainer,
                  onTap: state.cancel,
                  child: label(Icons.close_rounded, l10n.cancel, cs.onSecondaryContainer),
                ),
                const SizedBox(width: 10),
                pill(
                  tip: live ? l10n.pause : l10n.resume,
                  bg: cs.primary,
                  glow: live,
                  onTap: live ? state.pause : state.resume,
                  child: Icon(
                    live ? Icons.pause_rounded : Icons.mic_rounded,
                    color: cs.onPrimary,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 10),
                pill(
                  tip: l10n.sendAudio,
                  bg: cs.primaryContainer,
                  onTap: () => state.stopAndSend(onSend),
                  child: label(Icons.send_rounded, 'Send', cs.onPrimaryContainer),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A small dot that breathes while recording.
class _Breathing extends StatefulWidget {
  final Color color;
  final bool on;
  const _Breathing({required this.color, required this.on});

  @override
  State<_Breathing> createState() => _BreathingState();
}

class _BreathingState extends State<_Breathing> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, _) {
      final k = widget.on ? Curves.easeInOut.transform(_c.value) : 0.0;
      return Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: widget.color.withValues(alpha: 0.35 * k), spreadRadius: 4 * k)],
        ),
      );
    },
  );
}

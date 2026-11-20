// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:vibe/l10n/l10n.dart';
import 'package:vibe/vibe/buddy/vibe_buddy.dart';
import 'package:vibe/vibe/screens/chat/recording_view_model.dart';
import 'package:vibe/vibe/vibe_motion.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Recording a voice note: a pane over the text box in your colour theme.
/// A little stage shows the time, a mic and your voice as bars (Bujji
/// listens in its headphones); below, Cancel, Stop and Send. Stop lets you
/// listen back first, then Delete, Retake or Send.
class RecordingInputRow extends StatelessWidget {
  final RecordingViewModelState state;
  final Future<void> Function(String, int, List<int>, String) onSend;

  /// Throw the recording away and record again.
  final VoidCallback onAgain;
  const RecordingInputRow({
    required this.state,
    required this.onSend,
    required this.onAgain,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = L10n.of(context);
    final d = state.duration;
    final time = '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
    final review = state.reviewing;
    final live = !state.isPaused && !review;
    String fmt(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
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
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    transitionBuilder: (c, a) => FadeTransition(
                      opacity: a,
                      child: ScaleTransition(scale: Tween(begin: 0.8, end: 1.0).animate(a), child: c),
                    ),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    Widget label(IconData icon, String text, Color c) => Row(
      key: ValueKey(text),
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: c, size: 22),
        const SizedBox(width: 8),
        Text(text, style: TextStyle(color: c, fontSize: 15.5, fontWeight: FontWeight.w700)),
      ],
    );
    const tabular = [FontFeature.tabularFigures()];
    // the pane rises in and settles softly
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutQuart,
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
                  // how long; while listening back, how far it has played
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
                        child: review
                            ? ValueListenableBuilder<double>(
                                valueListenable: state.reviewAt,
                                builder: (context, at, _) => Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.headphones_rounded, size: 16, color: cs.primary),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${fmt(state.reviewLength * at)} / ${fmt(state.reviewLength)}',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: cs.onSurface,
                                        fontFeatures: tabular,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : Row(
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
                                      fontFeatures: tabular,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                  // pause or go on, out of the way in the corner
                  if (!review)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: VibePressable(
                        child: IconButton(
                          tooltip: live ? l10n.pause : l10n.resume,
                          style: IconButton.styleFrom(
                            backgroundColor: cs.surface.withValues(alpha: 0.8),
                            foregroundColor: cs.onSurface,
                          ),
                          onPressed: live ? state.pause : state.resume,
                          icon: Icon(live ? Icons.pause_rounded : Icons.mic_rounded, size: 20),
                        ),
                      ),
                    ),
                  // recording: the mic and your voice as bars; listening
                  // back: play, the whole note to tap or drag through
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 18,
                    child: Row(
                      children: [
                        if (review)
                          ValueListenableBuilder<bool>(
                            valueListenable: state.reviewPlaying,
                            builder: (context, playing, _) => VibePressable(
                              child: GestureDetector(
                                onTap: state.playReview,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 260),
                                  width: 52,
                                  height: 52,
                                  decoration: BoxDecoration(
                                    color: cs.primary,
                                    shape: BoxShape.circle,
                                    boxShadow: playing
                                        ? [BoxShadow(color: cs.primary.withValues(alpha: 0.25), spreadRadius: 7)]
                                        : const [],
                                  ),
                                  child: Icon(
                                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                    color: cs.onPrimary,
                                    size: 30,
                                  ),
                                ),
                              ),
                            ),
                          )
                        else
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
                                if (review) {
                                  final amps = _fit(state.amplitudeTimeline, n);
                                  double at(Offset o) => (o.dx / box.maxWidth).clamp(0.0, 1.0);
                                  return GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTapDown: (d) => state.seekReview(at(d.localPosition)),
                                    onHorizontalDragUpdate: (d) => state.reviewAt.value = at(d.localPosition),
                                    onHorizontalDragEnd: (_) => state.seekReview(state.reviewAt.value),
                                    child: ValueListenableBuilder<double>(
                                      valueListenable: state.reviewAt,
                                      builder: (context, played, _) => Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          for (var i = 0; i < amps.length; i++)
                                            AnimatedContainer(
                                              duration: const Duration(milliseconds: 160),
                                              width: w,
                                              height: 6 + 40 * (amps[i] / 100).clamp(0.0, 1.0),
                                              decoration: BoxDecoration(
                                                color: (i + 0.5) / amps.length <= played
                                                    ? cs.primary
                                                    : cs.primary.withValues(alpha: 0.28),
                                                borderRadius: BorderRadius.circular(w / 2),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  );
                                }
                                return _LiveWave(
                                  amps: state.amplitudeTimeline,
                                  live: live,
                                  color: live ? cs.primary : cs.outline,
                                );
                              },
                            ),
                          ),
                        ),
                        if (VibeBuddy.on) ...[
                          const SizedBox(width: 10),
                          // Bujji listens along, and sways while it plays back
                          ValueListenableBuilder<bool>(
                            valueListenable: state.reviewPlaying,
                            builder: (context, playing, _) => VibeBuddyFace(
                              size: 50,
                              color: cs.primary,
                              mood: BuddyMood.happy,
                              prop: BuddyProp.headphones,
                              outfit: VibeBuddy.outfit,
                              gaze: -0.8,
                              look: 0.3,
                              floating: true,
                              groove: live || playing ? 1 : 0,
                            ),
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
                  tip: review ? l10n.delete : l10n.cancel,
                  bg: cs.secondaryContainer,
                  onTap: state.cancel,
                  child: review
                      ? label(Icons.delete_outline_rounded, l10n.delete, cs.onSecondaryContainer)
                      : label(Icons.close_rounded, l10n.cancel, cs.onSecondaryContainer),
                ),
                const SizedBox(width: 10),
                pill(
                  tip: review ? 'Record again' : 'Stop to listen back',
                  bg: review ? cs.secondaryContainer : cs.primary,
                  glow: live,
                  onTap: () {
                    if (review) {
                      onAgain();
                    } else {
                      state.stopToReview();
                    }
                  },
                  child: review
                      ? label(Icons.replay_rounded, 'Retake', cs.onSecondaryContainer)
                      : label(Icons.stop_rounded, 'Stop', cs.onPrimary),
                ),
                const SizedBox(width: 10),
                pill(
                  tip: l10n.sendAudio,
                  bg: review ? cs.primary : cs.primaryContainer,
                  glow: review,
                  onTap: () => state.stopAndSend(onSend),
                  child: label(Icons.send_rounded, 'Send', review ? cs.onPrimary : cs.onPrimaryContainer),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// The whole recording as [n] bars.
  static List<double> _fit(List<double> a, int n) {
    if (n <= 0) return const [];
    if (a.isEmpty) return List.filled(n, 1.0);
    return [
      for (var i = 0; i < n; i++)
        () {
          final from = (i * a.length / n).floor();
          final to = (((i + 1) * a.length / n).ceil()).clamp(from + 1, a.length);
          var top = 0.0;
          for (var j = from; j < to; j++) {
            if (a[j] > top) top = a[j];
          }
          return top;
        }(),
    ];
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
  Widget build(BuildContext context) => RepaintBoundary(
    child: AnimatedBuilder(
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
    ),
  );
}

/// Your voice as bars gliding in from the right on every frame, instead of
/// jumping a step each time the microphone is read (10 times a second).
class _LiveWave extends StatefulWidget {
  final List<double> amps;
  final bool live;
  final Color color;
  const _LiveWave({required this.amps, required this.live, required this.color});

  @override
  State<_LiveWave> createState() => _LiveWaveState();
}

class _LiveWaveState extends State<_LiveWave> with SingleTickerProviderStateMixin {
  // how far the bars have moved, counted in bars; follows the readings
  final _pos = ValueNotifier<double>(0);
  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _pos.value = widget.amps.length.toDouble();
    _ticker.start();
  }

  @override
  void didUpdateWidget(_LiveWave old) {
    super.didUpdateWidget(old);
    if (widget.live && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void _tick(Duration now) {
    final dt = (now - _last).inMicroseconds / 1e6;
    _last = now;
    final n = widget.amps.length.toDouble();
    var p = math.min(_pos.value, n);
    // one bar per tenth of a second, a little quicker when behind
    if (n > p) p = math.min(n, p + dt * (n - p > 1.5 ? 16 : 10));
    if (n - p > 2) p = n - 2;
    _pos.value = p;
    // paused and caught up: rest until it records again
    if (!widget.live && p >= n) _ticker.stop();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _pos.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      size: Size.infinite,
      painter: _WavePainter(widget.amps, _pos, widget.color),
    ),
  );
}

class _WavePainter extends CustomPainter {
  final List<double> amps;
  final ValueNotifier<double> pos;
  final Color color;
  _WavePainter(this.amps, this.pos, this.color) : super(repaint: pos);

  @override
  void paint(Canvas canvas, Size size) {
    const w = 4.0, slot = 7.0, fade = 28.0;
    canvas.clipRect(Offset.zero & size);
    final p = pos.value;
    final paint = Paint();
    final mid = size.height / 2;
    for (var j = amps.length - 1; j >= 0; j--) {
      final age = p - j; // 1 and more: in place; below 1: still sliding in
      if (age <= 0) continue;
      final right = size.width - (age - 1) * slot;
      if (right < 0) break;
      final grow = Curves.easeOut.transform(age.clamp(0.0, 1.0));
      final h = (6 + 40 * (amps[j] / 100).clamp(0.0, 1.0)) * (0.35 + 0.65 * grow);
      // the oldest bars fade out at the left edge
      final a = (right / fade).clamp(0.0, 1.0);
      paint.color = color.withValues(alpha: color.a * a);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(right - w, mid - h / 2, w, h),
          const Radius.circular(w / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.color != color || !identical(old.amps, amps);
}

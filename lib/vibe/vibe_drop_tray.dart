// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:vibe/vibe/buddy/vibe_buddy.dart';

/// While photos or files are dragged over a chat: the text box rises into a
/// tray in the theme's colour, Bujji holds up a basket, and the tray says
/// where it goes and what it takes. Calm motion in, quicker out.
class VibeDropTray extends StatefulWidget {
  final bool show;
  final String name;
  const VibeDropTray({required this.show, required this.name, super.key});

  @override
  State<VibeDropTray> createState() => _VibeDropTrayState();
}

class _VibeDropTrayState extends State<VibeDropTray>
    with SingleTickerProviderStateMixin {
  late final AnimationController _in = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 640),
    reverseDuration: const Duration(milliseconds: 320),
    value: widget.show ? 1 : 0,
  );
  int _hop = 0;

  // slows down gently at the end, no bounce
  static const _calm = Cubic(0.22, 1, 0.36, 1);

  @override
  void didUpdateWidget(VibeDropTray old) {
    super.didUpdateWidget(old);
    if (widget.show == old.show) return;
    if (!widget.show) {
      _in.reverse();
      return;
    }
    _in.forward();
    // Bujji hops up as the tray arrives
    Future<void>.delayed(const Duration(milliseconds: 280), () {
      if (mounted && widget.show) setState(() => _hop++);
    });
  }

  @override
  void dispose() {
    _in.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ink = cs.onPrimaryContainer;
    return AnimatedBuilder(
      animation: _in,
      builder: (context, _) {
        final v = _in.value;
        if (v == 0) return const SizedBox.shrink();
        // each piece comes in over its own part of the motion
        double part(double a, double b) =>
            _calm.transform(((v - a) / (b - a)).clamp(0.0, 1.0));
        final bujji = VibeBuddy.on
            ? VibeBuddyFace(
                size: 64,
                color: cs.primary,
                mood: BuddyMood.happy,
                prop: BuddyProp.basket,
                outfit: VibeBuddy.outfit,
                look: 0.3,
                floating: true,
                hop: _hop,
              )
            : Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: cs.surface.withValues(alpha: 0.7),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.move_to_inbox_rounded,
                  size: 30,
                  color: cs.primary,
                ),
              );
        final words = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Drop here',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: ink,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'to ${widget.name}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14.5,
                color: ink.withValues(alpha: 0.75),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _chip(cs, Icons.photo_library_rounded, 'Photos and videos'),
                _chip(cs, Icons.insert_drive_file_rounded, 'Files'),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'You can add a caption before it goes',
              style: TextStyle(fontSize: 13, color: ink.withValues(alpha: 0.7)),
            ),
          ],
        );
        return IgnorePointer(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // the chat above stays readable, softly tinted towards the tray
              Opacity(
                opacity: part(0, 0.7),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.35, 1],
                      colors: [
                        cs.primary.withValues(alpha: 0),
                        cs.primary.withValues(alpha: 0.16),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 14,
                child: Transform.translate(
                  offset: Offset(0, 90 * (1 - part(0, 1))),
                  child: Opacity(
                    opacity: part(0, 0.45),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                            color: cs.primary.withValues(alpha: 0.22),
                            blurRadius: 32,
                            offset: const Offset(0, -8),
                          ),
                        ],
                      ),
                      child: CustomPaint(
                        painter: _Dashes(cs.primary.withValues(alpha: 0.5)),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Transform.translate(
                                offset: Offset(0, 24 * (1 - part(0.25, 1))),
                                child: Opacity(
                                  opacity: part(0.25, 0.75),
                                  child: bujji,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Transform.translate(
                                offset: Offset(0, 12 * (1 - part(0.35, 1))),
                                child: Opacity(
                                  opacity: part(0.35, 0.9),
                                  child: words,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static Widget _chip(ColorScheme cs, IconData icon, String label) =>
      Container(
        height: 34,
        padding: const EdgeInsets.only(left: 10, right: 12),
        decoration: BoxDecoration(
          color: cs.surface.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(17),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: cs.primary),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ],
        ),
      );
}

/// The dashed line inside the tray's edge.
class _Dashes extends CustomPainter {
  final Color color;
  const _Dashes(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final edge = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(10),
          const Radius.circular(22),
        ),
      );
    for (final m in edge.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 14) {
        canvas.drawPath(m.extractPath(d, math.min(d + 8, m.length)), pen);
      }
    }
  }

  @override
  bool shouldRepaint(_Dashes old) => old.color != color;
}

// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:vibe/vibe/screens/chat/typing_indicators.dart';

/// Entrance for a brand new message: the row opens up from the bottom (so
/// the timeline glides up) and the message itself stretches out of the
/// sender's picture (see [VibeEntrance.of]); nothing slides or fades.
/// Messages that do not animate are returned untouched.
class VibeEntrance extends StatefulWidget {
  final bool animate;
  final bool fromRight;
  final Widget child;

  const VibeEntrance({
    required this.animate,
    required this.fromRight,
    required this.child,
    super.key,
  });

  /// 0 → 1 while the message above is arriving, or null when it isn't.
  static Animation<double>? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_Grow>()
      ?.grow;

  @override
  State<VibeEntrance> createState() => _VibeEntranceState();
}

class _Grow extends InheritedWidget {
  final Animation<double> grow;
  const _Grow({required this.grow, required super.child});

  @override
  bool updateShouldNotify(_Grow old) => old.grow != grow;
}

class _VibeEntranceState extends State<VibeEntrance>
    with SingleTickerProviderStateMixin {
  AnimationController? _c;
  late final GlobalKey? _gk = widget.animate ? GlobalKey() : null;
  Animation<double>? _size;

  @override
  void initState() {
    super.initState();
    if (!widget.animate) return;
    // someone else's: their typing dots turn into the picture first
    final c = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.fromRight ? 640 : 860),
    );
    _c = c;
    _size = CurvedAnimation(
      parent: c,
      curve: const Interval(0.0, 0.45, curve: Curves.easeOutCubic),
    );
    c.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) setState(() {});
    });
    c.forward();
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null) return widget.child;
    final inner = KeyedSubtree(key: _gk, child: widget.child);
    if (c.isCompleted) return inner;
    return SizeTransition(
      sizeFactor: _size!,
      axisAlignment: 1.0,
      child: _Grow(grow: c, child: inner),
    );
  }
}

/// Wraps a message so it stretches out of the picture beside it: wide
/// first, then tall, with a little overshoot like a drop pulling free.
/// [left]: the picture is on the left.
class VibeGrowOut extends StatelessWidget {
  final bool left;
  final Widget child;
  const VibeGrowOut({required this.left, required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    final grow = VibeEntrance.of(context);
    if (grow == null) return child;
    return AnimatedBuilder(
      animation: grow,
      child: child,
      builder: (context, child) {
        final p = grow.value;
        // someone else's waits until the dots have become their picture
        final start = left ? VibeTypingMorph.end * 0.85 : 0.0;
        final q = ((p - start) / (1 - start)).clamp(0.0, 1.0);
        final w = const ElasticOutCurve(0.75).transform(
          ((q - 0.05) / 0.95).clamp(0.0, 1.0),
        );
        final h = const ElasticOutCurve(0.65).transform(
          ((q - 0.15) / 0.85).clamp(0.0, 1.0),
        );
        return Transform(
          alignment: left ? Alignment.centerLeft : Alignment.centerRight,
          transform: Matrix4.diagonal3Values(
            ((left ? 0.0 : 0.08) + (left ? 1.0 : 0.92) * w).clamp(0.0, 1.2),
            (0.3 + 0.7 * h).clamp(0.0, 1.2),
            1,
          ),
          child: child,
        );
      },
    );
  }
}

/// The picture of a brand new message from someone else: it starts as the
/// typing dots in their circle (where the typing indicator was) and turns
/// into their picture, then the message grows out of it ([VibeGrowOut]).
class VibeTypingMorph extends StatefulWidget {
  final double size;
  final Widget child;
  const VibeTypingMorph({required this.size, required this.child, super.key});

  /// The part of the entrance the change takes.
  static const end = 0.32;

  @override
  State<VibeTypingMorph> createState() => _VibeTypingMorphState();
}

class _VibeTypingMorphState extends State<VibeTypingMorph> {
  // keeps the picture (and its loaded image) when the entrance ends
  final _key = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final picture = KeyedSubtree(key: _key, child: widget.child);
    final grow = VibeEntrance.of(context);
    if (grow == null) return picture;
    final cs = Theme.of(context).colorScheme;
    final s = widget.size;
    return AnimatedBuilder(
      animation: grow,
      child: picture,
      builder: (context, picture) {
        final t = Curves.easeInOut.transform(
          (grow.value / VibeTypingMorph.end).clamp(0.0, 1.0),
        );
        return SizedBox.square(
          dimension: s,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              if (t < 1)
                Opacity(
                  opacity: 1 - t,
                  child: Transform.scale(
                    scale: 1 + 0.18 * t,
                    child: Container(
                      width: s,
                      height: s,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHigh,
                        shape: BoxShape.circle,
                      ),
                      child: const VibeTypingDots(),
                    ),
                  ),
                ),
              Opacity(
                opacity: t,
                child: Transform.scale(
                  scale: 0.6 + 0.4 * Curves.easeOutBack.transform(t),
                  child: picture,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

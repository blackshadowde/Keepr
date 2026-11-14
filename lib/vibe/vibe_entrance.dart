// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

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
    final c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 640),
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
        final w = const ElasticOutCurve(0.75).transform(
          ((p - 0.05) / 0.95).clamp(0.0, 1.0),
        );
        final h = const ElasticOutCurve(0.65).transform(
          ((p - 0.15) / 0.85).clamp(0.0, 1.0),
        );
        return Transform(
          alignment: left ? Alignment.centerLeft : Alignment.centerRight,
          transform: Matrix4.diagonal3Values(
            (0.08 + 0.92 * w).clamp(0.0, 1.2),
            (0.3 + 0.7 * h).clamp(0.0, 1.2),
            1,
          ),
          child: child,
        );
      },
    );
  }
}

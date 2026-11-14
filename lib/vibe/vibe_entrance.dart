// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

/// Google-Messages style entrance for a brand new message: the row grows from
/// the bottom (so the whole timeline glides up smoothly) while the bubble
/// slides up, scales from its corner and fades in. Messages that do not
/// animate are returned untouched (zero overhead).
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

  @override
  State<VibeEntrance> createState() => _VibeEntranceState();
}

class _VibeEntranceState extends State<VibeEntrance>
    with SingleTickerProviderStateMixin {
  AnimationController? _c;
  late final GlobalKey? _gk = widget.animate ? GlobalKey() : null;
  Animation<double>? _size;
  Animation<double>? _pop;
  Animation<double>? _fade;

  @override
  void initState() {
    super.initState();
    if (!widget.animate) return;
    final c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );
    _c = c;
    _size = CurvedAnimation(
      parent: c,
      curve: const Interval(0.0, 0.85, curve: Curves.easeOutCubic),
    );
    // the liquid swell runs on its own curves (see _Pop)
    _pop = CurvedAnimation(parent: c, curve: Curves.linear);
    _fade = CurvedAnimation(
      parent: c,
      curve: const Interval(0.0, 0.55, curve: Curves.easeOut),
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
    // Size grows (so the timeline glides up); fade, rise and pop are
    // paint-only transitions, so the message isn't rebuilt every frame.
    return SizeTransition(
      sizeFactor: _size!,
      axisAlignment: 1.0,
      child: FadeTransition(
        opacity: _fade!,
        child: _Pop(
          pop: _pop!,
          alignment: widget.fromRight
              ? Alignment.bottomRight
              : Alignment.bottomLeft,
          child: inner,
        ),
      ),
    );
  }
}

class _Pop extends AnimatedWidget {
  final Alignment alignment;
  final Widget child;
  const _Pop({
    required Animation<double> pop,
    required this.alignment,
    required this.child,
  }) : super(listenable: pop);

  @override
  Widget build(BuildContext context) {
    // Liquid: the bubble swells out of the corner where the typing circle
    // was, wide first and then tall, overshooting a little like a drop
    // pulling free, then settles to its shape.
    final p = (listenable as Animation<double>).value;
    final w = const ElasticOutCurve(0.7).transform((p * 1.15).clamp(0.0, 1.0));
    final h = const ElasticOutCurve(0.6).transform(
      ((p - 0.08) / 0.92).clamp(0.0, 1.0),
    );
    return Transform(
      alignment: alignment,
      transform: Matrix4.diagonal3Values(0.18 + 0.82 * w, 0.18 + 0.82 * h, 1),
      child: child,
    );
  }
}

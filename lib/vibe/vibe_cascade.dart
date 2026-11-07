// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Block motion: rows leave as solid blocks that slide right, shrink and
/// fade, one after another from the top, uncovering what's underneath; they
/// come back the same way in reverse.
///
/// A row wrapped in [VibeCascadeOut] leaves when the page it's on is covered
/// (a chat opening over the list), and when an enclosing [VibeCascadeScope]
/// says so (Chats / Spaces switch, a person or community pane opening).

/// "Leave" signal for the rows below it: 0 = in place, 1 = gone. Scopes
/// nest; a row follows whichever asks it to leave the most.
class VibeCascadeScope extends StatelessWidget {
  final Animation<double> leaving;
  final Widget child;
  const VibeCascadeScope({
    required this.leaving,
    required this.child,
    super.key,
  });

  static Animation<double>? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_CascadeData>()
      ?.leaving;

  @override
  Widget build(BuildContext context) {
    final parent = maybeOf(context);
    return _CascadeData(
      leaving: parent == null ? leaving : AnimationMax<double>(leaving, parent),
      child: child,
    );
  }
}

class _CascadeData extends InheritedWidget {
  final Animation<double> leaving;
  const _CascadeData({required this.leaving, required super.child});

  @override
  bool updateShouldNotify(_CascadeData old) => old.leaving != leaving;
}

/// Where a row sits on screen, 0 (top) to 1 (bottom), worked out once per
/// motion so rows lower down go a beat later.
mixin _ScreenSpot<T extends StatefulWidget> on State<T> {
  double? _spot;

  double spot(BuildContext context, double v) {
    if (v <= 0 || v >= 1) _spot = null; // idle: the row may have scrolled
    if (_spot != null) return _spot!;
    final box = context.findRenderObject();
    if (box is RenderBox && box.attached && box.hasSize) {
      final y = box.localToGlobal(Offset.zero).dy;
      final h = MediaQuery.sizeOf(context).height;
      if (h > 0) _spot = (y / h).clamp(0.0, 1.0);
    }
    return _spot ?? 0;
  }
}

/// A row that slides right as a block, shrinking and fading, when it has to
/// make way (see [VibeCascadeScope]); [follow] also makes it leave when a
/// page opens over its page.
class VibeCascadeOut extends StatefulWidget {
  final Widget child;
  final bool follow;
  const VibeCascadeOut({required this.child, this.follow = false, super.key});

  @override
  State<VibeCascadeOut> createState() => _VibeCascadeOutState();
}

class _VibeCascadeOutState extends State<VibeCascadeOut> with _ScreenSpot {
  @override
  Widget build(BuildContext context) {
    final scope = VibeCascadeScope.maybeOf(context);
    final page = widget.follow
        ? ModalRoute.of(context)?.secondaryAnimation
        : null;
    final Animation<double>? anim = scope != null && page != null
        ? AnimationMax<double>(scope, page)
        : scope ?? page;
    if (anim == null) return widget.child;
    return AnimatedBuilder(
      animation: anim,
      child: widget.child,
      builder: (context, child) {
        final v = anim.value.clamp(0.0, 1.0);
        // top rows first; the last ones start about a third of the way in
        final t = vibeCascadeT(v, spot(context, v));
        // the same widgets every frame (only the numbers change), so rows
        // keep their state through the motion
        return IgnorePointer(
          ignoring: t > 0,
          child: FractionalTranslation(
            translation: Offset(0.85 * t, 0),
            child: Transform.scale(
              scale: 1 - 0.32 * t,
              alignment: Alignment.centerRight,
              child: Opacity(
                opacity: (1 - t * 1.15).clamp(0.0, 1.0),
                // the row is drawn once and the fade reuses that picture,
                // instead of repainting it every frame
                child: RepaintBoundary(child: child),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A row in a pane or page that rises into place as the pane opens, rows
/// higher up first (and sinks back as it closes).
class VibeRiseIn extends StatefulWidget {
  final Widget child;
  const VibeRiseIn({required this.child, super.key});

  @override
  State<VibeRiseIn> createState() => _VibeRiseInState();
}

class _VibeRiseInState extends State<VibeRiseIn> with _ScreenSpot {
  @override
  Widget build(BuildContext context) {
    final anim = ModalRoute.of(context)?.animation;
    if (anim == null) return widget.child;
    return AnimatedBuilder(
      animation: anim,
      child: widget.child,
      builder: (context, child) {
        final v = anim.value.clamp(0.0, 1.0);
        final d = spot(context, v) * 0.3;
        final t = Curves.easeOutCubic.transform(
          ((v - d) / (1 - d)).clamp(0.0, 1.0),
        );
        return Transform.translate(
          offset: Offset(0, 28 * (1 - t)),
          child: Opacity(opacity: t, child: child),
        );
      },
    );
  }
}

/// Text that flickers into place: a short sideways smear with two coloured
/// copies, then it settles (unlocking, switching). Plays when shown and
/// whenever [text] changes.
class VibeGlitchText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final int? maxLines;
  const VibeGlitchText(this.text, {this.style, this.maxLines, super.key});

  @override
  State<VibeGlitchText> createState() => _VibeGlitchTextState();
}

class _VibeGlitchTextState extends State<VibeGlitchText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  )..forward();

  @override
  void didUpdateWidget(VibeGlitchText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.merge(widget.style);
    Text text(Color? color) => Text(
      widget.text,
      maxLines: widget.maxLines ?? 1,
      overflow: TextOverflow.ellipsis,
      style: color == null ? style : style.copyWith(color: color),
    );
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        // strong at first, gone by the end; a few hard steps, not a wobble
        final k = (1 - t) * (1 - t);
        final step = (t * 9).floor();
        final dx = k * 7 * (step.isEven ? 1 : -1) * math.sin(step * 1.7).abs();
        return Stack(
          children: [
            if (k > 0.02) ...[
              Transform.translate(
                offset: Offset(-dx - 2 * k, 0),
                child: Opacity(
                  opacity: k,
                  child: text(const Color(0xFFFF4D6D)),
                ),
              ),
              Transform.translate(
                offset: Offset(dx + 2 * k, 0),
                child: Opacity(
                  opacity: k,
                  child: text(const Color(0xFF4DD8FF)),
                ),
              ),
            ],
            Transform.translate(
              offset: Offset(dx * 0.4, 0),
              child: Opacity(opacity: 0.4 + 0.6 * t, child: text(null)),
            ),
          ],
        );
      },
    );
  }
}

/// How far a row at [spot] (0 top .. 1 bottom of the screen) has gone when
/// the motion is at [v]: top rows first, the last ones start about a third
/// of the way in. The chat being uncovered uses the same numbers, so its
/// strips open exactly where the rows have moved away.
double vibeCascadeT(double v, double spot) {
  final d = spot * 0.35;
  return Curves.easeInOutCubic.transform(((v - d) / (1 - d)).clamp(0.0, 1.0));
}

/// How far a row's left edge has moved, as a share of its width, at [t]:
/// it slides 0.85 and shrinks 0.32 towards its right end.
double vibeCascadeEdge(double t) => (1.17 * t).clamp(0.0, 1.0);

/// Each widget in [children] as its own block (see [VibeCascadeOut]).
List<Widget> vibeCascadeAll(List<Widget> children) => [
  for (final w in children) VibeCascadeOut(child: w),
];

/// For an [AnimatedSwitcher]: the old child's rows leave as blocks, then the
/// new child's rows come in (the same motion backwards).
Widget vibeCascadeSwitch(Widget child, Animation<double> animation) {
  final shown = CurvedAnimation(
    parent: animation,
    curve: const Interval(0.35, 1),
  );
  // no fade over the whole list (that blended two lists and flashed): the
  // rows themselves leave and arrive block by block
  return VibeCascadeScope(leaving: ReverseAnimation(shown), child: child);
}

// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:vibe/vibe/vibe_haptics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// Every pane / page that slides up closes with a swipe down that follows
/// the finger: the pane moves with it, and on letting go it either slides
/// away (pulled far enough, or flicked down) or springs back.
///
/// Works on the pane's scrolling list too: pulling down while the list is at
/// its top moves the pane. Nested ones do nothing (the outer one handles it).
class VibeSheetDragClose extends StatefulWidget {
  final Widget child;
  const VibeSheetDragClose({required this.child, super.key});

  @override
  State<VibeSheetDragClose> createState() => _VibeSheetDragCloseState();
}

class _Marker extends InheritedWidget {
  const _Marker({required super.child});
  @override
  bool updateShouldNotify(_Marker old) => false;
}

class _VibeSheetDragCloseState extends State<VibeSheetDragClose>
    with SingleTickerProviderStateMixin {
  // how far the pane is pulled down, in pixels: it follows the finger one
  // to one (the pane's own open/close curve doesn't bend it), then springs
  // back or carries on down at the finger's speed
  late final AnimationController _pull = AnimationController.unbounded(
    vsync: this,
  );
  bool _dragging = false;
  bool _closing = false;
  bool _past = false;

  /// Pulled this far (of the pane's height), letting go closes it.
  static const _closeAt = 0.28;

  double get _height {
    final h = context.size?.height ?? 0;
    return h > 50 ? h : MediaQuery.sizeOf(context).height;
  }

  @override
  void dispose() {
    _pull.dispose();
    super.dispose();
  }

  void _move(double dy) {
    if (_closing) return;
    if (!_dragging) {
      if (dy <= 0) return; // only a pull down starts it
      _dragging = true;
      _pull.stop();
    }
    final v = _pull.value + dy;
    // pushed back up past where it sits: a little give, then it stops
    _pull.value = v >= 0 ? v : -10 * (1 - 1 / (1 - v / 40));
    // a light tick when letting go would now close it
    final past = _pull.value > _height * _closeAt;
    if (past != _past) {
      _past = past;
      if (past) VibeHaptics.selection();
    }
  }

  void _end(double velocity) {
    if (!_dragging) return;
    _dragging = false;
    _past = false;
    final h = _height;
    final at = _pull.value;
    if (velocity > 700 || (at > h * _closeAt && velocity > -250)) {
      _closing = true;
      VibeHaptics.light();
      // it keeps going down from where the finger left it, at its speed,
      // while the pane's own close fades the dim behind it
      _pull.animateWith(
        SpringSimulation(
          SpringDescription.withDampingRatio(mass: 1, stiffness: 300, ratio: 1),
          at,
          h,
          velocity.clamp(0.0, 6000.0),
        ),
      );
      Navigator.of(context).pop();
    } else {
      // back into place with a soft settle, from the finger's speed
      _pull.animateWith(
        SpringSimulation(
          SpringDescription.withDampingRatio(
            mass: 1,
            stiffness: 520,
            ratio: 0.82,
          ),
          at,
          0,
          velocity,
        ),
      );
    }
  }

  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    if (n is OverscrollNotification && n.dragDetails != null && n.overscroll < 0) {
      _move(-n.overscroll);
    } else if (_dragging && n is ScrollUpdateNotification && n.dragDetails != null) {
      _move(-(n.scrollDelta ?? 0));
    } else if (n is ScrollEndNotification) {
      _end(n.dragDetails?.velocity.pixelsPerSecond.dy ?? 0);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (context.getInheritedWidgetOfExactType<_Marker>() != null) return widget.child;
    return _Marker(
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: GestureDetector(
          // the parts of the pane that don't scroll
          behavior: HitTestBehavior.translucent,
          onVerticalDragUpdate: (d) => _move(d.delta.dy),
          onVerticalDragEnd: (d) => _end(d.primaryVelocity ?? 0),
          onVerticalDragCancel: () => _end(0),
          child: ScrollConfiguration(
            // Clamping physics reports the pull-down as overscroll everywhere.
            behavior: ScrollConfiguration.of(context).copyWith(physics: const ClampingScrollPhysics()),
            child: AnimatedBuilder(
              animation: _pull,
              child: widget.child,
              builder: (context, child) => Transform.translate(
                offset: Offset(0, _pull.value),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

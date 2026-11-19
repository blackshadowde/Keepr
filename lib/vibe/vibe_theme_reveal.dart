// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// A new theme grows out of what you tapped (a theme card, Light, Dark) in
/// a soft-edged circle and fills the screen, over a still picture of the
/// old one. Sits round the whole app.
class VibeThemeReveal extends StatefulWidget {
  final Widget child;
  const VibeThemeReveal({required this.child, super.key});

  static final key = GlobalKey();

  /// Runs [change] (the new theme) and reveals it from [from], a point on
  /// the screen.
  static Future<void> run(
    BuildContext context,
    Offset from,
    FutureOr<void> Function() change,
  ) async {
    final state = key.currentState;
    if (state is! _VibeThemeRevealState ||
        MediaQuery.disableAnimationsOf(context)) {
      await change();
      return;
    }
    await state._run(from, change);
  }

  @override
  State<VibeThemeReveal> createState() => _VibeThemeRevealState();
}

class _VibeThemeRevealState extends State<VibeThemeReveal>
    with SingleTickerProviderStateMixin {
  final _boundary = GlobalKey();
  late final _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );
  ui.Image? _old;
  Offset _from = Offset.zero;

  Future<void> _run(Offset from, FutureOr<void> Function() change) async {
    final box = _boundary.currentContext?.findRenderObject();
    if (_old != null || box is! RenderRepaintBoundary) {
      await change();
      return;
    }
    final ui.Image image;
    try {
      image = box.toImageSync(
        pixelRatio: MediaQuery.devicePixelRatioOf(context),
      );
    } catch (_) {
      await change();
      return;
    }
    _anim.value = 0;
    setState(() {
      _old = image;
      _from = from;
    });
    await change();
    // the new theme settles under the picture first
    await Future.delayed(const Duration(milliseconds: 120));
    if (mounted) await _anim.forward(from: 0);
    if (mounted) setState(() => _old = null);
    image.dispose();
  }

  @override
  void dispose() {
    _anim.dispose();
    _old?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final old = _old;
    return Stack(
      textDirection: TextDirection.ltr,
      fit: StackFit.passthrough,
      children: [
        RepaintBoundary(key: _boundary, child: widget.child),
        if (old != null)
          Positioned.fill(
            // no taps while the screen changes
            child: AbsorbPointer(
              child: AnimatedBuilder(
                animation: _anim,
                builder: (context, _) => CustomPaint(
                  painter: _RevealPainter(
                    old,
                    _from,
                    Curves.fastOutSlowIn.transform(_anim.value),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The old screen with a hole growing from [from]; the hole's edge fades
/// over [_feather] so the new theme blends in softly.
class _RevealPainter extends CustomPainter {
  final ui.Image old;
  final Offset from;
  final double t;
  const _RevealPainter(this.old, this.from, this.t);

  static const _feather = 30.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.saveLayer(rect, Paint());
    paintImage(
      canvas: canvas,
      rect: rect,
      image: old,
      fit: BoxFit.fill,
      filterQuality: FilterQuality.low,
    );
    if (t > 0) {
      final far = [
        rect.topLeft,
        rect.topRight,
        rect.bottomLeft,
        rect.bottomRight,
      ].map((c) => (c - from).distance).reduce(math.max);
      final radius = (far + _feather) * t;
      final mask = math.max(radius + _feather, 1.0);
      final clear = ((radius - _feather) / mask).clamp(0.0, 1.0);
      final soft = (radius / mask).clamp(clear, 1.0);
      canvas.drawRect(
        rect,
        Paint()
          ..blendMode = BlendMode.dstIn
          ..shader = ui.Gradient.radial(
            from,
            mask,
            const [
              Color(0x00000000),
              Color(0x00000000),
              Color(0x47000000),
              Color(0xFF000000),
            ],
            [0, clear, soft, 1],
          ),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RevealPainter old) => old.t != t || old.old != this.old;
}

// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vibe/config/setting_keys.dart';
import 'package:vibe/vibe/vibe_chat_dock.dart';
import 'package:vibe/vibe/vibe_palette.dart';
import 'package:vibe/widgets/matrix.dart';
import 'package:vibe/widgets/vibe_app.dart';

/// The home screen builds itself when Keepr starts (after being closed or
/// removed from recents) or comes back after a while away: coloured sparks
/// fly in, blue outlines draw the rail, the search bar and the chat rows,
/// they fill in, and the real home fades up underneath.
/// Settings > Customisation > "Start-up animation".
class VibeBootIntro extends StatefulWidget {
  const VibeBootIntro({super.key});

  /// Away at least this long counts as "after sleep".
  static const away = Duration(minutes: 3);

  @override
  State<VibeBootIntro> createState() => _VibeBootIntroState();
}

class _VibeBootIntroState extends State<VibeBootIntro>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
  );
  bool _playing = false;
  DateTime? _leftAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // a cold start: play once the home screen is up
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => Future.delayed(const Duration(milliseconds: 250), _maybePlay),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _leftAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final left = _leftAt;
      _leftAt = null;
      if (left != null && DateTime.now().difference(left) >= VibeBootIntro.away) {
        _maybePlay();
      }
    }
  }

  void _maybePlay() {
    if (!mounted || _playing) return;
    if (!AppSettings.vibeBootIntro.value) return;
    // only over the home screen (signed in), never on top of an open chat
    final path = VibeApp.router.routeInformationProvider.value.uri.path;
    if (!path.startsWith('/rooms') || VibeChatDock.currentRoomId() != null) {
      return;
    }
    if (!Matrix.of(context).client.isLogged()) return;
    // people who turned animations off in Android don't get it
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
    setState(() => _playing = true);
    _c.forward(from: 0).whenComplete(() {
      if (mounted) setState(() => _playing = false);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_playing) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          size: Size.infinite,
          painter: _BootPainter(
            t: _c.value,
            top: MediaQuery.paddingOf(context).top,
            bg: Theme.of(context).scaffoldBackgroundColor,
            fillColor: cs.surfaceContainerHigh,
            accent: VibePalette.accent,
          ),
        ),
      ),
    );
  }
}

double _seg(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);

class _Box {
  final RRect r;
  final double at; // when its outline starts drawing (0..1 of the build)
  final bool hot; // drawn in the warm highlight colour
  const _Box(this.r, this.at, {this.hot = false});
}

class _BootPainter extends CustomPainter {
  final double t;
  final double top;
  final Color bg, fillColor, accent;
  _BootPainter({
    required this.t,
    required this.top,
    required this.bg,
    required this.fillColor,
    required this.accent,
  });

  /// The home screen's outline: the rail of server circles, the search
  /// bar and the chat rows (picture + two lines), top to bottom.
  List<_Box> _layout(Size s) {
    final boxes = <_Box>[];
    final y0 = top + 16;
    // rail
    for (var i = 0; i < 7; i++) {
      final c = Offset(36, y0 + 26 + i * 64);
      if (c.dy > s.height - 40) break;
      boxes.add(_Box(RRect.fromRectAndRadius(Rect.fromCircle(center: c, radius: 24), const Radius.circular(16)), 0.02 * i, hot: i == 0));
    }
    // search bar
    boxes.add(_Box(RRect.fromLTRBR(84, y0, s.width - 16, y0 + 44, const Radius.circular(22)), 0.05));
    // chat rows
    final w = s.width - 84 - 16;
    for (var i = 0; i < 9; i++) {
      final y = y0 + 64 + i * 74;
      if (y > s.height - 60) break;
      final at = 0.1 + i * 0.04;
      boxes.add(_Box(RRect.fromRectAndRadius(Rect.fromCircle(center: Offset(110, y + 26), radius: 22), const Radius.circular(22)), at, hot: i == 1));
      boxes.add(_Box(RRect.fromLTRBR(144, y + 10, 144 + w * (0.42 + (i % 3) * 0.08), y + 22, const Radius.circular(6)), at + 0.03));
      boxes.add(_Box(RRect.fromLTRBR(144, y + 32, 144 + w * (0.6 + (i % 2) * 0.15), y + 42, const Radius.circular(5)), at + 0.05));
    }
    return boxes;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final full = Offset.zero & size;
    // the screen behind stays covered until the build is done, then fades
    final cover = 1 - _seg(t, 0.72, 1);
    canvas.drawRect(full, Paint()..color = bg.withValues(alpha: cover));
    if (cover <= 0) return;

    const warm = Color(0xFFFF6B4A);
    const sparkColors = [Color(0xFF5BC0FF), Color(0xFF8C96F6), Color(0xFFFFA45B), Color(0xFFEB459E), Color(0xFF3BCB78)];
    final boxes = _layout(size);
    final rnd = math.Random(7);

    // 1. sparks fly in from the edges to the corners of the outlines
    for (var i = 0; i < 46; i++) {
      final box = boxes[rnd.nextInt(boxes.length)].r;
      final target = rnd.nextBool() ? box.outerRect.topLeft : box.outerRect.bottomRight;
      final edge = rnd.nextInt(4);
      final from = switch (edge) {
        0 => Offset(-30, rnd.nextDouble() * size.height),
        1 => Offset(size.width + 30, rnd.nextDouble() * size.height),
        2 => Offset(rnd.nextDouble() * size.width, -30),
        _ => Offset(rnd.nextDouble() * size.width, size.height + 30),
      };
      final start = rnd.nextDouble() * 0.2;
      final u = Curves.easeOutCubic.transform(_seg(t, start, start + 0.32));
      if (u <= 0 || u >= 1) continue;
      final p = Offset.lerp(from, target, u)!;
      final dir = (target - from) / (target - from).distance;
      canvas.drawLine(
        p - dir * 14,
        p,
        Paint()
          ..color = sparkColors[i % sparkColors.length].withValues(alpha: (1 - u) * 0.9 + 0.1)
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
    }

    // 2. outlines draw themselves, then 3. fill in
    for (final b in boxes) {
      final draw = _seg(t, 0.18 + b.at, 0.18 + b.at + 0.22);
      if (draw <= 0) continue;
      final path = Path()..addRRect(b.r);
      final fill = _seg(t, 0.5 + b.at * 0.5, 0.7 + b.at * 0.5);
      if (fill > 0) {
        canvas.drawRRect(b.r, Paint()..color = fillColor.withValues(alpha: fill * cover));
      }
      final col = (b.hot ? warm : accent).withValues(alpha: (1 - fill * 0.7) * cover);
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = col;
      for (final m in path.computeMetrics()) {
        canvas.drawPath(m.extractPath(0, m.length * draw), stroke);
        // a bright point running along the line while it draws
        if (draw < 1) {
          final tip = m.getTangentForOffset(m.length * draw)?.position;
          if (tip != null) {
            canvas.drawCircle(tip, 2.4, Paint()..color = Colors.white.withValues(alpha: cover));
          }
        }
      }
      // little corner ticks, like a blueprint
      if (draw >= 1 && fill < 1) {
        final r = b.r.outerRect;
        final tick = Paint()
          ..color = col
          ..strokeWidth = 1.6;
        for (final c in [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight]) {
          canvas.drawLine(c - const Offset(4, 0), c + const Offset(4, 0), tick);
          canvas.drawLine(c - const Offset(0, 4), c + const Offset(0, 4), tick);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BootPainter old) => old.t != t;
}

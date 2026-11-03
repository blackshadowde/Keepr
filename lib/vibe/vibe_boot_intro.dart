// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vibe/config/setting_keys.dart';
import 'package:vibe/vibe/vibe_chat_dock.dart';
import 'package:vibe/vibe/vibe_palette.dart';
import 'package:vibe/widgets/matrix.dart';
import 'package:vibe/widgets/vibe_app.dart';

/// A swarm of little coloured cursors builds the screen. They come in as a
/// flock, spread out, and each one drags out a piece (a selection box with
/// handles), which then fills in; when all pieces are placed they fly off
/// and the real screen shows. Plays when Keepr opens or comes back after a
/// while (the home screen), when a chat opens (the chat), and when you leave
/// a chat (the home again). Settings > Customisation > "Start-up animation".
class VibeBootIntro extends StatefulWidget {
  const VibeBootIntro({super.key});

  /// Away at least this long counts as "after sleep".
  static const away = Duration(minutes: 3);

  @override
  State<VibeBootIntro> createState() => _VibeBootIntroState();
}

enum _Screen { home, chat }

class _VibeBootIntroState extends State<VibeBootIntro>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _c = AnimationController(vsync: this);
  _Screen? _playing;
  DateTime? _leftAt;
  String? _lastPath;
  final _info = VibeApp.router.routeInformationProvider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lastPath = _info.value.uri.path;
    _info.addListener(_onRoute);
    // a cold start: play once the home screen is up
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => Future.delayed(
        const Duration(milliseconds: 250),
        () => _play(_Screen.home),
      ),
    );
  }

  bool _isHome(String p) => p == '/rooms' || p == '/rooms/';
  bool _isChat(String p) =>
      p.startsWith('/rooms/!') && p.split('/').length == 3;

  void _onRoute() {
    final p = _info.value.uri.path;
    final was = _lastPath;
    _lastPath = p;
    if (was == null || was == p) return;
    // the dock plays its own slide
    if (VibeChatDock.move.value != null) return;
    if (_isHome(was) && _isChat(p)) _play(_Screen.chat);
    if (_isChat(was) && _isHome(p)) _play(_Screen.home);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _leftAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final left = _leftAt;
      _leftAt = null;
      if (left != null &&
          DateTime.now().difference(left) >= VibeBootIntro.away &&
          _isHome(_info.value.uri.path)) {
        _play(_Screen.home);
      }
    }
  }

  void _play(_Screen screen) {
    if (!mounted || !AppSettings.vibeBootIntro.value) return;
    final p = _info.value.uri.path;
    if (screen == _Screen.home && !_isHome(p)) return;
    if (screen == _Screen.chat && !_isChat(p)) return;
    if (!Matrix.of(context).client.isLogged()) return;
    // people who turned animations off in Android don't get it
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
    setState(() => _playing = screen);
    _c.duration = screen == _Screen.home
        ? const Duration(milliseconds: 3400)
        : const Duration(milliseconds: 2400);
    _c.forward(from: 0).whenComplete(() {
      if (mounted && _playing == screen) setState(() => _playing = null);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _info.removeListener(_onRoute);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screen = _playing;
    if (screen == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          size: Size.infinite,
          painter: _SwarmPainter(
            screen: screen,
            t: _c.value,
            top: MediaQuery.paddingOf(context).top,
            bottom: MediaQuery.paddingOf(context).bottom,
            bg: Theme.of(context).scaffoldBackgroundColor,
            fillColor: cs.surfaceContainerHigh,
            accent: VibePalette.accent,
            text: cs.onSurface,
          ),
        ),
      ),
    );
  }
}

double _seg(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);
double _io(double t) => Curves.easeInOutCubic.transform(t.clamp(0.0, 1.0));

class _Piece {
  final Rect r;
  final double radius;
  final String tag;
  const _Piece(this.r, this.radius, this.tag);
}

const _cursorColors = [
  Color(0xFF5BC0FF),
  Color(0xFF8C96F6),
  Color(0xFFFFA45B),
  Color(0xFFEB459E),
  Color(0xFF3BCB78),
  Color(0xFFFFD54F),
  Color(0xFFFF6B4A),
];

class _SwarmPainter extends CustomPainter {
  final _Screen screen;
  final double t, top, bottom;
  final Color bg, fillColor, accent, text;
  _SwarmPainter({
    required this.screen,
    required this.t,
    required this.top,
    required this.bottom,
    required this.bg,
    required this.fillColor,
    required this.accent,
    required this.text,
  });

  static final Map<String, TextPainter> _labels = {};

  /// The screen's pieces, in the order they get built.
  List<_Piece> _layout(Size s) {
    final p = <_Piece>[];
    final y0 = top + 16;
    if (screen == _Screen.home) {
      p.add(_Piece(Rect.fromLTRB(84, y0, s.width - 16, y0 + 44), 22, 'search'));
      for (var i = 0; i < 7; i++) {
        final c = Offset(36, y0 + 26 + i * 64);
        if (c.dy > s.height - 60) break;
        p.add(_Piece(Rect.fromCircle(center: c, radius: 24), 16, i == 0 ? 'rail' : ''));
      }
      final w = s.width - 84 - 16;
      for (var i = 0; i < 8; i++) {
        final y = y0 + 64 + i * 74;
        if (y > s.height - 70) break;
        p.add(_Piece(Rect.fromCircle(center: Offset(110, y + 26), radius: 22), 22, i == 0 ? 'chat' : ''));
        p.add(_Piece(Rect.fromLTRB(144, y + 10, 144 + w * (0.42 + (i % 3) * 0.08), y + 22), 6, ''));
        p.add(_Piece(Rect.fromLTRB(144, y + 32, 144 + w * (0.6 + (i % 2) * 0.15), y + 42), 5, ''));
      }
    } else {
      // the chat: top bar, messages, text box
      p.add(_Piece(Rect.fromLTRB(12, y0, s.width - 12, y0 + 48), 16, 'header'));
      final inputTop = s.height - bottom - 72;
      for (var i = 0; i < 6; i++) {
        final y = inputTop - 24 - (6 - i) * 78;
        if (y < y0 + 60) continue;
        final mine = i.isOdd;
        p.add(_Piece(Rect.fromCircle(center: Offset(36, y + 20), radius: 20), 20, i == 0 ? 'message' : ''));
        p.add(_Piece(Rect.fromLTRB(68, y + 4, 68 + (mine ? 70 : 96), y + 16), 5, ''));
        p.add(_Piece(Rect.fromLTRB(68, y + 26, 68 + (s.width - 100) * (0.4 + (i % 3) * 0.17), y + 40), 7, ''));
      }
      p.add(_Piece(Rect.fromLTRB(12, inputTop, s.width - 84, inputTop + 56), 28, 'text box'));
      p.add(_Piece(Rect.fromLTRB(s.width - 72, inputTop, s.width - 12, inputTop + 56), 28, ''));
    }
    return p;
  }

  /// The classic pointer arrow, tip at (0, 0).
  static Path _arrow(double k) => Path()
    ..moveTo(0, 0)
    ..lineTo(0, 17 * k)
    ..lineTo(4.4 * k, 13 * k)
    ..lineTo(7.4 * k, 19.6 * k)
    ..lineTo(10.2 * k, 18.4 * k)
    ..lineTo(7.2 * k, 12 * k)
    ..lineTo(13 * k, 12 * k)
    ..close();

  void _cursor(Canvas c, Offset at, Color col, double alpha, String tag) {
    if (alpha <= 0) return;
    c.save();
    c.translate(at.dx, at.dy);
    final arrow = _arrow(1.15);
    c.drawShadow(arrow, Colors.black, 3, false);
    c.drawPath(arrow, Paint()..color = col.withValues(alpha: alpha));
    c.drawPath(
      arrow,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white.withValues(alpha: alpha),
    );
    if (tag.isNotEmpty) {
      final tp = _labels.putIfAbsent(
        tag,
        () => TextPainter(
          text: TextSpan(
            text: tag,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(),
      );
      final box = RRect.fromRectAndRadius(
        Rect.fromLTWH(12, 18, tp.width + 12, tp.height + 6),
        const Radius.circular(6),
      );
      c.drawRRect(box, Paint()..color = col.withValues(alpha: alpha));
      c.saveLayer(null, Paint()..color = Colors.white.withValues(alpha: alpha));
      tp.paint(c, const Offset(18, 21));
      c.restore();
    }
    c.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final full = Offset.zero & size;
    final home = screen == _Screen.home;
    // the real screen shows once everything is placed
    final cover = 1 - _seg(t, home ? 0.82 : 0.78, 1);
    canvas.drawRect(full, Paint()..color = bg.withValues(alpha: cover));
    if (t >= 1) return;

    final pieces = _layout(size);
    final n = home ? 12 : 9; // cursors in the swarm
    final rnd = math.Random(11);
    final center = Offset(size.width / 2, size.height * 0.48);
    final phase = List.generate(n, (_) => rnd.nextDouble() * math.pi * 2);
    final orbit = List.generate(n, (_) => 30 + rnd.nextDouble() * 70);
    final exitTo = List.generate(
      n,
      (i) => Offset(
        rnd.nextBool() ? -40 : size.width + 40,
        rnd.nextDouble() * size.height,
      ),
    );

    // the flock: circling together in the middle, drifting a little
    Offset flock(int i, double time) {
      final a = phase[i] + time * 9;
      final wobble = math.sin(time * 13 + i) * 12;
      return center +
          Offset(math.cos(a) * (orbit[i] + wobble), math.sin(a) * (orbit[i] * 0.6 + wobble)) +
          Offset(math.sin(time * 4) * 30, math.cos(time * 3) * 18);
    }

    // build timing: pieces are dealt to the cursors in turn
    final buildStart = home ? 0.18 : 0.16;
    final buildSpan = home ? 0.58 : 0.56;
    final perSlot = buildSpan / ((pieces.length / n).ceil());
    const fly = 0.32, drag = 0.38; // parts of a slot

    // pieces first (under the cursors)
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (var k = 0; k < pieces.length; k++) {
      final slot = k ~/ n;
      final s0 = buildStart + slot * perSlot + (k % n) * 0.006;
      final u = _seg(t, s0 + perSlot * fly, s0 + perSlot * (fly + drag));
      if (u <= 0) continue;
      final p = pieces[k];
      final grown = Rect.fromLTRB(
        p.r.left,
        p.r.top,
        p.r.left + p.r.width * _io(u),
        p.r.top + p.r.height * _io(u),
      );
      final fill = _seg(t, s0 + perSlot * (fly + drag), s0 + perSlot * (fly + drag) + 0.08);
      final rr = RRect.fromRectAndRadius(grown, Radius.circular(math.min(p.radius, grown.shortestSide / 2)));
      if (fill > 0) {
        canvas.drawRRect(rr, Paint()..color = fillColor.withValues(alpha: fill * cover));
      }
      // the selection box with its handles while it's being placed
      final sel = (1 - fill) * cover;
      if (sel > 0) {
        stroke.color = accent.withValues(alpha: sel);
        canvas.drawRect(grown, stroke);
        final h = Paint()..color = Colors.white.withValues(alpha: sel);
        final hb = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = accent.withValues(alpha: sel);
        for (final c in [grown.topLeft, grown.topRight, grown.bottomLeft, grown.bottomRight]) {
          final hr = Rect.fromCenter(center: c, width: 6, height: 6);
          canvas.drawRect(hr, h);
          canvas.drawRect(hr, hb);
        }
      }
    }

    // the cursors
    for (var i = 0; i < n; i++) {
      final col = _cursorColors[i % _cursorColors.length];
      // coming in from below as a group
      final enter = _io(_seg(t, i * 0.008, 0.12 + i * 0.008));
      Offset pos = Offset.lerp(Offset(center.dx + (i - n / 2) * 14, size.height + 40), flock(i, t), enter)!;
      var tag = '';
      final mine = [for (var k = i; k < pieces.length; k += n) k];
      var lastEnd = buildStart;
      for (final k in mine) {
        final slot = k ~/ n;
        final s0 = buildStart + slot * perSlot + (k % n) * 0.006;
        final flyU = _io(_seg(t, s0, s0 + perSlot * fly));
        final dragU = _io(_seg(t, s0 + perSlot * fly, s0 + perSlot * (fly + drag)));
        final p = pieces[k].r;
        if (t >= s0) {
          final from = k == mine.first ? flock(i, s0) : pieces[k - n].r.bottomRight;
          pos = Offset.lerp(from, p.topLeft, flyU)!;
          if (dragU > 0) pos = Offset.lerp(p.topLeft, p.bottomRight, dragU)!;
          tag = pieces[k].tag;
          lastEnd = s0 + perSlot * (fly + drag);
        }
      }
      // once its pieces are done, it flies off
      final leave = _io(_seg(t, math.max(lastEnd, 0.7), math.max(lastEnd, 0.7) + 0.2));
      if (leave > 0) pos = Offset.lerp(pos, exitTo[i], leave)!;
      final alpha = (1 - leave) * _seg(t, 0, 0.05).clamp(0.0, 1.0) + 0.0;
      _cursor(canvas, pos, col, alpha.clamp(0.0, 1.0), leave > 0 ? '' : tag);
    }
  }

  @override
  bool shouldRepaint(covariant _SwarmPainter old) => old.t != t || old.screen != screen;
}

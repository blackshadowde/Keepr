// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import 'package:vibe/config/setting_keys.dart';
import 'package:vibe/utils/account_config.dart';
import 'package:vibe/utils/file_selector.dart';
import 'package:vibe/vibe/vibe_connections.dart';
import 'package:vibe/vibe/vibe_haptics.dart';
import 'package:vibe/vibe/vibe_settings_style.dart';
import 'package:vibe/widgets/future_loading_dialog.dart';
import 'package:vibe/widgets/matrix.dart';
import 'package:vibe/widgets/mxc_image.dart';

/// Chat wallpapers: Keepr's own, painted from the theme's colours so they
/// always match (light and dark), or your own photo (kept on your account,
/// softened to fit).
abstract class VibeWallpaper {
  static const styles = ['doodles', 'flow', 'shapes', 'waves', 'dots'];
  static const names = {
    'none': 'None',
    'doodles': 'Doodles',
    'flow': 'Flow',
    'shapes': 'Shapes',
    'waves': 'Waves',
    'dots': 'Dots',
    'photo': 'Your photo',
    'music': 'Music',
  };

  /// Bumped when the pick changes, so open chats repaint.
  static final version = ValueNotifier<int>(0);

  /// 'photo' (yours, when you have one), 'music', 'none' or one of [styles].
  static String get style => AppSettings.vibeWallpaper.value;

  /// How strongly the drawings show, 0 to 1.
  static double get pattern => AppSettings.vibeWallpaperPattern.value;

  static Future<void> setStyle(String s) async {
    await AppSettings.vibeWallpaper.setItem(s);
    version.value++;
  }

  static Future<void> setPattern(double v) async {
    await AppSettings.vibeWallpaperPattern.setItem(v);
    version.value++;
  }

  /// One of Keepr's own is on.
  static bool get painted => styles.contains(style);

  /// The cover of what you're playing.
  static bool get music => style == 'music';

  /// Your photo shows.
  static bool photo(ApplicationAccountConfig c) =>
      style == 'photo' && c.wallpaperUrl != null;

  /// Something is behind the chats (the bars go see-through over it).
  static bool on(ApplicationAccountConfig c) => painted || music || photo(c);

  /// What Customisation says is on.
  static String label(ApplicationAccountConfig c) => painted || music
      ? names[style]!
      : photo(c)
      ? 'Your photo'
      : 'None';
}

/// One of Keepr's wallpapers, filling its space ([style], or the one
/// picked).
class VibeWallpaperPaint extends StatelessWidget {
  final String? style;
  const VibeWallpaperPaint({this.style, super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: VibeWallpaper.version,
    builder: (context, _, _) {
      final s = style ?? VibeWallpaper.style;
      if (!VibeWallpaper.styles.contains(s)) return const SizedBox.expand();
      final theme = Theme.of(context);
      // the chat keeps it as one picture (a snapshot) while messages
      // scroll over it, so no layer of its own here: the snapshot must see
      // when it changes
      return CustomPaint(
        size: Size.infinite,
        painter: _WallPainter(
          s,
          theme.colorScheme,
          theme.brightness == Brightness.dark,
          VibeWallpaper.pattern,
        ),
      );
    },
  );
}

/// Music: the cover of what you're playing, blown up soft behind the chats
/// and calmed toward the page colour so messages read well. It changes with
/// the song; with nothing playing, Flow shows.
class VibeMusicWallpaper extends StatelessWidget {
  const VibeMusicWallpaper({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<VibeTrack?>(
    valueListenable: VibeConnections.playing,
    builder: (context, t, _) {
      final cover = t?.cover;
      final theme = Theme.of(context);
      final dark = theme.brightness == Brightness.dark;
      const flow = VibeWallpaperPaint(style: 'flow');
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 900),
        child: cover == null || !cover.startsWith('https://')
            ? const KeyedSubtree(key: ValueKey('flow'), child: flow)
            : KeyedSubtree(
                key: ValueKey(cover),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(color: theme.colorScheme.surface),
                    // a small copy made big and soft: its colours, not
                    // the picture
                    ImageFiltered(
                      imageFilter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: Transform.scale(
                        scale: 1.2,
                        child: Image.network(
                          cover,
                          fit: BoxFit.cover,
                          cacheWidth: 64,
                          filterQuality: FilterQuality.medium,
                          gaplessPlayback: true,
                          errorBuilder: (_, _, _) => flow,
                        ),
                      ),
                    ),
                    ColoredBox(
                      color: theme.colorScheme.surface.withValues(
                        alpha: dark ? 0.55 : 0.4,
                      ),
                    ),
                  ],
                ),
              ),
      );
    },
  );
}

class _WallPainter extends CustomPainter {
  final String style;
  final ColorScheme cs;
  final bool dark;
  final double pattern;
  _WallPainter(this.style, this.cs, this.dark, this.pattern);

  /// 1 at the starting strength.
  double get k => (pattern / 0.55).clamp(0.0, 1.8);

  Color _mix(Color a, Color b, double t) => Color.lerp(a, b, t)!;

  double _a(double v) => (v * k).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    switch (style) {
      case 'doodles':
        _doodles(canvas, size);
      case 'flow':
        _flow(canvas, size);
      case 'shapes':
        _shapes(canvas, size);
      case 'waves':
        _waves(canvas, size);
      case 'dots':
        _dots(canvas, size);
    }
  }

  // little line drawings on a soft tone of the theme
  void _doodles(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = _mix(cs.surface, cs.primaryContainer, dark ? 0.32 : 0.38),
    );
    _Doodles.paint(
      canvas,
      size,
      cs.primary.withValues(alpha: _a(dark ? 0.16 : 0.2)),
      7,
    );
  }

  // soft colour flowing between the theme's colours, faint doodles over it
  void _flow(Canvas canvas, Size size) {
    final sx = size.width / 390, sy = size.height / 844;
    final cols = dark
        ? [
            _mix(cs.primaryContainer, cs.surface, 0.3),
            _mix(cs.tertiaryContainer, cs.surface, 0.35),
            _mix(cs.secondaryContainer, cs.surface, 0.4),
            _mix(cs.primaryContainer, cs.surface, 0.62),
          ]
        : [
            _mix(cs.primaryContainer, cs.surface, 0.05),
            _mix(cs.tertiaryContainer, cs.surface, 0.05),
            _mix(cs.secondaryContainer, cs.surface, 0.15),
            _mix(cs.primaryContainer, cs.surface, 0.45),
          ];
    canvas.drawRect(Offset.zero & size, Paint()..color = cols[3]);
    const blobs = [
      (70.0, 120.0, 330.0),
      (340.0, 260.0, 300.0),
      (40.0, 600.0, 340.0),
      (330.0, 760.0, 320.0),
    ];
    final soft = Paint()
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 70 * sx);
    for (var i = 0; i < blobs.length; i++) {
      final (x, y, r) = blobs[i];
      soft.color = cols[i];
      canvas.drawCircle(Offset(x * sx, y * sy), r * 0.62 * sx, soft);
    }
    _Doodles.paint(
      canvas,
      size,
      dark
          ? Colors.white.withValues(alpha: _a(0.07))
          : _mix(cs.primary, Colors.black, 0.3).withValues(alpha: _a(0.13)),
      11,
    );
  }

  // big, calm shapes in the theme's tones
  void _shapes(Canvas canvas, Size size) {
    final sx = size.width / 390, sy = size.height / 844;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = _mix(cs.surface, cs.secondaryContainer, dark ? 0.25 : 0.3),
    );
    final c = [cs.primaryContainer, cs.tertiaryContainer, cs.secondaryContainer];
    Offset at(double x, double y) => Offset(x * sx, y * sy);
    canvas.saveLayer(
      Offset.zero & size,
      Paint()..color = Colors.black.withValues(alpha: _a(dark ? 0.55 : 0.7)),
    );
    void flower(double x, double y, double r, Color col, double rot) {
      final p = Path();
      for (var i = 0; i <= 16; i++) {
        final ang = (rot + i * 180 / 8) * math.pi / 180;
        final rr = (i.isEven ? r : r * 0.8) * sx;
        final pt = at(x, y) + Offset(rr * math.cos(ang), rr * math.sin(ang));
        if (i == 0) {
          p.moveTo(pt.dx, pt.dy);
        } else {
          p.lineTo(pt.dx, pt.dy);
        }
      }
      p.close();
      canvas.drawPath(p, Paint()..color = col);
      canvas.drawPath(
        p,
        Paint()
          ..color = col
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.5 * sx
          ..strokeJoin = StrokeJoin.round,
      );
    }

    void turned(double x, double y, double deg, void Function() draw) {
      canvas.save();
      canvas.translate(x * sx, y * sy);
      canvas.rotate(deg * math.pi / 180);
      draw();
      canvas.restore();
    }

    void pill(double x, double y, double l, double w, Color col, double deg) =>
        turned(x, y, deg, () {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset.zero, width: l * sx, height: w * sx),
              Radius.circular(w * sx / 2),
            ),
            Paint()..color = col,
          );
        });
    void blob(double x, double y, double r, Color col) =>
        canvas.drawCircle(at(x, y), r * sx, Paint()..color = col);
    void arch(double x, double y, double w, Color col, double deg) =>
        turned(x, y, deg, () {
          final h = w / 2 * sx;
          canvas.drawPath(
            Path()
              ..moveTo(-h, h)
              ..lineTo(-h, 0)
              ..arcToPoint(Offset(h, 0), radius: Radius.circular(h))
              ..lineTo(h, h)
              ..close(),
            Paint()..color = col,
          );
        });
    flower(330, 110, 70, c[0], 10);
    pill(60, 250, 150, 54, c[1], -35);
    blob(360, 380, 44, c[2]);
    arch(70, 470, 96, c[0], 15);
    flower(300, 620, 56, c[1], 30);
    pill(110, 740, 170, 58, c[2], 25);
    blob(40, 60, 30, c[1]);
    blob(200, 540, 18, c[0]);
    arch(345, 820, 80, c[0], -20);
    canvas.restore();
  }

  // layered hills of the theme colour, a small sun on the horizon
  void _waves(Canvas canvas, Size size) {
    final sx = size.width / 390, sy = size.height / 844;
    final sky = _mix(cs.surface, cs.primaryContainer, dark ? 0.2 : 0.26);
    canvas.drawRect(Offset.zero & size, Paint()..color = sky);
    final sun = dark
        ? _mix(cs.tertiary, cs.surface, 0.45)
        : _mix(cs.tertiaryContainer, cs.tertiary, 0.15);
    final s = k.clamp(0.0, 1.0);
    canvas.drawCircle(
      Offset(292 * sx, 402 * sy),
      34 * sx,
      Paint()..color = _mix(sky, sun, s),
    );
    const bands = [
      (430.0, 300.0, 22.0, 0.0),
      (520.0, 250.0, 20.0, 1.6),
      (620.0, 330.0, 24.0, 3.1),
      (720.0, 280.0, 18.0, 4.4),
    ];
    final depth = dark ? [0.1, 0.16, 0.23, 0.31] : [0.12, 0.2, 0.28, 0.38];
    for (var i = 0; i < bands.length; i++) {
      final (base, wave, amp, phase) = bands[i];
      final band = _mix(sky, _mix(cs.surface, cs.primary, depth[i]), s);
      final p = Path()
        ..moveTo(0, size.height)
        ..lineTo(0, (base + amp * math.sin(phase)) * sy);
      for (var x = 0.0; x <= size.width + 6; x += 6) {
        p.lineTo(
          x,
          (base + amp * math.sin(2 * math.pi * (x / sx) / wave + phase)) * sy,
        );
      }
      p
        ..lineTo(size.width, size.height)
        ..close();
      canvas.drawPath(p, Paint()..color = band);
    }
  }

  // a fine dot grid with a glow in two corners
  void _dots(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()..color = _mix(cs.surface, cs.primaryContainer, dark ? 0.12 : 0.14),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0.6, -0.8),
          radius: 1.1,
          colors: [
            cs.primaryContainer.withValues(alpha: 0.9),
            cs.primaryContainer.withValues(alpha: 0),
          ],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.8, 0.9),
          radius: 0.9,
          colors: [
            cs.tertiaryContainer.withValues(alpha: 0.7),
            cs.tertiaryContainer.withValues(alpha: 0),
          ],
        ).createShader(rect),
    );
    final dot = Paint()
      ..color = (dark ? _mix(cs.primary, cs.surface, 0.2) : cs.primary)
          .withValues(alpha: _a(dark ? 0.28 : 0.32));
    for (var y = 10.0; y < size.height; y += 20) {
      for (var x = 10.0; x < size.width; x += 20) {
        canvas.drawCircle(Offset(x, y), 1.3, dot);
      }
    }
  }

  @override
  bool shouldRepaint(_WallPainter old) =>
      old.style != style ||
      old.cs != cs ||
      old.dark != dark ||
      old.pattern != pattern;
}

/// Keepr's doodles: bubbles, hearts, Bujji, notes, leaves, stars… drawn as
/// lines on a 24 box and scattered over a square that repeats.
abstract class _Doodles {
  static const _data = [
    // a chat bubble
    'M4 6.5a3.5 3.5 0 0 1 3.5-3.5h9A3.5 3.5 0 0 1 20 6.5v5a3.5 3.5 0 0 1-3.5 3.5H11l-4.5 4v-4A3 3 0 0 1 4 12zM8.5 9h7M8.5 12h4',
    // a heart
    'M12 20C12 20 4.5 15.4 4.5 9.8A4.3 4.3 0 0 1 12 7a4.3 4.3 0 0 1 7.5 2.8C19.5 15.4 12 20 12 20z',
    // a sparkle
    'M12 2.5c.7 5.2 2.3 6.8 7.5 7.5-5.2.7-6.8 2.3-7.5 7.5-.7-5.2-2.3-6.8-7.5-7.5 5.2-.7 6.8-2.3 7.5-7.5z',
    // a lock
    'M8 10.5h8a3 3 0 0 1 3 3v4a3 3 0 0 1-3 3H8a3 3 0 0 1-3-3v-4a3 3 0 0 1 3-3zM8 10.5V8a4 4 0 0 1 8 0v2.5M12 14.5v2.5',
    // a paper plane
    'M3 11.2 20.5 4 14 20.5l-3.2-6.7zM10.8 13.8 20.5 4',
    // a music note
    'M9 17.5V5.5l10-2v12M4 17.5a2.5 2.5 0 1 0 5 0a2.5 2.5 0 1 0-5 0M14 15.5a2.5 2.5 0 1 0 5 0a2.5 2.5 0 1 0-5 0',
    // a leaf
    'M5 19C5 10.5 10.5 5 19 5c0 8.5-5.5 14-14 14zM5 19 13 11',
    // the moon
    'M19.5 14.5A8 8 0 1 1 9.5 4.5a6.3 6.3 0 0 0 10 10z',
    // a cup
    'M5 10h11v4a5 5 0 0 1-5 5h-1a5 5 0 0 1-5-5zM16 11h1.5a2.5 2.5 0 0 1 0 5H16M8.5 3.5c0 1.6 1.5 1.6 1.5 3.5M12.5 3.5c0 1.6 1.5 1.6 1.5 3.5',
    // a cloud
    'M7.5 18.5h9.5a3.8 3.8 0 0 0 .3-7.6A5.8 5.8 0 0 0 6.2 12a3.3 3.3 0 0 0 1.3 6.5z',
    // a smile
    'M3.5 12a8.5 8.5 0 1 0 17 0a8.5 8.5 0 1 0-17 0M8.8 14.2a4.2 4.2 0 0 0 6.4 0M9.3 9.6v.8M14.7 9.6v.8',
    // Bujji
    'M4 16.2C4 10 7.6 6 12 6C16.4 6 20 10 20 16.2c0 1.9-1.4 2.8-3.4 2.8H7.4C5.4 19 4 18.1 4 16.2zM9.6 11.6v1.6M14.4 11.6v1.6M10.6 15.4a2.2 2.2 0 0 0 2.8 0',
    // a camera
    'M6.5 7h11a3 3 0 0 1 3 3v6a3 3 0 0 1-3 3h-11a3 3 0 0 1-3-3v-6a3 3 0 0 1 3-3zM9 7l1.4-2.5h3.2L15 7M8.8 13a3.2 3.2 0 1 0 6.4 0a3.2 3.2 0 1 0-6.4 0',
    // a balloon
    'M12 15.5c-3.6 0-6-3-6-6.3a6 6 0 0 1 12 0c0 3.3-2.4 6.3-6 6.3zM12 15.5l-1 1.5h2l-1-1.5M12 17c0 2 1.5 2.5 0 4.5',
    // a gift
    'M6.5 9.5h11a2 2 0 0 1 2 2v6.5a2 2 0 0 1-2 2h-11a2 2 0 0 1-2-2v-6.5a2 2 0 0 1 2-2zM3.5 9.5h17M12 9.5V20M12 9.5C9 9.5 7.5 5 10 5c1.4 0 2 2 2 4.5 0-2.5.6-4.5 2-4.5 2.5 0 1 4.5-2 4.5',
    // a star
    'M12 4l2.4 5 5.4.6-4 3.7 1.1 5.3L12 16l-4.9 2.6 1.1-5.3-4-3.7 5.4-.6z',
    // a pin
    'M12 20.5C12 20.5 6 14.9 6 10.1a6 6 0 0 1 12 0c0 4.8-6 10.4-6 10.4zM9.8 10a2.2 2.2 0 1 0 4.4 0a2.2 2.2 0 1 0-4.4 0',
    // an umbrella
    'M3.5 12a8.5 8.5 0 0 1 17 0zM12 12v6a2 2 0 0 1-4 0',
  ];

  static final List<Path> _paths = [for (final d in _data) _svg(d)];
  static final _tiles = <int, List<_Mark>>{};
  static const _tile = 210.0;

  static void paint(Canvas canvas, Size size, Color color, int seed) {
    if (color.a == 0) return;
    final marks = _tiles[seed] ??= _make(seed);
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final dot = Paint()..color = color;
    for (var ty = -_tile; ty < size.height + _tile; ty += _tile) {
      for (var tx = -_tile; tx < size.width + _tile; tx += _tile) {
        for (final m in marks) {
          canvas.save();
          canvas.translate(tx + m.x, ty + m.y);
          final path = m.path;
          if (path == null) {
            if (m.dot) {
              canvas.drawCircle(Offset.zero, 1.6, dot);
            } else {
              line.strokeWidth = 1.5;
              canvas.drawLine(const Offset(-3.2, 0), const Offset(3.2, 0), line);
              canvas.drawLine(const Offset(0, -3.2), const Offset(0, 3.2), line);
            }
          } else {
            canvas.rotate(m.turn);
            final s = m.size / 24;
            canvas.scale(s);
            canvas.translate(-12, -12);
            line.strokeWidth = 1.5 / s;
            canvas.drawPath(path, line);
          }
          canvas.restore();
        }
      }
    }
  }

  static List<_Mark> _make(int seed) {
    final r = math.Random(seed);
    const cells = 5, step = _tile / cells;
    double jitter(double by) => (r.nextDouble() * 2 - 1) * step * by;
    final out = <_Mark>[];
    var k = 0;
    for (var gy = 0; gy < cells; gy++) {
      for (var gx = 0; gx < cells; gx++) {
        final cx = gx * step + step / 2, cy = gy * step + step / 2;
        if ((gx + gy).isOdd && r.nextDouble() < 0.55) {
          // a small dot or plus in between
          out.add(_Mark(cx + jitter(.25), cy + jitter(.25), 0, 0, null, r.nextBool()));
          continue;
        }
        final path = _paths[(k * 7 + seed) % _paths.length];
        k++;
        final size = 22 + r.nextDouble() * 8;
        final x = cx + jitter(.18), y = cy + jitter(.18);
        final turn = (r.nextDouble() * 2 - 1) * 28 * math.pi / 180;
        out.add(_Mark(x, y, size, turn, path, false));
      }
    }
    return out;
  }

  /// A path from SVG path data (M L H V C Q A Z, with relative forms).
  static Path _svg(String d) {
    final tokens = RegExp(
      r'[MmLlHhVvCcQqAaZz]|[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?',
    ).allMatches(d).map((m) => m.group(0)!).toList();
    final path = Path();
    var i = 0;
    var cmd = '';
    double x = 0, y = 0, sx = 0, sy = 0;
    double n() => double.parse(tokens[i++]);
    bool isCmd(String t) => RegExp(r'^[A-Za-z]$').hasMatch(t);
    while (i < tokens.length) {
      if (isCmd(tokens[i])) {
        cmd = tokens[i++];
      } else if (cmd.isEmpty) {
        i++;
        continue;
      }
      switch (cmd) {
        case 'M':
          x = n();
          y = n();
          path.moveTo(x, y);
          sx = x;
          sy = y;
          cmd = 'L';
        case 'm':
          x += n();
          y += n();
          path.moveTo(x, y);
          sx = x;
          sy = y;
          cmd = 'l';
        case 'L':
          x = n();
          y = n();
          path.lineTo(x, y);
        case 'l':
          x += n();
          y += n();
          path.lineTo(x, y);
        case 'H':
          x = n();
          path.lineTo(x, y);
        case 'h':
          x += n();
          path.lineTo(x, y);
        case 'V':
          y = n();
          path.lineTo(x, y);
        case 'v':
          y += n();
          path.lineTo(x, y);
        case 'C':
          final a = n(), b = n(), c = n(), e = n();
          x = n();
          y = n();
          path.cubicTo(a, b, c, e, x, y);
        case 'c':
          final a = x + n(), b = y + n(), c = x + n(), e = y + n();
          x += n();
          y += n();
          path.cubicTo(a, b, c, e, x, y);
        case 'Q':
          final a = n(), b = n();
          x = n();
          y = n();
          path.quadraticBezierTo(a, b, x, y);
        case 'q':
          final a = x + n(), b = y + n();
          x += n();
          y += n();
          path.quadraticBezierTo(a, b, x, y);
        case 'A':
        case 'a':
          final rx = n(), ry = n(), turn = n();
          final large = n() != 0, sweep = n() != 0;
          if (cmd == 'A') {
            x = n();
            y = n();
          } else {
            x += n();
            y += n();
          }
          path.arcToPoint(
            Offset(x, y),
            radius: Radius.elliptical(rx, ry),
            rotation: turn,
            largeArc: large,
            clockwise: sweep,
          );
        case 'Z':
        case 'z':
          path.close();
          x = sx;
          y = sy;
          cmd = '';
        default:
          i++;
      }
    }
    return path;
  }
}

class _Mark {
  final double x, y, size, turn;
  final Path? path;
  final bool dot;
  const _Mark(this.x, this.y, this.size, this.turn, this.path, this.dot);
}

/// Customisation > Wallpaper: Keepr's own (each a small chat in it), or
/// your photo, with how strongly the drawings show and how far the photo
/// fades back.
class VibeWallpaperPage extends StatefulWidget {
  const VibeWallpaperPage({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => const VibeWallpaperPage()));

  @override
  State<VibeWallpaperPage> createState() => _VibeWallpaperPageState();
}

class _VibeWallpaperPageState extends State<VibeWallpaperPage> {
  double? _pattern, _dim;

  Future<void> _pick(String s) async {
    VibeHaptics.selection();
    await VibeWallpaper.setStyle(s);
    if (mounted) setState(() {});
  }

  /// Your photo: back to it, or a new one when it's already on (or there's
  /// none yet).
  Future<void> _photo() async {
    final client = Matrix.of(context).client;
    final has = client.applicationAccountConfig.wallpaperUrl != null;
    if (has && VibeWallpaper.style != 'photo') return _pick('photo');
    final picked = (await selectFiles(context, type: FileType.image)).firstOrNull;
    if (picked == null || !mounted) return;
    final r = await showFutureLoadingDialog(
      context: context,
      future: () async {
        final url = await client.uploadContent(
          await picked.readAsBytes(),
          filename: picked.name,
        );
        await client.updateApplicationAccountConfig(
          ApplicationAccountConfig(wallpaperUrl: url),
        );
      },
    );
    if (r.isValue) await _pick('photo');
  }

  Future<void> _removePhoto() async {
    final client = Matrix.of(context).client;
    final r = await showFutureLoadingDialog(
      context: context,
      future: () => client.setApplicationAccountConfig(
        const ApplicationAccountConfig(wallpaperUrl: null, wallpaperBlur: null),
      ),
    );
    if (r.isValue) await _pick('none');
  }

  /// What Music needs and what it's showing.
  Widget _musicNote(ColorScheme cs) {
    final style = TextStyle(fontSize: 13.5, height: 1.4, color: cs.onSurfaceVariant);
    final service = VibeConnections.service;
    final t = VibeConnections.playing.value;
    if (service == null) {
      // not connected yet: connect one right here
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Music shows the cover of what you\'re playing. Connect '
              'Last.fm or ListenBrainz so Keepr knows the song.',
              style: style,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in VibeService.values)
                  if (VibeConnections.available(s))
                    FilledButton.tonalIcon(
                      onPressed: () => VibeConnectSheet.show(context, s),
                      icon: Icon(s.icon, size: 18),
                      label: Text(s.label),
                    ),
              ],
            ),
          ],
        ),
      );
    }
    final text = !VibeConnections.sharing
        ? 'Sharing what you play is off in Connections on your profile. '
              'Turn it on so Keepr knows the song.'
        : t == null
        ? 'Nothing playing right now, so Flow shows until a song starts. '
              'Keepr checks ${service.label} every 30 seconds.'
        : 'Now: ${t.title}${t.artist.isEmpty ? '' : ' · ${t.artist}'}. '
              'The cover changes with the song.';
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.music_note_rounded, size: 20, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: style)),
        ],
      ),
    );
  }

  Widget _slider(
    String title,
    String sub,
    double value,
    ValueChanged<double> slide,
    ValueChanged<double> done,
  ) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  '${(value * 100).round()}%',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Text(sub, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          Slider(value: value, onChanged: slide, onChangeEnd: done),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final client = Matrix.of(context).client;
    return ListenableBuilder(
      listenable: Listenable.merge([
        VibeConnections.playing,
        VibeConnections.changed,
      ]),
      builder: (context, _) => _page(context, client),
    );
  }

  Widget _page(BuildContext context, Client client) {
    return StreamBuilder(
      stream: client.onSync.stream.where(
        (u) =>
            u.accountData?.any(
              (a) => a.type == ApplicationAccountConfigExtension.accountDataKey,
            ) ??
            false,
      ),
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        final config = client.applicationAccountConfig;
        final style = VibeWallpaper.style;
        final photo = config.wallpaperUrl;
        final photoOn = style == 'photo' && photo != null;
        final noneOn = style == 'none' || (style == 'photo' && photo == null);
        return VibeTitledPage(
          title: 'Wallpaper',
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text(
                "Keepr's own wallpapers take your theme's colours, light and "
                'dark, so they always match.',
                style: TextStyle(fontSize: 14, height: 1.4, color: cs.onSurfaceVariant),
              ),
            ),
            const VibeSectionLabel('Keepr wallpapers'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: LayoutBuilder(
                builder: (context, c) {
                  final w = ((c.maxWidth - 24) / 3).clamp(80.0, 150.0);
                  Widget tile(String s) => _Tile(
                    width: w,
                    label: VibeWallpaper.names[s]!,
                    picked: s == 'none' ? noneOn : style == s,
                    onTap: () => _pick(s),
                    child: s == 'none' ? null : VibeWallpaperPaint(style: s),
                  );
                  return Wrap(
                    spacing: 12,
                    runSpacing: 14,
                    children: [
                      tile('none'),
                      for (final s in VibeWallpaper.styles) tile(s),
                    ],
                  );
                },
              ),
            ),
            const VibeSectionLabel('Your own'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: LayoutBuilder(
                builder: (context, c) {
                  final w = ((c.maxWidth - 24) / 3).clamp(80.0, 150.0);
                  final cover = VibeConnections.playing.value?.cover;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 14,
                    children: [
                      _Tile(
                        width: w,
                        label: 'Your photo',
                        picked: photoOn,
                        onTap: _photo,
                        icon: Icons.add_photo_alternate_outlined,
                        child: photo == null
                            ? null
                            : MxcImage(
                                uri: photo,
                                cacheKey: photo.toString(),
                                fit: BoxFit.cover,
                                width: 390,
                                height: 844,
                                placeholder: (_) => const SizedBox.shrink(),
                              ),
                      ),
                      // the cover of what you're playing
                      _Tile(
                        width: w,
                        label: 'Music',
                        picked: VibeWallpaper.music,
                        onTap: () => _pick('music'),
                        icon: Icons.music_note_rounded,
                        child: cover == null
                            ? null
                            : const VibeMusicWallpaper(),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: VibeCard(
                margin: EdgeInsets.zero,
                children: [
                  if (VibeWallpaper.painted)
                    _slider(
                      'Pattern',
                      'How strongly the drawings show',
                      _pattern ?? VibeWallpaper.pattern,
                      (v) => setState(() => _pattern = v),
                      (v) => VibeWallpaper.setPattern(v),
                    ),
                  if (photoOn) ...[
                    _slider(
                      'Dim',
                      'How far your photo fades back',
                      _dim ?? (1 - (config.wallpaperOpacity ?? 0.5)),
                      (v) => setState(() => _dim = v),
                      (v) => client.updateApplicationAccountConfig(
                        ApplicationAccountConfig(
                          wallpaperOpacity: (1 - v).clamp(0.05, 1.0),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                        child: TextButton(
                          onPressed: _removePhoto,
                          style: TextButton.styleFrom(foregroundColor: cs.error),
                          child: const Text('Remove photo'),
                        ),
                      ),
                    ),
                  ],
                  if (VibeWallpaper.music) _musicNote(cs),
                  if (!VibeWallpaper.painted && !photoOn && !VibeWallpaper.music)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        "Pick one of Keepr's wallpapers above, tap Your photo "
                        'to use a picture of yours (it stays on your account, '
                        'softened to fit), or Music for the cover of what '
                        "you're playing.",
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.4,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 32),
          ],
        );
      },
    );
  }
}

/// A wallpaper choice: a small chat on it, a ring and a tick when picked.
class _Tile extends StatelessWidget {
  final double width;
  final String label;
  final bool picked;
  final VoidCallback onTap;
  final Widget? child;
  final IconData? icon;
  const _Tile({
    required this.width,
    required this.label,
    required this.picked,
    required this.onTap,
    this.child,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final h = width * 1.45;
    Widget bar(Color c, double w) => Container(
      width: w,
      height: 11,
      decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(6)),
    );
    final inner = child;
    final mark = icon;
    return Semantics(
      button: true,
      selected: picked,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: width,
          child: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: width,
                height: h,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: picked ? cs.primary : cs.outlineVariant,
                    width: picked ? 3 : 1,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(picked ? 15 : 17),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(
                        color: inner == null && mark != null
                            ? cs.surfaceContainer
                            : cs.surface,
                      ),
                      if (inner != null)
                        FittedBox(
                          fit: BoxFit.cover,
                          alignment: Alignment.topCenter,
                          child: SizedBox(width: 390, height: 844, child: inner),
                        ),
                      if (inner == null && mark != null)
                        Center(
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: cs.primaryContainer,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(mark, size: 22, color: cs.onPrimaryContainer),
                          ),
                        )
                      else ...[
                        // two small messages on it
                        Positioned(
                          left: 9,
                          bottom: h * 0.36,
                          child: bar(cs.tertiaryContainer, width * 0.55),
                        ),
                        Positioned(
                          right: 9,
                          bottom: h * 0.2,
                          child: bar(cs.primaryContainer, width * 0.62),
                        ),
                      ],
                      if (picked)
                        Positioned(
                          left: 7,
                          top: 7,
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: cs.primary,
                              shape: BoxShape.circle,
                              border: Border.all(color: cs.surface, width: 2),
                            ),
                            child: Icon(Icons.check_rounded, size: 14, color: cs.onPrimary),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 7),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: picked ? FontWeight.w700 : FontWeight.w600,
                  color: picked ? cs.primary : cs.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

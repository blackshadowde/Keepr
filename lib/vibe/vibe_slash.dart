// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:matrix/matrix.dart';
import 'package:vibe/vibe/vibe_haptics.dart';
import 'package:vibe/vibe/vibe_samurai.dart';
import 'package:flutter/material.dart';

/// Deleting a message: a small samurai (straw hat, red headband, big
/// katana) drops in at the end of the message and cuts it in one dash; it
/// falls apart behind his back. Without looking back he drives his sword
/// into the ground where it was, springs clear and walks away slowly (see
/// [VibeSamuraiPainter]).
///
/// It all happens over the message's own row, takes about 3.4 s, and is
/// skipped when the phone asks for reduced motion.
abstract class VibeSlash {
  static final active = ValueNotifier<Set<String>>({});
  static const duration = Duration(milliseconds: 3400);

  /// Plays the slash on [eventIds] and completes when the cut is done.
  static Future<void> play(BuildContext context, Iterable<String> eventIds) async {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
    final ids = eventIds.toSet();
    if (ids.isEmpty) return;
    // let the message menu / confirm dialog finish sliding down first
    await Future<void>.delayed(const Duration(milliseconds: 420));
    active.value = {...active.value, ...ids};
    await Future<void>.delayed(duration);
  }

  /// The rows go back to normal (after the message was deleted or hidden).
  static void clear(Iterable<String> eventIds) {
    final ids = eventIds.toSet();
    active.value = {...active.value}..removeAll(ids);
  }

  // ---- the other side: someone else deleted a message for everyone

  /// Recently shown messages, as they were before any deletion (the SDK
  /// empties a message in place when it is deleted).
  static final _shown = <String, Map<String, Object?>>{};
  static final _played = <String>{};

  static void remember(Event e) {
    if (e.redacted || _shown.containsKey(e.eventId)) return;
    if (!{EventTypes.Message, EventTypes.Sticker}.contains(e.type)) return;
    try {
      _shown[e.eventId] = e.toJson();
    } catch (_) {
      return;
    }
    if (_shown.length > 300) _shown.remove(_shown.keys.first);
  }

  /// The message as it was, while the samurai cuts it.
  static Event original(Event e) {
    final json = _shown[e.eventId];
    if (json == null || !e.redacted) return e;
    try {
      return Event.fromJson(json, e.room);
    } catch (_) {
      return e;
    }
  }

  /// A message on screen was just deleted by someone else: play the cut.
  static void maybePlayRemote(Event e) {
    if (!e.redacted || _played.contains(e.eventId)) return;
    if (!_shown.containsKey(e.eventId)) return;
    final by = e.redactedBecause;
    if (by == null || by.senderId == e.room.client.userID) return;
    if (DateTime.now().difference(by.originServerTs).inSeconds.abs() > 20) {
      return;
    }
    _played.add(e.eventId);
    final id = e.eventId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      active.value = {...active.value, id};
      Future<void>.delayed(
        duration + const Duration(milliseconds: 250),
        () => clear([id]),
      );
    });
  }
}

/// Wraps one message row; plays the samurai when its id is slashed.
class VibeSlashRow extends StatefulWidget {
  final String eventId;
  final Widget child;
  const VibeSlashRow({required this.eventId, required this.child, super.key});

  @override
  State<VibeSlashRow> createState() => _VibeSlashRowState();
}

class _VibeSlashRowState extends State<VibeSlashRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: VibeSlash.duration,
  );
  final _boundary = GlobalKey();
  bool _slashBuzz = false;
  bool _plantBuzz = false;
  // a picture of the row, cut in two when the message falls apart
  ui.Image? _shot;
  // the message's card in the row (the samurai stands on its bottom edge)
  Rect? _card;

  @override
  void initState() {
    super.initState();
    VibeSlash.active.addListener(_check);
    _c.addListener(() {
      final ms = _c.value * VibeSamurai.total;
      if (!_slashBuzz && ms >= VibeSamurai.draw) {
        _slashBuzz = true;
        VibeHaptics.light();
      }
      if (!_plantBuzz && ms >= VibeSamurai.impact) {
        _plantBuzz = true;
        VibeHaptics.heavy();
      }
    });
    _check();
  }

  void _check() {
    final on = VibeSlash.active.value.contains(widget.eventId);
    if (on && !_c.isAnimating && _c.value == 0) {
      _slashBuzz = _plantBuzz = false;
      _c.forward();
      WidgetsBinding.instance.addPostFrameCallback((_) => _capture());
    } else if (!on && _c.value != 0) {
      _c.value = 0;
      _forget();
    }
  }

  void _capture() {
    if (!mounted) return;
    final row = context.findRenderObject();
    if (row is! RenderBox || !row.hasSize) return;
    // find the message's card (marked with VibeSlashBubble)
    Rect? card;
    void visit(RenderObject o) {
      if (card != null) return;
      if (o is RenderMetaData && o.metaData is VibeSlashBubble && o.hasSize) {
        card = o.localToGlobal(Offset.zero, ancestor: row) & o.size;
        return;
      }
      o.visitChildren(visit);
    }

    row.visitChildren(visit);
    final w = row.size.width, h = row.size.height;
    _card = card ??
        Rect.fromLTRB(math.min(58.0, w * 0.18), math.max(0.0, h - 46), w * 0.86, h - 2);
    final b = _boundary.currentContext?.findRenderObject();
    if (b is RenderRepaintBoundary) {
      try {
        _shot?.dispose();
        _shot = b.toImageSync(pixelRatio: View.of(context).devicePixelRatio);
      } catch (_) {
        _shot = null;
      }
    }
    if (mounted) setState(() {});
  }

  void _forget() {
    _shot?.dispose();
    _shot = null;
    _card = null;
  }

  @override
  void dispose() {
    VibeSlash.active.removeListener(_check);
    _c.dispose();
    _forget();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        if (_c.value == 0) return child!;
        final ms = _c.value * VibeSamurai.total;
        final theme = Theme.of(context);
        final card = _card;
        // the message: whole until it falls apart, then its picture takes
        // over (or, without one, it fades as it crumbles)
        final gone = ms >= VibeSamurai.split
            ? (_shot != null ? 0.0 : 1 - _seg(ms, 1180, 1420))
            : 1.0;
        // the row shudders when the sword hits the ground
        final sp = _seg(ms, VibeSamurai.impact, VibeSamurai.impact + 180);
        final shake = sp > 0 && sp < 1
            ? Offset(
                math.sin(sp * math.pi * 7) * 3.2 * (1 - sp),
                math.cos(sp * math.pi * 9) * 1.1 * (1 - sp),
              )
            : Offset.zero;
        return Transform.translate(
          offset: shake,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Opacity(
                opacity: gone,
                child: RepaintBoundary(key: _boundary, child: child),
              ),
              if (card != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: VibeSamuraiPainter(
                        t: ms,
                        bubble: card,
                        row: _shot,
                        ink: theme.colorScheme.onSurface,
                        crumb: theme.colorScheme.outline,
                        dark: theme.brightness == Brightness.dark,
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
}

/// Marks the message's card, so the samurai knows where to stand and cut.
class VibeSlashBubble {
  const VibeSlashBubble();
}

double _seg(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);

const _red = Color(0xFFE53935);
const _steel = Color(0xFFD9DEE4);

/// The katana stuck in the grass. (0,0) = where the blade meets the ground.
void paintPlantedSword(
  Canvas canvas,
  double h,
  Color ink, {
  double opacity = 1,
  double grass = 1,
}) {
  final o = opacity.clamp(0.0, 1.0);
  // slightly leaning, like the reference picture
  canvas.save();
  canvas.rotate(-0.22);
  final blade = Paint()
    ..color = _steel.withValues(alpha: o)
    ..strokeWidth = math.max(1.6, h * 0.05)
    ..strokeCap = StrokeCap.butt;
  canvas.drawLine(const Offset(0, 4), Offset(0, -h * 0.62), blade);
  canvas.drawLine(
    Offset(h * 0.012, 2),
    Offset(h * 0.012, -h * 0.6),
    Paint()
      ..color = Colors.white.withValues(alpha: 0.7 * o)
      ..strokeWidth = 0.8,
  );
  final guardY = -h * 0.64;
  canvas.drawOval(
    Rect.fromCenter(center: Offset(0, guardY), width: h * 0.17, height: h * 0.05),
    Paint()..color = const Color(0xFF2B2B2B).withValues(alpha: o),
  );
  final top = -h * 0.98;
  canvas.drawLine(
    Offset(0, guardY - 1),
    Offset(0, top),
    Paint()
      ..color = const Color(0xFFF2F2F2).withValues(alpha: o)
      ..strokeWidth = math.max(2.6, h * 0.085)
      ..strokeCap = StrokeCap.round,
  );
  final wrap = Paint()
    ..color = const Color(0xFF1E1E1E).withValues(alpha: o)
    ..strokeWidth = 1.1;
  for (var i = 0; i < 4; i++) {
    final y = guardY - 3 + (top - guardY + 3) * (i + 0.5) / 4;
    canvas.drawLine(Offset(-h * 0.035, y - 2), Offset(h * 0.035, y + 2), wrap);
  }
  // a red cord tied below the guard, blowing in the wind
  final cord = Paint()
    ..color = _red.withValues(alpha: o)
    ..strokeWidth = math.max(1.4, h * 0.03)
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  canvas.drawPath(
    Path()
      ..moveTo(0, guardY - h * 0.06)
      ..quadraticBezierTo(h * 0.16, guardY - h * 0.02, h * 0.24, guardY + h * 0.1),
    cord,
  );
  canvas.restore();

  // silver pampas grass around the blade
  if (grass <= 0) return;
  final g = Paint()
    ..color = Color.lerp(ink, const Color(0xFFBFB7A6), 0.55)!
        .withValues(alpha: 0.85 * o * grass)
    ..strokeWidth = 1.3
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  const blades = [-0.5, -0.32, -0.16, 0.12, 0.26, 0.42, 0.56];
  for (var i = 0; i < blades.length; i++) {
    final bx = blades[i] * h;
    final len = h * (0.18 + 0.1 * ((i * 37) % 5) / 4) * grass;
    final lean = (i.isEven ? -1 : 1) * h * 0.08;
    final path = Path()
      ..moveTo(bx, 2)
      ..quadraticBezierTo(bx + lean * 0.3, -len * 0.6, bx + lean, -len);
    canvas.drawPath(path, g);
  }
  canvas.drawLine(
    Offset(-h * 0.6, 2),
    Offset(h * 0.65, 2),
    g..strokeWidth = 1,
  );
}

/// Shown where a deleted message was: the planted sword and "deleted".
class VibeSwordField extends StatelessWidget {
  final Color color;
  final double fontSize;
  final String label;
  final VoidCallback? onTap;
  const VibeSwordField({
    required this.color,
    required this.label,
    this.fontSize = 14,
    this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final ink = Theme.of(context).colorScheme.onSurface;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 44,
              height: 38,
              child: CustomPaint(painter: _FieldPainter(ink)),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: fontSize * 0.9,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldPainter extends CustomPainter {
  final Color ink;
  _FieldPainter(this.ink);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width * 0.5, size.height - 3);
    paintPlantedSword(canvas, size.height * 0.95, ink);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FieldPainter old) => old.ink != ink;
}

// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:matrix/matrix.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:vibe/config/setting_keys.dart';
import 'package:vibe/vibe/vibe_status.dart';
import 'package:vibe/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';

/// The typing buddy: a small blob in the theme colour that lives on the
/// text box and reacts to what happens in the chat. Everything it does
/// happens on this phone; only whether it's on, its name, colour and
/// outfit are shared in direct chats, so the other person's Keepr can show
/// it in your typing circle.
enum BuddyMood { idle, happy, love, worried, sleepy, puzzled, cover, giggle }

enum BuddyProp { none, shield, paper, wave }

class BuddyOutfit {
  final String id;
  final String label;

  /// Messages sent with the buddy around before it unlocks.
  final int unlockAt;
  const BuddyOutfit(this.id, this.label, this.unlockAt);
}

abstract class VibeBuddy {
  static const stateType = 'chat.keepr.buddy';
  static const _on = 'keepr.buddy.on';
  static const _name = 'keepr.buddy.name';
  static const _share = 'keepr.buddy.share';
  static const _outfit = 'keepr.buddy.outfit';
  static const _count = 'keepr.buddy.sent';

  static const outfits = [
    BuddyOutfit('none', 'None', 0),
    BuddyOutfit('bow', 'Bow', 25),
    BuddyOutfit('cap', 'Cap', 100),
    BuddyOutfit('glasses', 'Glasses', 250),
    BuddyOutfit('headphones', 'Headphones', 500),
    BuddyOutfit('crown', 'Crown', 1000),
  ];

  /// Fires when a message goes out (the chat bumps it; the buddy hops).
  static final sent = ValueNotifier<int>(0);

  /// Fires when its settings change.
  static final changed = ValueNotifier<int>(0);

  static bool get on => AppSettings.store.getBool(_on) ?? true;
  static String get name => AppSettings.store.getString(_name) ?? 'Mochi';
  static bool get shared => AppSettings.store.getBool(_share) ?? true;
  static String get outfit => AppSettings.store.getString(_outfit) ?? 'none';
  static int get count => AppSettings.store.getInt(_count) ?? 0;

  static Future<void> set({
    bool? on,
    String? name,
    bool? shared,
    String? outfit,
  }) async {
    final s = AppSettings.store;
    if (on != null) await s.setBool(_on, on);
    if (name != null) await s.setString(_name, name);
    if (shared != null) await s.setBool(_share, shared);
    if (outfit != null) await s.setString(_outfit, outfit);
    _checked.clear();
    changed.value++;
  }

  static bool unlocked(BuddyOutfit o) => count >= o.unlockAt;

  /// Counts a sent message; returns an outfit it just unlocked, if any.
  static BuddyOutfit? noteSent() {
    if (!on) return null;
    final before = count;
    AppSettings.store.setInt(_count, before + 1);
    for (final o in outfits) {
      if (o.unlockAt > before && o.unlockAt <= before + 1) return o;
    }
    return null;
  }

  // ---- looks like a secret ----

  static final _card = RegExp(r'(?:\d[ -]?){13,19}');
  static final _pw = RegExp(
    r'\b(pass(word)?|passwd|pwd|pin|otp|cvv)\b\s*(is|:|=)?\s*\S{3,}',
    caseSensitive: false,
  );

  static bool _luhn(String digits) {
    var sum = 0;
    var alt = false;
    for (var i = digits.length - 1; i >= 0; i--) {
      var n = digits.codeUnitAt(i) - 48;
      if (alt) {
        n *= 2;
        if (n > 9) n -= 9;
      }
      sum += n;
      alt = !alt;
    }
    return sum % 10 == 0;
  }

  /// A card number, a "password: …" or a long mixed token.
  static bool looksSecret(String text) {
    for (final m in _card.allMatches(text)) {
      final d = m.group(0)!.replaceAll(RegExp(r'[ -]'), '');
      if (d.length >= 13 && d.length <= 19 && _luhn(d)) return true;
    }
    if (_pw.hasMatch(text)) return true;
    for (final w in text.split(RegExp(r'\s+'))) {
      if (w.length >= 10 &&
          !w.contains('://') &&
          RegExp(r'[a-z]').hasMatch(w) &&
          RegExp(r'[A-Z]').hasMatch(w) &&
          RegExp(r'\d').hasMatch(w) &&
          RegExp(r'[^A-Za-z0-9]').hasMatch(w)) {
        return true;
      }
    }
    return false;
  }

  /// Before sending: asks once if it looks like a secret.
  static Future<bool> allowSend(BuildContext context, String text) async {
    if (!on || !looksSecret(text)) return true;
    final r = await showOkCancelAlertDialog(
      context: context,
      title: 'Send this?',
      message:
          '$name thinks this looks like a password or card number. '
          'Everyone in this chat will see it.',
      okLabel: 'Send anyway',
      cancelLabel: "Don't send",
    );
    return r == OkCancelResult.ok;
  }

  // ---- shared in direct chats ----

  static final _checked = <String>{};

  /// Shares whether the buddy is on (and its name, colour and outfit) in a
  /// direct chat, so the other side can show it in your typing circle.
  static Future<void> shareIn(Room r, Color color) async {
    final me = r.client.userID;
    if (me == null || !_checked.add(r.id)) return;
    if (!r.isDirectChat || r.membership != Membership.join) return;
    if (!VibeStatus.visibleIn(r)) return;
    final want = on && shared
        ? {'on': true, 'name': name, 'color': color.toARGB32(), 'outfit': outfit}
        : <String, Object?>{};
    final have = r.getState(stateType, me)?.content ?? const {};
    if (jsonEncode(have) == jsonEncode(want)) return;
    try {
      await r.client.setRoomStateWithKey(r.id, stateType, me, want);
    } catch (_) {}
  }

  /// [userId]'s buddy in [r], or null when they have none showing.
  static ({String name, Color color, String outfit})? of(
    Room r,
    String userId,
  ) {
    final c = r.getState(stateType, userId)?.content;
    if (c == null || c['on'] != true) return null;
    final color = c.tryGet<int>('color');
    return (
      name: c.tryGet<String>('name') ?? 'Buddy',
      color: color == null ? const Color(0xFFFFB98E) : Color(color),
      outfit: c.tryGet<String>('outfit') ?? 'none',
    );
  }

  // ---- reminders ----

  /// A notification at [at] reminding you to reply in [r].
  static Future<void> remind(Room r, DateTime at, String who) async {
    await FlutterLocalNotificationsPlugin().zonedSchedule(
      id: 'remind_${r.id}'.hashCode,
      title: 'Reply to $who',
      body: '$name is reminding you, as you asked.',
      scheduledDate: tz.TZDateTime.from(at.toUtc(), tz.UTC),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: '${r.client.clientName}|${r.id}|',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'keepr_reminders',
          'Reminders',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }
}

/// The buddy itself: a soft blob with big eyes, cheeks, a mood, an outfit
/// and a prop. It breathes and blinks on its own; [hop] and [wiggle] play
/// once each time they change.
class VibeBuddyFace extends StatefulWidget {
  final double size;
  final Color color;
  final BuddyMood mood;
  final BuddyProp prop;
  final String outfit;

  /// Where it looks, -1 (left) to 1 (right).
  final double gaze;
  final int hop;
  final int wiggle;
  const VibeBuddyFace({
    required this.color,
    this.size = 40,
    this.mood = BuddyMood.idle,
    this.prop = BuddyProp.none,
    this.outfit = 'none',
    this.gaze = 0,
    this.hop = 0,
    this.wiggle = 0,
    super.key,
  });

  @override
  State<VibeBuddyFace> createState() => _VibeBuddyFaceState();
}

class _VibeBuddyFaceState extends State<VibeBuddyFace>
    with TickerProviderStateMixin {
  late final AnimationController _life = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat();
  late final AnimationController _hop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  );
  late final AnimationController _wiggle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  double _blink = 0;
  int _nextBlink = 0;

  @override
  void didUpdateWidget(VibeBuddyFace old) {
    super.didUpdateWidget(old);
    if (old.hop != widget.hop) _hop.forward(from: 0);
    if (old.wiggle != widget.wiggle) _wiggle.forward(from: 0);
  }

  @override
  void dispose() {
    _life.dispose();
    _hop.dispose();
    _wiggle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox(
      width: s * 1.3,
      height: s * 1.3,
      child: AnimatedBuilder(
        animation: Listenable.merge([_life, _hop, _wiggle]),
        builder: (context, _) {
          // blink every few seconds
          final now = DateTime.now().millisecondsSinceEpoch;
          if (now > _nextBlink) {
            _nextBlink = now + 2400 + math.Random().nextInt(3200);
          }
          final left = _nextBlink - now;
          _blink = left < 140 ? 1 - (left - 70).abs() / 70 : 0;
          final breathe = math.sin(_life.value * math.pi * 2);
          final h = _hop.value;
          // squash, jump, land
          final jump = h < 0.15
              ? 0.0
              : h < 0.7
              ? math.sin((h - 0.15) / 0.55 * math.pi)
              : 0.0;
          final squash = h == 0
              ? 0.0
              : h < 0.15
              ? h / 0.15
              : h > 0.7
              ? (1 - (h - 0.7) / 0.3) * 0.6
              : 0.0;
          final w = _wiggle.value;
          final tilt = w == 0
              ? 0.0
              : math.sin(w * math.pi * 6) * (1 - w) * 0.25;
          return Transform.translate(
            offset: Offset(0, -jump * s * 0.55 + breathe * s * 0.015),
            child: Transform.rotate(
              angle: tilt,
              alignment: Alignment.bottomCenter,
              child: Transform(
                alignment: Alignment.bottomCenter,
                transform: Matrix4.diagonal3Values(
                  1 + 0.14 * squash + 0.01 * breathe,
                  1 - 0.18 * squash - 0.01 * breathe,
                  1,
                ),
                child: CustomPaint(
                  painter: _BuddyPainter(
                    color: widget.color,
                    mood: widget.mood,
                    prop: widget.prop,
                    outfit: widget.outfit,
                    gaze: widget.gaze,
                    blink: _blink,
                    wave: _life.value,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _BuddyPainter extends CustomPainter {
  final Color color;
  final BuddyMood mood;
  final BuddyProp prop;
  final String outfit;
  final double gaze, blink, wave;
  const _BuddyPainter({
    required this.color,
    required this.mood,
    required this.prop,
    required this.outfit,
    required this.gaze,
    required this.blink,
    required this.wave,
  });

  @override
  void paint(Canvas canvas, Size box) {
    // the body sits at the bottom of the box, with room above for outfits
    final w = box.width / 1.3, h = w * 0.86;
    final ox = (box.width - w) / 2, oy = box.height - h;
    canvas.save();
    canvas.translate(ox, oy);
    final body = RRect.fromLTRBAndCorners(
      0,
      0,
      w,
      h,
      topLeft: Radius.elliptical(w * 0.46, h * 0.55),
      topRight: Radius.elliptical(w * 0.46, h * 0.55),
      bottomLeft: Radius.elliptical(w * 0.4, h * 0.45),
      bottomRight: Radius.elliptical(w * 0.4, h * 0.45),
    );
    // soft shadow under it
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w / 2, h + 2), width: w * 0.8, height: 6),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    final light = Color.lerp(color, Colors.white, 0.55)!;
    final mid = Color.lerp(color, Colors.white, 0.2)!;
    canvas.drawRRect(
      body,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.45),
          radius: 1.0,
          colors: [light, mid, color],
          stops: const [0, 0.4, 1],
        ).createShader(Offset.zero & Size(w, h)),
    );
    // a soft shine on top
    canvas.drawOval(
      Rect.fromLTWH(w * 0.2, h * 0.08, w * 0.28, h * 0.14),
      Paint()..color = Colors.white.withValues(alpha: 0.35),
    );

    final ink = Color.lerp(color, Colors.black, 0.78)!;
    final white = Paint()..color = Colors.white;
    final ey = h * 0.42;
    final exs = [w * 0.35, w * 0.65];
    final ew = w * 0.16, eh = h * 0.3;
    final line = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = w * 0.06;

    void openEye(double x, {double scale = 1, double look = 0}) {
      final hh = eh * scale * (1 - 0.9 * blink);
      final r = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(x, ey), width: ew * scale, height: hh),
        Radius.circular(ew),
      );
      canvas.drawRRect(r, white);
      if (hh > eh * 0.3) {
        final p = Offset(x + look * ew * 0.22, ey + hh * 0.12);
        canvas.drawCircle(p, ew * 0.32 * scale, Paint()..color = ink);
        canvas.drawCircle(
          p + Offset(ew * 0.12, -ew * 0.14),
          ew * 0.11 * scale,
          white,
        );
      }
    }

    void heart(Offset c, double s) {
      final p = Path()
        ..moveTo(c.dx, c.dy + s * 0.55)
        ..cubicTo(c.dx - s, c.dy - s * 0.05, c.dx - s * 0.5, c.dy - s * 0.85,
            c.dx, c.dy - s * 0.3)
        ..cubicTo(c.dx + s * 0.5, c.dy - s * 0.85, c.dx + s, c.dy - s * 0.05,
            c.dx, c.dy + s * 0.55);
      canvas.drawPath(p, Paint()..color = const Color(0xFFFF5C8A));
    }

    switch (mood) {
      case BuddyMood.happy:
      case BuddyMood.giggle:
        for (final x in exs) {
          canvas.drawArc(
            Rect.fromCenter(
              center: Offset(x, ey + eh * 0.15),
              width: ew * 1.4,
              height: eh * 0.7,
            ),
            math.pi,
            math.pi,
            false,
            line,
          );
        }
      case BuddyMood.love:
        for (final x in exs) {
          heart(Offset(x, ey), ew * 0.95);
        }
      case BuddyMood.sleepy:
        for (final x in exs) {
          canvas.drawLine(
            Offset(x - ew * 0.6, ey + eh * 0.1),
            Offset(x + ew * 0.6, ey + eh * 0.1),
            line,
          );
        }
      case BuddyMood.worried:
        for (final x in exs) {
          openEye(x, scale: 0.9);
        }
        final brow = Paint()
          ..color = Colors.white
          ..strokeWidth = w * 0.045
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(Offset(exs[0] - ew * 0.7, ey - eh * 0.62),
            Offset(exs[0] + ew * 0.5, ey - eh * 0.82), brow);
        canvas.drawLine(Offset(exs[1] + ew * 0.7, ey - eh * 0.62),
            Offset(exs[1] - ew * 0.5, ey - eh * 0.82), brow);
      case BuddyMood.puzzled:
        openEye(exs[0], scale: 1.12, look: gaze);
        openEye(exs[1], scale: 0.78, look: gaze);
      case BuddyMood.cover:
      case BuddyMood.idle:
        for (final x in exs) {
          openEye(x, look: gaze);
        }
    }

    // cheeks
    final blush = Paint()
      ..color = const Color(0xFFFF6F91).withValues(
        alpha: mood == BuddyMood.love || mood == BuddyMood.giggle ? 0.6 : 0.4,
      );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.2, h * 0.63), width: w * 0.18, height: h * 0.1),
      blush,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.8, h * 0.63), width: w * 0.18, height: h * 0.1),
      blush,
    );

    // mouth
    final mouth = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = w * 0.04;
    final mc = Offset(w * 0.5, h * 0.66);
    switch (mood) {
      case BuddyMood.giggle:
      case BuddyMood.happy:
        canvas.drawArc(
          Rect.fromCenter(center: mc, width: w * 0.16, height: h * 0.14),
          0,
          math.pi,
          true,
          Paint()..color = ink,
        );
      case BuddyMood.puzzled:
        canvas.drawCircle(mc, w * 0.035, Paint()..color = ink);
      case BuddyMood.worried:
        final p = Path()
          ..moveTo(mc.dx - w * 0.07, mc.dy + h * 0.02)
          ..quadraticBezierTo(mc.dx, mc.dy - h * 0.04, mc.dx + w * 0.07, mc.dy + h * 0.02);
        canvas.drawPath(p, mouth);
      case BuddyMood.sleepy:
        canvas.drawOval(
          Rect.fromCenter(center: mc, width: w * 0.06, height: h * 0.06),
          Paint()..color = ink,
        );
      case BuddyMood.love:
      case BuddyMood.cover:
      case BuddyMood.idle:
        canvas.drawArc(
          Rect.fromCenter(center: mc, width: w * 0.12, height: h * 0.08),
          0.2,
          math.pi - 0.4,
          false,
          mouth,
        );
    }

    // little hands over the eyes
    final hand = Paint()..color = Color.lerp(color, Colors.white, 0.3)!;
    if (mood == BuddyMood.cover) {
      for (final x in exs) {
        canvas.drawOval(
          Rect.fromCenter(center: Offset(x, ey + 1), width: ew * 2.2, height: eh * 1.05),
          hand,
        );
      }
    }

    _outfit(canvas, w, h, ink);
    _prop(canvas, w, h, hand, ink);
    canvas.restore();
  }

  void _outfit(Canvas canvas, double w, double h, Color ink) {
    switch (outfit) {
      case 'bow':
        final p = Paint()..color = const Color(0xFFFF5C8A);
        final c = Offset(w * 0.78, h * 0.08);
        canvas.drawPath(
          Path()
            ..moveTo(c.dx, c.dy)
            ..lineTo(c.dx - w * 0.16, c.dy - h * 0.1)
            ..lineTo(c.dx - w * 0.16, c.dy + h * 0.1)
            ..close()
            ..moveTo(c.dx, c.dy)
            ..lineTo(c.dx + w * 0.16, c.dy - h * 0.1)
            ..lineTo(c.dx + w * 0.16, c.dy + h * 0.1)
            ..close(),
          p,
        );
        canvas.drawCircle(c, w * 0.045, Paint()..color = const Color(0xFFE0336B));
      case 'cap':
        final p = Paint()..color = ink;
        canvas.drawArc(
          Rect.fromLTWH(w * 0.14, -h * 0.12, w * 0.72, h * 0.5),
          math.pi,
          math.pi,
          true,
          p,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.5, h * 0.1, w * 0.48, h * 0.07),
            const Radius.circular(4),
          ),
          p,
        );
      case 'glasses':
        final p = Paint()
          ..color = ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.035;
        canvas.drawCircle(Offset(w * 0.35, h * 0.42), w * 0.13, p);
        canvas.drawCircle(Offset(w * 0.65, h * 0.42), w * 0.13, p);
        canvas.drawLine(Offset(w * 0.48, h * 0.42), Offset(w * 0.52, h * 0.42), p);
      case 'headphones':
        final band = Paint()
          ..color = ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.06;
        canvas.drawArc(
          Rect.fromLTWH(w * 0.02, -h * 0.12, w * 0.96, h * 0.9),
          math.pi,
          math.pi,
          false,
          band,
        );
        final cup = Paint()..color = ink;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(-w * 0.04, h * 0.26, w * 0.14, h * 0.3),
            const Radius.circular(5),
          ),
          cup,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.9, h * 0.26, w * 0.14, h * 0.3),
            const Radius.circular(5),
          ),
          cup,
        );
      case 'crown':
        final p = Paint()..color = const Color(0xFFFFC94A);
        canvas.drawPath(
          Path()
            ..moveTo(w * 0.28, h * 0.08)
            ..lineTo(w * 0.28, -h * 0.12)
            ..lineTo(w * 0.39, -h * 0.02)
            ..lineTo(w * 0.5, -h * 0.18)
            ..lineTo(w * 0.61, -h * 0.02)
            ..lineTo(w * 0.72, -h * 0.12)
            ..lineTo(w * 0.72, h * 0.08)
            ..close(),
          p,
        );
    }
  }

  void _prop(Canvas canvas, double w, double h, Paint hand, Color ink) {
    switch (prop) {
      case BuddyProp.none:
        return;
      case BuddyProp.shield:
        final c = Offset(w * 0.92, h * 0.78);
        final s = w * 0.2;
        final path = Path()
          ..moveTo(c.dx, c.dy - s)
          ..lineTo(c.dx + s * 0.8, c.dy - s * 0.65)
          ..quadraticBezierTo(c.dx + s * 0.75, c.dy + s * 0.55, c.dx, c.dy + s)
          ..quadraticBezierTo(c.dx - s * 0.75, c.dy + s * 0.55, c.dx - s * 0.8, c.dy - s * 0.65)
          ..close();
        canvas.drawPath(path, Paint()..color = Colors.white);
        canvas.drawPath(
          Path()
            ..moveTo(c.dx - s * 0.35, c.dy)
            ..lineTo(c.dx - s * 0.05, c.dy + s * 0.3)
            ..lineTo(c.dx + s * 0.4, c.dy - s * 0.3),
          Paint()
            ..color = ink
            ..style = PaintingStyle.stroke
            ..strokeWidth = w * 0.035
            ..strokeCap = StrokeCap.round,
        );
      case BuddyProp.paper:
        final r = Rect.fromLTWH(w * 0.78, h * 0.42, w * 0.3, h * 0.36);
        canvas.save();
        canvas.translate(r.center.dx, r.center.dy);
        canvas.rotate(0.25);
        canvas.translate(-r.center.dx, -r.center.dy);
        canvas.drawRRect(
          RRect.fromRectAndRadius(r, const Radius.circular(3)),
          Paint()..color = Colors.white,
        );
        final l = Paint()
          ..color = ink.withValues(alpha: 0.5)
          ..strokeWidth = 1.2;
        for (var i = 1; i <= 3; i++) {
          final y = r.top + r.height * i / 4.2;
          canvas.drawLine(Offset(r.left + 3, y), Offset(r.right - 3, y), l);
        }
        canvas.restore();
      case BuddyProp.wave:
        final a = math.sin(wave * math.pi * 8) * 0.35;
        canvas.save();
        canvas.translate(w * 0.95, h * 0.5);
        canvas.rotate(-0.6 + a);
        canvas.drawOval(
          Rect.fromCenter(center: Offset(0, -h * 0.18), width: w * 0.16, height: h * 0.3),
          hand,
        );
        canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _BuddyPainter old) => true;
}

/// Settings: on/off, name, whether others see it, and its outfit.
class VibeBuddyPage extends StatefulWidget {
  const VibeBuddyPage({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const VibeBuddyPage()));

  @override
  State<VibeBuddyPage> createState() => _VibeBuddyPageState();
}

class _VibeBuddyPageState extends State<VibeBuddyPage> {
  late final _name = TextEditingController(text: VibeBuddy.name);
  int _wiggle = 0;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final count = VibeBuddy.count;
    return Scaffold(
      appBar: AppBar(title: const Text('Typing buddy')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const SizedBox(height: 12),
          Center(
            child: GestureDetector(
              onTap: () => setState(() => _wiggle++),
              child: VibeBuddyFace(
                size: 96,
                color: cs.primary,
                mood: BuddyMood.happy,
                outfit: VibeBuddy.outfit,
                wiggle: _wiggle,
              ),
            ),
          ),
          SwitchListTile.adaptive(
            title: const Text('Show the buddy'),
            subtitle: const Text('It sits on the text box and reacts'),
            value: VibeBuddy.on,
            onChanged: (v) async {
              await VibeBuddy.set(on: v);
              setState(() {});
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _name,
              maxLength: 20,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name'),
              onSubmitted: (v) => VibeBuddy.set(
                name: v.trim().isEmpty ? 'Mochi' : v.trim(),
              ),
              onChanged: (v) {
                if (v.trim().isNotEmpty) VibeBuddy.set(name: v.trim());
              },
            ),
          ),
          SwitchListTile.adaptive(
            title: const Text('Others see it'),
            subtitle: const Text(
              'Your buddy shows in your typing circle in direct chats, for '
              'people who use Keepr',
            ),
            value: VibeBuddy.shared,
            onChanged: (v) async {
              await VibeBuddy.set(shared: v);
              setState(() {});
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Outfits · $count messages sent',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final o in VibeBuddy.outfits)
                Builder(
                  builder: (context) {
                    final open = VibeBuddy.unlocked(o);
                    final picked = VibeBuddy.outfit == o.id;
                    return InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: open
                          ? () async {
                              await VibeBuddy.set(outfit: o.id);
                              setState(() => _wiggle++);
                            }
                          : null,
                      child: Container(
                        width: 100,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: picked
                              ? cs.primaryContainer
                              : cs.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          children: [
                            Opacity(
                              opacity: open ? 1 : 0.35,
                              child: VibeBuddyFace(
                                size: 44,
                                color: cs.primary,
                                outfit: o.id,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              o.label,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              open ? (picked ? 'Wearing' : 'Ready') : 'At ${o.unlockAt}',
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

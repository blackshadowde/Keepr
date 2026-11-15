// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:matrix/matrix.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:vibe/config/setting_keys.dart';
import 'package:vibe/vibe/buddy/bujji.dart';
import 'package:vibe/vibe/buddy/bujji_model.dart';
import 'package:vibe/vibe/vibe_status.dart';
import 'package:vibe/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:vibe/vibe/buddy/bujji_life.dart';

/// The typing buddy: a small blob in the theme colour that lives on the
/// text box and reacts to what happens in the chat. Everything it does
/// happens on this phone; only whether it's on, its name, colour and
/// outfit are shared in direct chats, so the other person's Keepr can show
/// it in your typing circle.
enum BuddyMood {
  idle,
  happy,
  love,
  worried,
  sleepy,
  tired,
  puzzled,
  cover,
  giggle,
  // Bujji's life
  angry,
  smart,
  shy,
  dizzy,
  proud,
  wink,
  curious,
}

enum BuddyProp {
  none,
  shield,
  paper,
  wave,
  // Bujji's life: tools for what you do, things for the moment
  hammer,
  screwdriver,
  broom,
  clipboard,
  umbrella,
  popper,
  coffee,
  magnifier,
  camera,
  headphones,
  phone,
  flag,
  heart,
  bulb,
  book,
  ball,
  bed,
  catchHeart,
}

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

  /// Bujji's answer to something you asked it in a chat (the bar shows it).
  static final says = ValueNotifier<String?>(null);

  /// The chat open now (its typing bar shows what Bujji says about it).
  static String? here;

  /// Fires when its settings change.
  static final changed = ValueNotifier<int>(0);

  /// True while the buddy sleeps: the chat goes dull until it wakes.
  static final dozing = ValueNotifier<bool>(false);

  /// Midnight to 6 am: it sleeps unless you pet it awake.
  static bool get night {
    final h = DateTime.now().hour;
    return h < 6;
  }

  /// 10 pm to midnight: bedtime, it's tired and nods off quickly.
  static bool get bedtime => DateTime.now().hour >= 22;

  static bool get on => AppSettings.store.getBool(_on) ?? true;
  /// Always Bujji.
  static const name = 'Bujji';
  static bool get shared => AppSettings.store.getBool(_share) ?? true;
  static String get outfit => AppSettings.store.getString(_outfit) ?? 'none';
  static int get count => AppSettings.store.getInt(_count) ?? 0;

  static Future<void> set({
    bool? on,
    bool? shared,
    String? outfit,
  }) async {
    final s = AppSettings.store;
    if (on != null) await s.setBool(_on, on);
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

  /// How far down it looks, 0 (ahead) to 1 (down at the text box).
  final double look;

  /// Hovers in the air, bobbing, with its shadow on the ground below.
  final bool floating;
  final int hop;
  final int wiggle;

  /// Bump to squish it (it squashes, then wobbles like jelly).
  final int squish;

  /// Turned its back on you (cross).
  final bool away;
  const VibeBuddyFace({
    required this.color,
    this.size = 40,
    this.mood = BuddyMood.idle,
    this.prop = BuddyProp.none,
    this.outfit = 'none',
    this.gaze = 0,
    this.look = 0,
    this.floating = false,
    this.hop = 0,
    this.wiggle = 0,
    this.squish = 0,
    this.away = false,
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
  late final AnimationController _squish = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  double _blink = 0;
  int _nextBlink = 0;

  @override
  void didUpdateWidget(VibeBuddyFace old) {
    super.didUpdateWidget(old);
    if (old.hop != widget.hop) _hop.forward(from: 0);
    if (old.wiggle != widget.wiggle) _wiggle.forward(from: 0);
    if (old.squish != widget.squish) _squish.forward(from: 0);
  }

  @override
  void dispose() {
    _life.dispose();
    _hop.dispose();
    _wiggle.dispose();
    _squish.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final float = widget.floating;
    return SizedBox(
      width: s * 1.3,
      height: s * 1.3,
      child: AnimatedBuilder(
        animation: Listenable.merge([_life, _hop, _wiggle, _squish]),
        builder: (context, _) {
          // blink every few seconds
          final now = DateTime.now().millisecondsSinceEpoch;
          if (now > _nextBlink) {
            _nextBlink = now + 2400 + math.Random().nextInt(3200);
          }
          final left = _nextBlink - now;
          _blink = left < 140 ? 1 - (left - 70).abs() / 70 : 0;
          final breathe = math.sin(_life.value * math.pi * 2);
          final cycle = _life.value * math.pi * 2;
          // hovering: up and down once a breath, stretching a little on the
          // way up and squashing at the bottom, swaying gently
          final lift = float ? 0.5 + 0.5 * math.sin(cycle) : 0.0;
          final jelly = float ? 0.035 * math.cos(cycle) : 0.01 * breathe;
          final sway = float ? 0.035 * math.sin(cycle + 1.2) : 0.0;
          // squished: flat at first, then a wobble that dies away
          final q = _squish.value;
          final wobble = q == 0 || q == 1
              ? 0.0
              : math.exp(-4.5 * q) * math.cos(q * math.pi * 5);
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
              ? math.sin((h - 0.7) / 0.3 * math.pi) * 0.9
              : 0.0;
          final w = _wiggle.value;
          final tilt = w == 0
              ? 0.0
              : math.sin(w * math.pi * 6) * (1 - w) * 0.25;
          final up = jump * s * 0.55 + (float ? s * (0.05 + 0.08 * lift) : 0);
          final face = Transform.translate(
            offset: Offset(0, -up + (float ? 0 : breathe * s * 0.015)),
            child: Transform.rotate(
              angle: tilt + sway,
              alignment: Alignment.bottomCenter,
              child: Transform(
                alignment: Alignment.bottomCenter,
                transform: Matrix4.diagonal3Values(
                  1 + 0.2 * squash - jelly + 0.22 * wobble,
                  1 - 0.24 * squash + jelly - 0.22 * wobble,
                  1,
                ),
                child: CustomPaint(
                  size: Size.square(s * 1.3),
                  painter: _BuddyPainter(
                    // cross: it goes red in the face
                    color: widget.mood == BuddyMood.angry
                        ? Color.lerp(widget.color, const Color(0xFFE5484D), 0.5)!
                        : widget.color,
                    away: widget.away,
                    mood: widget.mood,
                    prop: widget.prop,
                    outfit: widget.outfit,
                    gaze: widget.gaze,
                    look: widget.look,
                    shadow: !float,
                    blink: _blink,
                    wave: _life.value,
                  ),
                ),
              ),
            ),
          );
          if (!float) return face;
          // its shadow stays on the ground, smaller and fainter as it rises
          final far = (up / (s * 0.6)).clamp(0.0, 1.0);
          return Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomCenter,
            children: [
              Positioned(
                bottom: 0,
                child: Container(
                  width: s * 0.8 * (1 - 0.35 * far),
                  height: 6,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: 0.28 * (1 - 0.5 * far),
                        ),
                        blurRadius: 5,
                      ),
                    ],
                  ),
                ),
              ),
              face,
            ],
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
  final double gaze, look, blink, wave;
  final bool shadow;
  final bool away;
  const _BuddyPainter({
    required this.color,
    this.away = false,
    required this.mood,
    required this.prop,
    required this.outfit,
    required this.gaze,
    required this.blink,
    required this.wave,
    this.look = 0,
    this.shadow = true,
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
    // soft shadow under it (a floating Bujji's is on the ground instead)
    if (shadow) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(w / 2, h + 2), width: w * 0.8, height: 6),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.25)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
    }
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
      away
          ? Rect.fromLTWH(w * 0.5, h * 0.12, w * 0.24, h * 0.12)
          : Rect.fromLTWH(w * 0.2, h * 0.08, w * 0.28, h * 0.14),
      Paint()..color = Colors.white.withValues(alpha: away ? 0.25 : 0.35),
    );
    if (away) {
      // its back to you: no face, just steam if it's cross
      if (mood == BuddyMood.angry) _fx(canvas, w);
      canvas.restore();
      return;
    }

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

    void openEye(double x, {double scale = 1, double look = 0, double? down}) {
      final hh = eh * scale * (1 - 0.9 * blink);
      final r = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(x, ey), width: ew * scale, height: hh),
        Radius.circular(ew),
      );
      canvas.drawRRect(r, white);
      if (hh > eh * 0.3) {
        // pupils follow where it looks: sideways, and down at the text box
        final p = Offset(
          x + look * ew * 0.22,
          ey + hh * 0.12 + (down ?? this.look) * hh * 0.17,
        );
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
      case BuddyMood.tired:
        // heavy lids: half shut, drooping a little lower now and then
        final droop = 0.45 + 0.25 * (0.5 + 0.5 * math.sin(wave * math.pi * 2));
        for (final x in exs) {
          openEye(x, look: gaze);
          final lid = Rect.fromLTWH(
            x - ew * 0.75,
            ey - eh * 0.62,
            ew * 1.5,
            eh * 1.2 * droop,
          );
          canvas.drawRect(lid, Paint()..color = Color.lerp(color, Colors.white, 0.28)!);
          canvas.drawLine(
            Offset(x - ew * 0.6, lid.bottom),
            Offset(x + ew * 0.6, lid.bottom),
            Paint()
              ..color = ink.withValues(alpha: 0.6)
              ..strokeWidth = w * 0.025
              ..strokeCap = StrokeCap.round,
          );
        }
      case BuddyMood.puzzled:
        openEye(exs[0], scale: 1.12, look: gaze);
        openEye(exs[1], scale: 0.78, look: gaze);
      case BuddyMood.cover:
      case BuddyMood.idle:
        for (final x in exs) {
          openEye(x, look: gaze);
        }
      case BuddyMood.angry:
        for (final x in exs) {
          openEye(x, scale: 0.92, look: gaze);
        }
        // lids pulled down to the middle, and frowning brows on them
        final lid = Paint()..color = Color.lerp(color, Colors.white, 0.2)!;
        final brow = Paint()
          ..color = ink
          ..strokeWidth = w * 0.045
          ..strokeCap = StrokeCap.round;
        for (var i = 0; i < 2; i++) {
          final x = exs[i];
          final inner = i == 0 ? 1.0 : -1.0;
          final top = ey - eh * 0.62;
          final a = Offset(x - inner * ew * 0.75, ey - eh * 0.36);
          final b = Offset(x + inner * ew * 0.75, ey - eh * 0.06);
          canvas.drawPath(
            Path()
              ..moveTo(a.dx, top)
              ..lineTo(b.dx, top)
              ..lineTo(b.dx, b.dy)
              ..lineTo(a.dx, a.dy)
              ..close(),
            lid,
          );
          canvas.drawLine(a, b, brow);
        }
      case BuddyMood.smart:
        for (final x in exs) {
          openEye(x, scale: 0.88, look: gaze);
        }
        final rim = Paint()
          ..color = ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.035;
        for (final x in exs) {
          canvas.drawCircle(Offset(x, ey + eh * 0.04), ew * 0.88, rim);
        }
        canvas.drawLine(
          Offset(exs[0] + ew * 0.88, ey),
          Offset(exs[1] - ew * 0.88, ey),
          rim,
        );
      case BuddyMood.shy:
        for (final x in exs) {
          openEye(x, scale: 0.88, down: 1);
        }
      case BuddyMood.dizzy:
        final swirl = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = w * 0.03;
        for (final x in exs) {
          for (var k = 1; k <= 3; k++) {
            canvas.drawArc(
              Rect.fromCircle(center: Offset(x, ey), radius: ew * 0.2 * k),
              wave * math.pi * 4 + k * 1.3,
              math.pi * 1.4,
              false,
              swirl,
            );
          }
        }
      case BuddyMood.proud:
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
      case BuddyMood.wink:
        openEye(exs[0], look: gaze);
        canvas.drawArc(
          Rect.fromCenter(
            center: Offset(exs[1], ey + eh * 0.15),
            width: ew * 1.4,
            height: eh * 0.7,
          ),
          math.pi,
          math.pi,
          false,
          line,
        );
      case BuddyMood.curious:
        for (final x in exs) {
          openEye(x, scale: 1.22, look: gaze);
        }
    }

    // cheeks
    final blush = Paint()
      ..color = const Color(0xFFFF6F91).withValues(
        alpha: mood == BuddyMood.shy
            ? 0.8
            : mood == BuddyMood.love || mood == BuddyMood.giggle
            ? 0.6
            : 0.4,
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
      case BuddyMood.proud:
        canvas.drawArc(
          Rect.fromCenter(center: mc, width: w * 0.16, height: h * 0.14),
          0,
          math.pi,
          true,
          Paint()..color = ink,
        );
      case BuddyMood.puzzled:
      case BuddyMood.curious:
        canvas.drawCircle(mc, w * 0.035, Paint()..color = ink);
      case BuddyMood.angry:
        final z = Path()..moveTo(mc.dx - w * 0.08, mc.dy + h * 0.02);
        for (var i = 1; i <= 4; i++) {
          z.lineTo(
            mc.dx - w * 0.08 + i * w * 0.04,
            mc.dy + (i.isOdd ? -h * 0.015 : h * 0.02),
          );
        }
        canvas.drawPath(z, mouth..strokeJoin = StrokeJoin.round);
      case BuddyMood.shy:
      case BuddyMood.dizzy:
        final wv = Path()..moveTo(mc.dx - w * 0.08, mc.dy);
        wv.quadraticBezierTo(mc.dx - w * 0.04, mc.dy - h * 0.04, mc.dx, mc.dy);
        wv.quadraticBezierTo(mc.dx + w * 0.04, mc.dy + h * 0.04, mc.dx + w * 0.08, mc.dy);
        canvas.drawPath(wv, mouth);
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
      case BuddyMood.tired:
        // a slow yawn in the middle of each breath
        final y = (0.5 + 0.5 * math.sin(wave * math.pi * 2 - 1.2)).clamp(0.0, 1.0);
        canvas.drawOval(
          Rect.fromCenter(
            center: mc + Offset(0, h * 0.02),
            width: w * (0.07 + 0.06 * y),
            height: h * (0.05 + 0.12 * y),
          ),
          Paint()..color = ink,
        );
      case BuddyMood.love:
      case BuddyMood.cover:
      case BuddyMood.idle:
      case BuddyMood.smart:
      case BuddyMood.wink:
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
    _fx(canvas, w);
    if (mood == BuddyMood.sleepy) _zzz(canvas, w, h, ink);
    canvas.restore();
  }

  /// Little z's drifting up while it sleeps.
  void _zzz(Canvas canvas, double w, double h, Color ink) {
    for (var i = 0; i < 3; i++) {
      final t = (wave + i / 3) % 1;
      final tp = TextPainter(
        text: TextSpan(
          text: 'z',
          style: TextStyle(
            fontSize: w * (0.18 + 0.12 * t),
            fontWeight: FontWeight.w800,
            color: Color.lerp(color, Colors.white, 0.4)!.withValues(
              alpha: (1 - t) * 0.9,
            ),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(w * (0.8 + 0.25 * t), -h * 0.05 - h * 0.6 * t));
      tp.dispose();
    }
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
      default:
        _life(canvas, w, hand);
    }
  }

  // ---- Bujji's life: what it holds and the little extras round it ----
  // Drawn in body units: the body is 100 across and 86 tall.

  static Path _heart(Offset c, double s) => Path()
    ..moveTo(c.dx, c.dy + s * 0.55)
    ..cubicTo(c.dx - s, c.dy - s * 0.05, c.dx - s * 0.5, c.dy - s * 0.85,
        c.dx, c.dy - s * 0.3)
    ..cubicTo(c.dx + s * 0.5, c.dy - s * 0.85, c.dx + s, c.dy - s * 0.05,
        c.dx, c.dy + s * 0.55)
    ..close();

  static Path _star(Offset c, double r) {
    final q = r * 0.28;
    return Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx + q, c.dy - q, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx + q, c.dy + q, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx - q, c.dy + q, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx - q, c.dy - q, c.dx, c.dy - r)
      ..close();
  }

  void _life(Canvas canvas, double w, Paint hand) {
    final u = w / 100;
    Offset p(double x, double y) => Offset(x * u, y * u);
    Paint fill(int c) => Paint()..color = Color(c);
    Paint pen(int c, double width) => Paint()
      ..color = Color(c)
      ..style = PaintingStyle.stroke
      ..strokeWidth = width * u
      ..strokeCap = StrokeCap.round;
    RRect box(double x, double y, double bw, double bh, double r) =>
        RRect.fromRectAndRadius(Rect.fromLTWH(x * u, y * u, bw * u, bh * u), Radius.circular(r * u));
    void hands(List<(double, double)> at) {
      for (final (x, y) in at) {
        canvas.drawCircle(p(x, y), 8.5 * u, hand);
      }
    }
    void turn(double x, double y, double a, void Function() draw) {
      canvas.save();
      canvas.translate(x * u, y * u);
      canvas.rotate(a);
      canvas.translate(-x * u, -y * u);
      draw();
      canvas.restore();
    }

    final t = wave; // goes round once every 2.6 seconds
    final beat = math.sin(t * math.pi * 2);
    switch (prop) {
      case BuddyProp.hammer:
        // tap, tap, tap
        final hit = math.max(0.0, math.sin(t * math.pi * 6));
        turn(96, 52, 0.25 + 0.5 * hit, () {
          canvas.drawRRect(box(92, -12, 8, 66, 3.5), fill(0xFFB07843));
          canvas.drawRRect(box(74, -26, 44, 19, 5), fill(0xFF8E97A8));
          canvas.drawRRect(box(76, -24, 40, 6, 3), fill(0xFFB9C0CD));
        });
        if (hit > 0.85) {
          final spark = pen(0xFFFFC93C, 4);
          canvas.drawLine(p(146, 18), p(160, 8), spark);
          canvas.drawLine(p(150, 34), p(168, 34), spark);
          canvas.drawLine(p(140, 6), p(142, -10), spark);
        }
        hands([(94, 44), (20, 70)]);
      case BuddyProp.screwdriver:
        turn(98, 50, 0.7 + 0.18 * beat, () {
          canvas.drawRect(Rect.fromLTWH(97 * u, -12 * u, 4 * u, 32 * u), fill(0xFF9AA3B5));
          canvas.drawRRect(box(93, 18, 12, 34, 5), fill(0xFFF2994A));
        });
        hands([(92, 48)]);
      case BuddyProp.broom:
        canvas.save();
        canvas.translate(6 * u * math.sin(t * math.pi * 4), 0);
        canvas.drawLine(p(112, -14), p(78, 84), pen(0xFFB07843, 6));
        canvas.drawPath(
          Path()
            ..moveTo(66 * u, 78 * u)
            ..lineTo(96 * u, 88 * u)
            ..lineTo(92 * u, 104 * u)
            ..quadraticBezierTo(74 * u, 108 * u, 56 * u, 100 * u)
            ..close(),
          fill(0xFFE8C26B),
        );
        canvas.restore();
        for (final (x, y, r) in [(40.0, 98.0, 5.0), (28.0, 92.0, 3.5), (20.0, 100.0, 2.5)]) {
          canvas.drawCircle(p(x - 8 * t, y), r * u, fill(0xCCD9D6E2));
        }
        hands([(88, 40), (84, 70)]);
      case BuddyProp.clipboard:
        canvas.drawRRect(box(28, 44, 44, 42, 5), fill(0xFFD9B47A));
        canvas.drawRRect(box(33, 51, 34, 31, 2), fill(0xFFFFFFFF));
        canvas.drawRRect(box(41, 40, 18, 8, 3), fill(0xFF8E97A8));
        final l = pen(0xFFB9BDCB, 3);
        canvas.drawLine(p(38, 60), p(56, 60), l);
        canvas.drawLine(p(38, 67), p(62, 67), l);
        canvas.drawLine(p(38, 74), p(52, 74), l);
        canvas.drawPath(
          Path()
            ..moveTo(58 * u, 72 * u)
            ..lineTo(62 * u, 76 * u)
            ..lineTo(70 * u, 66 * u),
          pen(0xFF2E9E5B, 3.5)..style = PaintingStyle.stroke,
        );
        hands([(30, 64), (70, 64)]);
      case BuddyProp.umbrella:
        canvas.drawLine(p(100, 54), p(100, -34), pen(0xFF6B4A2B, 4.5));
        canvas.drawPath(
          Path()
            ..moveTo(54 * u, -30 * u)
            ..quadraticBezierTo(100 * u, -84 * u, 146 * u, -30 * u)
            ..quadraticBezierTo(134 * u, -40 * u, 123 * u, -30 * u)
            ..quadraticBezierTo(112 * u, -40 * u, 100 * u, -30 * u)
            ..quadraticBezierTo(88 * u, -40 * u, 77 * u, -30 * u)
            ..quadraticBezierTo(66 * u, -40 * u, 54 * u, -30 * u)
            ..close(),
          fill(0xFFF27A93),
        );
        // rain round it
        final drop = pen(0xFF7FB5E6, 3);
        for (final (x, y) in [(30.0, -60.0), (150.0, -8.0), (20.0, -20.0), (165.0, -50.0)]) {
          final f = (y + 120 * t) % 100 - 60;
          canvas.drawLine(p(x, f), p(x - 4, f + 10), drop);
        }
        hands([(96, 56)]);
      case BuddyProp.popper:
        canvas.drawPath(
          Path()
            ..moveTo(4 * u, 58 * u)
            ..lineTo(-30 * u, -6 * u)
            ..lineTo(-12 * u, -16 * u)
            ..close(),
          fill(0xFFFFC93C),
        );
        const colors = [0xFFFFC93C, 0xFF7FB5E6, 0xFFF27A93, 0xFF6DD58C, 0xFFB39DFF];
        for (var i = 0; i < 8; i++) {
          final a = -math.pi * (0.55 + i * 0.07);
          final d = (20 + 50 * ((t + i * 0.13) % 1));
          final c = p(-20, -10) + Offset(math.cos(a), math.sin(a)) * d * u;
          canvas.save();
          canvas.translate(c.dx, c.dy);
          canvas.rotate(i + t * 6);
          canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: 7 * u, height: 3.5 * u), Radius.circular(1.5 * u)),
            fill(colors[i % colors.length]),
          );
          canvas.restore();
        }
        hands([(4, 58), (80, 66)]);
      case BuddyProp.coffee:
        canvas.drawPath(
          Path()
            ..moveTo(66 * u, 56 * u)
            ..quadraticBezierTo(80 * u, 56 * u, 80 * u, 66 * u)
            ..quadraticBezierTo(80 * u, 76 * u, 66 * u, 76 * u),
          pen(0xFFFFFFFF, 5),
        );
        canvas.drawRRect(box(32, 48, 36, 32, 7), fill(0xFFFFFFFF));
        canvas.drawOval(Rect.fromCenter(center: p(50, 51), width: 30 * u, height: 7 * u), fill(0xFF8A5A3B));
        // steam rising
        for (final x in [42.0, 56.0]) {
          final k = (t + x / 100) % 1;
          final st = Paint()
            ..color = const Color(0xFFC7C4D2).withValues(alpha: 1 - k)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3 * u
            ..strokeCap = StrokeCap.round;
          final y0 = 40 - 14 * k;
          canvas.drawPath(
            Path()
              ..moveTo(x * u, y0 * u)
              ..quadraticBezierTo((x - 6) * u, (y0 - 9) * u, x * u, (y0 - 18) * u),
            st,
          );
        }
        hands([(30, 66), (70, 66)]);
      case BuddyProp.magnifier:
        final bob = 3 * beat;
        canvas.drawLine(p(98, 50), p(112, 30 + bob), pen(0xFF5B5F6C, 7));
        canvas.drawCircle(p(124, 14 + bob), 20 * u, fill(0x73C8E4FF));
        canvas.drawCircle(p(124, 14 + bob), 20 * u, pen(0xFF5B5F6C, 6));
        hands([(96, 52)]);
      case BuddyProp.camera:
        canvas.drawRRect(box(24, 48, 52, 34, 8), fill(0xFF2B2E38));
        canvas.drawRRect(box(34, 42, 14, 8, 3), fill(0xFF2B2E38));
        canvas.drawCircle(p(50, 65), 11 * u, fill(0xFF5C6577));
        canvas.drawCircle(p(50, 65), 11 * u, pen(0xFFAAB3C5, 3));
        canvas.drawCircle(p(46, 61), 3 * u, fill(0xFFDDE3F0));
        // click: a flash now and then
        if (t > 0.9) canvas.drawCircle(p(68, 54), 9 * u, fill(0xCCFFF6C2));
        canvas.drawCircle(p(68, 54), 2.5 * u, fill(0xFFFFD54F));
        hands([(26, 64), (74, 64)]);
      case BuddyProp.headphones:
        canvas.drawPath(
          Path()
            ..moveTo(6 * u, 44 * u)
            ..quadraticBezierTo(50 * u, -30 * u, 94 * u, 44 * u),
          pen(0xFF2B2E38, 7),
        );
        canvas.drawRRect(box(-6, 34, 16, 28, 7), fill(0xFFE5484D));
        canvas.drawRRect(box(90, 34, 16, 28, 7), fill(0xFFE5484D));
      case BuddyProp.phone:
        canvas.drawRRect(box(92, 14, 22, 38, 5), fill(0xFF2B2E38));
        canvas.drawRRect(box(95, 19, 16, 26, 2), fill(0xFF8FB3FF));
        final ring = Paint()
          ..color = const Color(0xFF6DD58C).withValues(alpha: 0.4 + 0.6 * (0.5 + 0.5 * math.sin(t * math.pi * 8)))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5 * u
          ..strokeCap = StrokeCap.round;
        canvas.drawArc(Rect.fromCircle(center: p(116, 20), radius: 10 * u), -0.9, 1.8, false, ring);
        canvas.drawArc(Rect.fromCircle(center: p(116, 20), radius: 18 * u), -0.9, 1.8, false, ring);
        hands([(98, 52)]);
      case BuddyProp.flag:
        canvas.drawLine(p(0, 58), p(0, -26), pen(0xFF6B4A2B, 4));
        canvas.drawPath(
          Path()
            ..moveTo(1 * u, -26 * u)
            ..quadraticBezierTo(18 * u, (-24 + 4 * beat) * u, 34 * u, -16 * u)
            ..quadraticBezierTo(18 * u, (-8 - 4 * beat) * u, 1 * u, -4 * u)
            ..close(),
          fill(0xFF2E9E5B),
        );
        hands([(2, 58), (84, 68)]);
      case BuddyProp.heart:
        canvas.drawPath(_heart(p(50, 64), 30 * u * (1 + 0.04 * beat)), fill(0xFFFF5C8A));
        hands([(22, 66), (78, 66)]);
      case BuddyProp.bulb:
        final glow = 0.5 + 0.5 * beat;
        canvas.drawCircle(p(50, -34), 22 * u, Paint()..color = const Color(0xFFFFD54F).withValues(alpha: 0.25 * glow));
        canvas.drawCircle(p(50, -34), 15 * u, fill(0xFFFFD54F));
        canvas.drawRRect(box(43, -21, 14, 9, 2), fill(0xFFAEB4C2));
        final ray = pen(0xFFFFC93C, 3.5);
        for (final d in [-150.0, -110.0, -70.0, -30.0, 10.0, 170.0]) {
          final a = d * math.pi / 180;
          canvas.drawLine(
            p(50 + 22 * math.cos(a), -34 + 22 * math.sin(a)),
            p(50 + (28 + 3 * glow) * math.cos(a), -34 + (28 + 3 * glow) * math.sin(a)),
            ray,
          );
        }
      case BuddyProp.book:
        canvas.drawPath(
          Path()
            ..moveTo(22 * u, 56 * u)
            ..quadraticBezierTo(36 * u, 50 * u, 50 * u, 58 * u)
            ..quadraticBezierTo(64 * u, 50 * u, 78 * u, 56 * u)
            ..lineTo(78 * u, 84 * u)
            ..quadraticBezierTo(64 * u, 78 * u, 50 * u, 86 * u)
            ..quadraticBezierTo(36 * u, 78 * u, 22 * u, 84 * u)
            ..close(),
          fill(0xFFFFFFFF),
        );
        canvas.drawLine(p(50, 58), p(50, 86), pen(0xFFD9D6E2, 2));
        final l = pen(0xFFB9BDCB, 2.5);
        for (final y in [64.0, 70.0]) {
          canvas.drawLine(p(28, y), p(42, y), l);
          canvas.drawLine(p(58, y), p(72, y), l);
        }
        hands([(24, 66), (76, 66)]);
      case BuddyProp.ball:
        final up = (math.sin(t * math.pi * 4)).abs();
        final c = p(50, -16 - 26 * up);
        canvas.drawCircle(c, 14 * u, fill(0xFFFFC93C));
        canvas.drawArc(Rect.fromCircle(center: c, radius: 14 * u), 0.3, 2.4, false, pen(0xFFF2994A, 3));
        canvas.drawCircle(c + Offset(-5 * u, -5 * u), 3.5 * u, fill(0xB3FFFFFF));
        hands([(14, 30), (86, 30)]);
      case BuddyProp.bed:
        canvas.drawPath(
          Path()
            ..moveTo(-12 * u, 64 * u)
            ..quadraticBezierTo(50 * u, 50 * u, 112 * u, 64 * u)
            ..lineTo(114 * u, 94 * u)
            ..lineTo(-14 * u, 94 * u)
            ..close(),
          fill(0xFFF6B26B),
        );
        for (final (x, y) in [(10.0, 76.0), (34.0, 70.0), (60.0, 72.0), (86.0, 70.0), (100.0, 84.0), (22.0, 88.0), (48.0, 86.0), (74.0, 88.0)]) {
          canvas.drawCircle(p(x, y), 3.2 * u, fill(0xFFFFF3DD));
        }
        // its nightcap
        canvas.drawPath(
          Path()
            ..moveTo(18 * u, 14 * u)
            ..quadraticBezierTo(48 * u, -16 * u, 84 * u, 6 * u)
            ..quadraticBezierTo(104 * u, -2 * u, 122 * u, 36 * u)
            ..lineTo(110 * u, 40 * u)
            ..quadraticBezierTo(100 * u, 18 * u, 84 * u, 14 * u)
            ..close(),
          fill(0xFF8C7AE6),
        );
        canvas.drawLine(p(18, 15), p(84, 11), pen(0xFFFFFFFF, 7));
        canvas.drawCircle(p(118, 42), 7 * u, fill(0xFFFFFFFF));
      case BuddyProp.catchHeart:
        final fall = (t * 2) % 1;
        canvas.drawPath(_heart(p(50, -40 + 20 * fall), 18 * u), fill(0xFFFF5C8A));
        canvas.drawPath(_star(p(22, -40), 6 * u), fill(0xFFFFD54F));
        canvas.drawPath(_star(p(80, -46), 5 * u), fill(0xFFFFD54F));
        hands([(10, 26), (90, 26)]);
      default:
        break;
    }
  }

  /// The little extras round it: steam when cross, stars when dizzy,
  /// hearts, sparkles, music notes.
  void _fx(Canvas canvas, double w) {
    final u = w / 100;
    Offset p(double x, double y) => Offset(x * u, y * u);
    final t = wave;
    if (mood == BuddyMood.angry) {
      for (final cx in [10.0, 90.0]) {
        for (final (dx, dy, r) in [(0.0, 0.0, 8.0), (-8.0, -9.0, 6.0), (6.0, -14.0, 7.0), (-2.0, -24.0, 5.0)]) {
          final k = (t * 2 + dy / 30) % 1;
          final c = p(cx + dx, -6 + dy - 10 * k);
          canvas.drawCircle(c, r * u, Paint()..color = Colors.white.withValues(alpha: 0.9 * (1 - k * 0.6)));
          canvas.drawCircle(
            c,
            r * u,
            Paint()
              ..color = const Color(0xFFD9D6E2).withValues(alpha: 1 - k * 0.6)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2 * u,
          );
        }
      }
    }
    if (mood == BuddyMood.dizzy) {
      for (var i = 0; i < 3; i++) {
        final a = t * math.pi * 2 + i * math.pi * 2 / 3;
        canvas.drawPath(
          _star(p(50 + 52 * math.cos(a), -6 + 14 * math.sin(a)), 7 * u),
          Paint()..color = i == 1 ? const Color(0xFFB39DFF) : const Color(0xFFFFD54F),
        );
      }
    }
    if (mood == BuddyMood.love && (prop == BuddyProp.heart || prop == BuddyProp.catchHeart)) {
      for (var i = 0; i < 3; i++) {
        final k = (t + i / 3) % 1;
        final x = [-4.0, 104.0, 88.0][i];
        canvas.drawPath(
          _heart(p(x, -10 - 40 * k), [9.0, 11.0, 7.0][i] * u),
          Paint()..color = const Color(0xFFFF5C8A).withValues(alpha: 1 - k),
        );
      }
    }
    if (mood == BuddyMood.proud || mood == BuddyMood.wink) {
      final tw = 0.6 + 0.4 * math.sin(t * math.pi * 4);
      canvas.drawPath(_star(p(-8, 6), 9 * u * tw), Paint()..color = const Color(0xFFFFD54F));
      canvas.drawPath(_star(p(108, -6), 11 * u * (1.6 - tw)), Paint()..color = const Color(0xFFFFD54F));
      canvas.drawPath(_star(p(96, -38), 6 * u * tw), Paint()..color = const Color(0xFFB39DFF));
    }
    if (mood == BuddyMood.proud && outfit != 'crown') {
      canvas.drawPath(
        Path()
          ..moveTo(28 * u, 8 * u)
          ..lineTo(30 * u, -18 * u)
          ..lineTo(41 * u, -4 * u)
          ..lineTo(50 * u, -24 * u)
          ..lineTo(59 * u, -4 * u)
          ..lineTo(70 * u, -18 * u)
          ..lineTo(72 * u, 8 * u)
          ..close(),
        Paint()..color = const Color(0xFFFFC93C),
      );
      canvas.drawCircle(p(50, -2), 3.5 * u, Paint()..color = const Color(0xFFE5484D));
    }
    if (prop == BuddyProp.headphones) {
      final k = t;
      final note = Paint()..color = Color.lerp(color, Colors.black, 0.3)!.withValues(alpha: 1 - k);
      final stem = Paint()
        ..color = note.color
        ..strokeWidth = 3 * u
        ..strokeCap = StrokeCap.round;
      final o = p(118, 4 - 30 * k);
      canvas.drawCircle(o, 5 * u, note);
      canvas.drawLine(o + Offset(4 * u, 0), o + Offset(4 * u, -20 * u), stem);
      final o2 = p(-24, 0 - 30 * ((k + 0.5) % 1));
      canvas.drawCircle(o2, 5 * u, note..color = note.color.withValues(alpha: 1 - (k + 0.5) % 1));
      canvas.drawLine(o2 + Offset(4 * u, 0), o2 + Offset(4 * u, -20 * u), stem);
    }
  }

  @override
  bool shouldRepaint(covariant _BuddyPainter old) => true;
}

/// Settings: on/off, whether others see it, and its outfit.
class VibeBuddyPage extends StatefulWidget {
  const VibeBuddyPage({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const VibeBuddyPage()));

  @override
  State<VibeBuddyPage> createState() => _VibeBuddyPageState();
}

class _VibeBuddyPageState extends State<VibeBuddyPage> {
  int _wiggle = 0, _squish = 0;

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
              onTapDown: (_) => setState(() => _squish++),
              onTap: () => setState(() => _wiggle++),
              child: VibeBuddyFace(
                size: 96,
                color: cs.primary,
                mood: BuddyMood.happy,
                outfit: VibeBuddy.outfit,
                floating: true,
                wiggle: _wiggle,
                squish: _squish,
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
          ListTile(
            leading: const Icon(Icons.sticky_note_2_outlined),
            title: Text('${VibeBuddy.name}\'s notes and reminders'),
            subtitle: const Text('Or type @bujji chat in any chat'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => BujjiChatPage.open(context),
          ),
          const _BujjiModelTile(),
          // how much it does on its own
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              "${VibeBuddy.name}'s life",
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<BujjiPace>(
              segments: const [
                ButtonSegment(value: BujjiPace.lively, label: Text('Lively')),
                ButtonSegment(value: BujjiPace.calm, label: Text('Calm')),
                ButtonSegment(value: BujjiPace.off, label: Text('Off')),
              ],
              selected: {BujjiLife.pace},
              showSelectedIcon: false,
              onSelectionChanged: (v) async {
                await BujjiLife.setPace(v.first);
                setState(() {});
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
            child: Text(
              switch (BujjiLife.pace) {
                BujjiPace.lively =>
                  'Wanders over to new photos, peeks from behind messages, '
                      'brings little things for the moment and has moods',
                BujjiPace.calm =>
                  'Brings little things and has moods, but stays on the '
                      'text box',
                BujjiPace.off => 'Just sits on the text box and reacts',
              },
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
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

/// The chat behind the buddy: dull and dim while it sleeps, bright when
/// it's awake (a slow fade between the two). The chat keeps its state
/// (scroll position and all) when the filter comes and goes.
class VibeBuddyDim extends StatefulWidget {
  final Widget child;
  const VibeBuddyDim({required this.child, super.key});

  @override
  State<VibeBuddyDim> createState() => _VibeBuddyDimState();
}

class _VibeBuddyDimState extends State<VibeBuddyDim> {
  final _key = GlobalKey();

  static List<double> _matrix(double t) {
    // less colour and a little darker as t goes to 1
    final s = 1 - 0.55 * t, b = 1 - 0.22 * t;
    const r = 0.2126, g = 0.7152, bl = 0.0722;
    return [
      (r + (1 - r) * s) * b, g * (1 - s) * b, bl * (1 - s) * b, 0, 0,
      r * (1 - s) * b, (g + (1 - g) * s) * b, bl * (1 - s) * b, 0, 0,
      r * (1 - s) * b, g * (1 - s) * b, (bl + (1 - bl) * s) * b, 0, 0,
      0, 0, 0, 1, 0,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final child = KeyedSubtree(key: _key, child: widget.child);
    return ValueListenableBuilder<bool>(
      valueListenable: VibeBuddy.dozing,
      builder: (context, dozing, _) => TweenAnimationBuilder<double>(
        tween: Tween(end: dozing ? 1 : 0),
        duration: const Duration(milliseconds: 1200),
        curve: Curves.easeInOut,
        builder: (context, t, _) => t <= 0.001
            ? child
            : ColorFiltered(
                colorFilter: ColorFilter.matrix(_matrix(t)),
                child: child,
              ),
      ),
    );
  }
}

/// The optional sentence model: download, switch, delete.
class _BujjiModelTile extends StatelessWidget {
  const _BujjiModelTile();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BujjiModelStatus>(
      valueListenable: BujjiModel.status,
      builder: (context, st, _) {
        final have = BujjiModel.downloaded;
        Widget sub = Text(
          have
              ? 'Matches questions by meaning, on this phone. Nothing is sent.'
              : st == BujjiModelStatus.failed
              ? "Download didn't finish. Try again."
              : 'Optional ${BujjiModel.sizeMb} MB download from Keepr\'s GitHub '
                    'releases. Runs on this phone; nothing is sent.',
        );
        Widget? end;
        if (st == BujjiModelStatus.downloading) {
          sub = ValueListenableBuilder<double>(
            valueListenable: BujjiModel.progress,
            builder: (context, p, _) => Padding(
              padding: const EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(value: p),
            ),
          );
        } else if (have) {
          end = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () async {
                  final r = await showOkCancelAlertDialog(
                    context: context,
                    title: 'Delete the download?',
                    message: 'Frees ${BujjiModel.sizeMb} MB. You can download it again later.',
                    okLabel: 'Delete',
                    isDestructive: true,
                  );
                  if (r == OkCancelResult.ok) await BujjiModel.remove();
                },
              ),
              Switch.adaptive(
                value: BujjiModel.on,
                onChanged: (v) => BujjiModel.setOn(v),
              ),
            ],
          );
        } else {
          end = FilledButton.tonal(
            onPressed: BujjiModel.download,
            child: Text(st == BujjiModelStatus.failed ? 'Retry' : 'Download'),
          );
        }
        return ListTile(
          leading: const Icon(Icons.manage_search_rounded),
          title: const Text('Understand questions better'),
          subtitle: sub,
          trailing: end,
        );
      },
    );
  }
}

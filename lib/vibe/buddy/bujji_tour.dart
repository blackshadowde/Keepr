// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:vibe/vibe/buddy/bujji_life.dart';
import 'package:vibe/vibe/buddy/vibe_buddy.dart';
import 'package:vibe/vibe/vibe_threads.dart';
import 'package:vibe/widgets/vibe_app.dart';

/// The live mockups in Bujji's What's new tour, drawn with the real Bujji.
/// Each is laid out 300 x 200 and scaled to fit its message.
abstract class BujjiTourDemos {
  static Widget tools(BuildContext context) => const _Tools();
  static Widget life(BuildContext context) => const _Life();
  static Widget map(BuildContext context) => const _Map();
  static Widget live(BuildContext context) => const _Live();
  static Widget slide(BuildContext context) => const _Slide();
  static Widget threads(BuildContext context) => const _Threads();
  static Widget home(BuildContext context) => const _Home();
  static Widget pq(BuildContext context) => const _Pq();
}

Widget _bujji(
  BuildContext context, {
  double size = 56,
  BuddyMood mood = BuddyMood.happy,
  BuddyProp prop = BuddyProp.none,
  double gaze = 0,
  double look = 0,
  int hop = 0,
}) => VibeBuddyFace(
  size: size,
  color: Theme.of(context).colorScheme.primary,
  mood: mood,
  prop: prop,
  outfit: VibeBuddy.outfit,
  gaze: gaze,
  look: look,
  floating: true,
  hop: hop,
);

Widget _bubble(BuildContext context, String text, {bool mine = true}) {
  final cs = Theme.of(context).colorScheme;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
    decoration: BoxDecoration(
      color: mine ? cs.primaryContainer : cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 13.5, color: mine ? cs.onPrimaryContainer : cs.onSurface),
    ),
  );
}

Widget _avatar(String letter, Color a, Color b, {double size = 32}) => Container(
  width: size,
  height: size,
  alignment: Alignment.center,
  decoration: BoxDecoration(
    shape: BoxShape.circle,
    gradient: LinearGradient(colors: [a, b], begin: Alignment.topLeft, end: Alignment.bottomRight),
  ),
  child: Text(
    letter,
    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: size * 0.42),
  ),
);

Widget _chip(BuildContext context, IconData icon, String label, {bool on = false}) {
  final cs = Theme.of(context).colorScheme;
  return Container(
    height: 30,
    padding: const EdgeInsets.symmetric(horizontal: 11),
    decoration: BoxDecoration(
      color: on ? cs.primary : cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(15),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: on ? cs.onPrimary : cs.onSurface),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: on ? cs.onPrimary : cs.onSurface),
        ),
      ],
    ),
  );
}

/// Steps through a list every [ms], for the mockups that show a few things.
mixin _Steps<T extends StatefulWidget> on State<T> {
  int step = 0;
  Timer? _timer;
  int get steps;
  int get ms => 2600;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(Duration(milliseconds: ms), (_) {
      if (mounted) setState(() => step = (step + 1) % steps);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

// ---- #bujji: the right thing in hand, kept until it's done ----

class _Tools extends StatefulWidget {
  const _Tools();
  @override
  State<_Tools> createState() => _ToolsState();
}

class _ToolsState extends State<_Tools> with _Steps<_Tools> {
  static const _all = [
    (BuddyProp.hammer, BuddyMood.proud, Icons.push_pin_outlined, 'Pinning'),
    (BuddyProp.pen, BuddyMood.curious, Icons.edit_outlined, 'Editing, until it\'s sent'),
    (BuddyProp.broom, BuddyMood.idle, Icons.delete_outline_rounded, 'Deleting'),
    (BuddyProp.coffee, BuddyMood.sleepy, Icons.wb_sunny_outlined, 'Good morning'),
    (BuddyProp.headphones, BuddyMood.happy, Icons.headphones_outlined, 'A voice note'),
    (BuddyProp.umbrella, BuddyMood.curious, Icons.umbrella_outlined, 'Rain in the chat'),
  ];
  @override
  int get steps => _all.length;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (prop, mood, icon, label) = _all[step];
    return Stack(
      children: [
        Positioned(
          left: 14,
          right: 14,
          top: 12,
          child: Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                Icon(Icons.push_pin, size: 15, color: cs.primary),
                const SizedBox(width: 6),
                Text('Dinner at 8, Paradise', style: TextStyle(fontSize: 12.5, color: cs.onSurface)),
              ],
            ),
          ),
        ),
        Positioned(left: 14, top: 66, child: _bubble(context, 'Dinner at 8, Paradise')),
        Positioned(
          left: 14,
          bottom: 16,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            child: KeyedSubtree(key: ValueKey(step), child: _chip(context, icon, label)),
          ),
        ),
        Positioned(
          right: 34,
          bottom: 22,
          child: _bujji(context, size: 64, mood: mood, prop: prop, hop: step),
        ),
      ],
    );
  }
}

// ---- #bujji: hops onto a photo by day, naps on the newest message at night ----

class _Life extends StatefulWidget {
  const _Life();
  @override
  State<_Life> createState() => _LifeState();
}

class _LifeState extends State<_Life> with _Steps<_Life> {
  @override
  int get steps => 2;
  @override
  int get ms => 3200;

  @override
  Widget build(BuildContext context) {
    final night = step == 1;
    return Stack(
      children: [
        Positioned(
          left: 24,
          top: 44,
          child: Container(
            width: 170,
            height: 112,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(
                colors: [Color(0xFFFFB98E), Color(0xFFF27A93), Color(0xFF6B5BD6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
        ),
        Positioned(right: 18, top: 128, child: _bubble(context, 'Good night!', mine: false)),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeInOutBack,
          left: night ? 214 : 82,
          top: night ? 82 : 2,
          child: _bujji(
            context,
            size: 52,
            mood: night ? BuddyMood.sleepy : BuddyMood.curious,
            prop: night ? BuddyProp.bed : BuddyProp.none,
            look: night ? 0 : 1,
            hop: step,
          ),
        ),
      ],
    );
  }
}

// ---- #location: the new map, with your picture as the pin ----

class _Map extends StatelessWidget {
  const _Map();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      children: [
        Positioned(
          left: 14,
          top: 12,
          right: 70,
          bottom: 12,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: CustomPaint(painter: _MiniMap(dark)),
          ),
        ),
        // the sender's picture is the pin
        Positioned(
          left: 92,
          top: 46,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 10, offset: const Offset(0, 4))],
                ),
                child: _avatar('A', const Color(0xFFF7B6CB), const Color(0xFFE07FA3), size: 38),
              ),
              CustomPaint(size: const Size(12, 8), painter: _PinTip()),
            ],
          ),
        ),
        Positioned(
          left: 26,
          bottom: 24,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(12)),
            child: Text('2.4 km away', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurface)),
          ),
        ),
        Positioned(
          right: 10,
          bottom: 26,
          child: _bujji(context, size: 52, mood: BuddyMood.curious, prop: BuddyProp.magnifier, gaze: -1),
        ),
      ],
    );
  }
}

class _MiniMap extends CustomPainter {
  final bool dark;
  _MiniMap(this.dark);

  @override
  void paint(Canvas canvas, Size s) {
    Paint f(int c) => Paint()..color = Color(c);
    canvas.drawRect(Offset.zero & s, f(dark ? 0xFF15181E : 0xFFF5F3EF));
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(s.width * 0.18, s.height * 0.22, s.width * 0.5, s.height * 0.5), const Radius.circular(10)),
      f(dark ? 0xFF17261D : 0xFFCDE6C0),
    );
    canvas.drawOval(Rect.fromLTWH(s.width * 0.72, -s.height * 0.2, s.width * 0.5, s.height * 0.6), f(dark ? 0xFF0E2133 : 0xFFB3D6F2));
    final road = Paint()
      ..color = Color(dark ? 0xFF323846 : 0xFFFFFFFF)
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;
    final big = Paint()
      ..color = Color(dark ? 0xFF41485A : 0xFFFFE4B0)
      ..strokeWidth = 12;
    canvas.save();
    canvas.translate(s.width / 2, s.height / 2);
    canvas.rotate(-0.19);
    canvas.translate(-s.width / 2, -s.height / 2);
    for (final x in [0.08, 0.42, 0.82]) {
      canvas.drawLine(Offset(s.width * x, -20), Offset(s.width * x, s.height + 20), road);
    }
    canvas.drawLine(Offset(-20, s.height * 0.12), Offset(s.width + 20, s.height * 0.12), road);
    canvas.drawLine(Offset(-20, s.height * 0.86), Offset(s.width + 20, s.height * 0.86), big);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MiniMap old) => old.dark != dark;
}

class _PinTip extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(s.width, 0)
        ..lineTo(s.width / 2, s.height)
        ..close(),
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_PinTip old) => false;
}

// ---- #location: live for a while, or a check-in ----

class _Live extends StatefulWidget {
  const _Live();
  @override
  State<_Live> createState() => _LiveState();
}

class _LiveState extends State<_Live> with _Steps<_Live> {
  @override
  int get steps => 3;
  @override
  int get ms => 1800;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Stack(
      children: [
        Positioned(
          left: 14,
          top: 16,
          child: Row(
            children: [
              for (final (i, t) in const ['15 min', '1 hour', '8 hours'].indexed) ...[
                _chip(context, Icons.schedule_rounded, t, on: i == step),
                const SizedBox(width: 6),
              ],
            ],
          ),
        ),
        Positioned(
          left: 14,
          top: 70,
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 9, 14, 9),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 4))],
            ),
            child: Row(
              children: [
                _avatar('A', const Color(0xFFF7B6CB), const Color(0xFFE07FA3)),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Aria arrived', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: cs.onSurface)),
                    Text('Home, 9:42 PM', style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
                  ],
                ),
                const SizedBox(width: 10),
                const Icon(Icons.check_circle_rounded, size: 20, color: Color(0xFF2E9E5B)),
              ],
            ),
          ),
        ),
        Positioned(
          right: 22,
          bottom: 20,
          child: _bujji(context, size: 56, mood: BuddyMood.happy, prop: BuddyProp.flag),
        ),
      ],
    );
  }
}

// ---- #chats: hold a message and slide onto an action ----

class _Slide extends StatefulWidget {
  const _Slide();
  @override
  State<_Slide> createState() => _SlideState();
}

class _SlideState extends State<_Slide> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600),
  )..repeat();

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  static const _acts = [
    (Icons.reply_rounded, 'Reply'),
    (Icons.copy_rounded, 'Copy'),
    (Icons.push_pin_outlined, 'Pin'),
    (VibeThreads.icon, 'Thread'),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _a,
      builder: (context, _) {
        // the finger slides along the row and rests on each in turn
        final t = Curves.easeInOut.transform(math.min(1.0, _a.value * 1.25));
        final on = (t * 3.999).floor();
        final x = 18 + 30 + t * 3 * 68;
        return Stack(
          children: [
            Positioned(left: 14, top: 12, child: _bubble(context, 'See you at 7?', mine: false)),
            for (final (i, (icon, label)) in _acts.indexed)
              Positioned(
                left: 18 + i * 68.0,
                top: 66,
                child: AnimatedScale(
                  scale: i == on ? 1.08 : 1,
                  duration: const Duration(milliseconds: 160),
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: i == on ? cs.primary : cs.surface,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon, size: 20, color: i == on ? cs.onPrimary : cs.onSurface),
                        const SizedBox(height: 3),
                        Text(
                          label,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: i == on ? cs.onPrimary : cs.onSurface),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Positioned(
              left: x - 13,
              top: 124,
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.primary.withValues(alpha: 0.2),
                  border: Border.all(color: cs.primary, width: 2),
                ),
              ),
            ),
            Positioned(right: 12, bottom: 4, child: _bujji(context, size: 40, mood: BuddyMood.wink)),
          ],
        );
      },
    );
  }
}

// ---- #chats: threads beside the chat's name ----

class _Threads extends StatelessWidget {
  const _Threads();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget round(IconData icon) => Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(color: cs.surfaceContainerHighest, shape: BoxShape.circle),
      child: Icon(icon, size: 19, color: cs.onSurface),
    );
    Widget row(String name, String sub) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: cs.primaryContainer, shape: BoxShape.circle),
            child: Icon(VibeThreads.icon, size: 16, color: cs.onPrimaryContainer),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: cs.onSurface)),
                Text(sub, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          Icon(Icons.close_rounded, size: 17, color: cs.onSurfaceVariant),
        ],
      ),
    );
    return Stack(
      children: [
        Positioned(
          left: 12,
          top: 10,
          child: Row(
            children: [
              round(Icons.arrow_back),
              const SizedBox(width: 6),
              Container(
                height: 40,
                padding: const EdgeInsets.fromLTRB(4, 0, 14, 0),
                decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(20)),
                child: Row(
                  children: [
                    _avatar('A', const Color(0xFFF7B6CB), const Color(0xFFE07FA3)),
                    const SizedBox(width: 8),
                    Text('Aria', style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurface)),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              // right beside the name
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: cs.primary, width: 2)),
                child: round(VibeThreads.icon),
              ),
            ],
          ),
        ),
        Positioned(
          left: 12,
          right: 86,
          top: 66,
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
            decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(16)),
            child: Column(
              children: [row('Dinner plans', 'Aria · 6 replies'), row('Trip photos', 'You · 2 replies')],
            ),
          ),
        ),
        Positioned(
          right: 14,
          bottom: 22,
          child: _bujji(context, size: 54, mood: BuddyMood.curious, gaze: -1),
        ),
      ],
    );
  }
}

// ---- #home: you on top, unread chats as cards ----

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget card(String k, Color a, Color b, String name, String text) => Container(
      width: 128,
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _avatar(k, a, b, size: 24),
              const SizedBox(width: 6),
              Text(name, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: cs.onSurface)),
            ],
          ),
          const SizedBox(height: 6),
          Text(text, maxLines: 2, style: TextStyle(fontSize: 11.5, color: cs.onSurface)),
          const SizedBox(height: 7),
          Container(
            height: 24,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
            child: Text('Reply', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ),
        ],
      ),
    );
    return Stack(
      children: [
        Positioned(
          left: 14,
          right: 14,
          top: 10,
          child: Row(
            children: [
              _avatar('Y', const Color(0xFF9DB0F2), const Color(0xFF5568B5), size: 30),
              const SizedBox(width: 8),
              Text('You', style: TextStyle(fontWeight: FontWeight.w800, color: cs.onSurface)),
              const Spacer(),
              Icon(Icons.search_rounded, size: 20, color: cs.onSurface),
              const SizedBox(width: 10),
              Icon(Icons.settings_outlined, size: 20, color: cs.onSurface),
            ],
          ),
        ),
        Positioned(
          left: 14,
          top: 52,
          child: Row(
            children: [
              _chip(context, Icons.chat_bubble_outline_rounded, 'Chats 3', on: true),
              const SizedBox(width: 6),
              _chip(context, Icons.workspaces_outline, 'Spaces 1'),
            ],
          ),
        ),
        Positioned(
          left: 14,
          top: 94,
          child: Row(
            children: [
              card('A', const Color(0xFFF7B6CB), const Color(0xFFE07FA3), 'Aria', 'Are we still on for tonight?'),
              const SizedBox(width: 8),
              card('D', const Color(0xFF8FDACB), const Color(0xFF3EA592), 'Dev', 'Sent the photos'),
            ],
          ),
        ),
        Positioned(
          right: 6,
          top: 96,
          child: _bujji(context, size: 40, mood: BuddyMood.curious, gaze: -0.8, look: 0.7),
        ),
      ],
    );
  }
}

// ---- #security: a post-quantum layer inside the usual encryption ----

class _Pq extends StatelessWidget {
  const _Pq();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Stack(
      children: [
        Positioned(
          left: 18,
          top: 18,
          child: Container(
            width: 190,
            height: 162,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Matrix encryption', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
                const SizedBox(height: 8),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.enhanced_encryption_rounded, size: 34, color: cs.onPrimaryContainer),
                        const SizedBox(height: 6),
                        Text(
                          'ML-KEM-768',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: cs.onPrimaryContainer),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          right: 22,
          bottom: 30,
          child: _bujji(context, size: 58, mood: BuddyMood.smart, prop: BuddyProp.shield),
        ),
      ],
    );
  }
}

// ---- "Show me where": Bujji points at the real thing ----

abstract class BujjiCoach {
  static OverlayEntry? _entry;

  static void hide() {
    _entry?.remove();
    _entry = null;
  }

  /// Dims the screen except [spot] (or [orSpot] if that isn't showing),
  /// with Bujji beside it and a card: [title], [body], and Back to the tour
  /// when there's a [back].
  static Future<void> point(
    String spot, {
    String? orSpot,
    required String title,
    required String body,
    VoidCallback? back,
  }) async {
    hide();
    // the screen it's on opens first
    await Future.delayed(const Duration(milliseconds: 650));
    Rect? hole;
    for (var i = 0; i < 20 && hole == null; i++) {
      hole = BujjiLife.rectOf(spot) ?? (orSpot == null ? null : BujjiLife.rectOf(orSpot));
      if (hole == null) await Future.delayed(const Duration(milliseconds: 150));
    }
    final overlay = VibeApp.router.routerDelegate.navigatorKey.currentState?.overlay;
    if (overlay == null) return;
    _entry = OverlayEntry(
      builder: (_) => _Coach(hole: hole, title: title, body: body, back: back),
    );
    overlay.insert(_entry!);
  }
}

class _Coach extends StatefulWidget {
  final Rect? hole;
  final String title;
  final String body;
  final VoidCallback? back;
  const _Coach({required this.hole, required this.title, required this.body, this.back});

  @override
  State<_Coach> createState() => _CoachState();
}

class _CoachState extends State<_Coach> {
  bool _in = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _in = true);
    });
  }

  Future<void> _close([VoidCallback? then]) async {
    setState(() => _in = false);
    await Future.delayed(const Duration(milliseconds: 200));
    BujjiCoach.hide();
    then?.call();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final hole = widget.hole?.inflate(6);
    const face = 60.0;
    // Bujji and the card go below the spot when it's in the top half,
    // above it otherwise
    final below = hole == null || hole.center.dy < size.height / 2;
    final fx = ((hole?.center.dx ?? size.width / 2) - face / 2).clamp(16.0, size.width - face - 16);
    final faceTop = hole == null
        ? size.height * 0.3
        : below
        ? hole.bottom + 8
        : hole.top - face - 8;
    final card = Material(
      color: cs.surface,
      elevation: 8,
      shadowColor: Colors.black38,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: cs.onSurface)),
            const SizedBox(height: 4),
            Text(widget.body, style: TextStyle(fontSize: 14, height: 1.4, color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            Row(
              children: [
                const Spacer(),
                if (widget.back != null)
                  TextButton(onPressed: () => _close(widget.back), child: const Text('Back to the tour')),
                const SizedBox(width: 4),
                FilledButton(onPressed: _close, child: const Text('Got it')),
              ],
            ),
          ],
        ),
      ),
    );
    return AnimatedOpacity(
      opacity: _in ? 1 : 0,
      duration: const Duration(milliseconds: 220),
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: _close,
              child: CustomPaint(painter: _Dim(hole, cs.primary)),
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutBack,
            left: fx,
            top: _in ? faceTop : faceTop + (below ? 24 : -24),
            child: SizedBox(
              width: face,
              height: face,
              child: Center(
                child: VibeBuddyFace(
                  size: 48,
                  color: cs.primary,
                  mood: BuddyMood.happy,
                  outfit: VibeBuddy.outfit,
                  floating: true,
                  hop: _in ? 1 : 0,
                ),
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            top: below ? faceTop + face + 6 : null,
            bottom: below ? null : size.height - faceTop + 6,
            child: Padding(
              padding: EdgeInsets.only(bottom: below ? 0 : pad.bottom),
              child: card,
            ),
          ),
        ],
      ),
    );
  }
}

class _Dim extends CustomPainter {
  final Rect? hole;
  final Color ring;
  _Dim(this.hole, this.ring);

  @override
  void paint(Canvas canvas, Size size) {
    final all = Path()..addRect(Offset.zero & size);
    final h = hole;
    if (h == null) {
      canvas.drawPath(all, Paint()..color = Colors.black.withValues(alpha: 0.58));
      return;
    }
    final r = RRect.fromRectAndRadius(h, Radius.circular(math.min(h.width, h.height) / 2));
    canvas.drawPath(
      Path.combine(PathOperation.difference, all, Path()..addRRect(r)),
      Paint()..color = Colors.black.withValues(alpha: 0.58),
    );
    canvas.drawRRect(
      r,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_Dim old) => old.hole != hole;
}

// ---- Bujji telling the tour: its picture, its hello, its cheer ----

/// Bujji in a round tile: the tour's icon and its picture on messages.
class BujjiTile extends StatelessWidget {
  final double size;
  const BujjiTile({this.size = 40, super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: cs.primaryContainer, shape: BoxShape.circle),
      child: VibeBuddyFace(
        size: size * 0.66,
        color: cs.primary,
        mood: BuddyMood.happy,
        outfit: VibeBuddy.outfit,
      ),
    );
  }
}

class _Confetti extends CustomPainter {
  final Color tint;
  _Confetti(this.tint);

  @override
  void paint(Canvas canvas, Size s) {
    final r = math.Random(3);
    final cols = [
      const Color(0xFFFFC93C),
      const Color(0xFF7FB5E6),
      const Color(0xFFF27A93),
      const Color(0xFF6DD58C),
      const Color(0xFFB39DFF),
      tint,
    ];
    for (var i = 0; i < 26; i++) {
      final p = Offset(r.nextDouble() * s.width, r.nextDouble() * s.height);
      final paint = Paint()..color = cols[i % cols.length].withValues(alpha: 0.85);
      if (i % 3 == 0) {
        canvas.drawCircle(p, 3.5, paint);
      } else {
        canvas.save();
        canvas.translate(p.dx, p.dy);
        canvas.rotate(r.nextDouble() * 2.4 - 1.2);
        canvas.drawRRect(
          RRect.fromRectAndRadius(const Rect.fromLTWH(-4.5, -2, 9, 4), const Radius.circular(2)),
          paint,
        );
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(_Confetti old) => old.tint != tint;
}

/// A channel in Bujji's lists: its icon, name and one line.
typedef BujjiChannel = (IconData, String, String);

Widget _channelRow(BuildContext context, BujjiChannel c, {bool tick = false}) {
  final cs = Theme.of(context).colorScheme;
  final (icon, name, short) = c;
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    child: Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, size: 20, color: cs.onPrimaryContainer),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('#$name', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: cs.onSurface)),
              if (!tick && short.isNotEmpty)
                Text(short, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
            ],
          ),
        ),
        if (tick) const Icon(Icons.check_rounded, size: 20, color: Color(0xFF2E9E5B)),
      ],
    ),
  );
}

/// Bujji says hi before the tour: what's in it, Show me or Maybe later.
class BujjiHello extends StatefulWidget {
  final String version;
  final List<BujjiChannel> channels;
  final VoidCallback onStart;
  final VoidCallback onLater;
  const BujjiHello({
    required this.version,
    required this.channels,
    required this.onStart,
    required this.onLater,
    super.key,
  });

  @override
  State<BujjiHello> createState() => _BujjiHelloState();
}

class _BujjiHelloState extends State<BujjiHello> {
  int _hop = 0;

  @override
  void initState() {
    super.initState();
    // it hops in to say hi
    Future.delayed(const Duration(milliseconds: 420), () {
      if (mounted) setState(() => _hop++);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [cs.primaryContainer, cs.surface],
            stops: const [0, 0.58],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: cs.surface.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        'Keepr ${widget.version}',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onPrimaryContainer),
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: widget.onLater,
                      child: Text('Skip', style: TextStyle(color: cs.onSurfaceVariant)),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      SizedBox(
                        height: 190,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Positioned.fill(child: CustomPaint(painter: _Confetti(cs.primary))),
                            VibeBuddyFace(
                              size: 112,
                              color: cs.primary,
                              mood: BuddyMood.happy,
                              prop: BuddyProp.wave,
                              outfit: VibeBuddy.outfit,
                              floating: true,
                              hop: _hop,
                            ),
                          ],
                        ),
                      ),
                      Text(
                        "Hi, I'm Bujji!",
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: cs.onSurface),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Keepr just got an update. Can I show you what's new? It takes about a minute.",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 15.5, height: 1.45, color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Column(
                          children: [for (final c in widget.channels) _channelRow(context, c)],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton.icon(
                    onPressed: widget.onStart,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Show me', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
              TextButton(
                onPressed: widget.onLater,
                child: Text('Maybe later', style: TextStyle(color: cs.onSurfaceVariant)),
              ),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }
}

/// The end of the tour: Bujji cheers, every channel ticked.
class BujjiDone extends StatelessWidget {
  final List<BujjiChannel> channels;
  final VoidCallback onDone;
  const BujjiDone({required this.channels, required this.onDone, super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [cs.surface, cs.primaryContainer],
            stops: const [0.3, 1],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      SizedBox(
                        height: 220,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Positioned.fill(child: CustomPaint(painter: _Confetti(cs.tertiary))),
                            VibeBuddyFace(
                              size: 108,
                              color: cs.primary,
                              mood: BuddyMood.proud,
                              prop: BuddyProp.popper,
                              outfit: VibeBuddy.outfit,
                              floating: true,
                              hop: 1,
                            ),
                          ],
                        ),
                      ),
                      Text(
                        "That's everything!",
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: cs.onSurface),
                      ),
                      const SizedBox(height: 8),
                      Text.rich(
                        TextSpan(
                          text: 'Ask me any time: ',
                          children: [
                            TextSpan(
                              text: "@bujji what's new",
                              style: TextStyle(fontWeight: FontWeight.w800, color: cs.onSurface),
                            ),
                          ],
                        ),
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 15.5, color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: 22),
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: cs.surface,
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Column(
                          children: [for (final c in channels) _channelRow(context, c, tick: true)],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton(
                    onPressed: onDone,
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Start chatting', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                        SizedBox(width: 8),
                        Icon(Icons.arrow_forward_rounded),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

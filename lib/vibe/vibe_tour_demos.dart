// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Little looping mockups for the update tour: a small phone showing where
/// a feature is and what it does (a finger taps, things slide in).
enum VibeDemo {
  rename,
  threadCreate,
  threadRename,
  dock,
  search,
  quote,
  stack,
  doubleTap,
  typing,
  sounds,
  weather,
  avatar,
  restart,
  clearRead,
  failed,
  voice,
}

class VibeDemoView extends StatefulWidget {
  final VibeDemo demo;
  const VibeDemoView(this.demo, {super.key});

  @override
  State<VibeDemoView> createState() => _VibeDemoViewState();
}

class _VibeDemoViewState extends State<VibeDemoView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4600),
  )..repeat();

  @override
  void didUpdateWidget(VibeDemoView old) {
    super.didUpdateWidget(old);
    if (old.demo != widget.demo) _c.forward(from: 0).then((_) => _c.repeat());
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 260,
    child: AnimatedBuilder(
      animation: _c,
      builder: (context, _) =>
          _Demo(demo: widget.demo, t: _c.value, cs: Theme.of(context).colorScheme),
    ),
  );
}

// ---- timing helpers ----
double _seg(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);
double _ease(double t) => Curves.easeOutCubic.transform(t.clamp(0.0, 1.0));
double _pop(double t) => Curves.easeOutBack.transform(t.clamp(0.0, 1.0));

/// A finger: a soft circle that shrinks a bit while pressing.
Widget _finger(double x, double y, {bool down = false, double alpha = 1}) =>
    Positioned(
      left: x - 14,
      top: y - 14,
      child: Opacity(
        opacity: alpha.clamp(0.0, 1.0),
        child: AnimatedScale(
          scale: down ? 0.78 : 1,
          duration: const Duration(milliseconds: 120),
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.55),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.black26, width: 1.5),
            ),
          ),
        ),
      ),
    );

class _Demo extends StatelessWidget {
  final VibeDemo demo;
  final double t;
  final ColorScheme cs;
  const _Demo({required this.demo, required this.t, required this.cs});

  static const _w = 176.0, _h = 250.0;

  /// The phone: a header (name) and a body.
  Widget phone(String title, List<Widget> body, {Widget? header, Color? bg}) =>
      Center(
        child: Container(
          width: _w,
          height: _h,
          decoration: BoxDecoration(
            color: bg ?? cs.surface,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: cs.outlineVariant, width: 3),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: 40,
                child: Container(
                  color: cs.surfaceContainer,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.centerLeft,
                  child: header ??
                      Row(
                        children: [
                          _avatar(title, 20),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                ),
              ),
              ...body,
            ],
          ),
        ),
      );

  Widget _avatar(String name, double s) {
    const colors = [
      Color(0xFFED4245),
      Color(0xFF3BA55C),
      Color(0xFFFAA61A),
      Color(0xFF5865F2),
      Color(0xFFEB459E),
    ];
    return Container(
      width: s,
      height: s,
      decoration: BoxDecoration(
        color: colors[name.codeUnitAt(0) % colors.length],
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        name[0],
        style: TextStyle(
          color: Colors.white,
          fontSize: s * 0.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  /// A message row: avatar, name and text, like Keepr's chat.
  Widget msg(double top, String name, String text,
      {Color? glow, double dx = 0, Widget? under}) =>
      Positioned(
        left: 8 + dx,
        right: 8 - dx,
        top: top,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: glow,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _avatar(name, 18),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      text,
                      style: TextStyle(fontSize: 10, color: cs.onSurface),
                    ),
                    ?under,
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget inputBar({String text = ''}) => Positioned(
    left: 8,
    right: 8,
    bottom: 8,
    height: 26,
    child: Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(13),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.centerLeft,
      child: Text(
        text.isEmpty ? 'Message' : text,
        style: TextStyle(
          fontSize: 10,
          color: text.isEmpty ? cs.onSurfaceVariant : cs.onSurface,
        ),
      ),
    ),
  );

  Widget card(double top, Widget child, {double alpha = 1, double scale = 1}) =>
      Positioned(
        left: 14,
        right: 14,
        top: top,
        child: Opacity(
          opacity: alpha.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: scale,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 10),
                ],
              ),
              child: child,
            ),
          ),
        ),
      );

  Widget menuRow(IconData icon, String label, {bool on = false}) => Container(
    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
    decoration: BoxDecoration(
      color: on ? cs.primary.withValues(alpha: 0.22) : null,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      children: [
        Icon(icon, size: 13),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 10)),
      ],
    ),
  );

  Widget notif(double y, String title, String body, {double alpha = 1}) =>
      Positioned(
        left: 8,
        right: 8,
        top: y,
        child: Opacity(
          opacity: alpha.clamp(0.0, 1.0),
          child: Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
            ),
            child: Row(
              children: [
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: const Icon(Icons.lock, size: 11, color: Colors.white),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        body,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 9),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  // finger position inside the phone, as an offset in the centred frame
  Widget inPhone(BuildContext context, Widget Function(double ox) build) =>
      LayoutBuilder(
        builder: (context, c) => build((c.maxWidth - _w) / 2),
      );

  @override
  Widget build(BuildContext context) {
    switch (demo) {
      case VibeDemo.rename:
        final swap = t > 0.45;
        final s = _pop(_seg(t, 0.45, 0.62));
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Transform.scale(
                scale: swap ? 0.85 + 0.15 * s : 1 - 0.15 * _seg(t, 0.3, 0.45),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: swap
                      ? Image.asset(
                          'assets/logo/mini/logo_mini.png',
                          width: 110,
                          height: 110,
                          errorBuilder: (_, _, _) =>
                              Container(width: 110, height: 110, color: cs.primary),
                        )
                      : Container(
                          width: 110,
                          height: 110,
                          color: Colors.white,
                          child: const Icon(
                            Icons.chat_bubble,
                            size: 60,
                            color: Color(0xFF226DFD),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 14),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  swap ? 'Keepr' : 'Vibe',
                  key: ValueKey(swap),
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        );

      case VibeDemo.threadCreate:
        final inThread = t > 0.66;
        final press = t > 0.22 && t < 0.42;
        final menu = _seg(t, 0.38, 0.48) * (1 - _seg(t, 0.62, 0.66));
        return inPhone(context, (ox) => Stack(
          children: [
            phone(
              'Design crew',
              inThread
                  ? [
                      msg(52, 'Aria', 'Hike on Saturday?'),
                      msg(96 + 30 * (1 - _ease(_seg(t, 0.7, 0.85))), 'Kenji',
                          "I'm in, 8 AM?"),
                      inputBar(),
                    ]
                  : [
                      msg(50, 'Maya', 'Coffee later?'),
                      msg(96, 'Aria', 'Hike on Saturday?',
                          glow: press ? cs.primary.withValues(alpha: 0.18) : null),
                      msg(142, 'Leo', 'New mockups are up'),
                      inputBar(),
                      if (menu > 0)
                        card(118, Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            menuRow(Icons.reply, 'Reply'),
                            menuRow(Icons.forum_rounded, 'Create thread',
                                on: t > 0.52),
                            menuRow(Icons.copy, 'Copy'),
                          ],
                        ), alpha: menu, scale: 0.9 + 0.1 * menu),
                    ],
              header: inThread ? _threadHeader('Hike on Saturday?') : null,
            ),
            if (t < 0.64)
              _finger(
                ox + 90,
                t < 0.42 ? 116 : 116 + 42 * _ease(_seg(t, 0.46, 0.54)),
                down: press || (t > 0.54 && t < 0.6),
                alpha: _seg(t, 0.05, 0.15),
              ),
          ],
        ));

      case VibeDemo.threadRename:
        const name = 'Weekend plans';
        final typed = name.substring(
          0,
          (name.length * _seg(t, 0.32, 0.66)).round(),
        );
        final dialog = _seg(t, 0.24, 0.3) * (1 - _seg(t, 0.78, 0.82));
        final named = t > 0.8;
        return inPhone(context, (ox) => Stack(
          children: [
            phone('', [
              msg(52, 'Aria', 'Hike on Saturday?'),
              msg(96, 'Kenji', "I'm in, 8 AM?"),
              inputBar(),
              if (dialog > 0)
                card(80, Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Thread name',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.only(bottom: 3),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: cs.primary, width: 2)),
                      ),
                      child: Text(typed.isEmpty ? 'Hike on Saturday?' : '$typed|',
                          style: TextStyle(
                              fontSize: 10,
                              color: typed.isEmpty ? cs.onSurfaceVariant : cs.onSurface)),
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text('Save',
                          style: TextStyle(
                              fontSize: 10, fontWeight: FontWeight.w800, color: cs.primary)),
                    ),
                  ],
                ), alpha: dialog),
            ], header: _threadHeader(named ? name : 'Hike on Saturday?')),
            if (t < 0.24 || (t > 0.68 && t < 0.8))
              _finger(
                t < 0.24 ? ox + 80 : ox + 140,
                t < 0.24 ? 20 : 142,
                down: (t > 0.16 && t < 0.22) || (t > 0.72 && t < 0.77),
              ),
          ],
        ));

      case VibeDemo.dock:
        final pill = _seg(t, 0.06, 0.16) * (1 - _seg(t, 0.3, 0.34));
        final swapped = t > 0.34 && t < 0.84;
        final strip = swapped ? _ease(_seg(t, 0.36, 0.48)) : _ease(_seg(t, 0.86, 0.96));
        final swipe = _seg(t, 0.66, 0.8);
        final other = swapped ? 'Aria' : 'Maya';
        final showStrip = t > 0.36;
        return inPhone(context, (ox) => Stack(
          children: [
            phone(swapped ? 'Maya' : 'Aria', [
              if (swapped) ...[
                msg(50, 'Maya', 'Are you coming tonight?'),
                msg(94, 'You', 'Yes! 8 PM'),
              ] else ...[
                msg(50, 'Aria', 'Hike on Saturday?'),
                msg(94, 'You', "Sounds good"),
              ],
              Positioned(
                left: 8,
                right: 8,
                bottom: showStrip ? 42 : 8,
                height: 26,
                child: Container(
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.centerLeft,
                  child: Text('Message',
                      style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
                ),
              ),
              if (showStrip)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: -36 + 36 * strip + (swapped ? 0 : 0),
                  height: 36,
                  child: Transform.translate(
                    offset: Offset(0, swapped ? -120 * swipe : 0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Row(
                        children: [
                          _avatar(other, 18),
                          const SizedBox(width: 6),
                          Text(other,
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
                          const Spacer(),
                          Icon(Icons.keyboard_arrow_up, size: 14, color: cs.primary),
                        ],
                      ),
                    ),
                  ),
                ),
              if (pill > 0)
                Positioned(
                  left: 16,
                  right: 16,
                  top: -30 + 76 * _ease(pill),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
                    ),
                    child: Row(
                      children: [
                        _avatar('Maya', 16),
                        const SizedBox(width: 5),
                        const Expanded(
                          child: Text('Maya: are you coming?',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 9)),
                        ),
                      ],
                    ),
                  ),
                ),
            ]),
            if (t > 0.16 && t < 0.32)
              _finger(ox + 88, 58, down: t > 0.24),
            if (t > 0.6 && t < 0.82)
              _finger(ox + 88, 232 - 110 * swipe, down: t > 0.64),
          ],
        ));

      case VibeDemo.search:
        const q = 'pizza';
        final open = t > 0.24;
        final typed = q.substring(0, (q.length * _seg(t, 0.3, 0.5)).round());
        final hit = t > 0.55;
        return inPhone(context, (ox) => Stack(
          children: [
            phone('Leo', [
              msg(50, 'Leo', 'Dinner at 8?'),
              msg(94, 'Maya', 'Let\'s get pizza',
                  glow: hit ? cs.primary.withValues(alpha: 0.25) : null),
              msg(138, 'Leo', 'Perfect'),
              inputBar(),
            ], header: Row(
              children: [
                Expanded(
                  child: open
                      ? Text(typed.isEmpty ? 'Search this chat' : typed,
                          style: TextStyle(
                              fontSize: 11,
                              color: typed.isEmpty ? cs.onSurfaceVariant : cs.onSurface))
                      : const Text('Leo',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                ),
                if (hit)
                  Text('1 of 3', style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant)),
                const SizedBox(width: 6),
                Icon(open ? Icons.keyboard_arrow_up : Icons.search, size: 15),
              ],
            )),
            if (t < 0.26) _finger(ox + 158, 20, down: t > 0.16),
          ],
        ));

      case VibeDemo.quote:
        const words = ['Meet', 'at', '6', 'near', 'the', 'park'];
        final slide = 46 * _ease(_seg(t, 0.06, 0.2)) * (1 - _seg(t, 0.4, 0.46));
        final quoteIcon = t > 0.3;
        final picking = t > 0.46 && t < 0.8;
        final sel = (3 * _seg(t, 0.52, 0.72)).round();
        final done = t > 0.8;
        return inPhone(context, (ox) => Stack(
          children: [
            phone('Aria', [
              if (slide > 2)
                Positioned(
                  left: 12,
                  top: 110,
                  child: Icon(quoteIcon ? Icons.format_quote_rounded : Icons.reply,
                      size: 18, color: cs.primary),
                ),
              msg(100, 'Aria', words.join(' '), dx: slide),
              if (picking)
                card(150, Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (var i = 0; i < words.length; i++)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                          color: i >= 3 && i < 3 + sel
                              ? cs.primary.withValues(alpha: 0.35)
                              : null,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(words[i], style: const TextStyle(fontSize: 10)),
                      ),
                  ],
                )),
              if (done)
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 38,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      border: Border(left: BorderSide(color: cs.primary, width: 3)),
                      color: cs.surfaceContainer,
                    ),
                    child: const Text('"near the park"', style: TextStyle(fontSize: 9)),
                  ),
                ),
              inputBar(),
            ]),
            if (t < 0.44)
              _finger(ox + 40 + slide, 120, down: t > 0.06),
          ],
        ));

      case VibeDemo.stack:
        final grid = _ease(_seg(t, 0.55, 0.72));
        const colors = [
          Color(0xFF7E57C2),
          Color(0xFF26A69A),
          Color(0xFFFFA726),
          Color(0xFF42A5F5),
          Color(0xFFEC407A),
        ];
        return phone('Maya', [
          msg(46, 'Maya', '5 photos'),
          for (var i = 0; i < 5; i++)
            Builder(builder: (_) {
              final arrive = _ease(_seg(t, i * 0.08, i * 0.08 + 0.18));
              // a row of separate photos, then they gather into a 2x2 grid
              final row = Offset(14.0 + i * 30, 76 + 150 * (1 - arrive));
              final g = i < 4
                  ? Offset(34.0 + (i % 2) * 54, 76.0 + (i ~/ 2) * 54)
                  : const Offset(88, 130);
              final p = Offset.lerp(row, g, grid)!;
              final size = 26 + 24 * grid;
              return Positioned(
                left: p.dx,
                top: p.dy,
                child: Opacity(
                  opacity: i == 4 ? 1 - grid : arrive,
                  child: Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      color: colors[i],
                      borderRadius: BorderRadius.circular(6),
                    ),
                    alignment: Alignment.center,
                    child: i == 3 && grid > 0.6
                        ? const Text('+1',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800))
                        : const Icon(Icons.image, size: 14, color: Colors.white70),
                  ),
                ),
              );
            }),
          inputBar(),
        ]);

      case VibeDemo.doubleTap:
        final heart = _pop(_seg(t, 0.42, 0.56)) * (1 - _seg(t, 0.85, 0.95));
        return inPhone(context, (ox) => Stack(
          children: [
            phone('Kenji', [
              msg(80, 'Kenji', 'We won the match!',
                  under: heart > 0
                      ? Transform.scale(
                          scale: heart,
                          alignment: Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(top: 3),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: cs.primary.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text('❤️ 1', style: TextStyle(fontSize: 9)),
                          ),
                        )
                      : null),
              if (t > 0.4 && t < 0.62)
                Positioned(
                  left: 70,
                  top: 70 - 40 * _seg(t, 0.4, 0.62),
                  child: Opacity(
                    opacity: 1 - _seg(t, 0.5, 0.62),
                    child: const Text('❤️', style: TextStyle(fontSize: 30)),
                  ),
                ),
              inputBar(),
            ]),
            if (t > 0.1 && t < 0.46)
              _finger(ox + 96, 102,
                  down: (t > 0.22 && t < 0.27) || (t > 0.32 && t < 0.37)),
          ],
        ));

      case VibeDemo.typing:
        const emojis = ['☕', '✨', '🔥'];
        return phone('Sam', [
          msg(52, 'Sam', 'Wait, I have news'),
          Positioned(
            left: 12,
            bottom: 42,
            child: Row(
              children: [
                for (var i = 0; i < 3; i++)
                  Transform.translate(
                    offset: Offset(0, -5 * math.max(0, math.sin((t * 4 - i * 0.18) * 2 * math.pi))),
                    child: Text(emojis[i], style: const TextStyle(fontSize: 14)),
                  ),
                const SizedBox(width: 6),
                Text('Sam is cooking up a reply…',
                    style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          inputBar(),
        ]);

      case VibeDemo.sounds:
        final drop = _ease(_seg(t, 0.1, 0.25)) * (1 - _seg(t, 0.85, 0.95));
        return phone('', [
          notif(-60 + 100 * drop, 'Maya', 'See you soon', alpha: drop),
          for (var i = 0; i < 3; i++)
            Positioned(
              left: 60 + i * 26.0,
              top: 150 - 70 * _seg((t * 2 + i * 0.3) % 1, 0, 1),
              child: Opacity(
                opacity: drop * (1 - _seg((t * 2 + i * 0.3) % 1, 0.6, 1)),
                child: Icon(i.isEven ? Icons.music_note : Icons.graphic_eq,
                    size: 20, color: cs.primary),
              ),
            ),
        ], header: const Text('Keepr chime',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)));

      case VibeDemo.weather:
        final r = math.Random(3);
        return phone('Leo', [
          Positioned.fill(
            child: Container(color: const Color(0xFF263238).withValues(alpha: 0.35)),
          ),
          for (var i = 0; i < 26; i++)
            Builder(builder: (_) {
              final x = r.nextDouble() * 176;
              final off = r.nextDouble();
              final u = (t * 2 + off) % 1;
              return Positioned(
                left: x - u * 20,
                top: 40 + u * 210,
                child: Container(
                  width: 2,
                  height: 12,
                  color: const Color(0xFF90CAF9).withValues(alpha: 0.8),
                ),
              );
            }),
          msg(150, 'Leo', "It's raining here"),
          inputBar(),
        ]);

      case VibeDemo.avatar:
        return Center(
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: SweepGradient(
                transform: GradientRotation(t * 2 * math.pi),
                colors: const [
                  Color(0xFF5865F2),
                  Color(0xFFEB459E),
                  Color(0xFFFAA61A),
                  Color(0xFF3BA55C),
                  Color(0xFF5865F2),
                ],
              ),
            ),
            alignment: Alignment.center,
            child: Transform.rotate(
              angle: math.sin(t * 2 * math.pi) * 0.2,
              child: const Text('😎', style: TextStyle(fontSize: 54)),
            ),
          ),
        );

      case VibeDemo.restart:
        final gone = _ease(_seg(t, 0.08, 0.26));
        final clock = _seg(t, 0.3, 0.62);
        final back = _ease(_seg(t, 0.66, 0.78)) * (1 - _seg(t, 0.92, 1));
        return phone('', [
          Positioned(
            left: 34,
            right: 34,
            top: 54 - 140 * gone,
            height: 120,
            child: Opacity(
              opacity: 1 - gone,
              child: Container(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: const Text('Keepr',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
              ),
            ),
          ),
          if (clock > 0 && clock < 1)
            Positioned(
              left: 0,
              right: 0,
              top: 90,
              child: Column(
                children: [
                  Transform.rotate(
                    angle: clock * 4 * math.pi,
                    child: Icon(Icons.refresh, size: 34, color: cs.primary),
                  ),
                  const SizedBox(height: 4),
                  const Text('within 15 min', style: TextStyle(fontSize: 10)),
                ],
              ),
            ),
          notif(-50 + 96 * back, 'Keepr', 'Checking for new messages', alpha: back),
        ], header: const Text('Recent apps',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)));

      case VibeDemo.clearRead:
        final read = t > 0.42;
        final away = _seg(t, 0.5, 0.64);
        return Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 130,
                height: 220,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    decoration: BoxDecoration(
                      color: cs.surface,
                      border: Border.all(color: cs.outlineVariant, width: 3),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          left: 6 + 130 * away,
                          right: 6 - 130 * away,
                          top: 20,
                          child: Opacity(
                            opacity: 1 - away,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text('Maya: lunch?', style: TextStyle(fontSize: 9)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Container(
                width: 120,
                height: 84,
                decoration: BoxDecoration(
                  color: cs.surface,
                  border: Border.all(color: cs.outlineVariant, width: 3),
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.all(6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Maya', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
                    const Text('lunch?', style: TextStyle(fontSize: 9)),
                    const Spacer(),
                    if (read)
                      Row(
                        children: [
                          Icon(Icons.done_all, size: 12, color: cs.primary),
                          const SizedBox(width: 3),
                          const Text('Read', style: TextStyle(fontSize: 9)),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        );

      case VibeDemo.failed:
        final fail = t > 0.3;
        final drop = _ease(_seg(t, 0.45, 0.58)) * (1 - _seg(t, 0.9, 1));
        return phone('Leo', [
          msg(110, 'You', 'On my way',
              under: fail
                  ? const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, size: 11, color: Colors.red),
                          SizedBox(width: 3),
                          Text('Not sent · Retry',
                              style: TextStyle(fontSize: 9, color: Colors.red)),
                        ],
                      ),
                    )
                  : null),
          inputBar(),
          notif(-50 + 96 * drop, 'Keepr', 'Message not sent. Open the chat to try again.',
              alpha: drop),
        ]);

      case VibeDemo.voice:
        return phone('Aria', [
          Positioned(
            left: 14,
            right: 14,
            top: 100,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(Icons.pause_circle_filled, size: 22, color: cs.primary),
                  const SizedBox(width: 6),
                  for (var i = 0; i < 16; i++)
                    Container(
                      width: 3,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      height: 6 + 14 * (0.5 + 0.5 * math.sin(i * 1.3 + 1)),
                      decoration: BoxDecoration(
                        color: i / 16 < t ? cs.primary : cs.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                ],
              ),
            ),
          ),
          inputBar(),
        ]);
    }
  }

  Widget _threadHeader(String name) => Row(
    children: [
      Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: cs.primaryContainer,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(Icons.forum_rounded, size: 12, color: cs.onPrimaryContainer),
      ),
      const SizedBox(width: 6),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
            Text('Thread in Design crew',
                style: TextStyle(fontSize: 8, color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    ],
  );
}

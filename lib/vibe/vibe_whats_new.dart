// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:vibe/vibe/vibe_palette.dart';
import 'package:vibe/config/setting_keys.dart';
import 'package:vibe/widgets/vibe_app.dart';
import 'package:vibe/vibe/vibe_motion.dart';
import 'package:vibe/vibe/vibe_haptics.dart';
import 'package:vibe/vibe/vibe_updater.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:vibe/vibe/vibe_threads.dart';
import 'dart:math' as math;
import 'package:package_info_plus/package_info_plus.dart';

/// Release notes. NEWEST FIRST. Add a new entry at the top for every
/// release; `version` is the major.minor from pubspec.yaml (the build
/// number is added automatically by the release workflow).
const vibeReleaseNotes = <({String version, List<String> items})>[
  (
    version: '3.1',
    items: [
      'Sending shows a pulsing dot (a line runs between two dots while it encrypts), then 1 dot sent, 2 dots delivered, 3 blue dots read',
      'Questions, menus and settings pages slide up from the bottom and close with a swipe down',
      'Full-screen effects for words like love, miss you, good morning, good night, hug, kiss, congrats, bye, sweet dreams, hi and welcome',
      'Back up chats to Google Drive automatically: Settings, Backups, Back up to Google Drive',
      'Your profile pane looks like Keepr X: your picture blurred behind it, a floating bar and a smaller thought bubble',
      'Connecting shows three dots in the chat bar that turn green once you\'re connected',
      'Continue with Google, and your password manager fills in your login',
      'New messages glide into the chat, and chats slide open and closed more smoothly',
      'Bold names in the chat list, unread in white, and a red "read up to here" line',
      'Long messages keep their dots right after the text',
      'The media pane shows all the photos and videos in the chat',
    ],
  ),
  (
    version: '3.0',
    items: [
      'Save received photos to your gallery and keep media on the phone',
      'Swipe to reply, smoother and with a vibration',
      'Fixes: unread badges, read receipts, pop-up notifications, haptics, sign-in, and more',
    ],
  ),
];

abstract class VibeWhatsNew {
  static const _seenKey = 'chat.keepr.whats_new_seen';

  /// Show the card once after every update. Call when the home screen
  /// is up.
  static Future<void> maybeShow() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final version = info.version; // e.g. 1.1.37
      final seen = AppSettings.store.getString(_seenKey);
      if (seen == version) return;
      await AppSettings.store.setString(_seenKey, version);
      final ctx =
          VibeApp.router.routerDelegate.navigatorKey.currentContext;
      if (ctx == null || !ctx.mounted) return;
      // a big update has its own tour, shown once; smaller ones get the card
      final short = version.split('.').take(2).join('.');
      final tourKey = 'chat.keepr.tour_seen.${vibeTour.id}';
      if (vibeTour.version == short &&
          AppSettings.store.getBool(tourKey) != true) {
        await AppSettings.store.setBool(tourKey, true);
        if (!ctx.mounted) return;
        await VibeTour.open(ctx);
        return;
      }
      await show(ctx, version);
    } catch (_) {}
  }

  /// Vibe X's card: the logo, the title, one dot per change (each pops in,
  /// one after another) and a round "Got it".
  static Future<void> show(BuildContext context, String version) async {
    final short = version.split('.').take(2).join('.');
    final notes =
        vibeReleaseNotes.where((n) => n.version == short).firstOrNull ??
        vibeReleaseNotes.first;
    // this version's own notes from its release page (what really changed);
    // the list built into the app only if that can't be reached
    var items = notes.items;
    final fetched = await VibeUpdater.notesFor(version).timeout(
      const Duration(seconds: 6),
      onTimeout: () => const <String>[],
    );
    if (fetched.isNotEmpty) items = fetched;
    if (!context.mounted) return;
    VibeHaptics.medium();
    return showVibeSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.85,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.asset(
                          'assets/logo/mini/logo_mini.png',
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            width: 48,
                            height: 48,
                            color: _blurple,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'What\'s new in Keepr',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: cs.onSurface,
                              ),
                            ),
                            Text(
                              'You\'re now on $version',
                              style: TextStyle(color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  for (final (i, line) in items.indexed)
                    _PopIn(
                      index: i,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              margin: const EdgeInsets.only(top: 7),
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: _blurple,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                line,
                                style: TextStyle(
                                  fontSize: 15,
                                  height: 20 / 15,
                                  color: cs.onSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 18),
                  Material(
                    color: _blurple,
                    borderRadius: BorderRadius.circular(25),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => Navigator.of(ctx).pop(),
                      child: const SizedBox(
                        height: 50,
                        width: double.infinity,
                        child: Center(
                          child: Text(
                            'Got it',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

Color get _blurple => VibePalette.accent;

/// Vibe X's pop-in: each line springs up from nothing (a little squeeze
/// past full size), 28 ms after the one before.
class _PopIn extends StatefulWidget {
  final int index;
  final Widget child;
  const _PopIn({required this.index, required this.child});

  @override
  State<_PopIn> createState() => _PopInState();
}

class _PopInState extends State<_PopIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController.unbounded(
    vsync: this,
  );

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: widget.index * 28), () {
      if (!mounted) return;
      _c.animateWith(
        SpringSimulation(
          SpringDescription.withDampingRatio(
            mass: 1,
            stiffness: 420,
            ratio: 0.45,
          ),
          0,
          1,
          0,
        ),
      );
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    child: widget.child,
    builder: (context, child) {
      final v = _c.value;
      return Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform.scale(scale: v, child: child),
      );
    },
  );
}

/// One change in Vibe X's style: a blue dot and the text (any emoji at the
/// start is dropped), popping in [index] lines after the first.
class VibeNoteLine extends StatelessWidget {
  final int index;
  final String text;
  const VibeNoteLine({required this.index, required this.text, super.key});

  static final _lead = RegExp(r'^[^\p{L}\p{N}"(]+', unicode: true);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _PopIn(
      index: index,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 7),
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: _blurple,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text.replaceFirst(_lead, ''),
                style: TextStyle(
                  fontSize: 15,
                  height: 20 / 15,
                  color: cs.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


// ---- the update tour: a few pages, one per area, each with its cards ----

class VibeTourItem {
  final IconData icon;
  final String title;
  final String body;
  const VibeTourItem(this.icon, this.title, this.body);
}

class VibeTourPage {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<VibeTourItem> items;
  const VibeTourPage(this.icon, this.title, this.subtitle, this.items);
}

/// This update's tour. For the next big update: change [id] and [version]
/// and write new pages. The first page lists the others by itself.
const vibeTour = (
  id: '3.1-keepr',
  version: '3.1',
  pages: <VibeTourPage>[
    VibeTourPage(
      Icons.lock_rounded,
      'Vibe is now Keepr',
      'A new name and a new icon. Same account, same chats, same encryption.',
      [
        VibeTourItem(Icons.badge_outlined, 'A new name',
            'Vibe is now Keepr everywhere: the app, the website and the store.'),
        VibeTourItem(Icons.apps_rounded, 'A new icon',
            'A white chat bubble with a lock, on a smooth dark blue background.'),
        VibeTourItem(Icons.verified_user_outlined, 'Nothing to set up',
            'Your chats, keys and settings carry on as before.'),
      ],
    ),
    VibeTourPage(
      VibeThreads.icon,
      'Threads',
      'Keep side conversations out of the main chat.',
      [
        VibeTourItem(Icons.add_comment_outlined, 'Start one from any message',
            'Long-press a message, then Create thread.'),
        VibeTourItem(Icons.edit_outlined, 'Give it a name',
            'Tap the thread\'s name to rename it. Without a name, it\'s called after its first message.'),
        VibeTourItem(Icons.push_pin_outlined, 'Pinned until you close it',
            'Threads stay in the chat\'s side pane until you close them.'),
      ],
    ),
    VibeTourPage(
      Icons.chat_bubble_rounded,
      'Chatting',
      'Small things that make every chat quicker.',
      [
        VibeTourItem(Icons.call_to_action_outlined, 'Keep a chat docked',
            'Open another chat from the top pill, or pull a chat\'s name down, and it waits under the text box. Swipe it up to go back.'),
        VibeTourItem(Icons.search_rounded, 'Search in a chat',
            'Results as you type, with arrows to step through every match.'),
        VibeTourItem(Icons.format_quote_rounded, 'Quote part of a message',
            'Swipe to reply and hold a moment to pick the words you want.'),
        VibeTourItem(Icons.photo_library_outlined, 'Photo stacks',
            'Four or more photos sent together show as one grid.'),
        VibeTourItem(Icons.touch_app_outlined, 'Double tap, your way',
            'React, reply, quote, bookmark or copy: you choose.'),
      ],
    ),
    VibeTourPage(
      Icons.palette_rounded,
      'Make it yours',
      'Customisation has more to play with.',
      [
        VibeTourItem(Icons.more_horiz_rounded, 'Your own typing indicator',
            'Up to three emojis, an animation and a phrase others see while you type.'),
        VibeTourItem(Icons.music_note_outlined, 'Notification sounds',
            'Keepr chime, Pop, Bell or Pluck, each with a play button.'),
        VibeTourItem(Icons.thunderstorm_outlined, 'Weather on screen',
            'Rain, sunny day or winter words fill the screen with their own scene.'),
        VibeTourItem(Icons.gif_box_outlined, 'Animated profile pictures',
            'GIF profile pictures play in profiles and chat details.'),
      ],
    ),
    VibeTourPage(
      Icons.notifications_active_rounded,
      'Notifications',
      'Messages arrive, and read ones tidy themselves up.',
      [
        VibeTourItem(Icons.refresh_rounded, 'Back on its own',
            'If the phone stops Keepr in the background, it starts again within 15 minutes.'),
        VibeTourItem(Icons.done_all_rounded, 'Read here, cleared there',
            'Reading a chat on another device clears its notification.'),
        VibeTourItem(Icons.error_outline_rounded, 'Know when a message fails',
            'A notification tells you if a message couldn\'t be sent.'),
        VibeTourItem(Icons.mic_none_rounded, 'Voice messages everywhere',
            'Voice messages recorded on Android now play on every phone.'),
      ],
    ),
  ],
);

/// Full-screen tour: dots, back, "Skip for now", a big icon in a soft
/// shape, the title, cards, and Continue (last page: Start chatting).
class VibeTour extends StatefulWidget {
  const VibeTour({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context, rootNavigator: true).push(
        PageRouteBuilder<void>(
          transitionDuration: const Duration(milliseconds: 380),
          pageBuilder: (_, _, _) => const VibeTour(),
          transitionsBuilder: (_, a, _, child) => FadeTransition(
            opacity: a,
            child: SlideTransition(
              position: Tween(begin: const Offset(0, 0.06), end: Offset.zero)
                  .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
              child: child,
            ),
          ),
        ),
      );

  @override
  State<VibeTour> createState() => _VibeTourState();
}

class _VibeTourState extends State<VibeTour> {
  final _pages = PageController();
  int _i = 0;

  int get _count => vibeTour.pages.length + 1;

  void _go(int i) => _pages.animateToPage(
    i,
    duration: const Duration(milliseconds: 420),
    curve: Curves.easeOutCubic,
  );

  void _next() {
    VibeHaptics.light();
    if (_i >= _count - 1) {
      Navigator.of(context).pop();
    } else {
      _go(_i + 1);
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final last = _i == _count - 1;
    return PopScope(
      canPop: _i == 0,
      onPopInvokedWithResult: (pop, _) {
        if (!pop) _go(_i - 1);
      },
      child: Scaffold(
        backgroundColor: cs.surface,
        body: SafeArea(
          child: Column(
            children: [
              SizedBox(
                height: 52,
                child: Row(
                  children: [
                    SizedBox(
                      width: 56,
                      child: _i == 0
                          ? null
                          : IconButton(
                              tooltip: 'Back',
                              icon: const Icon(Icons.arrow_back),
                              onPressed: () => _go(_i - 1),
                            ),
                    ),
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var k = 0; k < _count; k++)
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 260),
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              width: k == _i ? 22 : 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: k == _i ? cs.onSurface : cs.outlineVariant,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(
                        last ? 'Close' : 'Skip for now',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pages,
                  itemCount: _count,
                  onPageChanged: (i) => setState(() => _i = i),
                  itemBuilder: (context, i) => i == 0
                      ? _TourPageView(
                          page: VibeTourPage(
                            Icons.auto_awesome_rounded,
                            'Keepr ${vibeTour.version} is here',
                            'Our biggest update yet. Here\'s a quick look at what\'s new.',
                            [
                              for (final p in vibeTour.pages)
                                VibeTourItem(p.icon, p.title, ''),
                            ],
                          ),
                          onItem: (k) => _go(k + 1),
                        )
                      : _TourPageView(page: vibeTour.pages[i - 1]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: _blurple,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(27),
                      ),
                    ),
                    onPressed: _next,
                    icon: Icon(last ? Icons.chat_rounded : Icons.arrow_forward),
                    label: Text(
                      last ? 'Start chatting' : 'Continue',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
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

class _TourPageView extends StatelessWidget {
  final VibeTourPage page;
  final void Function(int)? onItem;
  const _TourPageView({required this.page, this.onItem});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      children: [
        Center(child: _TourBlob(icon: page.icon)),
        const SizedBox(height: 20),
        Text(
          page.title,
          style: TextStyle(
            fontSize: 30,
            height: 1.15,
            fontWeight: FontWeight.w800,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          page.subtitle,
          style: TextStyle(fontSize: 16, height: 1.4, color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        for (final (k, item) in page.items.indexed)
          _PopIn(
            index: k + 3,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(20),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onItem == null ? null : () => onItem!(k),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
                    child: Row(
                      crossAxisAlignment: item.body.isEmpty
                          ? CrossAxisAlignment.center
                          : CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(item.icon, size: 21, color: cs.onSurface),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (item.body.isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Text(
                                  item.body,
                                  style: TextStyle(
                                    fontSize: 14,
                                    height: 1.35,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (onItem != null)
                          Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The big icon in a slowly turning soft scalloped shape, with two small
/// dots floating beside it.
class _TourBlob extends StatefulWidget {
  final IconData icon;
  const _TourBlob({required this.icon});

  @override
  State<_TourBlob> createState() => _TourBlobState();
}

class _TourBlobState extends State<_TourBlob>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 190,
      height: 150,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value * 2 * math.pi;
          return Stack(
            alignment: Alignment.center,
            children: [
              Transform.rotate(
                angle: t,
                child: CustomPaint(
                  size: const Size(128, 128),
                  painter: _Scallop(cs.secondaryContainer),
                ),
              ),
              Icon(widget.icon, size: 54, color: cs.onSecondaryContainer),
              Positioned(
                right: 18 + math.sin(t) * 4,
                top: 4 + math.cos(t) * 4,
                child: _dot(22, cs.secondaryContainer),
              ),
              Positioned(
                left: 20 + math.cos(t) * 3,
                bottom: 10 + math.sin(t) * 3,
                child: _dot(12, cs.secondaryContainer),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _dot(double s, Color c) => Container(
    width: s,
    height: s,
    decoration: BoxDecoration(color: c, shape: BoxShape.circle),
  );
}

class _Scallop extends CustomPainter {
  final Color color;
  _Scallop(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final path = Path();
    for (var k = 0; k <= 180; k++) {
      final a = k / 180 * 2 * math.pi;
      final rr = r * (0.9 + 0.1 * math.cos(9 * a));
      final p = c + Offset(math.cos(a), math.sin(a)) * rr;
      k == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path..close(), Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _Scallop old) => old.color != color;
}

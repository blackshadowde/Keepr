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
import 'dart:async';
import 'package:vibe/vibe/vibe_tour_demos.dart';
import 'package:vibe/vibe/vibe_hot_words.dart';
import 'package:vibe/widgets/typing_animation.dart';
import 'package:vibe/widgets/matrix.dart';
import 'package:vibe/vibe/buddy/bujji_tour.dart';
import 'package:vibe/vibe/buddy/vibe_buddy.dart';
import 'package:matrix/matrix.dart' show Membership;
import 'package:package_info_plus/package_info_plus.dart';

/// Release notes. NEWEST FIRST. Add a new entry at the top for every
/// release; `version` is the major.minor from pubspec.yaml (the build
/// number is added automatically by the release workflow).
const vibeReleaseNotes = <({String version, List<String> items})>[
  (
    version: '3.1',
    items: [
      'Bujji, your typing buddy, has a life of its own: it hops onto new photos, brings the right thing (a hammer to pin, a pen while you edit) and tells you about live locations',
      'Ask @bujji to remember notes and birthdays, set reminders, or open and change settings, all on your phone',
      'A new map: send a spot, share live for 15 minutes to 8 hours, or check in',
      'Hold a message and slide onto an action or a reaction',
      'Threads one tap away, right beside the chat\'s name',
      'Home: your profile on top, unread chats as cards you can answer right there',
      'Post-quantum direct chats between Keepr users',
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
      // the tour plays its channels not seen yet (each channel once);
      // when there's nothing new to show, the card
      final short = version.split('.').take(2).join('.');
      final unseen = VibeTour.unseen();
      if (vibeTour.version == short && unseen.isNotEmpty) {
        await VibeTour.markSeen(unseen);
        if (!ctx.mounted) return;
        await VibeTour.open(ctx, only: unseen);
        return;
      }
      await show(ctx, version);
    } catch (_) {}
  }

  /// "@bujji what's new": the whole tour again.
  static void tour() {
    final ctx = VibeApp.router.routerDelegate.navigatorKey.currentContext;
    if (ctx != null && ctx.mounted) VibeTour.open(ctx);
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
                      if (VibeBuddy.on)
                        const BujjiTile(size: 48)
                      else
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
                  const SizedBox(height: 14),
                  Center(
                    child: TextButton.icon(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        VibeTour.open(context);
                      },
                      icon: const Icon(Icons.play_circle_outline_rounded),
                      label: Text(
                        VibeBuddy.on ? "Watch Bujji's tour" : 'Watch the tour',
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
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

  /// The little animation that shows where it is and what it does.
  final VibeDemo? demo;

  /// Or a live mockup with Bujji in it.
  final Widget Function(BuildContext)? show;

  /// "Show me where": the spot in the app Bujji points at, and what it says.
  final String? where;
  final String? tip;
  const VibeTourItem(
    this.icon,
    this.title,
    this.body, [
    this.demo,
    this.show,
    this.where,
    this.tip,
  ]);
}

class VibeTourPage {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<VibeTourItem> items;

  /// One line for Bujji's hello list.
  final String short;
  const VibeTourPage(
    this.icon,
    this.title,
    this.subtitle,
    this.items, {
    this.short = '',
  });
}

/// This update's tour. For the next big update: change [id] and [version]
/// and write new pages; each channel plays once per [id].
const vibeTour = (
  id: '3.1-bujji',
  version: '3.1',
  channels: <String>['bujji', 'location', 'chats', 'home', 'security'],
  pages: <VibeTourPage>[
    VibeTourPage(
      Icons.auto_awesome_rounded,
      'Bujji, your typing buddy',
      "That's me! I float above the text box, and now I have a life of my own.",
      short: 'Bujji got a life of its own',
      [
        VibeTourItem(
          Icons.handyman_outlined,
          'I bring the right thing',
          "A hammer when you pin, a pen while you edit (I keep it until it's sent), a broom when you delete, coffee in the morning, headphones for a voice note.",
          null,
          BujjiTourDemos.tools,
          'tour.bujji',
          'Here I am, above the text box. Tap me, or drag me and let me go.',
        ),
        VibeTourItem(
          Icons.photo_outlined,
          'A life of my own',
          "I hop onto a new photo to look, peek from behind your messages, run over to someone's typing dots and nap on the newest message at night. Start typing and I'm back.",
          null,
          BujjiTourDemos.life,
        ),
        VibeTourItem(
          Icons.sentiment_satisfied_alt_rounded,
          'Moods',
          'I hug a heart when someone sends love, wink at a hello, go shy when you call me cute and get dizzy if you shake the phone. Poke me too much and I turn my back; hold me to make up.',
        ),
        VibeTourItem(
          Icons.alternate_email_rounded,
          'Ask me',
          '"@bujji remind me to call mom at 6 pm", "@bujji turn on dark mode", "@bujji open notification settings". All on your phone, no AI.',
        ),
        VibeTourItem(
          Icons.tune_rounded,
          'Your pace',
          'Settings, Typing buddy: Lively, Calm (I stay on the text box) or Off.',
        ),
      ],
    ),
    VibeTourPage(
      Icons.place_rounded,
      'Location',
      'A brand new map: pinch, turn and tilt it in 3D, light or dark with the app.',
      short: 'A new map, live and check-ins',
      [
        VibeTourItem(
          Icons.place_outlined,
          'Send a spot',
          'Your picture is the pin, and the card shows how far it is. Open it for Google Maps, Waze or directions.',
          null,
          BujjiTourDemos.map,
          'tour.attach',
          'Tap + and pick Location to send a spot, share live or check in.',
        ),
        VibeTourItem(
          Icons.share_location_outlined,
          'Live, or a check-in',
          "Share live for 15 minutes, 1 hour or 8 hours, or check in. I tell you when they're close, when they arrive, or if a check-in is missed.",
          null,
          BujjiTourDemos.live,
        ),
        VibeTourItem(
          Icons.map_outlined,
          'Everyone on one map',
          "Everyone sharing in a chat, with the time each has left, the way they're heading and their trail.",
        ),
        VibeTourItem(
          Icons.notifications_outlined,
          'Stop from anywhere',
          "A bar on the home screen shows when you're sharing, and the notification has Stop and +30 min.",
        ),
      ],
    ),
    VibeTourPage(
      Icons.chat_bubble_rounded,
      'Chats',
      "Bubbles curve round the sender's picture, and a new message grows out of their typing dots.",
      short: 'Hold and slide, threads by the name',
      [
        VibeTourItem(
          Icons.swipe_rounded,
          'Hold and slide',
          'Hold a message and, without lifting, slide onto an action or a reaction. Let go to pick it.',
          null,
          BujjiTourDemos.slide,
        ),
        VibeTourItem(
          VibeThreads.icon,
          'Threads beside the name',
          "Every thread in the chat is one tap away, right beside its name. Close any of them with its X.",
          null,
          BujjiTourDemos.threads,
          'tour.threads',
          "Every thread in this chat is behind this button. Once a chat has a thread, it sits right beside the chat's name.",
        ),
        VibeTourItem(
          Icons.poll_outlined,
          'Polls and View once',
          'Ask with a poll, or send a photo that can be opened only once.',
        ),
        VibeTourItem(
          Icons.mail_outline_rounded,
          'Invites',
          'See who invited you, with Accept and Decline right there.',
        ),
      ],
    ),
    VibeTourPage(
      Icons.home_rounded,
      'Home',
      'Everything on one screen.',
      short: 'Filters, and unread as cards',
      [
        VibeTourItem(
          Icons.dashboard_outlined,
          'Filters, and unread as cards',
          'A big Chats title with All, Unread, Groups, Direct and Spaces under it, your profile behind the three dots, and unread chats as cards you can answer right there.',
          null,
          BujjiTourDemos.home,
          'tour.profile',
          'Your profile is behind these three dots. Unread chats show below as cards you can answer right there.',
        ),
      ],
    ),
    VibeTourPage(
      Icons.shield_rounded,
      'Security',
      'Direct chats between Keepr users get an extra post-quantum layer.',
      short: 'Post-quantum direct chats',
      [
        VibeTourItem(
          Icons.enhanced_encryption_outlined,
          'Post-quantum direct chats',
          'ML-KEM-768 (libcrux, formally verified) inside the normal encryption. Look for the lock beside the name.',
          null,
          BujjiTourDemos.pq,
          'tour.pill',
          "A lock beside the chat's name means its new messages get the post-quantum layer.",
        ),
        VibeTourItem(
          Icons.key_rounded,
          'A fresh key for every message',
          'With strict encryption, every message gets its own new key.',
        ),
        VibeTourItem(
          Icons.login_rounded,
          "Your server's own sign-in",
          "Sign in through your server's page; your sign-in and keys stay in the phone's secure storage.",
        ),
      ],
    ),
  ],
);

/// The update tour, told the Keepr way: a little server called "What's new"
/// with a channel per area. In each channel Keepr posts the news as
/// messages (typing first, like a person), each with a live mockup. Quick
/// replies sit where the text box would be.
class VibeTour extends StatefulWidget {
  /// The channels to show (indexes into [vibeTour]); all when null.
  final List<int>? only;

  /// Back from "Show me where": straight to this channel (an index into
  /// [vibeTour]), its messages all there, without the hello.
  final int? start;
  const VibeTour({this.only, this.start, super.key});

  static String _seenKey(String channel) =>
      'chat.keepr.tour_ch.${vibeTour.id}.$channel';

  /// Channels of this tour not seen yet.
  static List<int> unseen() => [
    for (final (i, c) in vibeTour.channels.indexed)
      if (AppSettings.store.getBool(_seenKey(c)) != true) i,
  ];

  static Future<void> markSeen(List<int> channels) async {
    for (final i in channels) {
      await AppSettings.store.setBool(_seenKey(vibeTour.channels[i]), true);
    }
  }

  static Future<void> open(
    BuildContext context, {
    List<int>? only,
    int? start,
  }) => Navigator.of(context, rootNavigator: true).push(
        PageRouteBuilder<void>(
          transitionDuration: const Duration(milliseconds: 380),
          pageBuilder: (_, _, _) => VibeTour(only: only, start: start),
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
  int _ch = 0;

  /// How many of each channel's messages are posted so far (the first one
  /// is the channel's intro line).
  /// The channels shown, in order (indexes into [vibeTour]).
  late final List<int> _ids = widget.only == null || widget.only!.isEmpty
      ? [for (var i = 0; i < vibeTour.pages.length; i++) i]
      : widget.only!;
  late final List<VibeTourPage> _pages = [for (final i in _ids) vibeTour.pages[i]];
  late final List<String> _channels = [for (final i in _ids) vibeTour.channels[i]];
  late final List<int> _shown = List.filled(_pages.length, 0);
  bool _typing = false;

  /// Told by Bujji (unless it's off): it says hi first and cheers at the end.
  final bool _bujji = VibeBuddy.on;
  late bool _hello = _bujji && widget.start == null;
  bool _end = false;
  Timer? _timer;
  final _scroll = ScrollController();

  VibeTourPage get _page => _pages[_ch];
  int get _total => _page.items.length + 1;
  bool get _allShown => _shown[_ch] >= _total;
  bool get _lastChannel => _ch == _pages.length - 1;

  @override
  void initState() {
    super.initState();
    final start = widget.start;
    if (start != null) {
      // back from "Show me where": that channel, as it was
      final k = _ids.indexOf(start);
      if (k >= 0) {
        _ch = k;
        for (var i = 0; i <= k; i++) {
          _shown[i] = _pages[i].items.length + 1;
        }
      }
      return;
    }
    if (!_hello) _postNext(first: true);
  }

  void _start() {
    VibeHaptics.medium();
    setState(() => _hello = false);
    _postNext(first: true);
  }

  /// "Show me where": the real screen, with Bujji pointing at the spot.
  Future<void> _where(VibeTourItem it) async {
    final spot = it.where;
    if (spot == null) return;
    final back = _ids[_ch];
    final client = Matrix.of(context).client;
    Navigator.of(context).pop();
    if (spot == 'tour.profile') {
      VibeApp.router.go('/rooms');
    } else {
      final room = client.rooms
          .where((r) => r.membership == Membership.join && !r.isSpace)
          .firstOrNull;
      if (room != null) VibeApp.router.go('/rooms/${room.id}');
    }
    await BujjiCoach.point(
      spot,
      orSpot: spot == 'tour.threads' ? 'tour.pill' : null,
      title: it.title,
      body: it.tip ?? it.body,
      back: () {
        final ctx = VibeApp.router.routerDelegate.navigatorKey.currentContext;
        if (ctx != null && ctx.mounted) VibeTour.open(ctx, start: back);
      },
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  /// "Keepr is typing…", then the next message lands; then the one after,
  /// on its own, until the channel is done.
  void _postNext({bool first = false, bool now = false}) {
    _timer?.cancel();
    if (_allShown) return;
    setState(() => _typing = true);
    _timer = Timer(Duration(milliseconds: now ? 250 : (first ? 500 : 900)), () {
      if (!mounted) return;
      VibeHaptics.light();
      setState(() {
        _typing = false;
        _shown[_ch]++;
      });
      _toBottom();
      if (!_allShown) {
        _timer = Timer(const Duration(milliseconds: 2600), _postNext);
      }
    });
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  });

  void _open(int ch) {
    if (ch == _ch) return;
    VibeHaptics.selection();
    _timer?.cancel();
    setState(() {
      _ch = ch;
      _typing = false;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    if (_shown[ch] == 0) _postNext(first: true);
  }

  void _finish() {
    if (_bujji && !_end) {
      // Bujji cheers, with every channel ticked
      VibeHaptics.medium();
      setState(() => _end = true);
      VibeHotWords.play(context, VibeScene.party);
      return;
    }
    Navigator.of(context).pop();
    if (_end) return;
    final ctx = VibeApp.router.routerDelegate.navigatorKey.currentContext;
    if (ctx != null && ctx.mounted) VibeHotWords.play(ctx, VibeScene.party);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final shown = _shown[_ch];
    if (_hello) {
      return BujjiHello(
        version: vibeTour.version,
        channels: [
          for (final (k, p) in _pages.indexed) (p.icon, _channels[k], p.short),
        ],
        onStart: _start,
        onLater: () => Navigator.of(context).pop(),
      );
    }
    if (_end) {
      return BujjiDone(
        channels: [
          for (final (k, p) in _pages.indexed) (p.icon, _channels[k], p.short),
        ],
        onDone: () => Navigator.of(context).pop(),
      );
    }
    return PopScope(
      canPop: _ch == 0,
      onPopInvokedWithResult: (pop, _) {
        if (!pop) _open(_ch - 1);
      },
      child: Scaffold(
        backgroundColor: cs.surface,
        body: SafeArea(
          child: Column(
            children: [
              // the "server": its icon, name and version
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
                child: Row(
                  children: [
                    _bujji
                        ? const BujjiTile(size: 36)
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.asset(
                              'assets/logo/mini/logo_mini.png',
                              width: 36,
                              height: 36,
                              errorBuilder: (_, _, _) => Container(
                                width: 36,
                                height: 36,
                                color: _blurple,
                              ),
                            ),
                          ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "What's new",
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                          ),
                          Text(
                            _bujji
                                ? 'Keepr ${vibeTour.version} · with Bujji'
                                : 'Keepr ${vibeTour.version}',
                            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text('Skip', style: TextStyle(color: cs.onSurfaceVariant)),
                    ),
                  ],
                ),
              ),
              // the channels
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (final (k, name) in _channels.indexed)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: _ChannelChip(
                          name: name,
                          active: k == _ch,
                          done: _shown[k] >= _pages[k].items.length + 1,
                          onTap: () => _open(k),
                        ),
                      ),
                  ],
                ),
              ),
              Divider(height: 12, color: cs.outlineVariant.withValues(alpha: 0.5)),
              // the channel's messages
              Expanded(
                child: ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  children: [
                    _ChannelHeader(
                      name: _channels[_ch],
                      title: _page.title,
                      icon: _page.icon,
                      bujji: _bujji && _channels[_ch] == 'bujji',
                    ),
                    for (var k = 0; k < shown; k++)
                      _TourMessage(
                        key: ValueKey('$_ch-$k'),
                        first: k == 0,
                        bujji: _bujji,
                        title: k == 0 ? null : _page.items[k - 1].title,
                        body: k == 0 ? _page.subtitle : _page.items[k - 1].body,
                        demo: k == 0 ? null : _page.items[k - 1].demo,
                        show: k == 0 ? null : _page.items[k - 1].show,
                        onWhere: k == 0 || _page.items[k - 1].where == null
                            ? null
                            : () => _where(_page.items[k - 1]),
                      ),
                    if (_typing)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(52, 6, 0, 6),
                        child: Row(
                          children: [
                            // Bujji bounces on its own typing dots
                            if (_bujji) ...[
                              VibeBuddyFace(
                                size: 22,
                                color: cs.primary,
                                mood: BuddyMood.curious,
                                outfit: VibeBuddy.outfit,
                                floating: true,
                                hop: shown,
                              ),
                              const SizedBox(width: 6),
                            ],
                            const TypingAnimation(size: 6),
                            const SizedBox(width: 8),
                            Text(
                              _bujji ? 'Bujji is typing…' : 'Keepr is typing…',
                              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              // quick replies, where the text box would be
              Container(
                margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _allShown
                            ? (_lastChannel ? "That's everything" : 'Reply to keep going')
                            : '# ${_channels[_ch]}',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: _blurple,
                        foregroundColor: Colors.white,
                        shape: const StadiumBorder(),
                      ),
                      onPressed: !_allShown
                          ? () => _postNext(now: true)
                          : _lastChannel
                          ? _finish
                          : () => _open(_ch + 1),
                      child: Text(
                        !_allShown
                            ? 'Show more'
                            : _lastChannel
                            ? (_bujji ? 'Done' : 'Start chatting')
                            : '# ${_channels[_ch + 1]}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChannelChip extends StatelessWidget {
  final String name;
  final bool active;
  final bool done;
  final VoidCallback onTap;
  const _ChannelChip({
    required this.name,
    required this.active,
    required this.done,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: active ? _blurple : cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '#',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: active ? Colors.white70 : cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                name,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: active ? Colors.white : cs.onSurface,
                ),
              ),
              if (done && !active) ...[
                const SizedBox(width: 4),
                Icon(Icons.check, size: 14, color: cs.primary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The top of a channel: "Welcome to #threads!", like a new channel.
class _ChannelHeader extends StatelessWidget {
  final String name;
  final String title;
  final IconData icon;
  final bool bujji;
  const _ChannelHeader({
    required this.name,
    required this.title,
    required this.icon,
    this.bujji = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              shape: BoxShape.circle,
            ),
            child: bujji
                ? Center(
                    child: VibeBuddyFace(
                      size: 38,
                      color: cs.primary,
                      mood: BuddyMood.happy,
                      outfit: VibeBuddy.outfit,
                    ),
                  )
                : Icon(icon, size: 28, color: _blurple),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, height: 1.15),
          ),
          const SizedBox(height: 2),
          Text(
            'This is the start of #$name.',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// One message from Keepr: the picture, "Keepr  NEW  now", the text and,
/// for a feature, its live mockup. Slides in like a new message.
class _TourMessage extends StatefulWidget {
  final bool first;
  final bool bujji;
  final String? title;
  final String body;
  final VibeDemo? demo;
  final Widget Function(BuildContext)? show;
  final VoidCallback? onWhere;
  const _TourMessage({
    required this.first,
    required this.title,
    required this.body,
    required this.demo,
    this.bujji = false,
    this.show,
    this.onWhere,
    super.key,
  });

  @override
  State<_TourMessage> createState() => _TourMessageState();
}

class _TourMessageState extends State<_TourMessage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _in = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  )..forward();

  @override
  void dispose() {
    _in.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final a = CurvedAnimation(parent: _in, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: a,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(a),
        child: Padding(
          padding: EdgeInsets.only(top: widget.first ? 4 : 2, bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 40,
                child: widget.first && widget.bujji
                    ? const BujjiTile(size: 40)
                    : widget.first
                    ? ClipOval(
                        child: Image.asset(
                          'assets/logo/mini/logo_mini.png',
                          width: 40,
                          height: 40,
                          errorBuilder: (_, _, _) => CircleAvatar(
                            radius: 20,
                            backgroundColor: _blurple,
                          ),
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.first)
                      Row(
                        children: [
                          Text(
                            widget.bujji ? 'Bujji' : 'Keepr',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: _blurple,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'NEW',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text('now', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                        ],
                      ),
                    if (widget.title != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          widget.title!,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        widget.body,
                        style: TextStyle(fontSize: 15, height: 1.4, color: cs.onSurface),
                      ),
                    ),
                    if (widget.demo != null)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainer,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
                        ),
                        child: SizedBox(
                          height: 220,
                          child: FittedBox(child: SizedBox(width: 300, child: VibeDemoView(widget.demo!))),
                        ),
                      ),
                    if (widget.show != null)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: cs.surfaceContainer,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
                        ),
                        child: FittedBox(
                          child: SizedBox(
                            width: 300,
                            height: 200,
                            child: widget.show!(context),
                          ),
                        ),
                      ),
                    if (widget.onWhere != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: ActionChip(
                          avatar: Icon(Icons.touch_app_outlined, size: 16, color: cs.onPrimaryContainer),
                          label: const Text('Show me where'),
                          labelStyle: TextStyle(fontWeight: FontWeight.w700, color: cs.onPrimaryContainer),
                          backgroundColor: cs.primaryContainer,
                          side: BorderSide.none,
                          shape: const StadiumBorder(),
                          onPressed: widget.onWhere,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

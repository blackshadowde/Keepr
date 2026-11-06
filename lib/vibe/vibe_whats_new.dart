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
                  const SizedBox(height: 14),
                  Center(
                    child: TextButton.icon(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        VibeTour.open(context);
                      },
                      icon: const Icon(Icons.play_circle_outline_rounded),
                      label: const Text('Watch the tour'),
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
  const VibeTourItem(this.icon, this.title, this.body, [this.demo]);
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
  // one channel per page, like a server in Keepr
  channels: <String>[
    'welcome', 'threads', 'chatting', 'make-it-yours', 'notifications',
    'privacy', 'themes-and-text', 'home',
  ],
  pages: <VibeTourPage>[
    VibeTourPage(
      Icons.lock_rounded,
      'Vibe is now Keepr',
      'A new name and a new icon. Same account, same chats, same encryption.',
      [
        VibeTourItem(Icons.badge_outlined, 'A new name',
            'Vibe is now Keepr everywhere: the app, the website and the store.', VibeDemo.rename),
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
            'Long-press a message, then Create thread.', VibeDemo.threadCreate),
        VibeTourItem(Icons.edit_outlined, 'Give it a name',
            'Tap the thread\'s name to rename it. Without a name, it\'s called after its first message.', VibeDemo.threadRename),
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
            'Open another chat from the top pill, or pull a chat\'s name down, and it waits under the text box. Swipe it up to go back.', VibeDemo.dock),
        VibeTourItem(Icons.search_rounded, 'Search in a chat',
            'Results as you type, with arrows to step through every match.', VibeDemo.search),
        VibeTourItem(Icons.format_quote_rounded, 'Quote part of a message',
            'Swipe to reply and hold a moment to pick the words you want.', VibeDemo.quote),
        VibeTourItem(Icons.photo_library_outlined, 'Photo stacks',
            'Four or more photos sent together show as one grid.', VibeDemo.stack),
        VibeTourItem(Icons.touch_app_outlined, 'Double tap, your way',
            'React, reply, quote, bookmark or copy: you choose.', VibeDemo.doubleTap),
      ],
    ),
    VibeTourPage(
      Icons.palette_rounded,
      'Make it yours',
      'Customisation has more to play with.',
      [
        VibeTourItem(Icons.more_horiz_rounded, 'Your own typing indicator',
            'Up to three emojis, an animation and a phrase others see while you type.', VibeDemo.typing),
        VibeTourItem(Icons.music_note_outlined, 'Notification sounds',
            'Keepr chime, Pop, Bell or Pluck, each with a play button.', VibeDemo.sounds),
        VibeTourItem(Icons.thunderstorm_outlined, 'Weather on screen',
            'Rain, sunny day or winter words fill the screen with their own scene.', VibeDemo.weather),
        VibeTourItem(Icons.gif_box_outlined, 'Animated profile pictures',
            'GIF profile pictures play in profiles and chat details.', VibeDemo.avatar),
      ],
    ),
    VibeTourPage(
      Icons.notifications_active_rounded,
      'Notifications',
      'Messages arrive, and read ones tidy themselves up.',
      [
        VibeTourItem(Icons.refresh_rounded, 'Back on its own',
            'If the phone stops Keepr in the background, it starts again within 15 minutes.', VibeDemo.restart),
        VibeTourItem(Icons.done_all_rounded, 'Read here, cleared there',
            'Reading a chat on another device clears its notification.', VibeDemo.clearRead),
        VibeTourItem(Icons.error_outline_rounded, 'Know when a message fails',
            'A notification tells you if a message couldn\'t be sent.', VibeDemo.failed),
        VibeTourItem(Icons.mic_none_rounded, 'Voice messages everywhere',
            'Voice messages recorded on Android now play on every phone.', VibeDemo.voice),
      ],
    ),
    VibeTourPage(
      Icons.key_rounded,
      'Privacy',
      'Direct chats change their key even more often.',
      [
        VibeTourItem(Icons.key_rounded, 'A fresh key every 3 messages',
            'With strict encryption, direct chats get a new key every 3 messages or 5 minutes. Groups keep every 10 messages or an hour.', VibeDemo.dmKeys),
        VibeTourItem(Icons.translate_rounded, 'Keepr in every language',
            'Every translation now says Keepr, and invites point to Keepr\'s website.'),
      ],
    ),
    VibeTourPage(
      Icons.format_paint_rounded,
      'Themes and text',
      'More looks, and text that\'s easier to read.',
      [
        VibeTourItem(Icons.download_rounded, 'Import HyDE themes',
            'In the Glass look, import any theme from HyDE\'s gallery or from a GitHub link, with its colours and wallpapers.', VibeDemo.hydeImport),
        VibeTourItem(Icons.label_outline_rounded, 'Your name in a pill',
            'Show your name in a coloured pill in chats, like a group tag. Set it in your status.', VibeDemo.namePill),
        VibeTourItem(Icons.text_fields_rounded, 'Bigger, clearer text',
            'Names, channels, titles and settings are bigger and bolder; names in chats match your text size.', VibeDemo.textScale),
        VibeTourItem(Icons.gif_box_outlined, 'Animated pictures from your profile',
            'GIFs picked from your profile\'s Photo button stay animated too.', VibeDemo.avatar),
      ],
    ),
    VibeTourPage(
      Icons.home_rounded,
      'Home',
      'Opening Keepr feels livelier, and muted chats stay quiet.',
      [
        VibeTourItem(Icons.animation_rounded, 'Chats bounce in',
            'After the dots, your chats spring in one by one. Turn it off in Customisation, Start-up animation.', VibeDemo.homeBounce),
        VibeTourItem(Icons.notifications_off_outlined, 'Muted means quiet',
            'Muted chats no longer show pop-ups or side pictures. Want them anyway? Notifications, Pop-ups for muted chats.', VibeDemo.mutedQuiet),
        VibeTourItem(Icons.more_horiz_rounded, 'Your typing indicator, everywhere',
            'It now reaches direct chats started after you set it.', VibeDemo.typing),
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
  const VibeTour({this.only, super.key});

  static String _seenKey(String channel) => 'chat.keepr.tour_ch.$channel';

  /// Channels of this tour not seen yet. Someone who watched the first
  /// version of the tour (one flag for all of it) has seen its 5 channels.
  static List<int> unseen() {
    final old = AppSettings.store.getBool('chat.keepr.tour_seen.3.1-keepr') == true;
    return [
      for (final (i, c) in vibeTour.channels.indexed)
        if (AppSettings.store.getBool(_seenKey(c)) != true && !(old && i < 5)) i,
    ];
  }

  static Future<void> markSeen(List<int> channels) async {
    for (final i in channels) {
      await AppSettings.store.setBool(_seenKey(vibeTour.channels[i]), true);
    }
  }

  static Future<void> open(BuildContext context, {List<int>? only}) =>
      Navigator.of(context, rootNavigator: true).push(
        PageRouteBuilder<void>(
          transitionDuration: const Duration(milliseconds: 380),
          pageBuilder: (_, _, _) => VibeTour(only: only),
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
  Timer? _timer;
  final _scroll = ScrollController();

  VibeTourPage get _page => _pages[_ch];
  int get _total => _page.items.length + 1;
  bool get _allShown => _shown[_ch] >= _total;
  bool get _lastChannel => _ch == _pages.length - 1;

  @override
  void initState() {
    super.initState();
    _postNext(first: true);
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
    Navigator.of(context).pop();
    final ctx = VibeApp.router.routerDelegate.navigatorKey.currentContext;
    if (ctx != null && ctx.mounted) VibeHotWords.play(ctx, VibeScene.party);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final shown = _shown[_ch];
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
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.asset(
                        'assets/logo/mini/logo_mini.png',
                        width: 36,
                        height: 36,
                        errorBuilder: (_, _, _) =>
                            Container(width: 36, height: 36, color: _blurple),
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
                            'Keepr ${vibeTour.version}',
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
                    ),
                    for (var k = 0; k < shown; k++)
                      _TourMessage(
                        key: ValueKey('$_ch-$k'),
                        first: k == 0,
                        title: k == 0 ? null : _page.items[k - 1].title,
                        body: k == 0 ? _page.subtitle : _page.items[k - 1].body,
                        demo: k == 0 ? null : _page.items[k - 1].demo,
                      ),
                    if (_typing)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(52, 6, 0, 6),
                        child: Row(
                          children: [
                            const TypingAnimation(size: 6),
                            const SizedBox(width: 8),
                            Text(
                              'Keepr is typing…',
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
                            ? 'Start chatting'
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
  const _ChannelHeader({required this.name, required this.title, required this.icon});

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
            child: Icon(icon, size: 28, color: _blurple),
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
  final String? title;
  final String body;
  final VibeDemo? demo;
  const _TourMessage({
    required this.first,
    required this.title,
    required this.body,
    required this.demo,
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
                child: widget.first
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
                          const Text('Keepr', style: TextStyle(fontWeight: FontWeight.w800)),
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

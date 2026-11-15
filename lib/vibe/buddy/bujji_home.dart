// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:vibe/vibe/buddy/bujji.dart';
import 'package:vibe/vibe/buddy/bujji_live.dart';
import 'package:vibe/vibe/vibe_live_location.dart';
import 'package:vibe/vibe/buddy/vibe_buddy.dart';
import 'package:vibe/vibe/vibe_haptics.dart';

/// Bujji on the home screen, next to Chats and Spaces. Its face follows
/// your inbox and the clock: happy when you're all caught up, looking at
/// the unread cards when there are some, tired at bedtime, asleep after
/// midnight (tap to wake it), and it hops when you clear the last unread
/// chat. Tap opens its notes and reminders; hold to tell it something
/// right here.
class BujjiHome extends StatefulWidget {
  final int unread;
  const BujjiHome({required this.unread, super.key});

  @override
  State<BujjiHome> createState() => _BujjiHomeState();
}

class _BujjiHomeState extends State<BujjiHome> {
  int _wiggle = 0;
  DateTime? _woken;
  int _squish = 0;

  @override
  void initState() {
    super.initState();
    Bujji.load();
  }

  @override
  void didUpdateWidget(BujjiHome old) {
    super.didUpdateWidget(old);
    // all caught up
    if (old.unread > 0 && widget.unread == 0) _wiggle++;
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: VibeBuddy.changed,
    builder: (context, _, _) {
      if (!VibeBuddy.on) return const SizedBox.shrink();
      final cs = Theme.of(context).colorScheme;
      final awake =
          _woken != null && DateTime.now().difference(_woken!).inMinutes < 2;
      final mood = VibeBuddy.night && !awake
          ? BuddyMood.sleepy
          : VibeBuddy.bedtime
          ? BuddyMood.tired
          : widget.unread == 0
          ? BuddyMood.happy
          : BuddyMood.idle;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _squish++),
        onTap: () {
          VibeHaptics.light();
          if (mood == BuddyMood.sleepy) {
            setState(() {
              _woken = DateTime.now();
              _wiggle++;
            });
            return;
          }
          BujjiChatPage.open(context);
        },
        onLongPress: () {
          VibeHaptics.medium();
          BujjiQuick.show(context);
        },
        child: Tooltip(
          message: VibeBuddy.name,
          child: VibeBuddyFace(
            size: 34,
            color: cs.primary,
            mood: mood,
            outfit: VibeBuddy.outfit,
            // peeks down at the unread cards
            gaze: widget.unread > 0 ? -0.8 : 0,
            look: widget.unread > 0 ? 0.7 : 0,
            floating: true,
            wiggle: _wiggle,
            squish: _squish,
          ),
        ),
      );
    },
  );
}

/// Under Chats and Spaces: what Bujji has for today (birthdays, reminders
/// still to come), or a birthday in the next few days. Tap for the list.
class BujjiToday extends StatelessWidget {
  const BujjiToday({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([Bujji.changed, BujjiLive.sharing]),
    builder: (context, _) {
      if (!VibeBuddy.on) return const SizedBox.shrink();
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [_live(context), _reminders(context)],
      );
    },
  );

  /// Someone sharing their live location with you: who, and for how long.
  Widget _live(BuildContext context) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final on = BujjiLive.sharing.value.where((s) => s.until > now).toList();
    if (on.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final s = on.first;
    final more = on.length > 1 ? '  +${on.length - 1}' : '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      child: Material(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => context.go('/rooms/${s.roomId}'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                const VibeLiveDot(),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${s.name} is sharing live · ${VibeLive.left(s.until)} left$more',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: cs.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _reminders(BuildContext context) {
      final now = DateTime.now();
      final items = Bujji.today()
          .where((r) => r.yearly || r.next.isAfter(now))
          .toList();
      final soon = Bujji.soon();
      if (items.isEmpty && soon.isEmpty) return const SizedBox.shrink();
      final cs = Theme.of(context).colorScheme;
      final today = items.isNotEmpty;
      final first = today ? items.first : soon.first;
      final n = today ? items.length : soon.length;
      final more = n > 1 ? '  +${n - 1}' : '';
      final text = today
          ? 'Today: ${Bujji.cap(first.yearly ? first.text : '${DateFormat.jm().format(first.next)} · ${first.text}')}'
          : '${Bujji.cap(first.text.replaceFirst(RegExp(r' today$'), ''))} · ${BujjiQuick.inDays(first.next)}';
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
        child: Material(
          color: today ? cs.secondaryContainer : cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => BujjiChatPage.open(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    first.yearly ? Icons.cake_outlined : Icons.alarm_rounded,
                    size: 18,
                    color: cs.onSecondaryContainer,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '$text$more',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: cs.onSecondaryContainer,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: cs.onSecondaryContainer,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
  }
}

/// Hold Bujji on the home screen: tell it something or ask it, without
/// opening its chat.
class BujjiQuick extends StatefulWidget {
  const BujjiQuick({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => const BujjiQuick(),
  );

  /// "tomorrow", "Friday", "in 9 days".
  static String inDays(DateTime d) {
    final now = DateTime.now();
    final n = DateTime(d.year, d.month, d.day)
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
    if (n == 1) return 'tomorrow';
    if (n > 1 && n < 7) return DateFormat.EEEE().format(d);
    return 'in $n days';
  }

  @override
  State<BujjiQuick> createState() => _BujjiQuickState();
}

class _BujjiQuickState extends State<BujjiQuick> {
  final _text = TextEditingController();
  BujjiReply? _reply;
  bool _busy = false;
  int _hop = 0;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  String get _hello {
    final h = DateTime.now().hour;
    if (h < 5) return 'Up late?';
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    if (h < 22) return 'Good evening';
    return 'Good night';
  }

  String get _summary {
    final now = DateTime.now();
    final left = Bujji.today().where((r) => !r.yearly && r.next.isAfter(now)).length;
    final days = [
      ...Bujji.today().where((r) => r.yearly),
      ...Bujji.soon(),
    ];
    final parts = [
      if (left > 0) '$left reminder${left == 1 ? '' : 's'} left today',
      if (days.isNotEmpty)
        '${Bujji.cap(days.first.text.replaceFirst(RegExp(r' today$'), ''))} '
            '${days.first.next.day == now.day && days.first.next.month == now.month ? 'today' : BujjiQuick.inDays(days.first.next)}',
    ];
    return parts.isEmpty ? 'Nothing planned today' : parts.join(' · ');
  }

  void _openChat() {
    final root = Navigator.of(context, rootNavigator: true);
    Navigator.of(context).pop();
    root.push(MaterialPageRoute(builder: (_) => const BujjiChatPage()));
  }

  Future<void> _go(Future<BujjiReply> f) async {
    setState(() => _busy = true);
    final r = await f;
    if (!mounted) return;
    if (r.openChat) {
      _openChat();
      return;
    }
    // it's opening a page: the sheet makes way
    if (r.act != null) {
      Navigator.of(context).pop();
      r.act!();
      return;
    }
    VibeHaptics.light();
    setState(() {
      _reply = r;
      _busy = false;
      _hop++;
    });
  }

  void _send() {
    final t = _text.text.trim();
    if (t.isEmpty || _busy) return;
    _text.clear();
    _go(Bujji.handle(Bujji.forBujji(t) ?? t));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final reply = _reply;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              VibeBuddyFace(
                size: 48,
                color: cs.primary,
                mood: BuddyMood.happy,
                outfit: VibeBuddy.outfit,
                hop: _hop,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_hello, style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    Text(
                      _summary,
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Notes and reminders',
                icon: const Icon(Icons.sticky_note_2_outlined),
                onPressed: _openChat,
              ),
            ],
          ),
          if (reply != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              decoration: BoxDecoration(
                color: cs.secondaryContainer,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                  bottomRight: Radius.circular(18),
                ),
              ),
              child: Text(
                reply.text,
                style: TextStyle(fontSize: 15, height: 1.35, color: cs.onSecondaryContainer),
              ),
            ),
            if (reply.choices.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(
                  spacing: 6,
                  children: [
                    for (final c in reply.choices)
                      ActionChip(
                        label: Text(c.label),
                        onPressed: _busy ? null : () => _go(Bujji.choose(c)),
                      ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 14),
          TextField(
            controller: _text,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _send(),
            decoration: InputDecoration(
              hintText: 'Tell ${VibeBuddy.name} something…',
              filled: true,
              fillColor: cs.surfaceContainerHigh,
              contentPadding: const EdgeInsets.fromLTRB(18, 12, 6, 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
              suffixIcon: IconButton(
                icon: const Icon(Icons.send_rounded),
                color: cs.primary,
                onPressed: _send,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

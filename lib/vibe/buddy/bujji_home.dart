// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vibe/vibe/buddy/bujji.dart';
import 'package:vibe/vibe/buddy/vibe_buddy.dart';
import 'package:vibe/vibe/vibe_haptics.dart';

/// Bujji on the home screen, next to Chats and Spaces. Its face follows
/// your inbox and the clock: happy when you're all caught up, looking at
/// the unread cards when there are some, tired at bedtime, asleep after
/// midnight (tap to wake it). Tap opens its notes and reminders.
class BujjiHome extends StatefulWidget {
  final int unread;
  const BujjiHome({required this.unread, super.key});

  @override
  State<BujjiHome> createState() => _BujjiHomeState();
}

class _BujjiHomeState extends State<BujjiHome> {
  int _wiggle = 0;
  DateTime? _woken;

  @override
  void initState() {
    super.initState();
    Bujji.load();
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
          BujjiChatPage.open(context);
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
            wiggle: _wiggle,
          ),
        ),
      );
    },
  );
}

/// Under Chats and Spaces: what Bujji has for today (birthdays,
/// reminders). Tap for the full list.
class BujjiToday extends StatelessWidget {
  const BujjiToday({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: Bujji.changed,
    builder: (context, _, _) {
      if (!VibeBuddy.on) return const SizedBox.shrink();
      final items = Bujji.today();
      if (items.isEmpty) return const SizedBox.shrink();
      final cs = Theme.of(context).colorScheme;
      final first = items.first;
      final more = items.length > 1 ? '  +${items.length - 1}' : '';
      final text = first.yearly
          ? first.text
          : '${DateFormat.jm().format(first.next)} · ${first.text}';
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
        child: Material(
          color: cs.secondaryContainer,
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
                      'Today: ${text[0].toUpperCase()}${text.substring(1)}$more',
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
    },
  );
}

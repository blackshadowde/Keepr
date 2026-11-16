// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:vibe/vibe/buddy/vibe_buddy.dart';
import 'dart:math' as math;

import 'package:vibe/vibe/screens/chat/chat.dart';
import 'package:vibe/widgets/avatar.dart';
import 'package:vibe/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:vibe/vibe/vibe_typing_style.dart';
import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';
import 'package:vibe/utils/matrix_sdk_extensions/filtered_timeline_extension.dart';
import 'package:vibe/utils/string_color.dart';
import 'package:vibe/vibe/vibe_message.dart';
import 'package:vibe/vibe/vibe_text_size.dart';
import 'package:vibe/vibe/buddy/bujji_life.dart';

/// Typing indicator at the bottom of the timeline, like their messages:
/// their picture where their next message will be, and a small card curving
/// round it with three dots in their colour (their name on top in groups).
/// When they sent the newest message, the dots join the bottom of its card
/// instead. Several people: the others small in the card. Their own typing
/// style or typing buddy shows in the card instead of the dots.
class TypingIndicators extends StatelessWidget {
  final ChatController controller;
  const TypingIndicators(this.controller, {super.key});

  static const _duration = Duration(milliseconds: 200);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Object>(
      stream: controller.room.client.onSync.stream.where(
        (syncUpdate) =>
            syncUpdate.rooms?.join?[controller.room.id]?.ephemeral?.any(
              (ephemeral) => ephemeral.type == 'm.typing',
            ) ??
            false,
      ),
      builder: (context, _) {
        final me = Matrix.of(context).client.userID;
        // a message just came from someone typing: it grows out of their
        // picture, so the dots go at once here
        final newest = controller.timeline?.events.firstOrNull;
        final arrived =
            newest != null &&
            newest.senderId != me &&
            DateTime.now().difference(newest.originServerTs).inSeconds.abs() <
                4;
        final typingUsers = controller.room.typingUsers
            .where(
              (u) =>
                  u.stateKey != me && !(arrived && newest.senderId == u.id),
            )
            .toList();
        final typing = typingUsers.isNotEmpty;
        final duration = !typing && arrived ? Duration.zero : _duration;
        // the newest message shown, if its sender is the one writing on
        final timeline = controller.timeline;
        final shown = timeline?.events.firstWhereOrNull(
          (e) =>
              e.isVisibleInGui &&
              e.relationshipType != RelationshipTypes.thread,
        );
        final joins =
            typingUsers.length == 1 &&
            controller.activeThreadId == null &&
            timeline != null &&
            shown != null &&
            shown.senderId == typingUsers.single.id &&
            VibeCards.inCard(shown, timeline);
        final id = joins ? shown.eventId : null;
        if (VibeCards.continuing.value != id) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => VibeCards.continuing.value = id,
          );
        }
        return AnimatedSize(
          duration: duration,
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: AnimatedOpacity(
            duration: duration,
            opacity: typing ? 1 : 0,
            child: AnimatedSlide(
              duration: duration,
              curve: Curves.easeOut,
              offset: typing ? Offset.zero : const Offset(0, 0.25),
              child: !typing
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: EdgeInsets.fromLTRB(12, joins ? 0 : 6, 12, 4),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        // Bujji hurries over here when they start typing
                        child: BujjiSpot(
                          id: 'typing',
                          child: _TypingCard(
                            room: controller.room,
                            users: typingUsers,
                            joins: joins
                                ? (
                                    card: VibeCards.width(
                                      VibeCards.keyOf(shown, timeline),
                                    ),
                                    time: shown.originServerTs,
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }
}

/// Their picture and the small card round it: dots in their colour, their
/// typing style or their buddy; [joins] continues the card of the newest
/// message (square top, a hairline, its time).
class _TypingCard extends StatelessWidget {
  final Room room;
  final List<User> users;
  final ({ValueNotifier<double> card, DateTime time})? joins;
  const _TypingCard({required this.room, required this.users, this.joins});

  static const _pic = 30.0, _gap = 3.0, _reach = _pic / 2 + _gap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final who = users.first;
    final name = who.calcDisplayname();
    final tint = dark
        ? name.colorScheme.primaryContainer
        : name.colorScheme.primary;
    // the same card colour as their messages
    final under = dark ? const Color(0xFF1B1B1F) : const Color(0xFFF1F1F4);
    final color = Color.alphaBlend(cs.surfaceContainerHigh, under);
    final meta = cs.onSurface.withValues(alpha: 0.62);
    // their own typing indicator (Settings > Customisation), or their
    // typing buddy, if they have one showing
    final style = users.length == 1 ? VibeTypingStyle.of(room, who.id) : null;
    final buddy = users.length == 1 ? VibeBuddy.of(room, who.id) : null;
    final others = users.skip(1).take(2).toList();
    final names = switch (users.length) {
      1 => name,
      2 => '$name and ${users[1].calcDisplayname()}',
      3 => '$name, ${users[1].calcDisplayname()} and ${users[2].calcDisplayname()}',
      _ => '$name, ${users[1].calcDisplayname()} and ${users.length - 2} more',
    };
    final Widget inside = buddy != null
        ? VibeBuddyFace(
            size: 24,
            color: buddy.color,
            outfit: buddy.outfit,
            mood: BuddyMood.happy,
          )
        : style != null
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (style.emojis.isNotEmpty)
                VibeTypingEmojis(style)
              else
                VibeTypingDots(color: tint, scale: 1.4),
              if (style.text.isNotEmpty)
                Text(
                  style.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: meta),
                ),
            ],
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // the others, small, before the dots
              for (final (i, u) in others.indexed)
                Transform.translate(
                  offset: Offset(-6.0 * i, 0),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: color, width: 2),
                    ),
                    child: Avatar(
                      mxContent: u.avatarUrl,
                      name: u.calcDisplayname(),
                      size: 20,
                    ),
                  ),
                ),
              if (others.isNotEmpty) SizedBox(width: 8 - 6.0 * others.length + 6),
              VibeTypingDots(color: tint, scale: 1.4),
            ],
          );
    final j = joins;
    Widget cardOf(double cardW) {
      final boxMin = math.max(0.0, cardW - _reach);
      return ConstrainedBox(
        constraints: BoxConstraints(minWidth: boxMin),
        child: CustomPaint(
          painter: VibeBubblePainter(
            color: color,
            left: true,
            top: j == null ? 20 : 0,
            bottom: 20,
            farTop: j == null ? 20 : 0,
            farBottom: 20,
            reach: _reach,
            cut: true,
            line: j == null ? null : cs.onSurface.withValues(alpha: 0.12),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // groups: who it is, on top
                if (j == null && !room.isDirectChat)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      names,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: VibeTextSize.message * 0.84,
                        height: 1.3,
                        color: tint,
                      ),
                    ),
                  ),
                if (j == null)
                  inside
                else
                  // still the time of their newest message, at the edge
                  VibeTimeFlow(
                    minWidth: math.max(0.0, boxMin - 28),
                    content: inside,
                    trailing: Text(
                      vibeTime(j.time),
                      style: TextStyle(fontSize: 11, height: 1.2, color: meta),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Avatar(mxContent: who.avatarUrl, name: name, size: _pic),
        const SizedBox(width: _gap),
        Flexible(
          child: j == null
              ? cardOf(0)
              : ValueListenableBuilder<double>(
                  valueListenable: j.card,
                  builder: (context, w, _) => cardOf(w),
                ),
        ),
      ],
    );
  }
}

/// Three dots bouncing one after another (1.2 s cycle), like Vibgram.
class VibeTypingDots extends StatefulWidget {
  /// Their colour; black or white when not given.
  final Color? color;
  final double scale;
  const VibeTypingDots({this.color, this.scale = 1, super.key});

  @override
  State<VibeTypingDots> createState() => _VibeTypingDotsState();
}

class _VibeTypingDotsState extends State<VibeTypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final k = widget.scale;
    return CustomPaint(
      size: Size(18 * k, 14 * k),
      painter: _DotsPainter(
        _ctrl,
        widget.color ??
            (dark ? const Color(0xFFFFFFFF) : const Color(0xFF000000)),
        k,
      ),
    );
  }
}

class _DotsPainter extends CustomPainter {
  final Animation<double> progress;
  final Color color;
  final double scale;

  _DotsPainter(this.progress, this.color, [this.scale = 1])
    : super(repaint: progress);

  @override
  void paint(Canvas canvas, Size size) {
    final r = 2.2 * scale;
    final paint = Paint()..isAntiAlias = true;
    final cy = size.height / 2 + 1.5 * scale;
    for (var i = 0; i < 3; i++) {
      final phase = progress.value * math.pi * 2 - i * 0.7;
      final bounce = math.max(0.0, math.sin(phase));
      paint.color = color.withAlpha((150 + 105 * bounce).round());
      canvas.drawCircle(
        Offset(r + i * 6.8 * scale, cy - bounce * 3 * scale),
        r,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DotsPainter old) =>
      old.color != color || old.scale != scale;
}

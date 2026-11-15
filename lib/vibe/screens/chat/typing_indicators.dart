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

/// Typing indicator at the bottom of the timeline, like Vibgram: a small
/// round picture of who is typing and three bouncing dots, no bubble.
/// Dots are white in dark mode and black in light mode. Fades and slides
/// up into place, and makes room so it never sits on the last message.
class TypingIndicators extends StatelessWidget {
  final ChatController controller;
  const TypingIndicators(this.controller, {super.key});

  static const _duration = Duration(milliseconds: 180);

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
        // a message just came from someone typing: their dots become the
        // message's picture (see VibeTypingMorph), so they go at once here
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
        final who = typing ? typingUsers.first : null;
        // their own typing indicator (Settings > Customisation), if any
        final style = who == null
            ? null
            : VibeTypingStyle.of(controller.room, who.id);
        // their typing buddy visits, if they have one showing
        final buddy = who == null ? null : VibeBuddy.of(controller.room, who.id);

        return AnimatedContainer(
          duration: duration,
          curve: Curves.easeOut,
          height: typing ? 36 : 0,
          alignment: Alignment.centerLeft,
          clipBehavior: Clip.hardEdge,
          decoration: const BoxDecoration(),
          child: AnimatedOpacity(
            duration: duration,
            opacity: typing ? 1 : 0,
            child: AnimatedSlide(
              duration: duration,
              curve: Curves.easeOut,
              offset: typing ? Offset.zero : const Offset(0, 0.25),
              child: Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // typing: the dots sit inside a circle where their
                    // picture goes; the message grows out of it
                    if (typing && buddy != null)
                      VibeBuddyFace(
                        size: 26,
                        color: buddy.color,
                        outfit: buddy.outfit,
                        mood: BuddyMood.happy,
                      )
                    else if (typing && style == null)
                      Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: const VibeTypingDots(),
                      ),
                    if (who != null && style != null) ...[
                      Avatar(
                        size: 24,
                        mxContent: who.avatarUrl,
                        name: who.calcDisplayname(),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (style != null && who != null) ...[
                      if (style.emojis.isNotEmpty) ...[
                        VibeTypingEmojis(style),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        child: Text(
                          '${who.calcDisplayname()} ${style.text}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Three dots bouncing one after another (1.2 s cycle), like Vibgram.
class VibeTypingDots extends StatefulWidget {
  const VibeTypingDots({super.key});

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
    return CustomPaint(
      size: const Size(18, 14),
      painter: _DotsPainter(
        _ctrl,
        dark ? const Color(0xFFFFFFFF) : const Color(0xFF000000),
      ),
    );
  }
}

class _DotsPainter extends CustomPainter {
  final Animation<double> progress;
  final Color color;

  _DotsPainter(this.progress, this.color) : super(repaint: progress);

  @override
  void paint(Canvas canvas, Size size) {
    const r = 2.2;
    final paint = Paint()..isAntiAlias = true;
    final cy = size.height / 2 + 1.5;
    for (var i = 0; i < 3; i++) {
      final phase = progress.value * math.pi * 2 - i * 0.7;
      final bounce = math.max(0.0, math.sin(phase));
      paint.color = color.withAlpha((150 + 105 * bounce).round());
      canvas.drawCircle(Offset(r + i * 6.8, cy - bounce * 3), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DotsPainter old) => old.color != color;
}

// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:vibe/utils/date_time_extension.dart';
import 'package:vibe/vibe/vibe_media_viewer.dart';
import 'package:vibe/widgets/avatar.dart';
import 'package:vibe/widgets/mxc_image.dart';

/// Several photos sent at once (2 or more from one person, close together)
/// show as one stack: the first photo on top, cards tucked behind it tilted a
/// little. Tap to swipe through them. Display only: the photos are still
/// separate messages.
class VibePhotoStack extends StatelessWidget {
  /// Oldest first.
  final List<Event> events;

  /// Long-press on a photo: the message menu for that photo.
  final void Function(Event)? onLongPress;
  const VibePhotoStack(
    this.events, {
    super.key,
    this.onLongPress,
  });

  static const int minCount = 2;

  /// Is [e] a photo that can go into a stack?
  static bool fits(Event e) =>
      e.type == EventTypes.Message &&
      e.messageType == MessageTypes.Image &&
      !e.redacted &&
      e.inReplyToEventId(includingFallback: false) == null;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final last = events.last;
    final name = last.senderFromMemoryOrFallback.calcDisplayname();
    final sender = last.senderFromMemoryOrFallback;
    final own = last.senderId == last.room.client.userID;
    // your photos sit on your side, like your messages
    final dir = Directionality.of(context);
    final side = own
        ? (dir == ui.TextDirection.ltr ? ui.TextDirection.rtl : ui.TextDirection.ltr)
        : dir;
    final tilt = side == ui.TextDirection.ltr ? 1.0 : -1.0;
    const w = 240.0, h = 170.0;
    final behind = events.length > 2 ? 2 : 1;
    final radius = BorderRadius.circular(12);
    // laid out like a message: avatar on the left, name and time on top
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Row(
        textDirection: side,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Avatar(
            mxContent: sender.avatarUrl,
            name: name,
            size: 40,
            client: last.room.client,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
        crossAxisAlignment:
            own ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text.rich(
            textDirection: side,
            TextSpan(
              children: [
                TextSpan(
                  text: '$name  ',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(
                  text: '${events.length} photos · '
                      '${last.originServerTs.localizedTimeShort(context)}',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Directionality(
            textDirection: side,
            child: SizedBox(
              width: w + 14.0 * behind + 6,
              height: h + 6.0 * behind + 10,
              child: Stack(
                children: [
                  for (var k = behind; k >= 1; k--)
                    PositionedDirectional(
                      start: 14.0 * k,
                      top: 6.0 * k,
                      child: Transform.rotate(
                        angle: 0.0698 * k * tilt, // 4° per card
                        child: Container(
                          width: w,
                          height: h,
                          decoration: BoxDecoration(
                            color: k == 1
                                ? cs.surfaceContainerHighest
                                : cs.surfaceContainerHigh,
                            borderRadius: radius,
                          ),
                        ),
                      ),
                    ),
                  GestureDetector(
                    onTap: () => VibeMediaViewer.open(context, events, 0),
                    onLongPress: onLongPress == null
                        ? null
                        : () => onLongPress!(events.first),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: cs.surface,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: ClipRRect(
                        borderRadius: radius,
                        child: MxcImage(
                          event: events.first,
                          fit: BoxFit.cover,
                          width: w,
                          height: h,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
            ),
          ),
        ],
      ),
    );
  }
}

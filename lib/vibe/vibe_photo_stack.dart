// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:vibe/utils/date_time_extension.dart';
import 'package:vibe/vibe/vibe_media_viewer.dart';
import 'package:vibe/widgets/mxc_image.dart';

/// Many photos sent at once (4 or more from one person, close together) show
/// as one stack: a 2x2 grid with "+N" on the last tile. Tap to swipe through
/// them. Display only: the photos are still separate messages.
class VibePhotoStack extends StatelessWidget {
  /// Oldest first.
  final List<Event> events;

  /// Sent by me: on the right, without my name.
  final bool mine;

  /// Long-press on a photo: the message menu for that photo.
  final void Function(Event)? onLongPress;
  const VibePhotoStack(
    this.events, {
    super.key,
    this.mine = false,
    this.onLongPress,
  });

  static const int minCount = 4;

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
    final shown = events.take(4).toList();
    final more = events.length - shown.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(64, 8, 16, 6),
      child: Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                if (!mine)
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
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: GridView.count(
              crossAxisCount: 2,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (var i = 0; i < shown.length; i++)
                  GestureDetector(
                    onTap: () => VibeMediaViewer.open(context, events, i),
                    onLongPress: onLongPress == null
                        ? null
                        : () => onLongPress!(shown[i]),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          MxcImage(
                            event: shown[i],
                            fit: BoxFit.cover,
                            width: 140,
                            height: 140,
                          ),
                          if (i == 3 && more > 0)
                            Container(
                              color: Colors.black54,
                              alignment: Alignment.center,
                              child: Text(
                                '+$more',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
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

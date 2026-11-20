// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:vibe/vibe/vibe_swipe.dart';
import 'package:vibe/vibe/vibe_haptics.dart';
import 'package:vibe/utils/date_time_extension.dart';
import 'package:vibe/vibe/vibe_media_viewer.dart';
import 'package:vibe/vibe/vibe_message_orbit.dart';
import 'package:vibe/vibe/screens/chat/events/message_reactions.dart';
import 'package:vibe/widgets/avatar.dart';
import 'package:vibe/widgets/mxc_image.dart';

/// Several photos sent at once (2 or more from one person, close together)
/// show as one stack: the first photo on top, cards tucked behind it tilted a
/// little. Tap to swipe through them. Display only: the photos are still
/// separate messages.
class VibePhotoStack extends StatefulWidget {
  /// Oldest first.
  final List<Event> events;

  /// Long-press on a photo: the message menu for that photo.
  final void Function(Event)? onLongPress;

  /// For the reactions on the photos.
  final Timeline? timeline;
  const VibePhotoStack(
    this.events, {
    super.key,
    this.onLongPress,
    this.timeline,
  });

  static const int minCount = 2;

  /// Is [e] a photo that can go into a stack?
  static bool fits(Event e) =>
      e.type == EventTypes.Message &&
      e.messageType == MessageTypes.Image &&
      !e.redacted &&
      // a photo that couldn't be sent stays on its own, with Send again
      !e.status.isError &&
      e.inReplyToEventId(includingFallback: false) == null;

  @override
  State<VibePhotoStack> createState() => _VibePhotoStackState();
}

class _VibePhotoStackState extends State<VibePhotoStack> {
  /// The photo on top; swipe the stack to flip through.
  int _i = 0;
  double _dx = 0;

  /// The photo on top, for the menu round it.
  final _top = GlobalKey();

  List<Event> get events => widget.events;
  void Function(Event)? get onLongPress => widget.onLongPress;

  void _flip(int by) {
    VibeHaptics.selection();
    setState(() {
      _i = (_i + by) % events.length;
      if (_i < 0) _i += events.length;
      _dx = 0;
    });
  }

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
                  // swipe the top photo away to flip to the next (or back)
                  VibeNoBackSwipe(
                    child: GestureDetector(
                    onTap: () => VibeMediaViewer.open(context, events, _i),
                    // hold: the same menu round the photo as for a message,
                    // and slide onto an action without lifting
                    onLongPressStart: onLongPress == null
                        ? null
                        : (_) {
                            VibeHaptics.heavy();
                            final box = _top.currentContext?.findRenderObject();
                            if (box is RenderBox && box.hasSize) {
                              VibeMessageOrbit.hold(
                                box.localToGlobal(Offset.zero) & box.size,
                              );
                            }
                            onLongPress!(events[_i]);
                          },
                    onLongPressMoveUpdate: onLongPress == null
                        ? null
                        : (d) => VibeMessageOrbit.move(d.globalPosition),
                    onLongPressEnd: onLongPress == null
                        ? null
                        : (d) => VibeMessageOrbit.release(d.globalPosition),
                    onHorizontalDragUpdate: (d) =>
                        setState(() => _dx += d.delta.dx),
                    onHorizontalDragEnd: (d) {
                      final v = d.primaryVelocity ?? 0;
                      if (_dx < -50 || v < -300) {
                        _flip(1);
                      } else if (_dx > 50 || v > 300) {
                        _flip(-1);
                      } else {
                        setState(() => _dx = 0);
                      }
                    },
                    child: AnimatedSlide(
                      key: _top,
                      offset: Offset(_dx / w, 0),
                      duration: Duration(milliseconds: _dx == 0 ? 220 : 0),
                      curve: Curves.easeOutCubic,
                      child: Transform.rotate(
                        angle: _dx / w * 0.25,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 260),
                          switchInCurve: Curves.easeOutCubic,
                          transitionBuilder: (child, a) => ScaleTransition(
                            scale: Tween(begin: 0.9, end: 1.0).animate(a),
                            child: FadeTransition(opacity: a, child: child),
                          ),
                          child: Container(
                            key: ValueKey(_i),
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: cs.surface,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: radius,
                                  child: MxcImage(
                                    event: events[_i],
                                    fit: BoxFit.cover,
                                    width: w,
                                    height: h,
                                  ),
                                ),
                                // which one of how many
                                Positioned(
                                  right: 8,
                                  bottom: 8,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      '${_i + 1}/${events.length}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
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
          ..._reactions(context),
        ],
            ),
          ),
        ],
      ),
    );
  }

  /// The reactions on the photo on top, and how many the others have.
  List<Widget> _reactions(BuildContext context) {
    final timeline = widget.timeline;
    if (timeline == null) return const [];
    final top = events[_i];
    var others = 0;
    for (final (k, e) in events.indexed) {
      if (k != _i) {
        others += e.aggregatedEvents(timeline, RelationshipTypes.reaction).length;
      }
    }
    return [
      if (top.hasAggregatedEvents(timeline, RelationshipTypes.reaction))
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: MessageReactions(top, timeline),
        ),
      if (others > 0)
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(
            others == 1
                ? '1 reaction on another photo'
                : '$others reactions on the other photos',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
    ];
  }
}

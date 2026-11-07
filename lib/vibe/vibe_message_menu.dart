// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math' as math;

import 'package:vibe/vibe/vibe_event_body.dart';
import 'package:vibe/vibe/vibe_cascade.dart';
import 'package:vibe/vibe/vibe_dial.dart';
import 'package:vibe/vibe/vibe_palette.dart';
import 'package:vibe/vibe/vibe_haptics.dart';
import 'package:vibe/vibe/vibe_new_hint.dart';
import 'package:vibe/vibe/vibe_threads.dart';
import 'package:vibe/vibe/vibe_motion.dart';
import 'package:vibe/vibe/vibe_animated_emoji.dart';
import 'package:vibe/vibe/vibe_emoji_sheet.dart';
import 'package:vibe/l10n/l10n.dart';
import 'package:vibe/vibe/screens/chat/chat.dart';
import 'package:vibe/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:vibe/vibe/vibe_message.dart';
import 'package:vibe/vibe/vibe_starred.dart';
import 'package:vibe/widgets/avatar.dart';
import 'package:vibe/vibe/vibe_slash.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

const Color _red = Color(0xFFF87171);
Color get _blue => VibePalette.accent;

/// Long-press menu for a message (reactions, preview, actions).
abstract class VibeMessageMenu {
  static Future<void> show(
    BuildContext context,
    ChatController controller,
    Event event,
  ) {
    // Dial: a ring of actions round the message instead of a sheet
    if (VibeDial.on) return _Pie.show(context, controller, event);
    final cs = Theme.of(context).colorScheme;
    return showVibeSheet<void>(
      sheetAnimationStyle: vibeSheetStyle,
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: cs.surfaceContainerHigh,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      // Own layer: sliding the menu up moves a picture of it instead of
      // repainting it every frame.
      builder: (sheetContext) => RepaintBoundary(
        child: _Menu(
          controller: controller,
          event: event,
          sheetContext: sheetContext,
        ),
      ),
    );
  }
}

class _Menu extends StatelessWidget {
  final ChatController controller;
  final Event event;
  final BuildContext sheetContext;

  const _Menu({
    required this.controller,
    required this.event,
    required this.sheetContext,
  });

  void _close() => Navigator.of(sheetContext).pop();

  /// Runs a controller action that works on the current selection.
  Future<void> _withSelection(Future<void> Function() action) async {
    _close();
    controller.selectedEvents
      ..clear()
      ..add(event);
    try {
      await action();
    } finally {
      controller.selectedEvents.clear();
    }
  }

  /// Puts the message into the input box in "editing" mode.
  void _edit() {
    _close();
    final timeline = controller.timeline;
    if (timeline == null) return;
    final text = event
        .getDisplayEvent(timeline)
        .vibeBodyFallback(
          MatrixLocals(L10n.of(controller.context)),
          withSenderNamePrefix: false,
          hideReply: true,
        );
    // ignore: invalid_use_of_protected_member
    controller.setState(() {
      if (controller.editEvent == null) {
        controller.pendingText = controller.sendController.text;
      }
      controller.replyEvent = null;
      controller.replyQuote = null;
      controller.editEvent = event;
      controller.sendController.text = text;
      controller.sendController.selection = TextSelection.collapsed(
        offset: text.length,
      );
    });
    controller.inputFocus.requestFocus();
  }

  Future<void> _react(BuildContext context, String emoji) async {
    _close();
    await event.room.sendReaction(event.eventId, emoji);
  }

  Future<void> _moreEmojis(BuildContext context) async {
    final parent = controller.context;
    _close();
    if (!parent.mounted) return;
    final emoji = await VibeEmojiSheet.pick(parent);
    if (emoji != null) await event.room.sendReaction(event.eventId, emoji);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final i18n = MatrixLocals(L10n.of(context));
    final sender = event.senderFromMemoryOrFallback;
    final name = sender.calcDisplayname(i18n: i18n);
    final body = event.getDisplayEvent(controller.timeline!).body;

    // Evaluate permissions against a temporary selection.
    controller.selectedEvents
      ..clear()
      ..add(event);
    final canEdit =
        !controller.isArchived &&
        event.senderId == event.room.client.userID &&
        event.type == EventTypes.Message &&
        !event.redacted &&
        const {
          MessageTypes.Text,
          MessageTypes.Notice,
          MessageTypes.Emote,
        }.contains(event.messageType) &&
        event.status != EventStatus.error &&
        event.status != EventStatus.sending;
    final canRedact = controller.canRedactSelectedEvents;
    controller.selectedEvents.clear();

    final starred = VibeStarred.isStarred(event.room.id, event.eventId);
    final canSend = event.room.canSendDefaultMessages;
    final inner = BoxDecoration(
      color: cs.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: theme.dividerColor),
    );

    Widget item(
      IconData icon,
      String label,
      VoidCallback onTap, {
      Color? color,
      String? subtitle,
    }) => VibeRiseIn(child: InkWell(
      onTap: () {
        VibeHaptics.selection();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
        child: Row(
          children: [
            Icon(icon, size: 22, color: color ?? cs.onSurfaceVariant),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: color ?? cs.onSurface,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ));

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (canSend)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                decoration: inner,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final e in _quickEmojis.keys)
                      Material(
                        color: cs.surfaceContainerHigh,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () {
                            VibeHaptics.light();
                            _react(context, e);
                          },
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: Center(child: VibeAnimatedEmoji(e, size: 32)),
                          ),
                        ),
                      ),
                    Material(
                      color: cs.surfaceContainerHigh,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => _moreEmojis(context),
                        child: const SizedBox(
                          width: 48,
                          height: 48,
                          child: Icon(
                            Icons.sentiment_satisfied_alt_outlined,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              decoration: inner,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Icon(
                      Icons.arrow_back,
                      size: 20,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Avatar(
                    mxContent: sender.avatarUrl,
                    name: name,
                    size: 38,
                    client: event.room.client,
                    presenceUserId: sender.id,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 15),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    vibeTime(event.originServerTs),
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (canSend)
              item(Icons.reply, 'Reply', () {
                _close();
                controller.replyAction(replyTo: event);
              }),
            // start a thread from this message; it's pinned in the middle
            // pane (new: highlighted the first few times)
            if (canSend && controller.activeThreadId == null)
              VibeNewHint(
                id: 'create_thread',
                child: item(
                  VibeThreads.icon,
                  VibeThreads.isPinned(event.room.id, event.eventId)
                      ? 'Open thread'
                      : 'Create thread',
                  () {
                    _close();
                    controller.createThread(event);
                  },
                ),
              ),
            // answer just some words of a text message (new: highlighted
            // the first few times so people find it)
            if (canSend &&
                {
                  MessageTypes.Text,
                  MessageTypes.Notice,
                  MessageTypes.Emote,
                }.contains(event.messageType))
              VibeNewHint(
                id: 'quote_part',
                child: item(Icons.format_quote_rounded, 'Quote part', () {
                  _close();
                  controller.quotePartAction(event);
                }),
              ),
            if (canEdit)
              item(Icons.edit_outlined, 'Edit', _edit, color: _blue),
            item(
              Icons.shortcut,
              'Forward',
              () => _withSelection(controller.forwardEventsAction),
            ),
            item(Icons.copy_outlined, 'Copy Text', () {
              _close();
              controller.selectedEvents
                ..clear()
                ..add(event);
              controller.copyEventsAction();
              controller.selectedEvents.clear();
            }),
            item(
              starred ? Icons.bookmark : Icons.bookmark_border,
              starred ? 'Remove Bookmark' : 'Bookmark Message',
              () {
                _close();
                VibeStarred.toggle(event.room.id, event.eventId);
              },
            ),
            item(Icons.info_outline, 'Info', () {
              _close();
              controller.showEventInfo(event);
            }),
            Divider(
              height: 1,
              indent: 16,
              endIndent: 16,
              color: theme.dividerColor,
            ),
            if (canRedact)
              item(
                Icons.block,
                'Delete for Everyone',
                () => _withSelection(controller.redactEventsAction),
                color: _red,
              ),
            if (event.senderId != event.room.client.userID)
              item(
                Icons.flag_outlined,
                'Report',
                () => _withSelection(controller.reportEventAction),
                color: _red,
                subtitle: 'Sends it to your server\'s admins.',
              ),
            item(
              Icons.delete_outline,
              'Hide on this device',
              () async {
                _close();
                controller.clearSelectedEvents();
                await VibeSlash.play(controller.context, [event.eventId]);
                VibeHidden.hide(event.room.id, event.eventId);
                VibeSlash.clear([event.eventId]);
              },
              color: _red,
              subtitle: 'Other people still see it.',
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Quick reactions and their Noto Animated Emoji code (Google, CC BY 4.0).
const Map<String, String> _quickEmojis = {
  '❤️': '2764_fe0f',
  '👍': '1f44d',
  '🔥': '1f525',
  '😂': '1f602',
  '🎉': '1f389',
};

/// An animated emoji, like Vibgram's animated reactions. Loaded once from
/// Google's Noto Animated Emoji and kept in the image cache; shows the plain
/// emoji while loading, offline, or in Low data mode.


/// Dial's long-press menu: the message in a disc in the middle, its actions
/// on a ring round it (they turn into place like the dial), quick reactions
/// above. Tap outside to close.
class _Pie extends StatefulWidget {
  final ChatController controller;
  final Event event;
  const _Pie({required this.controller, required this.event});

  static Future<void> show(
    BuildContext context,
    ChatController controller,
    Event event,
  ) {
    VibeHaptics.medium();
    return showGeneralDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: Colors.black.withValues(alpha: 0.72),
      transitionDuration: const Duration(milliseconds: 420),
      pageBuilder: (ctx, anim, _) => _Pie(controller: controller, event: event),
    );
  }

  @override
  State<_Pie> createState() => _PieState();
}

class _PieAct {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;
  const _PieAct(this.icon, this.label, this.onTap, {this.danger = false});
}

class _PieState extends State<_Pie> {
  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final event = widget.event;
    // the sheet's own actions, closing this ring instead of the sheet
    final m = _Menu(controller: controller, event: event, sheetContext: context);
    final i18n = MatrixLocals(L10n.of(context));
    final name = event.senderFromMemoryOrFallback.calcDisplayname(i18n: i18n);
    final body = event.getDisplayEvent(controller.timeline!).body;
    controller.selectedEvents
      ..clear()
      ..add(event);
    final canRedact = controller.canRedactSelectedEvents;
    controller.selectedEvents.clear();
    final own = event.senderId == event.room.client.userID;
    final canEdit =
        !controller.isArchived &&
        own &&
        event.type == EventTypes.Message &&
        !event.redacted &&
        const {
          MessageTypes.Text,
          MessageTypes.Notice,
          MessageTypes.Emote,
        }.contains(event.messageType) &&
        event.status != EventStatus.error &&
        event.status != EventStatus.sending;
    final canSend = event.room.canSendDefaultMessages;
    final text = const {
      MessageTypes.Text,
      MessageTypes.Notice,
      MessageTypes.Emote,
    }.contains(event.messageType);
    final starred = VibeStarred.isStarred(event.room.id, event.eventId);
    final acts = <_PieAct>[
      if (canSend)
        _PieAct(Icons.reply, 'Reply', () {
          m._close();
          controller.replyAction(replyTo: event);
        }),
      if (canSend && controller.activeThreadId == null)
        _PieAct(VibeThreads.icon, 'Thread', () {
          m._close();
          controller.createThread(event);
        }),
      if (canSend && text)
        _PieAct(Icons.format_quote_rounded, 'Quote', () {
          m._close();
          controller.quotePartAction(event);
        }),
      if (canEdit) _PieAct(Icons.edit_outlined, 'Edit', m._edit),
      _PieAct(
        Icons.shortcut,
        'Forward',
        () => m._withSelection(controller.forwardEventsAction),
      ),
      _PieAct(Icons.copy_outlined, 'Copy', () {
        m._close();
        controller.selectedEvents
          ..clear()
          ..add(event);
        controller.copyEventsAction();
        controller.selectedEvents.clear();
      }),
      _PieAct(starred ? Icons.bookmark : Icons.bookmark_border, 'Save', () {
        m._close();
        VibeStarred.toggle(event.room.id, event.eventId);
      }),
      _PieAct(Icons.info_outline, 'Info', () {
        m._close();
        controller.showEventInfo(event);
      }),
      if (canRedact)
        _PieAct(
          Icons.block,
          'Delete',
          () => m._withSelection(controller.redactEventsAction),
          danger: true,
        ),
      if (!own)
        _PieAct(
          Icons.flag_outlined,
          'Report',
          () => m._withSelection(controller.reportEventAction),
          danger: true,
        ),
    ];
    final anim = ModalRoute.of(context)!.animation!;
    // (a Material so text gets the app's style, not the plain fallback)
    return Material(
      type: MaterialType.transparency,
      child: AnimatedBuilder(
      animation: anim,
      builder: (context, _) {
        final t = Curves.easeOutCubic.transform(anim.value);
        return LayoutBuilder(
          builder: (context, box) {
            final c = Offset(box.maxWidth / 2, box.maxHeight / 2);
            const r = 128.0;
            const s = 56.0;
            return Stack(
              children: [
                // tap anywhere else to close
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: m._close,
                  ),
                ),
                // the ring line
                Positioned(
                  left: c.dx - r,
                  top: c.dy - r,
                  child: Opacity(
                    opacity: t,
                    child: Container(
                      width: r * 2,
                      height: r * 2,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: VibeDial.faint),
                      ),
                    ),
                  ),
                ),
                // the message
                Positioned(
                  left: c.dx - 74,
                  top: c.dy - 74,
                  child: Transform.scale(
                    scale: 0.7 + 0.3 * t,
                    child: Opacity(
                      opacity: t,
                      child: Container(
                        width: 148,
                        height: 148,
                        padding: const EdgeInsets.all(18),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: VibeDial.card,
                          border: Border.all(
                            color: own ? VibeDial.lime : VibeDial.faint,
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              name.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: VibeDial.label(
                                color: own ? VibeDial.lime : VibeDial.dim,
                                size: 9,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              body,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 14,
                                color: VibeDial.ink,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // the actions turn into place round it, like the dial
                for (var i = 0; i < acts.length; i++)
                  () {
                    final deg = -90 + i * 360 / acts.length - (1 - t) * 70;
                    final a = deg * 3.141592653589793 / 180;
                    final rr = r * (0.6 + 0.4 * t);
                    final p = c + Offset(rr * math.cos(a), rr * math.sin(a));
                    final act = acts[i];
                    final color = act.danger ? _red : VibeDial.ink;
                    return Positioned(
                      left: p.dx - 36,
                      top: p.dy - s / 2,
                      width: 72,
                      child: Opacity(
                        opacity: t,
                        child: GestureDetector(
                          onTap: () {
                            VibeHaptics.selection();
                            act.onTap();
                          },
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: s,
                                height: s,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: VibeDial.bg,
                                  border: Border.all(
                                    color: act.danger
                                        ? _red.withValues(alpha: 0.6)
                                        : VibeDial.faint,
                                    width: 1.5,
                                  ),
                                ),
                                child: Icon(act.icon, color: color, size: 22),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                act.label.toUpperCase(),
                                style: VibeDial.label(
                                  color: act.danger ? _red : VibeDial.dim,
                                  size: 8.5,
                                ).copyWith(decoration: TextDecoration.none),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }(),
                // quick reactions above the ring
                if (canSend)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: c.dy - r - 96,
                    child: Opacity(
                      opacity: t,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (final e in _quickEmojis.keys)
                            GestureDetector(
                              onTap: () => m._react(context, e),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                ),
                                child: Text(
                                  e,
                                  style: const TextStyle(
                                    fontSize: 28,
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                              ),
                            ),
                          GestureDetector(
                            onTap: () => m._moreEmojis(context),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 7),
                              child: Icon(
                                Icons.add_reaction_outlined,
                                color: VibeDial.dim,
                                size: 26,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    ),
    );
  }
}

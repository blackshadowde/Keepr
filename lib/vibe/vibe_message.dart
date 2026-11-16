// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import 'package:flutter/services.dart';
import 'package:vibe/vibe/vibe_event_body.dart';
import 'package:vibe/vibe/vibe_starred.dart';
import 'package:vibe/vibe/vibe_member_tags.dart';
import 'package:vibe/vibe/vibe_palette.dart';
import 'package:vibe/vibe/vibe_quote.dart';
import 'package:vibe/vibe/vibe_entrance.dart';
import 'package:vibe/vibe/vibe_view_once.dart';
import 'package:vibe/vibe/vibe_live_location.dart';
import 'package:vibe/vibe/vibe_pq.dart';
import 'package:vibe/vibe/vibe_message_orbit.dart';
import 'package:vibe/vibe/vibe_effects.dart';
import 'package:vibe/vibe/vibe_emoji_sheet.dart';
import 'package:vibe/vibe/vibe_haptics.dart';
import 'package:collection/collection.dart';
import 'package:vibe/config/app_config.dart';
import 'package:vibe/config/setting_keys.dart';
import 'package:vibe/config/themes.dart';
import 'package:vibe/l10n/l10n.dart';
import 'package:vibe/vibe/screens/chat/events/message_content.dart';
import 'package:vibe/vibe/screens/chat/events/message_reactions.dart';
import 'package:vibe/utils/date_time_extension.dart';
import 'package:vibe/utils/matrix_sdk_extensions/filtered_timeline_extension.dart';
import 'package:vibe/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:vibe/utils/string_color.dart';
import 'package:vibe/vibe/vibe_disappearing.dart';
import 'package:vibe/vibe/vibe_heart_burst.dart';
import 'package:vibe/vibe/vibe_user_sheet.dart';
import 'package:vibe/widgets/avatar.dart';
import 'package:vibe/widgets/matrix.dart';
import 'package:vibe/vibe/vibe_stable_id.dart';
import 'package:vibe/vibe/vibe_slash.dart';
import 'package:vibe/vibe/vibe_name_style.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart';
import 'package:vibe/vibe/vibe_threads.dart';
import 'package:vibe/vibe/vibe_text_size.dart';
import 'package:vibe/vibe/vibe_swipe_reply.dart';
import 'package:vibe/vibe/vibe_chunks.dart';
import 'package:vibe/vibe/vibe_link_preview.dart';
import 'package:vibe/vibe/vibe_links.dart';
import 'package:vibe/vibe/vibe_hot_words.dart';
import 'package:vibe/vibe/buddy/bujji_life.dart';

const Color _ownNameColor = Color(0xFFB5BAC1);
const Color _otherNameColor = Color(0xFFF2F3F5);
// Light mode: dark names (the dark-mode greys/whites vanish on white).
const Color _ownNameColorLight = Color(0xFF4E5058);
const Color _otherNameColorLight = Color(0xFF060607);

/// Soft shadow under names in light mode, so they stand out on white.
List<Shadow>? _nameShadows(ThemeData theme) =>
    theme.brightness == Brightness.light
    ? const [
        Shadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
      ]
    : null;

String vibeTime(DateTime ts) {
  final local = ts.toLocal();
  final now = DateTime.now();
  final t = DateFormat('h:mm a').format(local);
  final d = DateTime(local.year, local.month, local.day);
  final today = DateTime(now.year, now.month, now.day);
  // Discord style: just the time for today.
  if (d == today) return t;
  if (today.difference(d).inDays == 1) return 'Yesterday at $t';
  return '${DateFormat.yMd().format(local)} $t';
}

String vibeDayLabel(DateTime ts) {
  final local = ts.toLocal();
  final now = DateTime.now();
  final d = DateTime(local.year, local.month, local.day);
  final today = DateTime(now.year, now.month, now.day);
  if (d == today) return 'Today';
  if (today.difference(d).inDays == 1) return 'Yesterday';
  return DateFormat.yMMMMd().format(local);
}

/// "──── Today ────" divider between days.
class VibeDateDivider extends StatelessWidget {
  final DateTime date;
  const VibeDateDivider(this.date, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Row(
        children: [
          Expanded(child: Divider(height: 1, color: theme.dividerColor)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              vibeDayLabel(date),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Divider(height: 1, color: theme.dividerColor)),
        ],
      ),
    );
  }
}

/// "Welcome to your chat with X!" block shown at the very top of a chat.
class VibeChatIntro extends StatelessWidget {
  final Room room;
  const VibeChatIntro(this.room, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final name = room.getLocalizedDisplayname(MatrixLocals(L10n.of(context)));
    final dm = room.isDirectChat;
    final enc = room.encrypted;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 84,
            height: 84,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cs.surfaceContainerHighest,
            ),
            child: Text(
              dm ? '@' : '#',
              style: const TextStyle(fontSize: 38, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            dm ? 'Welcome to your chat with $name!' : 'Welcome to $name!',
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Text(
            dm
                ? 'This is the start of your direct ${enc ? 'encrypted ' : ''}conversation with $name.${enc ? ' End-to-end encrypted with Megolm v1 AES-SHA2.' : ''}'
                : 'This is the start of the $name conversation.${enc ? ' End-to-end encrypted with Megolm v1 AES-SHA2.' : ''}',
            style: TextStyle(
              fontSize: 16,
              height: 1.35,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(child: Divider(height: 1, color: theme.dividerColor)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  enc ? 'LIVE ENCRYPTED STREAM' : 'LIVE STREAM',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
              Expanded(child: Divider(height: 1, color: theme.dividerColor)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Has anyone else read [event] (a receipt on it or anything newer)?
bool _readByOther(Event event, Timeline timeline) {
  final me = event.room.client.userID;
  for (final e in timeline.events) {
    if (e.receipts.any((r) => r.user.id != me)) return true;
    if (e.eventId == event.eventId) break;
  }
  return false;
}

/// Who has read up to [event], but only for your newest read message, so
/// "Seen by" shows once under a run of your messages, not under each one.
List<String>? _seenBy(Event event, Timeline timeline) {
  final me = event.room.client.userID;
  final names = <String, String>{};
  for (final e in timeline.events) {
    for (final r in e.receipts) {
      if (r.user.id != me) names[r.user.id] = r.user.calcDisplayname();
    }
    if (e.eventId == event.eventId) break;
    // a newer message of yours is already read: it carries the line
    if (names.isNotEmpty &&
        e.senderId == me &&
        e.status.isSynced &&
        {EventTypes.Message, EventTypes.Sticker}.contains(e.type)) {
      return null;
    }
  }
  return names.isEmpty ? null : names.values.toList();
}

/// "Seen by Leo and Maya" under your newest read message.
class _SeenBy extends StatelessWidget {
  final Event event;
  final Timeline timeline;
  const _SeenBy(this.event, this.timeline);

  @override
  Widget build(BuildContext context) => StreamBuilder(
    stream: event.room.client.onSync.stream.where(
      (u) =>
          u.rooms?.join?[event.room.id]?.ephemeral?.any(
            (e) => e.type == 'm.receipt',
          ) ??
          false,
    ),
    builder: (context, _) {
      if (!event.status.isSynced) return const SizedBox.shrink();
      final names = _seenBy(event, timeline);
      if (names == null) return const SizedBox.shrink();
      final who = switch (names.length) {
        1 => names[0],
        2 => '${names[0]} and ${names[1]}',
        3 => '${names[0]}, ${names[1]} and ${names[2]}',
        _ => '${names[0]}, ${names[1]} and ${names.length - 2} others',
      };
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          'Seen by $who',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    },
  );
}

class _MiniAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _MiniAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  // Retry / Cancel: at least 40 dp tall so they're easy to hit.
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(8),
    onTap: onTap,
    child: Container(
      constraints: const BoxConstraints(minHeight: 40),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Failed messages and file uploads show their status (with buttons) under
/// the message; everything else shows it inline after the text.
bool _statusBelow(Event e) =>
    e.status == EventStatus.error ||
    (e.status == EventStatus.sending && e.fileSendingStatus != null);

/// Message status as a small word: Encrypting, Sent, Delivered.
class _StatusBits extends StatelessWidget {
  final Event event;
  final Timeline timeline;
  /// Text colour (inside a bubble); the theme's dim colour otherwise.
  final Color? ink;
  const _StatusBits(this.event, this.timeline, {this.ink});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = event.status;
    final dim = theme.colorScheme.onSurfaceVariant;
    if (status == EventStatus.error) {
      return Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 16,
                color: theme.colorScheme.error,
              ),
              const SizedBox(width: 4),
              Text(
                L10n.of(context).couldNotBeSent,
                style: TextStyle(fontSize: 12, color: theme.colorScheme.error),
              ),
            ],
          ),
          _MiniAction(
            icon: Icons.refresh,
            label: 'Retry',
            color: theme.colorScheme.primary,
            onTap: () => event.sendAgain(),
          ),
          _MiniAction(
            icon: Icons.close,
            label: 'Cancel',
            color: theme.colorScheme.error,
            onTap: () => event.cancelSend(),
          ),
        ],
      );
    }
    if (status == EventStatus.sending && event.fileSendingStatus != null) {
      final label = switch (event.fileSendingStatus!) {
        FileSendingStatus.generatingThumbnail =>
          L10n.of(context).generatingThumbnail,
        FileSendingStatus.encrypting => L10n.of(context).encrypting,
        FileSendingStatus.uploading => L10n.of(context).uploading,
      };
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: dim)),
          const SizedBox(width: 6),
          SizedBox.square(
            dimension: 11,
            child: CircularProgressIndicator(strokeWidth: 1.4, color: dim),
          ),
          const SizedBox(width: 10),
          _MiniAction(
            icon: Icons.close,
            label: 'Cancel',
            color: theme.colorScheme.error,
            onTap: () => event.cancelSend(),
          ),
        ],
      );
    }
    return StreamBuilder(
      stream: event.room.client.onSync.stream.where(
        (u) =>
            u.rooms?.join?[event.room.id]?.ephemeral?.any(
              (e) => e.type == 'm.receipt',
            ) ??
            false,
      ),
      builder: (context, _) {
        // one small word that changes in place: Encrypting, Sent,
        // Delivered. Once read it goes away and "Seen by …" shows under
        // your newest read message.
        final offline =
            event.room.client.onSyncStatus.value?.status == SyncStatus.error;
        final String? word = status == EventStatus.sending
            ? (offline
                  ? 'Waiting for connection'
                  : event.room.encrypted
                  ? 'Encrypting'
                  : 'Sending')
            : _readByOther(event, timeline)
            ? null
            : status.isSynced
            ? 'Delivered'
            : 'Sent';
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.centerRight,
            children: [...previous, if (current != null) current],
          ),
          transitionBuilder: (child, a) => FadeTransition(
            opacity: a,
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, 0.5),
                end: Offset.zero,
              ).animate(a),
              child: child,
            ),
          ),
          child: word == null
              ? const SizedBox.shrink(key: ValueKey(''))
              : Padding(
                  key: ValueKey(word),
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    word,
                    style: TextStyle(
                      fontSize: 10.5,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                      color: ink ?? dim,
                      shadows: const [],
                    ),
                  ),
                ),
        );
      },
    );
  }
}

class VibeMessage extends StatelessWidget {
  final Event event;
  final Event? nextEvent;
  final Event? previousEvent;
  final bool displayReadMarker;
  final void Function(Event) onSelect;
  final void Function(Event) onInfoTab;
  final void Function(String) scrollToEventId;
  final void Function() onSwipe;
  final void Function()? onQuote;
  final void Function() onMention;
  final void Function(String eventId)? enterThread;
  final bool longPressSelect;
  final bool selected;
  final bool singleSelected;
  final Timeline timeline;
  final bool highlightMarker;
  final Set<String> bigEmojis;
  final void Function(Event)? onLongPress;
  final bool threadView;

  const VibeMessage(
    this.event, {
    required this.nextEvent,
    required this.previousEvent,
    required this.displayReadMarker,
    required this.onSelect,
    required this.onInfoTab,
    required this.scrollToEventId,
    required this.onSwipe,
    this.onQuote,
    required this.onMention,
    required this.enterThread,
    required this.longPressSelect,
    required this.selected,
    required this.singleSelected,
    required this.timeline,
    required this.highlightMarker,
    required this.bigEmojis,
    this.onLongPress,
    this.threadView = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    // the newest message: when its sender is writing again, their dots join
    // its card below, so it hands them its picture and time
    if (previousEvent == null && !threadView) {
      return ValueListenableBuilder<String?>(
        valueListenable: VibeCards.continuing,
        builder: (context, id, _) => _build(context, id == event.eventId),
      );
    }
    return _build(context, false);
  }

  Widget _build(BuildContext context, bool writingOn) {
    if (VibeDisappearing.isExpired(event)) return const SizedBox.shrink();
    final once = VibeViewOnce.of(event) && !event.redacted;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final client = Matrix.of(context).client;
    final ownMessage = event.senderId == client.userID;
    // a view-once message you've opened is gone
    if (!ownMessage && VibeViewOnce.viewed(event)) return const SizedBox.shrink();
    // Your messages sit on the other side: avatar and text on the right
    // (left in right-to-left languages).
    final dir = Directionality.of(context);
    final side = ownMessage
        ? (dir == ui.TextDirection.ltr ? ui.TextDirection.rtl : ui.TextDirection.ltr)
        : dir;

    bool sameGroup(Event? e) =>
        e != null &&
        {EventTypes.Message, EventTypes.Sticker}.contains(e.type) &&
        e.senderId == event.senderId &&
        e.originServerTs.sameEnvironment(event.originServerTs);

    // The list is newest-first, so "nextEvent" is the OLDER neighbour.
    bool hasReply(Event? e) =>
        e != null && e.inReplyToEventId(includingFallback: false) != null;
    // A reply always starts a new visual group (avatar + header + reply line).
    // In the thread pane the tree lines show who answers whom, so no reply
    // line, and every message is its own row (avatar + name).
    final replying = !threadView && hasReply(event);
    final first = threadView || replying || !sameGroup(nextEvent);
    final runLast =
        threadView || hasReply(previousEvent) || !sameGroup(previousEvent);

    // edits of a post-quantum message are wrapped too
    final displayEvent = VibePq.open(event.getDisplayEvent(timeline));
    final sender = event.senderFromMemoryOrFallback;
    final hasReactions = event.hasAggregatedEvents(
      timeline,
      RelationshipTypes.reaction,
    );
    final threadChildren = event.aggregatedEvents(
      timeline,
      RelationshipTypes.thread,
    );
    // live location and check-in update themselves by edits: not "edited"
    final isEdited =
        event.hasAggregatedEvents(timeline, RelationshipTypes.edit) &&
        VibeLive.live(displayEvent) == null &&
        VibeLive.checkIn(displayEvent) == null;
    final showReactionPicker =
        singleSelected && event.room.canSendDefaultMessages;
    final enterThread = this.enterThread;
    // a small round picture; the last bubble of a run curves in round it
    const avatarSize = 30.0;
    const nestGap = 3.0;
    final picLeft = side == ui.TextDirection.ltr;
    // the other messages of a run line up with that bubble
    final inset = EdgeInsets.only(
      left: picLeft ? avatarSize + nestGap : 0,
      right: picLeft ? 0 : avatarSize + nestGap,
    );
    // text sits in a bubble; photos, stickers, big emoji and cards stay as
    // they are
    final bubble = displayEvent.type == EventTypes.Message &&
        const {
          MessageTypes.Text,
          MessageTypes.Notice,
          MessageTypes.Emote,
        }.contains(displayEvent.messageType) &&
        !once &&
        VibeLive.checkIn(displayEvent) == null &&
        !displayEvent.onlyEmotes &&
        VibeChunks.info(displayEvent) == null &&
        !VibeLinkPreview.onlyLink(displayEvent);
    final last = runLast && !(writingOn && bubble && !ownMessage);
    // one card per run: their text messages in a row share one card with a
    // hairline between them; photos, stickers and cards sit between cards
    final cardFirst = first || !VibeCards.inCard(nextEvent, timeline);
    final cardLast =
        (last || !VibeCards.inCard(previousEvent, timeline)) && runLast == last;
    final card = bubble && !threadView
        ? VibeCards.width(VibeCards.keyOf(event, timeline))
        : null;
    // how far a bubble reaches past its box towards the picture
    const reach = avatarSize / 2 + nestGap;
    // a card that starts with a reply: the reply's line runs on down the
    // card's edge to their picture beside the newest message
    final cardKey = bubble && !threadView ? VibeCards.keyOf(event, timeline) : null;
    final rail = cardKey != null &&
        hasReply(
          cardKey == event.eventId
              ? event
              : timeline.events.where((e) => e.eventId == cardKey).firstOrNull,
        );
    // solid colours from the phone's colour theme when it has one: yours in
    // the theme colour, theirs neutral
    final dark = theme.brightness == Brightness.dark;
    final wall = (dark ? VibePalette.wallDark : VibePalette.wallLight) ?? cs;
    final under = dark ? const Color(0xFF1B1B1F) : const Color(0xFFF1F1F4);
    final bubbleColor = Color.alphaBlend(
      ownMessage ? wall.primaryContainer : cs.surfaceContainerHigh,
      under,
    );
    final bubbleInk = ownMessage ? wall.onPrimaryContainer : cs.onSurface;
    final showHeader = first && !bubble;

    final sentReactions = <String>{};
    if (singleSelected) {
      sentReactions.addAll(
        event
            .aggregatedEvents(timeline, RelationshipTypes.reaction)
            .where(
              (e) =>
                  e.senderId == e.room.client.userID && e.type == 'm.reaction',
            )
            .map(
              (e) => e.content
                  .tryGetMap<String, Object?>('m.relates_to')
                  ?.tryGet<String>('key'),
            )
            .whereType<String>(),
      );
    }

    Widget avatar() {
      if (longPressSelect && !event.redacted) {
        return SizedBox(
          width: avatarSize,
          height: avatarSize,
          child: IconButton(
            padding: EdgeInsets.zero,
            tooltip: L10n.of(context).select,
            icon: Icon(
              selected ? Icons.check_circle : Icons.circle_outlined,
            ),
            onPressed: () => onSelect(event),
          ),
        );
      }
      return const SizedBox.shrink();
    }

    // their picture, beside the last message of a run
    Widget pic() {
      final picture = FutureBuilder<User?>(
        future: event.fetchSenderUser(),
        builder: (context, snapshot) {
          final user = snapshot.data ?? sender;
          return Avatar(
            mxContent: user.avatarUrl,
            name: user.calcDisplayname(),
            size: avatarSize,
            client: client,
            onTap: () => VibeUserSheet.show(
              context,
              client: client,
              userId: user.id,
              displayName: user.calcDisplayname(),
              avatarUrl: user.avatarUrl,
              currentRoomId: event.room.id,
            ),
          );
        },
      );
      // someone else's new message: their typing dots become the picture
      return ownMessage
          ? picture
          : VibeTypingMorph(size: avatarSize, child: picture);
    }

    Widget header() {
      return FutureBuilder<User?>(
        future: event.fetchSenderUser(),
        builder: (context, snapshot) {
          final displayname =
              snapshot.data?.calcDisplayname() ?? sender.calcDisplayname();
          final color = ownMessage
              ? (theme.brightness == Brightness.light ? _ownNameColorLight : _ownNameColor)
              : event.room.isDirectChat
              ? (theme.brightness == Brightness.light ? _otherNameColorLight : _otherNameColor)
              : (theme.brightness == Brightness.light
                    ? displayname.colorScheme.primary
                    : displayname.colorScheme.primaryContainer);
          return Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 0,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: VibeNameText(
                  displayname,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: VibeTextSize.message,
                    height: 1.15,
                    color: color,
                    shadows: _nameShadows(theme),
                  ),
                ),
              ),
              ...VibeMemberTags.chips(event.room, snapshot.data ?? sender),
              // Encrypted is the normal case (shown once in the chat
              // header); only warn when a chat is NOT encrypted.
              if (!event.room.encrypted)
                const Icon(
                  Icons.lock_open,
                  size: 14,
                  color: Colors.redAccent,
                ),
              if (isEdited)
                Text(
                  L10n.of(context).edited,
                  style: TextStyle(
                    fontSize: VibeTextSize.message * 0.74,
                    color: cs.onSurfaceVariant,
                  ),
                ),
            ],
          );
        },
      );
    }

    Widget replyStrip() {
      return FutureBuilder<Event?>(
        future: event.getReplyEvent(timeline),
        builder: (context, snapshot) {
          final replyEvent = snapshot.data;
          final lineColor = cs.onSurfaceVariant.withValues(alpha: 0.45);
          Widget content;
          if (replyEvent == null) {
            content = Text(
              snapshot.connectionState == ConnectionState.done
                  ? 'Original message not available'
                  : '…',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: VibeTextSize.message * 0.88,
                fontStyle: FontStyle.italic,
                color: cs.onSurfaceVariant,
              ),
            );
          } else {
            final rs = replyEvent.senderFromMemoryOrFallback;
            final rname = rs.calcDisplayname();
            final rown = replyEvent.senderId == client.userID;
            final rcolor = rown
                ? (theme.brightness == Brightness.light ? _ownNameColorLight : _ownNameColor)
                : event.room.isDirectChat
                ? (theme.brightness == Brightness.light ? _otherNameColorLight : _otherNameColor)
                : (theme.brightness == Brightness.light
                      ? rname.colorScheme.primary
                      : rname.colorScheme.primaryContainer);
            // a reply to part of a message shows the quoted words
            final quoted = VibeQuotePicker.quoteOf(event);
            final preview = quoted ?? replyEvent
                .getDisplayEvent(timeline)
                .vibeBodyFallback(
                  MatrixLocals(L10n.of(context)),
                  hideReply: true,
                  hideEdit: true,
                  plaintextBody: true,
                  removeMarkdown: true,
                );
            content = Row(
              mainAxisAlignment: ownMessage
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.start,
              children: [
                Avatar(
                  mxContent: rs.avatarUrl,
                  name: rname,
                  size: 16,
                  client: client,
                ),
                const SizedBox(width: 6),
                Flexible(
                  flex: 0,
                  child: Text(
                    '@$rname',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: VibeTextSize.message * 0.88,
                      fontWeight: FontWeight.w700,
                      color: rcolor,
                      shadows: _nameShadows(theme),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  fit: ownMessage ? FlexFit.loose : FlexFit.tight,
                  child: Text(
                    preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: VibeTextSize.message * 0.88,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            );
          }
          return InkWell(
            onTap: replyEvent == null
                ? null
                : () => scrollToEventId(replyEvent.eventId),
            child: SizedBox(
              height: 22,
              child: Row(
                textDirection: side,
                children: [
                  SizedBox(
                    width: avatarSize,
                    height: 22,
                    // the same curve, mirrored when the avatar is on the right
                    child: Transform.flip(
                      flipX: side == ui.TextDirection.rtl,
                      child: CustomPaint(painter: _ReplyCurve(lineColor)),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(child: content),
                ],
              ),
            ),
          );
        },
      );
    }

    final body = Column(
      crossAxisAlignment: ownMessage
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showHeader) header(),
        Align(
          alignment: ownMessage
              ? AlignmentDirectional.centerEnd
              : AlignmentDirectional.centerStart,
          child: Builder(
            builder: (context) {
              // a link at the start or end with a preview card: the card
              // (in the same card as the text) opens it, so the text leaves
              // it out once the card is here
              final edgeUrl = bubble ? VibeLinkPreview.edgeUrl(displayEvent) : null;
              Widget text(bool hide) => MessageContent(
                displayEvent,
                textColor: bubble ? bubbleInk : cs.onSurface,
                linkColor: bubble && ownMessage ? bubbleInk : cs.primary,
                // the quoted words already show on the reply line
                hideQuote: replying && VibeQuotePicker.quoteOf(event) != null,
                hideUrl: hide ? edgeUrl : null,
                onInfoTab: onInfoTab,
                borderRadius: BorderRadius.circular(14),
                timeline: timeline,
                selected: selected,
                bigEmojis: bigEmojis,
              );
              // Vibe X's soft shadow under the text in light mode
              final Widget content = DefaultTextStyle.merge(
                // message text like the mocks: Figtree Regular, airy lines
                style: TextStyle(
                  shadows: bubble ? const [] : _nameShadows(theme),
                  fontWeight: FontWeight.w400,
                  height: 1.45,
                ),
                // your messages: every line lines up to the right edge
                textAlign: ownMessage && !bubble ? TextAlign.end : null,
                // a long message is only as wide as its longest line, so the dots sit right after it
                textWidthBasis: TextWidthBasis.longestLine,
                child: once
                  ? VibeViewOnceTile(
                      event: event,
                      timeline: timeline,
                      own: ownMessage,
                      color: bubbleColor,
                      ink: bubbleInk,
                    )
                  : VibeLive.checkIn(displayEvent) != null
                  ? VibeCheckInCard(
                      event: displayEvent,
                      eventId: event.eventId,
                      color: bubbleColor,
                      ink: bubbleInk,
                    )
                  : VibeChunks.info(displayEvent) != null
                  ? VibeChunkCard(displayEvent)
                  // just a link: the preview card below stands in for it
                  : VibeLinkPreview.onlyLink(displayEvent)
                  ? const SizedBox.shrink()
                  : edgeUrl == null
                  ? text(false)
                  : FutureBuilder<bool>(
                      future: VibeLinkPreview.shows(displayEvent, edgeUrl),
                      initialData: VibeLinkPreview.showsNow(edgeUrl),
                      builder: (context, snap) => text(snap.data == true),
                    ),
              );
              // Sent with an effect: play it once as it arrives, and keep a
              // small badge to play it again.
              final effect = VibeEffects.of(event);
              if (effect != null) {
                VibeEffects.maybePlay(context, event);
              } else {
                // hot words (hahaha, congrats, kiss, hug, party...) fill the screen
                VibeHotWords.maybePlay(context, event);
              }
              // Status sits right after the text the whole time:
              // "Encrypting…" → ✓ → blue ✓✓, changing in place. Only
              // failures and file uploads (with Retry / Cancel) go below.
              final ticks = ownMessage && !_statusBelow(event);
              final Widget shown;
              if (!bubble) {
                shown = content;
              } else {
                final meta = bubbleInk.withValues(alpha: 0.62);
                final name = sender.calcDisplayname();
                final maxW = MediaQuery.sizeOf(context).width * 0.76 +
                    (last ? 0 : reach);
                // text clears the picture: the last one's box starts after
                // it, the others reach there themselves
                final padNear = last ? 14.0 : 14.0 + reach;
                // the time, edited and the ticks: after the text, at the
                // card's far edge
                final trailing = <Widget>[
                  if (isEdited)
                    Text(
                      L10n.of(context).edited,
                      style: TextStyle(
                        fontSize: 10.5,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                        color: meta,
                      ),
                    ),
                  if (last && event.status.isSent)
                    Text(
                      vibeTime(event.originServerTs),
                      style: TextStyle(fontSize: 11, height: 1.2, color: meta),
                    ),
                  // only warn when a chat is NOT encrypted
                  if (last && event.status.isSent && !event.room.encrypted)
                    const Icon(Icons.lock_open, size: 12, color: Colors.redAccent),
                  // Encrypting, Sent, Delivered: inside the bubble
                  if (ticks) _StatusBits(event, timeline, ink: meta),
                ];
                Widget bubbleOf(double cardW) {
                  final boxMin = math.min(maxW, math.max(0.0, cardW - (last ? reach : 0)));
                  final inner = math.max(0.0, boxMin - padNear - 14);
                  // marked, so the samurai knows where the card is
                  return MetaData(
                    metaData: const VibeSlashBubble(),
                    child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: boxMin, maxWidth: maxW),
                    child: _ReportWidth(
                      card: card,
                      extra: last ? reach : 0,
                      child: CustomPaint(
                        painter: VibeBubblePainter(
                          color: bubbleColor,
                          left: picLeft,
                          top: cardFirst ? 20 : 0,
                          bottom: cardLast ? 20 : 0,
                          farTop: cardFirst ? 20 : 0,
                          farBottom: cardLast ? 20 : 0,
                          // every bubble of a run ends at the picture's
                          // middle, so their edges line up; the last one
                          // reaches there and curves in round the picture
                          reach: last ? reach : 0,
                          cut: last,
                          // a hairline between messages of one card
                          line: cardFirst
                              ? null
                              : bubbleInk.withValues(alpha: 0.12),
                          lineNear: padNear,
                        ),
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            picLeft ? padNear : 14,
                            8,
                            picLeft ? 14 : padNear,
                            8,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // groups: who it is, inside their first bubble
                              if (first && !ownMessage && !event.room.isDirectChat)
                                Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 6,
                                  children: [
                                    VibeNameText(
                                      name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: VibeTextSize.message * 0.84,
                                        height: 1.3,
                                        color: dark
                                            ? name.colorScheme.primaryContainer
                                            : name.colorScheme.primary,
                                      ),
                                    ),
                                    ...VibeMemberTags.chips(event.room, sender),
                                  ],
                                ),
                              trailing.isEmpty
                                  ? content
                                  : VibeTimeFlow(
                                      minWidth: inner,
                                      content: content,
                                      trailing: Padding(
                                        padding: const EdgeInsets.only(bottom: 3),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          spacing: 5,
                                          children: trailing,
                                        ),
                                      ),
                                    ),
                              // a link's preview and the reactions stay in
                              // the card, under their own message
                              VibeLinkPreview(event: displayEvent, inCard: true),
                              if (hasReactions)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: MessageReactions(event, timeline),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  );
                }
                shown = card == null
                    ? bubbleOf(0)
                    : ValueListenableBuilder<double>(
                        valueListenable: card,
                        builder: (context, w, _) => bubbleOf(w),
                      );
              }
              // the last message of a run carries the picture; a bubble
              // curves in round it
              Widget place(Widget w) => CustomPaint(
                foregroundPainter: rail
                    ? _ReplyRail(
                        cs.onSurfaceVariant.withValues(alpha: 0.45),
                        left: picLeft,
                        toPicture: last,
                        pic: avatarSize,
                      )
                    : null,
                child: Padding(
                padding: EdgeInsets.only(
                  top: first || (bubble && !cardFirst) ? 0 : 2,
                ),
                child: last
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        textDirection: side,
                        // the picture sits in the bubble's curve
                        crossAxisAlignment: bubble
                            ? CrossAxisAlignment.center
                            : CrossAxisAlignment.end,
                        children: [
                          pic(),
                          const SizedBox(width: nestGap),
                          Flexible(child: VibeGrowOut(left: picLeft, child: w)),
                        ],
                      )
                    : Padding(
                        padding: bubble
                            ? EdgeInsets.only(
                                left: picLeft ? avatarSize / 2 : 0,
                                right: picLeft ? 0 : avatarSize / 2,
                              )
                            : inset,
                        child: VibeGrowOut(left: picLeft, child: w),
                      ),
              ),
              );
              // Bujji can find it on screen and come and sit on it
              if ((!ticks || bubble) && effect == null) {
                return place(BujjiSpot(id: event.eventId, child: shown));
              }
              // Sent/read ticks sit beside the text: after it, or before it
              // on your side so the right edge stays clean.
              return place(Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                textDirection: side,
                children: [
                  Flexible(
                    child: BujjiSpot(id: event.eventId, child: shown),
                  ),
                  if (effect != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 1),
                      child: VibeEffectBadge(effect),
                    ),
                  if (ticks && !bubble)
                    Padding(
                      // the gap always sits between the ticks and the text
                      padding: EdgeInsets.only(
                        left: side == ui.TextDirection.ltr ? 6 : 0,
                        right: side == ui.TextDirection.rtl ? 6 : 0,
                        bottom: 3,
                      ),
                      child: _StatusBits(event, timeline),
                    ),
                ],
              ));
            },
          ),
        ),
        if (!bubble) VibeLinkPreview(event: displayEvent),
        if (hasReactions && !bubble)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: MessageReactions(event, timeline),
          ),
        // the time, once, under the last message of a run (a card has it
        // inside)
        if (last && event.status.isSent && !bubble)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              children: [
                Text(
                  vibeTime(event.originServerTs),
                  style: TextStyle(
                    fontSize: 11.5,
                    color: cs.onSurfaceVariant,
                    shadows: _nameShadows(theme),
                  ),
                ),
                // only warn when a chat is NOT encrypted
                if (!event.room.encrypted)
                  const Icon(Icons.lock_open, size: 12, color: Colors.redAccent),
              ],
            ),
          ),
        if (ownMessage) _SeenBy(event, timeline),
        // Sending / failed (with Retry and Cancel) stays under the message.
        if (ownMessage && _statusBelow(event))
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: _StatusBits(event, timeline),
          ),
                                    Align(
                              alignment: Alignment.bottomLeft,
                              child: AnimatedSize(
                                duration: VibeThemes.animationDuration,
                                curve: VibeThemes.animationCurve,
                                child: showReactionPicker
                                    ? Padding(
                                        padding: const EdgeInsets.all(4.0),
                                        child: Material(
                                          elevation: 4,
                                          borderRadius: BorderRadius.circular(
                                            AppConfig.borderRadius,
                                          ),
                                          shadowColor: theme.colorScheme.surface
                                              .withAlpha(128),
                                          child: SingleChildScrollView(
                                            scrollDirection: Axis.horizontal,
                                            child: Row(
                                              mainAxisSize: .min,
                                              children: [
                                                ...AppConfig.defaultReactions.map(
                                                  (emoji) => IconButton(
                                                    padding: EdgeInsets.zero,
                                                    icon: Center(
                                                      child: Opacity(
                                                        opacity:
                                                            sentReactions
                                                                .contains(emoji)
                                                            ? 0.33
                                                            : 1,
                                                        child: Text(
                                                          emoji,
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 20,
                                                              ),
                                                          textAlign:
                                                              TextAlign.center,
                                                        ),
                                                      ),
                                                    ),
                                                    onPressed:
                                                        sentReactions.contains(
                                                          emoji,
                                                        )
                                                        ? null
                                                        : () {
                                                            onSelect(event);
                                                            event.room
                                                                .sendReaction(
                                                                  event.eventId,
                                                                  emoji,
                                                                );
                                                          },
                                                  ),
                                                ),
                                                IconButton(
                                                  icon: const Icon(
                                                    Icons.add_reaction_outlined,
                                                  ),
                                                  tooltip: L10n.of(
                                                    context,
                                                  ).customReaction,
                                                  onPressed: () async {
                                                    final emoji = await VibeEmojiSheet.pick(
                                                      context,
                                                      room: event.room,
                                                    );
                                                    if (emoji == null) {
                                                      return;
                                                    }
                                                    if (sentReactions.contains(
                                                      emoji,
                                                    )) {
                                                      return;
                                                    }
                                                    onSelect(event);

                                                    await event.room
                                                        .sendReaction(
                                                          event.eventId,
                                                          emoji,
                                                        );
                                                  },
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ),
      ],
    );

    return VibeHeartHost(
      event: event,
      timeline: timeline,
      builder: (context, heart) => Center(
      child: VibeSwipeReply(
        key: ValueKey(VibeStableId.of(event)),
        onReply: onSwipe,
        // swipe and hold quotes part of a text message
        onQuote: {
          MessageTypes.Text,
          MessageTypes.Notice,
          MessageTypes.Emote,
        }.contains(event.messageType)
            ? onQuote
            : null,
        child: VibeSlashRow(
        eventId: event.eventId,
        child: Container(
          constraints: const BoxConstraints(
            maxWidth: VibeThemes.maxTimelineWidth,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Material(
                color: highlightMarker
                    ? VibePalette.accent.withAlpha(64)
                    : selected
                    ? cs.secondaryContainer.withAlpha(110)
                    : Colors.transparent,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: longPressSelect ? () => onSelect(event) : null,
                  onLongPressStart: longPressSelect
                      ? null
                      : (d) {
                          // held on a link: Open, Copy link and Share for it
                          final url = VibeLinks.at(context, d.globalPosition);
                          if (url != null) {
                            VibeLinks.options(context, url);
                            return;
                          }
                          VibeHaptics.heavy();
                          // where the message is, for the menu round it
                          final box = context.findRenderObject();
                          if (box is RenderBox && box.hasSize) {
                            VibeMessageOrbit.hold(
                              box.localToGlobal(Offset.zero) & box.size,
                            );
                          }
                          final cb = onLongPress;
                          if (cb != null) {
                            cb(event);
                          } else {
                            onSelect(event);
                          }
                        },
                  // keep following the finger after the menu opens, so it
                  // can glide onto an action and let go
                  onLongPressMoveUpdate: longPressSelect
                      ? null
                      : (d) => VibeMessageOrbit.move(d.globalPosition),
                  onLongPressEnd: longPressSelect
                      ? null
                      : (d) => VibeMessageOrbit.release(d.globalPosition),
                  onDoubleTap:
                      AppSettings.doubleTapToReact.value &&
                          event.room.canSendDefaultMessages
                      ? () {
                          VibeHaptics.light();
                          // the action picked in Settings > Chats & storage
                          switch (AppSettings.doubleTapAction.value) {
                            case 'reply':
                              onSwipe();
                              return;
                            case 'quote':
                              (onQuote ?? onSwipe)();
                              return;
                            case 'star':
                              VibeStarred.toggle(event.room.id, event.eventId);
                              return;
                            case 'copy':
                              Clipboard.setData(
                                ClipboardData(
                                  text: event.calcUnlocalizedBody(
                                    hideReply: true,
                                    plaintextBody: true,
                                  ),
                                ),
                              );
                              return;
                          }
                          final emoji = AppSettings.doubleTapReaction.value;
                          final existing = event
                              .aggregatedEvents(
                                timeline,
                                RelationshipTypes.reaction,
                              )
                              .firstWhereOrNull(
                                (e) =>
                                    e.senderId == event.room.client.userID &&
                                    e.content
                                            .tryGetMap<String, Object?>(
                                              'm.relates_to',
                                            )
                                            ?.tryGet<String>('key') ==
                                        emoji,
                              );
                          if (existing != null) {
                            existing.redactEvent();
                          } else {
                            if (emoji.contains('❤')) heart.burst();
                            event.room.sendReaction(event.eventId, emoji);
                          }
                        }
                      : null,
                  onDoubleTapDown: (d) => heart.noteTap(d.globalPosition),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      12,
                      first ? 10 : 0,
                      12,
                      last ? 4 : 0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (replying) replyStrip(),
                        // the picture sits under the last message of a run;
                        // one line grows up from it, curving into each
                        // earlier message of that run
                        Stack(
                          children: [
                            Row(
                              textDirection: side,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (longPressSelect && !event.redacted) ...[
                                  avatar(),
                                  const SizedBox(width: 6),
                                ],
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: body.crossAxisAlignment,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      for (final (i, w) in body.children.indexed)
                                        i == (showHeader ? 1 : 0)
                                            ? w
                                            : Padding(padding: inset, child: w),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
                            if (enterThread != null)
                AnimatedSize(
                  duration: VibeThemes.animationDuration,
                  curve: VibeThemes.animationCurve,
                  alignment: Alignment.bottomCenter,
                  child: threadChildren.isEmpty
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(
                            top: 2.0,
                            bottom: 8.0,
                            left: avatarSize + 8,
                          ),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: VibeThemes.columnWidth * 1.5,
                            ),
                            child: TextButton.icon(
                              style: TextButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                foregroundColor: theme.colorScheme.primary,
                                backgroundColor: theme
                                    .colorScheme
                                    .primaryContainer
                                    .withValues(alpha: 0.4),
                              ),
                              onPressed: () => enterThread(event.eventId),
                              icon: const Icon(VibeThreads.icon, size: 18),
                              label: Text(
                                '${L10n.of(context).countReplies(threadChildren.length)} | ${threadChildren.first.vibeBodyFallback(MatrixLocals(L10n.of(context)), withSenderNamePrefix: true)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ),
                ),
                            if (displayReadMarker)
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 1.2,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF23F43),
                          boxShadow: theme.brightness == Brightness.light
                              ? const [BoxShadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1))]
                              : null,
                        ),
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 16.0,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(
                          AppConfig.borderRadius / 3,
                        ),
                        color: theme.colorScheme.surface.withAlpha(128),
                      ),
                      child: Text(
                        L10n.of(context).readUpToHere,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFF23F43),
                          shadows: _nameShadows(theme),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        height: 1.2,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF23F43),
                          boxShadow: theme.brightness == Brightness.light
                              ? const [BoxShadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1))]
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        ),
      ),
    ),
    );
  }
}


/// Discord-style reply connector: up from the avatar's top-centre, then a
/// rounded corner to the right, ending beside the replied-to author.
class _ReplyCurve extends CustomPainter {
  final Color color;
  const _ReplyCurve(this.color);

  /// How far past its box the line goes: up to the small avatar.
  static const reach = 7.0;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final mid = size.height / 2;
    const r = 8.0;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(cx, size.height + 4)
      ..lineTo(cx, mid + r)
      ..quadraticBezierTo(cx, mid, cx + r, mid)
      // runs on into the small picture of the person being replied to
      ..lineTo(size.width + _ReplyCurve.reach, mid);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ReplyCurve old) => old.color != color;
}

/// A reply's line carried on down the card's edge, row by row, to the top of
/// the sender's picture beside the newest message.
class _ReplyRail extends CustomPainter {
  final Color color;
  final bool left, toPicture;
  final double pic;
  const _ReplyRail(this.color, {required this.left, required this.toPicture, required this.pic});

  @override
  void paint(Canvas canvas, Size size) {
    final x = left ? pic / 2 : size.width - pic / 2;
    // the newest row: down to its picture (centred beside the bubble)
    final end = toPicture ? size.height / 2 - pic / 2 - 2 : size.height;
    if (end <= 0) return;
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, end),
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_ReplyRail old) =>
      old.color != color || old.left != left || old.toPicture != toPicture;
}

/// A bubble's solid shape: one card per run, so its corners are round only
/// at the card's top and bottom. It reaches [reach] past its box towards the
/// picture, so every bubble of a run lines up; with [cut] (the last one) that
/// end curves in round the picture: O)____) for theirs, (____(O for yours.
class VibeBubblePainter extends CustomPainter {
  final Color color;

  /// The picture is on the left.
  final bool left;

  /// Corner sizes on the picture's side, and on the far side.
  final double top, bottom, farTop, farBottom;
  final double reach;
  final bool cut;

  /// A hairline across the top (between messages of one card), from where
  /// the text starts on the picture's side to near the far edge.
  final Color? line;
  final double lineNear;
  const VibeBubblePainter({
    required this.color,
    required this.left,
    required this.top,
    required this.bottom,
    this.farTop = 20,
    this.farBottom = 20,
    this.reach = 0,
    this.cut = false,
    this.line,
    this.lineNear = 14,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final ft = Radius.circular(farTop), fb = Radius.circular(farBottom);
    final t = Radius.circular(top), b = Radius.circular(bottom);
    var path = Path()
      ..addRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTRB(
            left ? -reach : 0,
            0,
            size.width + (left ? 0 : reach),
            size.height,
          ),
          topLeft: left ? t : ft,
          bottomLeft: left ? b : fb,
          topRight: left ? ft : t,
          bottomRight: left ? fb : b,
        ),
      );
    if (cut && reach > 0) {
      // the picture's centre is on the reached edge, halfway down
      path = Path.combine(
        PathOperation.difference,
        path,
        Path()..addOval(
          Rect.fromCircle(
            center: Offset(
              left ? -reach : size.width + reach,
              size.height / 2,
            ),
            radius: reach,
          ),
        ),
      );
    }
    canvas.drawPath(path, Paint()..color = color);
    final l = line;
    if (l != null) {
      final from = left ? lineNear : 4.0;
      final to = left ? size.width - 4 : size.width - lineNear;
      if (to > from) {
        canvas.drawRect(
          Rect.fromLTWH(from, 0, to - from, 0.8),
          Paint()..color = l,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant VibeBubblePainter old) =>
      old.color != color ||
      old.left != left ||
      old.top != top ||
      old.bottom != bottom ||
      old.farTop != farTop ||
      old.farBottom != farBottom ||
      old.reach != reach ||
      old.cut != cut ||
      old.line != line ||
      old.lineNear != lineNear;
}

/// One card per run: a person's text messages in a row share one card, as
/// wide as its widest message.
abstract class VibeCards {
  /// The newest message, when its sender is writing again right under it
  /// (their dots join its card): set by the typing indicator.
  static final continuing = ValueNotifier<String?>(null);

  static final _widths = <String, ValueNotifier<double>>{};

  /// The card's width as painted, by card (its oldest message).
  static ValueNotifier<double> width(String key) {
    if (_widths.length > 3000) _widths.clear();
    return _widths.putIfAbsent(key, () => ValueNotifier(0));
  }

  /// Text that sits in a card; photos, stickers, big emoji and cards don't.
  static bool inCard(Event? e, Timeline timeline) {
    if (e == null || e.type != EventTypes.Message) return false;
    if (VibeViewOnce.of(e) && !e.redacted) return false;
    final d = VibePq.open(e.getDisplayEvent(timeline));
    return d.type == EventTypes.Message &&
        const {
          MessageTypes.Text,
          MessageTypes.Notice,
          MessageTypes.Emote,
        }.contains(d.messageType) &&
        VibeLive.checkIn(d) == null &&
        !d.onlyEmotes &&
        VibeChunks.info(d) == null &&
        !VibeLinkPreview.onlyLink(d);
  }

  /// The card [e] is in, named by its oldest message: back through the
  /// shown messages while they're the same person's, close in time, in a
  /// card, and no reply starts a new one.
  static String keyOf(Event e, Timeline timeline) {
    final events = timeline.events;
    final i = events.indexWhere((x) => x.eventId == e.eventId);
    if (i < 0) return e.eventId;
    var cur = e;
    for (var j = i + 1; j < events.length; j++) {
      final older = events[j];
      if (!older.isVisibleInGui ||
          older.relationshipType == RelationshipTypes.thread) {
        continue;
      }
      if (cur.inReplyToEventId(includingFallback: false) != null ||
          older.senderId != cur.senderId ||
          !older.originServerTs.sameEnvironment(cur.originServerTs) ||
          !inCard(older, timeline)) {
        break;
      }
      cur = older;
    }
    return cur.eventId;
  }
}

/// Tells the card how wide this message is (as painted), after layout.
class _ReportWidth extends SingleChildRenderObjectWidget {
  final ValueNotifier<double>? card;
  final double extra;
  const _ReportWidth({required this.card, required this.extra, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderReportWidth(card, extra);

  @override
  void updateRenderObject(BuildContext context, _RenderReportWidth r) => r
    ..card = card
    ..extra = extra;
}

class _RenderReportWidth extends RenderProxyBox {
  _RenderReportWidth(this.card, this.extra);
  ValueNotifier<double>? card;
  double extra;

  @override
  void performLayout() {
    super.performLayout();
    final c = card;
    final w = size.width + extra;
    if (c != null && w > c.value + 0.5) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (w > c.value + 0.5) c.value = w;
      });
    }
  }
}

/// The text, then the time and ticks at the far edge: on the text's last
/// line when they fit beside it, under it otherwise. At least [minWidth]
/// wide, so the time sits at the card's edge.
class VibeTimeFlow extends MultiChildRenderObjectWidget {
  final double minWidth;
  VibeTimeFlow({
    required Widget content,
    required Widget trailing,
    this.minWidth = 0,
    super.key,
  }) : super(children: [content, trailing]);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderTimeFlow(minWidth);

  @override
  void updateRenderObject(BuildContext context, _RenderTimeFlow r) =>
      r.minWidth = minWidth;
}

class _TimeFlowData extends ContainerBoxParentData<RenderBox> {}

class _RenderTimeFlow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _TimeFlowData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _TimeFlowData> {
  _RenderTimeFlow(this._minWidth);
  static const _gap = 8.0;

  double _minWidth;
  set minWidth(double v) {
    if (v == _minWidth) return;
    _minWidth = v;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _TimeFlowData) child.parentData = _TimeFlowData();
  }

  Size _place(BoxConstraints c, Size text, Size time) {
    final inline = text.width + _gap + time.width <= c.maxWidth;
    final w = math.max(
      _minWidth,
      inline ? text.width + _gap + time.width : math.max(text.width, time.width),
    );
    final h = inline
        ? math.max(text.height, time.height)
        : text.height + time.height;
    return c.constrain(Size(w, h));
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final text = firstChild!, time = childAfter(text)!;
    final loose = BoxConstraints(maxWidth: constraints.maxWidth);
    return _place(constraints, text.getDryLayout(loose), time.getDryLayout(loose));
  }

  @override
  void performLayout() {
    final text = firstChild!, time = childAfter(text)!;
    final loose = BoxConstraints(maxWidth: constraints.maxWidth);
    text.layout(loose, parentUsesSize: true);
    time.layout(loose, parentUsesSize: true);
    size = _place(constraints, text.size, time.size);
    (text.parentData as _TimeFlowData).offset = Offset.zero;
    (time.parentData as _TimeFlowData).offset = Offset(
      size.width - time.size.width,
      size.height - time.size.height,
    );
  }

  @override
  double computeMinIntrinsicWidth(double height) => math.max(
    firstChild!.getMinIntrinsicWidth(height),
    childAfter(firstChild!)!.getMinIntrinsicWidth(height),
  );

  @override
  double computeMaxIntrinsicWidth(double height) =>
      firstChild!.getMaxIntrinsicWidth(height) +
      _gap +
      childAfter(firstChild!)!.getMaxIntrinsicWidth(height);

  @override
  double computeMinIntrinsicHeight(double width) =>
      firstChild!.getMinIntrinsicHeight(width) +
      childAfter(firstChild!)!.getMinIntrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) =>
      firstChild!.getMaxIntrinsicHeight(width) +
      childAfter(firstChild!)!.getMaxIntrinsicHeight(width);

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:vibe/utils/date_time_extension.dart';
import 'package:vibe/vibe/vibe_event_body.dart';
import 'package:vibe/vibe/vibe_mute.dart';
import 'package:vibe/l10n/l10n.dart';
import 'package:vibe/vibe/vibe_activity_pill.dart';
import 'package:vibe/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:vibe/vibe/vibe_chat_actions.dart';
import 'package:vibe/vibe/vibe_groups.dart';
import 'package:vibe/vibe/vibe_cascade.dart';
import 'package:vibe/vibe/vibe_motion.dart';
import 'package:vibe/vibe/vibe_palette.dart';
import 'package:vibe/vibe/vibe_view_once.dart';
import 'package:vibe/vibe/vibe_archive.dart';
import 'package:vibe/vibe/vibe_typing_pen.dart';
import 'package:vibe/widgets/avatar.dart';
import 'package:vibe/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

/// Middle pane: search, starred, DM list, invites, user card.
class VibeDmPane extends StatefulWidget {
  final List<Room> rooms;
  final String? activeRoomId;
  final void Function(Room room) onTap;
  final void Function(Room room) onOpen;

  /// The search field (the home screen's search button shows it).
  final bool showSearch;

  /// false: only direct chats. true: only groups and communities.
  final bool spacesMode;

  /// Communities, listed in [spacesMode]; tapping one calls [onSpace].
  final List<Room> spaces;
  final void Function(Room room)? onSpace;

  const VibeDmPane({
    required this.rooms,
    required this.activeRoomId,
    required this.onTap,
    required this.onOpen,
    this.showSearch = true,
    this.spacesMode = false,
    this.spaces = const [],
    this.onSpace,
    super.key,
  });

  @override
  State<VibeDmPane> createState() => _VibeDmPaneState();
}

class _VibeDmPaneState extends State<VibeDmPane> {
  final TextEditingController _filter = TextEditingController();

  /// Unread cards opened by hand while they're folded (more than 5 unread).
  final _opened = <String>{};

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final client = Matrix.of(context).client;
    final l10n = L10n.of(context);
    final q = _filter.text.trim().toLowerCase();

    String nameOf(Room r) =>
        r.getLocalizedDisplayname(MatrixLocals(l10n));

    // Chats: direct chats only. Spaces: groups and communities only.
    bool keep(Room r) =>
        widget.spacesMode ? VibeGroups.isGroup(r) : !VibeGroups.isGroup(r);
    final visible = widget.rooms
        .where((r) => keep(r))
        .where((r) => q.isEmpty || nameOf(r).toLowerCase().contains(q))
        .toList();
    final spaces = !widget.spacesMode
        ? const <Room>[]
        : widget.spaces
              .where((r) => q.isEmpty || nameOf(r).toLowerCase().contains(q))
              .toList();
    final invites = visible
        .where((r) => r.membership == Membership.invite)
        .toList();
    final joined = visible
        .where((r) => r.membership != Membership.invite)
        .toList();
    // pinned chats live in the row at the top, not in the list (unless
    // you're searching)
    final others = q.isEmpty
        ? joined.where((r) => !r.isFavourite).toList()
        : joined;
    // unread chats are cards on top; more than 5 fold to one line each
    final fresh = q.isEmpty
        ? joined.where((r) => r.isUnread).toList()
        : const <Room>[];
    final rest = q.isEmpty ? others.where((r) => !r.isUnread).toList() : others;
    final folded = fresh.length > 5;

    Widget dmTile(Room r, int index) => VibeStagger(
      key: ValueKey('dm_${r.id}'),
      index: index,
      child: VibePressable(
        scale: 0.97,
        child: _DmTile(
          room: r,
          name: nameOf(r),
          active: r.id == widget.activeRoomId,
          // the row opens the chat; the picture opens the person's page
          onTap: () => widget.onOpen(r),
          onAvatarTap: () => widget.onTap(r),
          onLongPress: () => VibeChatActions.show(
            context,
            r,
            onOpen: () => widget.onOpen(r),
          ),
        ),
      ),
    );

    return Material(
      color: Colors.transparent,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (widget.showSearch)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: TextField(
                controller: _filter,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Find a chat',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerLowest,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(
              // Built lazily: only rows on (or near) the screen exist, so a
              // long chat list scrolls and animates as lightly as a short one.
              // the list sits in one rounded panel
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
              child: Builder(
                builder: (context) {
                  final rows = <Widget Function()>[
                    if (invites.isNotEmpty) ...[
                      () => _SectionLabel('Invites'),
                      for (var i = 0; i < invites.length; i++)
                        () => VibeStagger(
                          key: ValueKey('inv_${invites[i].id}'),
                          index: i,
                          child: _InviteTile(
                            room: invites[i],
                            name: nameOf(invites[i]),
                            onTap: () => widget.onTap(invites[i]),
                          ),
                        ),
                    ],
                    if (spaces.isNotEmpty) ...[
                      () => const _SectionLabel('Communities'),
                      for (var i = 0; i < spaces.length; i++)
                        () => VibeStagger(
                          key: ValueKey('sp_${spaces[i].id}'),
                          index: i + invites.length + 1,
                          child: VibePressable(
                            scale: 0.97,
                            child: _DmTile(
                              room: spaces[i],
                              name: nameOf(spaces[i]),
                              active: false,
                              subtitle:
                                  '${VibeGroups.memberCount(spaces[i])} members',
                              onTap: () => widget.onSpace?.call(spaces[i]),
                              onAvatarTap: () => widget.onSpace?.call(spaces[i]),
                              onLongPress: () => VibeChatActions.show(
                                context,
                                spaces[i],
                                onOpen: () => widget.onSpace?.call(spaces[i]),
                              ),
                            ),
                          ),
                        ),
                    ],
                    for (var i = 0; i < fresh.length; i++)
                      () => VibeStagger(
                        key: ValueKey('new_${fresh[i].id}'),
                        index: i + invites.length + spaces.length,
                        child: _UnreadCard(
                          room: fresh[i],
                          name: nameOf(fresh[i]),
                          foldable: folded,
                          open: !folded || _opened.contains(fresh[i].id),
                          onToggle: () => setState(() {
                            if (!_opened.remove(fresh[i].id)) {
                              _opened.add(fresh[i].id);
                            }
                          }),
                          onOpen: () => widget.onOpen(fresh[i]),
                          onAvatarTap: () => widget.onTap(fresh[i]),
                          onLongPress: () => VibeChatActions.show(
                            context,
                            fresh[i],
                            onOpen: () => widget.onOpen(fresh[i]),
                          ),
                        ),
                      ),
                    // adding lives in the + tile above, not on each label
                    if (rest.isNotEmpty)
                      () => _SectionLabel(
                        widget.spacesMode ? 'All groups' : 'All chats',
                      ),
                    for (var i = 0; i < rest.length; i++)
                      () => dmTile(
                        rest[i],
                        i + fresh.length + invites.length + spaces.length + 1,
                      ),
                  ];
                  // every chat its own pill; the archive one more pill
                  // under them
                  // Chats <-> Spaces: the old rows leave as blocks, the
                  // new ones come in
                  return AnimatedSwitcher(
                    duration: const Duration(milliseconds: 560),
                    layoutBuilder: (current, previous) => Stack(
                      fit: StackFit.expand,
                      children: [...previous, ?current],
                    ),
                    transitionBuilder: vibeCascadeSwitch,
                    child: CustomScrollView(
                    key: ValueKey(widget.spacesMode),
                    cacheExtent: 600,
                    slivers: [
                      SliverList.builder(
                        itemCount: rows.length,
                        // each row a block: slides away when a chat opens
                        itemBuilder: (context, i) =>
                            VibeCascadeOut(child: rows[i]()),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            10,
                            10,
                            10,
                            20 + MediaQuery.paddingOf(context).bottom,
                          ),
                          child: VibeCascadeOut(
                          child: VibePressable(
                            child: Material(
                              color: theme.colorScheme.surfaceContainerLow
                                  .withValues(alpha: 0.88),
                              shape: const StadiumBorder(),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: () => VibeArchive.open(
                                  context,
                                  client,
                                  onOpen: widget.onOpen,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 14,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.archive_outlined,
                                        size: 20,
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 14),
                                      const Expanded(
                                        child: Text(
                                          'Archived chats',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      Icon(
                                        Icons.chevron_right_rounded,
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          )),
                        ),
                      ),
                    ],
                  ),
                  );
                },
              ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(26, 16, 16, 6),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 12,
        letterSpacing: 0.9,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

class _DmTile extends StatelessWidget {
  final Room room;
  final String name;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onAvatarTap;
  final VoidCallback onLongPress;

  /// Replaces the last-message line (a community's member count).
  final String? subtitle;

  const _DmTile({
    this.subtitle,
    required this.room,
    required this.name,
    required this.active,
    required this.onTap,
    required this.onAvatarTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final unread = room.isUnread;
    // the last message, or what kind of chat it is
    final preview = subtitle ?? _previewOf(context, room);
    // rows are flat: only the open chat is tinted, and unread chats are
    // cards above the list
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
      child: Material(
      color: active
          ? cs.secondaryContainer.withValues(alpha: 0.92)
          : Colors.transparent,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 16, 6),
          child: Row(
            children: [
              GestureDetector(
                onTap: onAvatarTap,
                child: VibeTypingOverlay(
                  room: room,
                  child: VibeMuteBadge(
                    room: room,
                    child: Avatar(
                      mxContent: room.avatar,
                      name: name,
                      size: 44,
                      client: room.client,
                      presenceUserId: room.directChatMatrixID,
                      hideOffline: true,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // the name takes the room, so every time lines up
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                        if (room.isFavourite) ...[
                          const SizedBox(width: 4),
                          Icon(Icons.push_pin, size: 13, color: cs.onSurfaceVariant),
                        ],
                        const SizedBox(width: 8),
                        Text(
                          room.latestEventReceivedTime.localizedTimeShort(context),
                          style: TextStyle(
                            fontSize: 12.5,
                            color: unread ? cs.primary : cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Expanded(
                          child: _PreviewText(
                            preview,
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 14.5,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                        VibeUnreadBadge(room: room),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }
}

class _InviteTile extends StatelessWidget {
  final Room room;
  final String name;
  final VoidCallback onTap;
  const _InviteTile({
    required this.room,
    required this.name,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        child: ListTile(
          onTap: onTap,
          contentPadding: const EdgeInsets.only(left: 10, right: 4),
          leading: Avatar(
            mxContent: room.avatar,
            name: name,
            size: 42,
            client: room.client,
            presenceUserId: room.directChatMatrixID,
          ),
          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: const Text('Wants to chat with you'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.close, color: Colors.redAccent),
                tooltip: 'Reject',
                onPressed: () async {
                  try {
                    await room.leave();
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text('$e')));
                    }
                  }
                },
              ),
              IconButton(
                icon: Icon(Icons.check, color: theme.colorScheme.onSurface),
                tooltip: 'Accept',
                onPressed: () async {
                  try {
                    await room.join();
                    if (context.mounted) context.go('/rooms/${room.id}');
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text('$e')));
                    }
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Starts a preview that is a reply (shown with a small reply icon).
const _replyMark = '\u2063';

/// A preview line; a reply gets a small reply icon in front.
class _PreviewText extends StatelessWidget {
  final String text;
  final int maxLines;
  final TextStyle style;
  const _PreviewText(this.text, {required this.maxLines, required this.style});

  @override
  Widget build(BuildContext context) {
    final you = text.startsWith('You: $_replyMark');
    final reply = you || text.startsWith(_replyMark);
    if (!reply) {
      return Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    final rest = text.replaceFirst(_replyMark, '');
    final size = (style.fontSize ?? 14) * 1.05;
    return Text.rich(
      TextSpan(
        children: [
          if (you) const TextSpan(text: 'You: '),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(Icons.reply_rounded, size: size, color: style.color),
            ),
          ),
          TextSpan(text: you ? rest.substring(5) : rest),
        ],
      ),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }
}

/// The last message as one clean line: your own starts with "You:", and a
/// reply to part of a message shows the answer, not the quoted words.
String _previewOf(BuildContext context, Room room) {
  final last = room.lastEvent;
  final group = VibeGroups.isGroup(room);
  if (last == null) {
    return group ? '${VibeGroups.memberCount(room)} members' : 'Encrypted chat';
  }
  if (VibeViewOnce.of(last) && !last.redacted) {
    return last.senderId == room.client.userID
        ? 'You: View once'
        : 'View once · tap to open';
  }
  var body = last.vibeBodyFallback(
    MatrixLocals(L10n.of(context)),
    hideReply: true,
    withSenderNamePrefix: group,
  );
  if (group) return body;
  if (body.startsWith('> ')) {
    final answer = body
        .split('\n')
        .skipWhile((l) => l.startsWith('> ') || l.trim().isEmpty)
        .join(' ')
        .trim();
    if (answer.isNotEmpty) body = '$_replyMark$answer';
  }
  return last.senderId == room.client.userID ? 'You: $body' : body;
}

/// An unread chat as a card: who, when and how many; the message in a
/// bubble; a box to answer right there. Folded (more than 5 unread) it's
/// one line with a round arrow that opens it.
class _UnreadCard extends StatefulWidget {
  final Room room;
  final String name;
  final bool foldable;
  final bool open;
  final VoidCallback onToggle;
  final VoidCallback onOpen;
  final VoidCallback onAvatarTap;
  final VoidCallback onLongPress;
  const _UnreadCard({
    required this.room,
    required this.name,
    required this.foldable,
    required this.open,
    required this.onToggle,
    required this.onOpen,
    required this.onAvatarTap,
    required this.onLongPress,
  });

  @override
  State<_UnreadCard> createState() => _UnreadCardState();
}

class _UnreadCardState extends State<_UnreadCard> {
  final _text = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final t = _text.text.trim();
    if (t.isEmpty || _sending) return;
    setState(() => _sending = true);
    _text.clear();
    try {
      await widget.room.sendTextEvent(t);
    } catch (_) {
      // not sent: give the words back
      if (mounted) _text.text = t;
    }
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    // the phone's colour theme when it has one, like the chat bubbles
    final wall = (dark ? VibePalette.wallDark : VibePalette.wallLight) ?? cs;
    final card = Color.alphaBlend(
      wall.primaryContainer,
      dark ? const Color(0xFF1B1B1F) : const Color(0xFFF1F1F4),
    );
    final ink = wall.onPrimaryContainer;
    final well = Color.alphaBlend(
      cs.surface,
      dark ? const Color(0xFF111318) : Colors.white,
    );
    final room = widget.room;
    final n = room.notificationCount;
    final typing = room.typingUsers.any((u) => u.id != room.client.userID);
    final empty = _text.text.trim().isEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: card,
        borderRadius: BorderRadius.circular(26),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onOpen,
          onLongPress: widget.onLongPress,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: widget.onAvatarTap,
                      child: Avatar(
                        mxContent: room.avatar,
                        name: widget.name,
                        size: 40,
                        client: room.client,
                        presenceUserId: room.directChatMatrixID,
                        presenceBackgroundColor: card,
                        hideOffline: true,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w700,
                          color: ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      room.latestEventReceivedTime.localizedTimeShort(context),
                      style: TextStyle(
                        fontSize: 12,
                        color: ink.withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      constraints: BoxConstraints(minWidth: n > 0 ? 20 : 10),
                      height: n > 0 ? 20 : 10,
                      padding: EdgeInsets.symmetric(horizontal: n > 0 ? 6 : 0),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: wall.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: n > 0
                          ? Text(
                              n > 99 ? '99+' : '$n',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: wall.onPrimary,
                              ),
                            )
                          : null,
                    ),
                    // folded: a round arrow opens the card
                    if (widget.foldable) ...[
                      const SizedBox(width: 8),
                      Material(
                        color: well,
                        shape: const CircleBorder(),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: widget.onToggle,
                          child: SizedBox.square(
                            dimension: 32,
                            child: AnimatedRotation(
                              turns: widget.open ? 0.5 : 0,
                              duration: const Duration(milliseconds: 240),
                              child: Icon(
                                Icons.expand_more_rounded,
                                size: 22,
                                color: cs.onSurface,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: !widget.open
                      ? const SizedBox(width: double.infinity)
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                padding: const EdgeInsets.fromLTRB(
                                  13,
                                  8,
                                  13,
                                  8,
                                ),
                                decoration: BoxDecoration(
                                  color: well,
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(6),
                                    topRight: Radius.circular(18),
                                    bottomLeft: Radius.circular(18),
                                    bottomRight: Radius.circular(18),
                                  ),
                                ),
                                child: _PreviewText(
                                  typing
                                      ? '••• typing'
                                      : _previewOf(context, room),
                                  maxLines: 3,
                                  style: TextStyle(
                                    fontSize: 14.5,
                                    height: 1.35,
                                    color: typing ? cs.primary : cs.onSurface,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: SizedBox(
                                    height: 38,
                                    child: TextField(
                                      controller: _text,
                                      onChanged: (_) => setState(() {}),
                                      onSubmitted: (_) => _send(),
                                      textInputAction: TextInputAction.send,
                                      textCapitalization:
                                          TextCapitalization.sentences,
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: cs.onSurface,
                                      ),
                                      decoration: InputDecoration(
                                        hintText: 'Reply…',
                                        isDense: true,
                                        filled: true,
                                        fillColor: well,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 9,
                                            ),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            19,
                                          ),
                                          borderSide: BorderSide.none,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: wall.primary,
                                    foregroundColor: wall.onPrimary,
                                    shape: const StadiumBorder(),
                                    minimumSize: const Size(0, 38),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                  ),
                                  onPressed: empty ? widget.onOpen : _send,
                                  child: Text(empty ? 'Open' : 'Send'),
                                ),
                              ],
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

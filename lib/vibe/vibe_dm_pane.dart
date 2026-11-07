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
import 'package:vibe/vibe/vibe_motion.dart';
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
    final pinned = joined.where((r) => r.isFavourite).toList();
    final others = joined.where((r) => !r.isFavourite).toList();

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
                    if (pinned.isNotEmpty) ...[
                      () => _SectionLabel('Pinned'),
                      for (var i = 0; i < pinned.length; i++)
                        () => dmTile(pinned[i], i + invites.length + 1),
                    ],
                    if (spaces.isNotEmpty) ...[
                      () => const _SectionLabel('Communities'),
                      for (var i = 0; i < spaces.length; i++)
                        () => VibeStagger(
                          key: ValueKey('sp_${spaces[i].id}'),
                          index: i + invites.length + pinned.length + 1,
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
                    // adding lives in the + tile above, not on each label
                    () => _SectionLabel(
                      widget.spacesMode ? 'Groups' : 'Direct messages',
                    ),
                    for (var i = 0; i < others.length; i++)
                      () => dmTile(
                        others[i],
                        i + invites.length + pinned.length + spaces.length + 1,
                      ),
                  ];
                  // every chat its own pill; the archive one more pill
                  // under them
                  return CustomScrollView(
                    cacheExtent: 600,
                    slivers: [
                      SliverList.builder(
                        itemCount: rows.length,
                        itemBuilder: (context, i) => rows[i](),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            10,
                            10,
                            10,
                            20 + MediaQuery.paddingOf(context).bottom,
                          ),
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
                          ),
                        ),
                      ),
                    ],
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
    padding: const EdgeInsets.fromLTRB(16, 22, 16, 8),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
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
    final last = room.lastEvent;
    // the last message, or what kind of chat it is
    final preview = subtitle ?? last?.vibeBodyFallback(
          MatrixLocals(L10n.of(context)),
          hideReply: true,
          withSenderNamePrefix: VibeGroups.isGroup(room),
        ) ??
        (VibeGroups.isGroup(room)
            ? '${VibeGroups.memberCount(room)} members'
            : 'Encrypted chat');
    // each chat is its own pill on the wallpaper (like the start pane's
    // rows), not one shared panel
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: Material(
      color: active
          ? cs.secondaryContainer.withValues(alpha: 0.92)
          : cs.surfaceContainerLow.withValues(alpha: 0.88),
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(9, 9, 20, 9),
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
                      size: 48,
                      client: room.client,
                      presenceUserId: room.directChatMatrixID,
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
                          child: Text(
                            preview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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

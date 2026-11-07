// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:vibe/vibe/vibe_palette.dart';
import 'package:vibe/vibe/vibe_dialog.dart';
import 'dart:async';

import 'package:vibe/l10n/l10n.dart';
import 'package:vibe/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:vibe/vibe/vibe_dm_detail.dart';
import 'package:vibe/vibe/vibe_groups.dart';
import 'package:vibe/vibe/vibe_threads.dart';
import 'package:vibe/vibe/vibe_tree.dart';
import 'package:vibe/vibe/vibe_user_sheet.dart';
import 'package:vibe/vibe/vibe_haptics.dart';
import 'package:vibe/vibe/vibe_motion.dart';
import 'package:vibe/vibe/vibe_settings_style.dart' hide VibeGroups;
import 'package:vibe/widgets/avatar.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/matrix.dart' as sdk show Visibility;

/// Communities are Matrix spaces: one place that holds several group chats
/// ("channels"), like a Discord server. They sit in the rail under your
/// groups; tapping one opens its channels in the middle pane.
abstract class VibeCommunities {
  /// Mute / unmute a community: every channel you're in, and the community.
  static Future<void> setMuted(Room space, bool muted) async {
    final state = muted ? PushRuleState.dontNotify : PushRuleState.notify;
    for (final c in space.spaceChildren) {
      final id = c.roomId;
      if (id == null) continue;
      final r = space.client.getRoomById(id);
      if (r == null || r.isSpace || r.membership != Membership.join) continue;
      if (r.pushRuleState != state) await r.setPushRuleState(state);
    }
    await space.setPushRuleState(state);
  }

  /// Ask Home to open a community (after creating or joining one).
  static final ValueNotifier<String?> select = ValueNotifier(null);

  static List<Room> joined(Client client) => client.rooms
      .where(
        (r) =>
            r.isSpace &&
            (r.membership == Membership.join ||
                r.membership == Membership.invite),
      )
      .toList();

  static Set<String> childIds(Room space) {
    if (!space.isSpace) return const {};
    return {
      for (final c in space.spaceChildren)
        if (c.roomId != null) c.roomId!,
    };
  }

  /// Rooms that live inside one of your communities: shown there instead of
  /// as their own rail icons.
  static Set<String> channelIds(Client client) => {
    for (final s in client.rooms)
      if (s.isSpace && s.membership == Membership.join) ...childIds(s),
  };

  /// Unread messages across a community's channels (for the rail badge).
  static int unread(Room space) {
    var n = 0;
    for (final id in childIds(space)) {
      final r = space.client.getRoomById(id);
      if (r != null && r.membership == Membership.join) {
        n += r.notificationCount;
      }
    }
    return n;
  }

  static Future<void> _waitFor(Client client, String id) async {
    if (client.getRoomById(id) != null) return;
    try {
      await client
          .waitForRoomInSync(id, join: true)
          .timeout(const Duration(seconds: 20));
    } on TimeoutException catch (_) {}
  }

  static Future<String> create(
    Client client, {
    required String name,
    required bool isPublic,
    String? alias,
    List<String> invite = const [],
    List<StateEvent> initialState = const [],
  }) async {
    final id = await client.createRoom(
      name: name,
      creationContent: {'type': RoomCreationTypes.mSpace},
      preset: isPublic
          ? CreateRoomPreset.publicChat
          : CreateRoomPreset.privateChat,
      visibility: isPublic ? sdk.Visibility.public : sdk.Visibility.private,
      roomAliasName: alias,
      invite: invite,
      initialState: initialState,
      // only admins post into the space room itself
      powerLevelContentOverride: {'events_default': 100},
    );
    await _waitFor(client, id);
    final space = client.getRoomById(id);
    if (space != null) {
      try {
        await createChannel(client, space, 'general', invite: invite);
      } catch (e, s) {
        Logs().w('Keepr: could not create #general', e, s);
      }
    }
    return id;
  }

  /// A new channel. In a private community it's end-to-end encrypted and
  /// anyone in the community can join it; in a public one anyone can.
  static Future<String> createChannel(
    Client client,
    Room space,
    String name, {
    List<String> invite = const [],
    bool voice = false,
  }) async {
    final isPublic = space.joinRules == JoinRules.public;
    final id = await client.createRoom(
      name: name,
      // voice channels are call rooms, the same kind Sable and Element use
      creationContent: voice ? {'type': _voiceRoomType} : null,
      preset: isPublic
          ? CreateRoomPreset.publicChat
          : CreateRoomPreset.privateChat,
      invite: invite.isEmpty ? null : invite,
      initialState: [
        if (!isPublic)
          StateEvent(
            type: EventTypes.RoomJoinRules,
            content: {
              'join_rule': 'restricted',
              'allow': [
                {'type': 'm.room_membership', 'room_id': space.id},
              ],
            },
          ),
        if (!isPublic)
          StateEvent(
            type: EventTypes.Encryption,
            content: {'algorithm': 'm.megolm.v1.aes-sha2'},
          ),
      ],
    );
    await space.setSpaceChild(id);
    return id;
  }

  static Future<void> newChannel(BuildContext context, Room space) async {
    final ctrl = TextEditingController();
    var voice = false;
    final name = await showVibeDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('New channel'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      avatar: const Icon(Icons.tag, size: 18),
                      label: const Text('Text'),
                      selected: !voice,
                      showCheckmark: false,
                      onSelected: (_) => setLocal(() => voice = false),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      avatar: const Icon(Icons.volume_up, size: 18),
                      label: const Text('Voice'),
                      selected: voice,
                      showCheckmark: false,
                      onSelected: (_) => setLocal(() => voice = true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: InputDecoration(
                  prefixText: voice ? '🔊 ' : '# ',
                  hintText: voice ? 'voice-chat' : 'channel-name',
                ),
                onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    if (name == null || name.isEmpty || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await createChannel(space.client, space, name, voice: voice);
      VibeHaptics.light();
      messenger.showSnackBar(
        SnackBar(content: Text(voice ? 'Created voice channel $name' : 'Created #$name')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  /// Put one of your existing groups into the community.
  static Future<void> addExisting(BuildContext context, Room space) async {
    final inside = childIds(space);
    final groups = space.client.rooms
        .where(
          (r) =>
              VibeGroups.isGroup(r) &&
              r.membership == Membership.join &&
              !inside.contains(r.id),
        )
        .toList();
    final t1 = VibeSettingsStyle.text(context);
    final t2 = VibeSettingsStyle.text2(context);
    final room = await showVibeSheet<Room>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: VibeSettingsStyle.page(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.7,
          ),
          child: groups.isEmpty
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  child: Text(
                    'You have no other groups to add.',
                    style: TextStyle(color: t2),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: groups.length,
                  itemBuilder: (ctx, i) {
                    final g = groups[i];
                    return ListTile(
                      leading: Avatar(
                        mxContent: g.avatar,
                        name: VibeGroups.nameOf(ctx, g),
                        size: 40,
                        client: g.client,
                      ),
                      title: Text(
                        VibeGroups.nameOf(ctx, g),
                        style: TextStyle(color: t1),
                      ),
                      subtitle: Text(
                        '${VibeGroups.memberCount(g)} members',
                        style: TextStyle(color: t2),
                      ),
                      onTap: () => Navigator.pop(ctx, g),
                    );
                  },
                ),
        ),
      ),
    );
    if (room == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await space.setSpaceChild(room.id);
      messenger.showSnackBar(
        SnackBar(content: Text('Added ${room.getLocalizedDisplayname()}')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}

/// One channel of a community, from the server's list or your own rooms.
class _Channel {
  final String id;
  final String name;
  final String? topic;
  final int members;
  final List<String> via;
  final bool voice;
  const _Channel({
    required this.id,
    required this.name,
    this.topic,
    this.members = 0,
    this.via = const [],
    this.voice = false,
  });
}

/// The middle pane for a community: its channels, then its settings.
class VibeCommunityPane extends StatefulWidget {
  final Room space;
  final VoidCallback onBack;
  final void Function(Room room) onOpenRoom;

  /// The chat open beside this pane, shown tinted in the list.
  final String? activeRoomId;
  const VibeCommunityPane({
    required this.space,
    required this.onBack,
    required this.onOpenRoom,
    this.activeRoomId,
    super.key,
  });

  @override
  State<VibeCommunityPane> createState() => _VibeCommunityPaneState();
}

class _VibeCommunityPaneState extends State<VibeCommunityPane> {
  /// 0: rooms, 1: threads, 2: people, 3: the community's settings (⋯).
  int _tab = 0;
  List<_Channel>? _remote;
  String? _joining;
  StreamSubscription? _sub;

  Room get space => widget.space;

  void _onThreads() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    VibeThreads.revision.addListener(_onThreads);
    _load();
    // channels added or removed elsewhere
    _sub = space.client.onSync.stream
        .where((s) {
          final u = s.rooms?.join?[space.id];
          if (u == null) return false;
          bool child(e) => e.type == EventTypes.SpaceChild;
          return (u.state?.any(child) ?? false) ||
              (u.timeline?.events?.any(child) ?? false);
        })
        .listen((_) => _load());
  }

  @override
  void dispose() {
    VibeThreads.revision.removeListener(_onThreads);
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (space.membership != Membership.join) return;
    try {
      final h = await space.client.getSpaceHierarchy(
        space.id,
        maxDepth: 1,
        limit: 100,
      );
      final via = {
        for (final c in space.spaceChildren)
          if (c.roomId != null) c.roomId!: c.via,
      };
      final list = [
        for (final r in h.rooms)
          if (r.roomId != space.id && r.roomType != RoomCreationTypes.mSpace)
            _Channel(
              id: r.roomId,
              name: r.name ?? r.canonicalAlias ?? 'channel',
              topic: r.topic,
              members: r.numJoinedMembers,
              via: via[r.roomId] ?? const [],
              voice: r.roomType == _voiceRoomType,
            ),
      ];
      if (mounted) setState(() => _remote = list);
    } catch (e) {
      Logs().w('Keepr: space hierarchy failed', e);
      if (mounted) setState(() => _remote ??= const []);
    }
  }

  List<_Channel> _channels(BuildContext context) {
    final out = <_Channel>[...?_remote];
    final known = out.map((c) => c.id).toSet();
    // channels you're already in that the server didn't list (yet)
    for (final c in space.spaceChildren) {
      final id = c.roomId;
      if (id == null || known.contains(id)) continue;
      final r = space.client.getRoomById(id);
      if (r == null || r.isSpace) continue;
      out.add(
        _Channel(
          id: id,
          name: VibeGroups.nameOf(context, r),
          members: VibeGroups.memberCount(r),
          via: c.via,
          voice: r.getState(EventTypes.RoomCreate)?.content['type'] == _voiceRoomType,
        ),
      );
    }
    return out;
  }

  Future<void> _open(_Channel c) async {
    final client = space.client;
    final local = client.getRoomById(c.id);
    if (local != null && local.membership == Membership.join) {
      widget.onOpenRoom(local);
      return;
    }
    setState(() => _joining = c.id);
    try {
      await client.joinRoom(c.id, via: c.via.isEmpty ? null : c.via);
      await VibeCommunities._waitFor(client, c.id);
      VibeHaptics.light();
      final r = client.getRoomById(c.id);
      if (r != null && mounted) {
        widget.onOpenRoom(r);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _joining = null);
    }
  }

  /// Long-press a channel: mute / unmute it, and (admins) remove it.
  Future<void> _channelMenu(_Channel c) async {
    final local = space.client.getRoomById(c.id);
    final joined = local != null && local.membership == Membership.join;
    final canRemove = space.canChangeStateEvent(EventTypes.SpaceChild);
    if (!joined && !canRemove) return;
    VibeHaptics.medium();
    final muted = joined && VibeMuteRow.isMuted(local);
    final action = await showVibeSheet<String>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      backgroundColor: VibeSettingsStyle.page(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                '#${c.name}',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: VibeSettingsStyle.text(ctx),
                ),
              ),
            ),
            if (joined)
              ListTile(
                leading: Icon(
                  muted
                      ? Icons.notifications_rounded
                      : Icons.notifications_off_rounded,
                ),
                title: Text(muted ? 'Unmute channel' : 'Mute channel'),
                onTap: () => Navigator.pop(ctx, 'mute'),
              ),
            if (canRemove)
              ListTile(
                leading: const Icon(
                  Icons.remove_circle_outline,
                  color: Color(0xFFDA373C),
                ),
                title: const Text(
                  'Remove from community',
                  style: TextStyle(color: Color(0xFFDA373C)),
                ),
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'mute' && local != null) {
      try {
        await VibeMuteRow.setMuted(local, !muted);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(muted ? 'Notifications on' : 'Muted #${c.name}'),
            ),
          );
          setState(() {});
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('$e')));
        }
      }
      return;
    }
    if (action != 'remove') return;
    final ok = await showVibeDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove #${c.name} from this community?'),
        content: const Text(
          'The chat itself stays; it just won\'t be listed here any more.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await space.removeSpaceChild(c.id);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _accept(bool join) async {
    try {
      if (join) {
        await space.join();
        VibeHaptics.medium();
        await _load();
      } else {
        await space.leave();
        widget.onBack();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _leave() async {
    final name = VibeGroups.nameOf(context, space);
    final ok = await showVibeDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Leave $name?'),
        content: const Text(
          'You\'ll stay in the channels you joined; you can leave them '
          'one by one.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Leave',
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await space.leave();
      widget.onBack();
      if (mounted) context.go('/rooms');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = cs.onSurfaceVariant;
    final name = space.getLocalizedDisplayname(MatrixLocals(L10n.of(context)));
    final invited = space.membership == Membership.invite;
    final isPublic = VibeGroups.isPublic(space);
    final canAdd = space.canChangeStateEvent(EventTypes.SpaceChild);
    final channels = _channels(context);
    final text = channels.where((c) => !c.voice).toList();
    final voice = channels.where((c) => c.voice).toList();
    final topic = space.topic;

    return Material(
      // full screen, no box: a tint over the wallpaper so the text
      // reads on light and dark wallpapers alike
      color: cs.surfaceContainerLow.withValues(alpha: 0.88),
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 120),
          children: [
            VibeTreeTop(
              onBack: widget.onBack,
              // the community's own settings
              onMore: invited ? null : () => setState(() => _tab = 3),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
              child: Row(
                children: [
                  GestureDetector(
                    onLongPress: space.canChangeStateEvent(EventTypes.RoomAvatar)
                        ? () => VibeGroupEdit.changePicture(context, space)
                        : null,
                    child: Avatar(
                      mxContent: space.avatar,
                      name: name,
                      size: 56,
                      client: space.client,
                      borderRadius: BorderRadius.circular(16),
                    ),
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
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.24,
                          ),
                        ),
                        Text(
                          '${VibeGroups.memberCount(space)} members · '
                          '${isPublic ? 'Public' : 'Private'}',
                          style: TextStyle(fontSize: 14, color: sub),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (topic.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                child: Text(
                  topic,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13.5, color: sub),
                ),
              ),
            if (!invited)
              // Rooms  Threads  People ............ Invite
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 6, 22, 2),
                child: Row(
                  children: [
                    for (final (i, label)
                        in const ['Rooms', 'Threads', 'People'].indexed)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setState(() => _tab = i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.only(right: 22),
                          padding: const EdgeInsets.only(bottom: 6),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: _tab == i
                                    ? cs.primary
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                          ),
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _tab == i ? cs.onSurface : sub,
                            ),
                          ),
                        ),
                      ),
                    const Spacer(),
                    if (space.canInvite)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => VibeGroups.showInvite(context, space),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            'Invite',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: cs.primary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            if (invited)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: _InviteBanner(name: name, onAnswer: _accept),
              )
            else if (_tab == 0) ...[
              VibeTreeSection(
                title: 'Channels',
                onAdd: canAdd
                    ? () => VibeCommunities.newChannel(context, space)
                    : null,
                children: [
                  if (_remote == null && channels.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator.adaptive()),
                    )
                  else if (channels.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      child: Text(
                        canAdd
                            ? 'No channels yet. Tap + to add one.'
                            : 'No channels yet.',
                        style: TextStyle(color: sub),
                      ),
                    ),
                  for (final c in text) ..._rows(context, c),
                  if (canAdd)
                    VibeTreeRow(
                      icon: Icons.add_rounded,
                      label: 'Add existing group',
                      onTap: () => VibeCommunities.addExisting(context, space),
                    ),
                ],
              ),
              if (voice.isNotEmpty)
                VibeTreeSection(
                  title: 'Voice',
                  children: [for (final c in voice) ..._rows(context, c)],
                ),
            ] else if (_tab == 1)
              ..._threads(context, channels)
            else if (_tab == 2)
              _people(context)
            else
              VibeTreeSection(
                title: 'Community',
                children: [
                  VibeTreeRow(
                    icon: Icons.group_outlined,
                    label: 'Members',
                    meta: '${VibeGroups.memberCount(space)}',
                    onTap: () => VibeGroups.showMembers(context, space),
                  ),
                  if (space.canInvite)
                    VibeTreeRow(
                      icon: Icons.person_add_alt_rounded,
                      label: 'Invite people',
                      onTap: () => VibeGroups.showInvite(context, space),
                    ),
                  if (space.canChangeStateEvent(EventTypes.RoomAvatar))
                    VibeTreeRow(
                      icon: Icons.image_outlined,
                      label: 'Community picture',
                      onTap: () => VibeGroupEdit.changePicture(context, space),
                    ),
                  if (space.canChangeStateEvent(EventTypes.RoomName))
                    VibeTreeRow(
                      icon: Icons.edit_outlined,
                      label: 'Rename community',
                      onTap: () => VibeGroups.rename(context, space),
                    ),
                  VibeTreeRow(
                    icon: isPublic ? Icons.public_rounded : Icons.lock_rounded,
                    label: 'Privacy',
                    meta: isPublic ? 'Public' : 'Private',
                    onTap: () => VibeGroupEdit.privacy(context, space),
                  ),
                  VibeTreeRow(
                    icon: Icons.logout_rounded,
                    label: 'Leave community',
                    onTap: _leave,
                  ),
                  if (VibeGroups.canDelete(space))
                    VibeTreeRow(
                      icon: Icons.delete_outline_rounded,
                      label: 'Delete community',
                      color: cs.error,
                      iconColor: cs.error,
                      onTap: () => VibeGroups.delete(context, space),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// A channel's row, and its open threads hanging under it.
  List<Widget> _rows(BuildContext context, _Channel c) {
    final found = space.client.getRoomById(c.id);
    final local = found != null && found.membership == Membership.join
        ? found
        : null;
    final label = VibeGroups.slug(
      local != null ? VibeGroups.nameOf(context, local) : c.name,
    );
    final threads = local == null ? const <String>[] : VibeThreads.ids(local.id);
    String? meta;
    Widget? trailing;
    if (_joining == c.id) {
      trailing = const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else if (local == null) {
      meta = 'Join';
    } else if (c.voice) {
      meta = 'Voice';
    } else if (threads.isNotEmpty) {
      meta = threads.length == 1 ? '1 thread' : '${threads.length} threads';
    }
    return [
      VibeTreeRow(
        key: ValueKey(c.id),
        icon: c.voice ? Icons.music_note_rounded : Icons.tag_rounded,
        label: label.isEmpty ? 'channel' : label,
        meta: meta,
        unread: local?.notificationCount ?? 0,
        bold: local?.isUnread ?? false,
        selected: local != null && local.id == widget.activeRoomId,
        trailing: trailing,
        onTap: () => _open(c),
        onLongPress: () => _channelMenu(c),
      ),
      if (local != null)
        for (final id in threads)
          FutureBuilder<Event?>(
            key: ValueKey('${c.id}/$id'),
            future: local.getEventById(id),
            builder: (context, snap) => VibeTreeRow(
              nested: true,
              icon: Icons.subdirectory_arrow_right_rounded,
              label: VibeThreads.nameOf(local.id, id, snap.data),
              onTap: () {
                VibeThreads.openNext(local.id, id);
                widget.onOpenRoom(local);
              },
            ),
          ),
    ];
  }

  /// Threads tab: every open thread, under its channel.
  List<Widget> _threads(BuildContext context, List<_Channel> channels) {
    final out = <Widget>[];
    for (final c in channels) {
      final r = space.client.getRoomById(c.id);
      if (r == null || r.membership != Membership.join) continue;
      final ids = VibeThreads.ids(r.id);
      if (ids.isEmpty) continue;
      out.add(
        VibeTreeSection(
          key: ValueKey('threads/${r.id}'),
          title: VibeGroups.slug(VibeGroups.nameOf(context, r)),
          children: [
            for (final id in ids)
              FutureBuilder<Event?>(
                future: r.getEventById(id),
                builder: (context, snap) => VibeTreeRow(
                  icon: VibeThreads.icon,
                  label: VibeThreads.nameOf(r.id, id, snap.data),
                  onTap: () {
                    VibeThreads.openNext(r.id, id);
                    widget.onOpenRoom(r);
                  },
                ),
              ),
          ],
        ),
      );
    }
    if (out.isEmpty) {
      out.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 8),
          child: Text(
            'No open threads yet.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return out;
  }

  /// People tab: the members this device knows about, then everyone.
  Widget _people(BuildContext context) {
    final users = space.getParticipants();
    return VibeTreeSection(
      title: 'Members',
      note: '${VibeGroups.memberCount(space)}',
      children: [
        for (final u in users.take(50))
          VibeTreeRow(
            leading: Avatar(
              mxContent: u.avatarUrl,
              name: u.calcDisplayname(),
              size: 22,
              client: space.client,
            ),
            label: u.calcDisplayname(),
            onTap: () => VibeUserSheet.show(
              context,
              client: space.client,
              userId: u.id,
              displayName: u.calcDisplayname(),
              avatarUrl: u.avatarUrl,
            ),
          ),
        VibeTreeRow(
          icon: Icons.group_outlined,
          label: 'See everyone',
          onTap: () => VibeGroups.showMembers(context, space),
        ),
      ],
    );
  }
}

class _InviteBanner extends StatelessWidget {
  final String name;
  final Future<void> Function(bool join) onAnswer;
  const _InviteBanner({required this.name, required this.onAnswer});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'You\'re invited to $name',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => onAnswer(false),
                      child: const Text('Decline'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: VibePalette.accent,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => onAnswer(true),
                      child: const Text('Join'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Voice channels (call rooms, the kind Sable and Element make); they open as chats now.
const _voiceRoomType = 'org.matrix.msc3417.call';

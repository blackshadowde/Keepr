// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:vibe/vibe/vibe_glass.dart';
import 'package:vibe/vibe/screens/chat_list/chat_list.dart';
import 'package:vibe/utils/stream_extension.dart';
import 'package:vibe/vibe/vibe_archive.dart';
import 'package:vibe/vibe/vibe_chat_actions.dart';
import 'package:vibe/vibe/vibe_communities.dart';
import 'package:vibe/vibe/vibe_lock.dart';
import 'package:vibe/vibe/vibe_dm_detail.dart';
import 'package:vibe/vibe/vibe_dm_pane.dart';
import 'package:vibe/widgets/avatar.dart';
import 'package:vibe/vibe/vibe_groups.dart';
import 'package:vibe/vibe/vibe_start_pane.dart';
import 'package:vibe/vibe/vibe_swipe.dart';
import 'package:vibe/vibe/vibe_user_bar.dart';
import 'package:vibe/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

/// Discord-style home: [rail of DM avatars] | [Home list or selected DM].
class VibeHomeView extends StatefulWidget {
  final ChatListController controller;
  const VibeHomeView(this.controller, {super.key});

  @override
  State<VibeHomeView> createState() => _VibeHomeViewState();
}

class _VibeHomeViewState extends State<VibeHomeView> {
  /// The rail's "+" pane (Start something).
  static const _startId = '+start';
  bool _search = false;
  String? selectedId;
  String? _lastOpenedId;

  bool _dragging = false;
  double _progress = 0;
  double _width = 400;
  AnimationController? _ctl;
  NavigatorState? _nav;
  GoRouter? _router;
  List<Room> _rooms = const [];

  void _onLockChange() {
    if (mounted) setState(() {});
  }

  /// A community was just created or joined: open its pane.
  void _onSelectCommunity() {
    final id = VibeCommunities.select.value;
    if (id == null || !mounted) return;
    VibeCommunities.select.value = null;
    setState(() => selectedId = id);
  }

  @override
  void initState() {
    super.initState();
    VibeLock.changes.addListener(_onLockChange);
    VibeCommunities.select.addListener(_onSelectCommunity);
  }

  @override
  void dispose() {
    VibeLock.changes.removeListener(_onLockChange);
    VibeCommunities.select.removeListener(_onSelectCommunity);
    VibeSwipe.reset();
    super.dispose();
  }

  String? _targetId() {
    final id = selectedId ?? widget.controller.activeChat ?? _lastOpenedId;
    if (id == null) return null;
    for (final r in _rooms) {
      if (r.id == id && r.membership == Membership.join) return id;
    }
    return null;
  }

  void _onRoute(PageRoute<dynamic> route) {
    final c = route.controller;
    if (c == null) return;
    _ctl = c;
    _nav = route.navigator;
    c.stop();
    c.value = _progress;
    _nav?.didStartUserGesture();
    if (!_dragging) _settle(0);
  }

  void _dragUpdate(DragUpdateDetails d) {
    if (!_dragging) {
      if (_busy || d.delta.dx >= 0) return;
      final id = _targetId();
      if (id == null) return;
      _dragging = true;
      _busy = true;
      _progress = 0;
      _ctl = null;
      _nav = null;
      _router = GoRouter.of(context);
      _width = MediaQuery.sizeOf(context).width;
      _lastOpenedId = id;
      VibeSwipe.pending = true;
      VibeSwipe.onRoute = _onRoute;
      _router!.go('/rooms/$id');
    }
    _progress = (_progress - d.delta.dx / _width).clamp(0.0, 1.0);
    _ctl?.value = _progress;
  }

  bool _busy = false;

  void _dragEnd(DragEndDetails d) {
    if (!_dragging) return;
    _dragging = false;
    _settle(d.primaryVelocity ?? 0);
  }

  /// Finish the gesture: spring the real route animation open or shut.
  Future<void> _settle(double v) async {
    final c = _ctl;
    if (c == null) {
      // the route has not started yet; _onRoute settles it when it does
      Future<void>.delayed(const Duration(seconds: 2), () {
        if (_ctl == null) {
          VibeSwipe.reset();
          _busy = false;
          _router?.go('/rooms');
        }
      });
      return;
    }
    final commit = v < -500 || (c.value > 0.35 && v < 500);
    try {
      await c.animateWith(
        SpringSimulation(
          SpringDescription.withDampingRatio(
            mass: 1,
            stiffness: 420,
            ratio: 1,
          ),
          c.value,
          commit ? 1.0 : 0.0,
          -v / _width,
        ),
      );
    } catch (_) {}
    _nav?.didStopUserGesture();
    if (!commit) _router?.go('/rooms');
    _ctl = null;
    _nav = null;
    _busy = false;
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final client = Matrix.of(context).client;
    return PopScope(
      canPop: selectedId == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => selectedId = null);
      },
      child: _RoomListBuilder(
        key: ValueKey(client.userID.toString()),
        client: client,
        builder: (context) {
          final rooms = VibeChatActions.pinnedFirst(
            client.rooms
                .where(
                  (r) =>
                      !r.isSpace &&
                      !VibeLock.isLocked(r.id) &&
                      !VibeArchive.hidden(r) &&
                      (r.membership == Membership.join ||
                          r.membership == Membership.invite),
                )
                .toList(),
          );
          _rooms = rooms;
          // Communities sit in the rail; their channels live inside them.
          final spaces = VibeCommunities.joined(client);
          final channels = VibeCommunities.channelIds(client);
          final railRooms = [
            ...rooms.where(
              (r) =>
                  !VibeGroups.isGroup(r) ||
                  r.isFavourite ||
                  r.membership == Membership.invite ||
                  !channels.contains(r.id),
            ),
            ...spaces,
          ];
          Room? selected;
          for (final r in [...rooms, ...spaces]) {
            if (r.id == selectedId) selected = r;
          }
          final theme = Theme.of(context);
          return GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragUpdate: _dragUpdate,
            onHorizontalDragEnd: _dragEnd,
            onHorizontalDragCancel: () => _dragEnd(DragEndDetails()),
            child: ColoredBox(
            color: theme.colorScheme.surfaceContainerLowest,
            child: Stack(
              children: [
                // chats and communities in a row across the top, the pane
                // under it
                Column(
                  children: [
                    // home: the title, search and new chat, then the
                    // communities as tiles (hidden while one is open)
                    if (selectedId == null)
                      _HomeTop(
                        spaces: railRooms.where((r) => r.isSpace).toList(),
                        onSearch: () => setState(() => _search = !_search),
                        onCompose: () => VibeGroups.showNew(context),
                        onSelect: (room) => setState(() => selectedId = room.id),
                        onAdd: () => setState(() => selectedId = _startId),
                        onLongPress: (room) => VibeChatActions.show(
                          context,
                          room,
                          onOpen: () => setState(() => selectedId = room.id),
                        ),
                      ),
                    Expanded(
                      // the row above already keeps clear of the status bar
                      child: MediaQuery.removePadding(
                        context: context,
                        removeTop: selectedId == null,
                      // glossy glass: a floating, frosted pane with edges
                      child: VibeGlassPane(
                        plainRadius: const BorderRadius.vertical(
                          top: Radius.circular(24),
                        ),
                        child: selectedId == _startId
                            ? VibeStartPane(
                                onBack: () => setState(() => selectedId = null),
                              )
                            : selected == null
                            ? VibeDmPane(
                                showSearch: _search,
                                rooms: rooms,
                                activeRoomId: controller.activeChat,
                                onTap: (room) =>
                                    setState(() => selectedId = room.id),
                                onOpen: (room) {
                                  _lastOpenedId = room.id;
                                  controller.onChatTap(room);
                                },
                              )
                            : selected.isSpace
                            ? VibeCommunityPane(
                                key: ValueKey(selected.id),
                                space: selected,
                                onBack: () => setState(() => selectedId = null),
                                onOpenRoom: (room) {
                                  _lastOpenedId = room.id;
                                  controller.onChatTap(room);
                                },
                              )
                            : VibeDmDetail(
                                key: ValueKey(selected.id),
                                room: selected,
                                onBack: () => setState(() => selectedId = null),
                                onOpenChat: () {
                                  _lastOpenedId = selected!.id;
                                  controller.onChatTap(selected);
                                },
                              ),
                      ),
                      ),
                    ),
                  ],
                ),
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: VibeUserBar(),
                ),
              ],
            ),
            ),
          );
        },
      ),
    );
  }
}

/// Rebuilds the home screen only when something it shows changed (order,
/// unread counts, names, pictures, last messages, invites), not on every
/// sync. Keeps animations and scrolling free of needless rebuilds.
class _RoomListBuilder extends StatefulWidget {
  final Client client;
  final WidgetBuilder builder;
  const _RoomListBuilder({
    required this.client,
    required this.builder,
    super.key,
  });

  @override
  State<_RoomListBuilder> createState() => _RoomListBuilderState();
}

class _RoomListBuilderState extends State<_RoomListBuilder> {
  StreamSubscription? _sub;
  int _sig = 0;

  int _signature() {
    var h = widget.client.rooms.length;
    for (final r in widget.client.rooms) {
      h = Object.hash(
        h,
        r.id,
        r.membership,
        r.notificationCount,
        r.highlightCount,
        r.isFavourite,
        VibeArchive.isArchived(r),
        r.lastEvent?.eventId,
        r.lastEvent?.status,
        r.lastEvent?.body,
        r.avatar,
        r.getLocalizedDisplayname(),
        r.isUnreadOrInvited,
        r.joinRules,
        r.isSpace ? r.spaceChildren.length : 0,
      );
    }
    return h;
  }

  @override
  void initState() {
    super.initState();
    _sig = _signature();
    _sub = widget.client.onSync.stream
        .where((s) => s.hasRoomUpdate)
        .rateLimit(const Duration(milliseconds: 500))
        .listen((_) {
          final sig = _signature();
          if (sig == _sig || !mounted) return;
          _sig = sig;
          setState(() {});
        });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}


/// The top of the home screen: "Chats" with search and new chat, then the
/// communities as tiles (Direct first, + last).
class _HomeTop extends StatelessWidget {
  final List<Room> spaces;
  final VoidCallback onSearch;
  final VoidCallback onCompose;
  final VoidCallback onAdd;
  final void Function(Room room) onSelect;
  final void Function(Room room) onLongPress;
  const _HomeTop({
    required this.spaces,
    required this.onSearch,
    required this.onCompose,
    required this.onAdd,
    required this.onSelect,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget tile({required Widget child, Color? color, VoidCallback? onTap, VoidCallback? onHold, bool dot = false, String? label}) =>
        Padding(
          padding: const EdgeInsets.only(right: 10),
          child: Semantics(
            label: label,
            button: true,
            child: GestureDetector(
              onTap: onTap,
              onLongPress: onHold,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: color ?? cs.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: child,
                  ),
                  if (dot)
                    Positioned(
                      top: -2,
                      right: -2,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: cs.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: cs.surfaceContainerLowest, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 8, 6),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Chats',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.4),
                  ),
                ),
                IconButton(
                  tooltip: 'Search',
                  icon: const Icon(Icons.search),
                  onPressed: onSearch,
                ),
                IconButton(
                  tooltip: 'New chat or group',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: onCompose,
                ),
              ],
            ),
          ),
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(20, 4, 10, 4),
              children: [
                tile(
                  label: 'Chats',
                  color: cs.primary,
                  child: Icon(Icons.chat_bubble_outline_rounded, color: cs.onPrimary),
                ),
                for (final s in spaces)
                  tile(
                    label: s.getLocalizedDisplayname(),
                    onTap: () => onSelect(s),
                    onHold: () => onLongPress(s),
                    dot: VibeCommunities.unread(s) > 0 ||
                        s.membership == Membership.invite,
                    child: Avatar(
                      mxContent: s.avatar,
                      name: s.getLocalizedDisplayname(),
                      size: 48,
                      client: s.client,
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                tile(
                  label: 'Join or create a community',
                  onTap: onAdd,
                  color: Colors.transparent,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: cs.outline),
                    ),
                    child: Icon(Icons.add, color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

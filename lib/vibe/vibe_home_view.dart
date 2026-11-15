// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:vibe/vibe/buddy/bujji_home.dart';
import 'package:vibe/vibe/vibe_glass.dart';
import 'package:vibe/vibe/screens/chat_list/chat_list.dart';
import 'package:vibe/utils/stream_extension.dart';
import 'package:vibe/vibe/vibe_archive.dart';
import 'package:vibe/vibe/vibe_chat_actions.dart';
import 'package:vibe/vibe/vibe_communities.dart';
import 'package:vibe/vibe/vibe_cascade.dart';
import 'package:vibe/vibe/vibe_lock.dart';
import 'package:vibe/vibe/vibe_motion.dart';
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

  /// false: the list shows direct chats; true: groups and communities.
  bool _spacesMode = false;

  /// "Chats" / "Spaces" shown in the profile bar for a moment after
  /// switching, then your name again.
  String? _flash;
  Timer? _flashTimer;

  void _setMode(bool spaces) {
    _flashTimer?.cancel();
    setState(() {
      _spacesMode = spaces;
      _flash = spaces ? 'Spaces' : 'Chats';
    });
    _flashTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _flash = null);
    });
  }
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
    _flashTimer?.cancel();
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
    if (!_dragging && selectedId != null && d.delta.dx > 0) {
      _back += d.delta.dx;
      return;
    }
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

  /// How far a right swipe has gone on a middle pane.
  double _back = 0;

  void _dragEnd(DragEndDetails d) {
    final back = _back;
    _back = 0;
    if (!_dragging) {
      if (selectedId != null &&
          (back > 80 || (back > 20 && (d.primaryVelocity ?? 0) > 400))) {
        setState(() => selectedId = null);
      }
      return;
    }
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
          // Communities are listed under Spaces; their channels live inside
          // them, not in the list.
          final spaces = VibeCommunities.joined(client);
          final channels = VibeCommunities.channelIds(client);
          final listRooms = rooms
              .where(
                (r) =>
                    !VibeGroups.isGroup(r) ||
                    r.isFavourite ||
                    r.membership == Membership.invite ||
                    !channels.contains(r.id),
              )
              .toList();
          // the rail: pinned chats and channels (unread ones are cards in the
          // list)
          final quick = <Room>[];
          void add(Room r) {
            if (quick.length < 14 && !quick.contains(r)) quick.add(r);
          }
          final joinedRooms = rooms.where(
            (r) => r.membership == Membership.join,
          );
          bool unread(Room r) => r.notificationCount > 0 || r.markedUnread;
          final chatsUnread = joinedRooms
              .where((r) => !VibeGroups.isGroup(r) && unread(r))
              .length;
          final spacesUnread =
              joinedRooms.where((r) => VibeGroups.isGroup(r) && unread(r)).length;
          for (final r in joinedRooms.where((r) => r.isFavourite)) {
            add(r);
          }
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
                        quick: quick,
                        chatsUnread: chatsUnread,
                        spacesUnread: spacesUnread,
                        spacesMode: _spacesMode,
                        flash: _flash,
                        onMode: _setMode,
                        onOpenChat: (room) {
                          _lastOpenedId = room.id;
                          controller.onChatTap(room);
                        },
                        onSearch: () => setState(() => _search = !_search),
                        onAdd: () => setState(() => selectedId = _startId),
                        onLongPress: (room) => VibeChatActions.show(
                          context,
                          room,
                          onOpen: () => setState(() => selectedId = room.id),
                        ),
                        onLockedChats: () => VibeLock.openFolder(
                          context,
                          client,
                          controller.onChatTap,
                        ),
                      ),
                    Expanded(
                      // the row above already keeps clear of the status bar
                      child: MediaQuery.removePadding(
                        context: context,
                        removeTop: selectedId == null,
                      // glossy glass: a floating, frosted pane with edges
                      child: VibeGlassPane(
                        // full screen: no window frame or rounded edge
                        frame: false,
                        child: ClipRect(
                        child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 560),
                        // the list's rows leave as blocks, then the person
                        // or community pane's sections come in (and back)
                        layoutBuilder: (current, previous) => Stack(
                          fit: StackFit.expand,
                          children: [...previous, ?current],
                        ),
                        // the start pane has no rows of blocks: it fades
                        transitionBuilder: (child, animation) =>
                            child.key == const ValueKey(_startId)
                            ? FadeTransition(opacity: animation, child: child)
                            : vibeCascadeSwitch(child, animation),
                        child: selectedId == _startId
                            ? VibeStartPane(
                                key: const ValueKey(_startId),
                                onBack: () => setState(() => selectedId = null),
                              )
                            : selected == null
                            ? VibeDmPane(
                                key: const ValueKey('list'),
                                showSearch: _search,
                                spacesMode: _spacesMode,
                                spaces: spaces,
                                onSpace: (room) =>
                                    setState(() => selectedId = room.id),
                                rooms: listRooms,
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
                                activeRoomId: controller.activeChat,
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
                      ),
                    ),
                  ],
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
  /// Pinned, unread and recent chats for the rail.
  final List<Room> quick;

  /// Unread direct chats, and unread groups / channels / communities.
  final int chatsUnread;
  final int spacesUnread;
  final bool spacesMode;
  final ValueChanged<bool> onMode;
  final void Function(Room room) onOpenChat;
  final VoidCallback onSearch;
  final String? flash;
  final VoidCallback onAdd;
  final void Function(Room room) onLongPress;
  final VoidCallback onLockedChats;
  const _HomeTop({
    required this.quick,
    required this.chatsUnread,
    required this.spacesUnread,
    required this.spacesMode,
    required this.onMode,
    required this.onOpenChat,
    required this.onSearch,
    required this.flash,
    required this.onAdd,
    required this.onLongPress,
    required this.onLockedChats,
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
    // Material: the app's font and colours for the title (without it Flutter
    // shows its red, underlined fallback text)
    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // your profile bar sits on top: name (or "Chats" / "Spaces" for
          // a moment after switching), search and settings
          VibeUserRow(flash: flash, onSearch: onSearch),
          // Chats / Spaces with their unread counts, + at the end
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
            child: Row(
              children: [
                _ModePill(
                  chatsUnread: chatsUnread,
                  spacesUnread: spacesUnread,
                  spaces: spacesMode,
                  onChange: onMode,
                  onHold: onLockedChats,
                ),
                const Spacer(),
                // Bujji: its notes and reminders, and a face that follows
                // your inbox and the clock
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: BujjiHome(unread: chatsUnread),
                ),
                Semantics(
                  label: 'Join or create a community',
                  button: true,
                  child: Material(
                    color: cs.surfaceContainerHigh,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: onAdd,
                      child: SizedBox.square(
                        dimension: 44,
                        child: Icon(Icons.add_rounded, color: cs.onSurface),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // birthdays and reminders Bujji has for today
          const BujjiToday(),
          // pinned chats as pictures, when there are any
          if (quick.isNotEmpty)
            SizedBox(
              height: 56,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 4, 10, 4),
                children: [
                  for (final r in quick)
                    tile(
                      label: r.getLocalizedDisplayname(),
                      onTap: () => onOpenChat(r),
                      onHold: () => onLongPress(r),
                      dot: r.notificationCount > 0 || r.markedUnread,
                      color: Colors.transparent,
                      child: Avatar(
                        mxContent: r.avatar,
                        name: r.getLocalizedDisplayname(),
                        size: 48,
                        client: r.client,
                        presenceUserId: r.directChatMatrixID,
                        hideOffline: true,
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 6),
        ],
      ),
      ),
    );
  }
}

/// The rail's first tile: Chats or Spaces. Tap it and it grows into a pill
/// with both, pick one and it folds back. Hold it for locked chats.
class _ModePill extends StatefulWidget {
  final bool spaces;
  final ValueChanged<bool> onChange;
  final VoidCallback onHold;
  final int chatsUnread;
  final int spacesUnread;
  const _ModePill({
    required this.chatsUnread,
    required this.spacesUnread,
    required this.spaces,
    required this.onChange,
    required this.onHold,
  });

  @override
  State<_ModePill> createState() => _ModePillState();
}

class _ModePillState extends State<_ModePill> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget seg(bool sp) {
      final on = sp == widget.spaces;
      final n = sp ? widget.spacesUnread : widget.chatsUnread;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: VibePressable(
          scale: 0.94,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onChange(sp),
            onLongPress: sp ? null : widget.onHold,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(
                color: on ? cs.primary : cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    sp ? 'Spaces' : 'Chats',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: on ? FontWeight.w700 : FontWeight.w600,
                      color: on ? cs.onPrimary : cs.onSurfaceVariant,
                    ),
                  ),
                  // how many of each are unread
                  if (n > 0) ...[
                    const SizedBox(width: 8),
                    _Count(n, inverted: on),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [seg(false), seg(true)],
    );
  }
}

/// A small unread count: red, or white on the selected segment.
class _Count extends StatelessWidget {
  final int n;
  final bool inverted;
  const _Count(this.n, {this.inverted = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 18),
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: inverted ? cs.onPrimary : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        n > 99 ? '99+' : '$n',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: inverted ? cs.primary : cs.onSurface,
        ),
      ),
    );
  }
}

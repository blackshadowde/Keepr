// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;

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
import 'package:vibe/vibe/buddy/vibe_buddy.dart';
import 'package:vibe/vibe/vibe_haptics.dart';
import 'package:vibe/vibe/vibe_own_profile.dart';
import 'package:vibe/vibe/vibe_profile_cache.dart';
import 'package:vibe/widgets/matrix.dart';
import 'package:vibe/vibe/vibe_live_map.dart';
import 'package:vibe/vibe/buddy/bujji_life.dart';
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
          // one quiet line: your picture, the page's name (tap it to switch
          // between Chats and Spaces, hold it for locked chats; Bujji sits
          // on it holding up how many chats are unread), search, new chat
          _QuietTop(
            spaces: spacesMode,
            chatsUnread: chatsUnread,
            spacesUnread: spacesUnread,
            onMode: onMode,
            onHold: onLockedChats,
            onSearch: onSearch,
            onAdd: onAdd,
          ),
          // sharing your live location (or a check-in): who with, Stop
          const VibeLiveBar(),
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

/// The top line of home: your picture (your profile), "Chats" or "Spaces"
/// (tap for the switch), search and new chat.
class _QuietTop extends StatelessWidget {
  final bool spaces;
  final int chatsUnread;
  final int spacesUnread;
  final ValueChanged<bool> onMode;
  final VoidCallback onHold;
  final VoidCallback onSearch;
  final VoidCallback onAdd;
  const _QuietTop({
    required this.spaces,
    required this.chatsUnread,
    required this.spacesUnread,
    required this.onMode,
    required this.onHold,
    required this.onSearch,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final client = Matrix.of(context).client;
    // round buttons squeeze a little under the finger
    Widget round(IconData icon, String tip, Color bg, Color fg, VoidCallback onTap) => Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Tooltip(
        message: tip,
        child: VibePressable(
          scale: 0.9,
          child: Material(
          color: bg,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox.square(dimension: 44, child: Icon(icon, color: fg)),
          ),
        ),
        ),
      ),
    );
    void pick(BuildContext title) {
      final box = title.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      final at = box.localToGlobal(Offset.zero) & box.size;
      _ModeSwitch.open(context, at, spaces, chatsUnread, spacesUnread, onMode);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 6),
      child: Row(
        children: [
          BujjiSpot(
            id: 'tour.profile',
            child: VibeOwnProfileBuilder(
              client: client,
              builder: (context, profile) => Avatar(
                mxContent: profile?.avatarUrl,
                name: profile?.displayName ?? client.userID?.localpart ?? '',
                size: 40,
                client: client,
                onTap: () => VibeOwnProfile.show(context, client),
                presenceUserId: client.userID,
                presenceBackgroundColor: cs.surfaceContainerLowest,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Semantics(
                    button: true,
                    label: spaces ? 'Spaces, switch to Chats' : 'Chats, switch to Spaces',
                    child: Builder(
                      builder: (title) => GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => pick(title),
                      onLongPress: onHold,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 240),
                        transitionBuilder: (child, a) => FadeTransition(
                          opacity: a,
                          child: SlideTransition(
                            position: Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(a),
                            child: child,
                          ),
                        ),
                        child: Text(
                          spaces ? 'Spaces' : 'Chats',
                          key: ValueKey(spaces),
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: cs.onSurface,
                            height: 1.1,
                          ),
                        ),
                      ),
                    ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // Bujji sits on the name, holding up the unread count
                _BujjiBoard(n: chatsUnread, spaces: spaces),
              ],
            ),
          ),
          round(Icons.search_rounded, 'Search', cs.surfaceContainerHigh, cs.onSurface, onSearch),
          round(Icons.edit_rounded, 'New chat', cs.primaryContainer, cs.onPrimaryContainer, onAdd),
        ],
      ),
    );
  }
}

/// Bujji with a little board of how many chats are unread ("3 new", or "3
/// chats" while you look at Spaces). With Bujji off, just the count.
class _BujjiBoard extends StatelessWidget {
  final int n;
  final bool spaces;
  const _BujjiBoard({required this.n, required this.spaces});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ValueListenableBuilder<int>(
      valueListenable: VibeBuddy.changed,
      builder: (context, _, _) {
        if (!VibeBuddy.on) return n > 0 ? _Count(n) : const SizedBox.shrink();
        final board = Container(
          width: 40,
          height: 26,
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: cs.primary, width: 2),
            boxShadow: const [
              BoxShadow(color: Color(0x2E1E2850), blurRadius: 8, offset: Offset(0, 3)),
            ],
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                n > 99 ? '99+' : '$n',
                style: TextStyle(fontSize: 12.5, height: 1, fontWeight: FontWeight.w800, color: cs.primary),
              ),
              Text(
                spaces ? 'CHATS' : 'NEW',
                style: TextStyle(
                  fontSize: 7,
                  height: 1.2,
                  letterSpacing: 0.4,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
        Widget hand() => Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: Color.lerp(cs.primary, Colors.white, 0.32),
            shape: BoxShape.circle,
          ),
        );
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            BujjiHome(unread: n),
            // the board pops up in its hands when something is unread
            Positioned(
              bottom: -8,
              child: IgnorePointer(
                child: AnimatedScale(
                  scale: n > 0 ? 1 : 0,
                  duration: const Duration(milliseconds: 320),
                  curve: n > 0 ? Curves.easeOutBack : Curves.easeIn,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Transform.translate(offset: const Offset(3, 0), child: hand()),
                      board,
                      Transform.translate(offset: const Offset(-3, 0), child: hand()),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Chats / Spaces as a switch that opens over the title: slide the thumb or
/// tap the other side, and it closes on the one picked.
class _ModeSwitch extends StatefulWidget {
  final Rect at;
  final bool spaces;
  final int chatsUnread;
  final int spacesUnread;
  final ValueChanged<bool> onMode;
  const _ModeSwitch({
    required this.at,
    required this.spaces,
    required this.chatsUnread,
    required this.spacesUnread,
    required this.onMode,
  });

  static Future<void> open(
    BuildContext context,
    Rect at,
    bool spaces,
    int chatsUnread,
    int spacesUnread,
    ValueChanged<bool> onMode,
  ) {
    VibeHaptics.selection();
    return Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierDismissible: true,
        barrierLabel: 'Close',
        barrierColor: Theme.of(context).colorScheme.surfaceContainerLowest.withValues(alpha: 0.7),
        transitionDuration: const Duration(milliseconds: 280),
        reverseTransitionDuration: const Duration(milliseconds: 170),
        pageBuilder: (context, a, _) => _ModeSwitch(
          at: at,
          spaces: spaces,
          chatsUnread: chatsUnread,
          spacesUnread: spacesUnread,
          onMode: onMode,
        ),
        transitionsBuilder: (context, a, _, child) => FadeTransition(opacity: a, child: child),
      ),
    );
  }

  @override
  State<_ModeSwitch> createState() => _ModeSwitchState();
}

class _ModeSwitchState extends State<_ModeSwitch> with SingleTickerProviderStateMixin {
  static const _w = 236.0, _h = 52.0, _pad = 4.0;
  late final AnimationController _x = AnimationController.unbounded(
    vsync: this,
    value: widget.spaces ? 1 : 0,
  );
  bool _done = false;

  @override
  void dispose() {
    _x.dispose();
    super.dispose();
  }

  void _settle(bool spaces, [double velocity = 0]) {
    if (_done) return;
    _done = true;
    VibeHaptics.selection();
    _x.animateWith(
      SpringSimulation(
        SpringDescription.withDampingRatio(mass: 1, stiffness: 520, ratio: 0.8),
        _x.value,
        spaces ? 1 : 0,
        velocity,
      ),
    );
    if (spaces != widget.spaces) widget.onMode(spaces);
    Future<void>.delayed(const Duration(milliseconds: 220), () {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final screen = MediaQuery.sizeOf(context);
    final left = (widget.at.left - 8).clamp(12.0, math.max(12.0, screen.width - _w - 12)).toDouble();
    const thumbW = (_w - _pad * 2) / 2;
    final route = ModalRoute.of(context)?.animation ?? kAlwaysCompleteAnimation;
    Widget seg(bool sp) {
      final n = sp ? widget.spacesUnread : widget.chatsUnread;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _settle(sp),
          child: AnimatedBuilder(
            animation: _x,
            builder: (context, _) {
              final on = (sp ? _x.value : 1 - _x.value) > 0.5;
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    sp ? 'Spaces' : 'Chats',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: on ? FontWeight.w800 : FontWeight.w600,
                      color: on ? cs.onPrimary : cs.onSurface,
                    ),
                  ),
                  if (n > 0) ...[
                    const SizedBox(width: 6),
                    _Count(n, inverted: on),
                  ],
                ],
              );
            },
          ),
        ),
      );
    }

    return Stack(
      children: [
        Positioned(
          left: left,
          top: widget.at.center.dy - _h / 2,
          child: ScaleTransition(
            scale: Tween(begin: 0.86, end: 1.0).animate(
              CurvedAnimation(parent: route, curve: Curves.easeOutBack, reverseCurve: Curves.easeIn),
            ),
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              onHorizontalDragUpdate: (d) {
                if (_done) return;
                _x.value = (_x.value + d.delta.dx / (_w - thumbW - _pad * 2)).clamp(-0.08, 1.08);
              },
              onHorizontalDragEnd: (d) {
                final v = d.primaryVelocity ?? 0;
                final to = v.abs() > 300 ? v > 0 : _x.value > 0.5;
                _settle(to, v / (_w - thumbW - _pad * 2));
              },
              child: Material(
                color: cs.surfaceContainerHigh,
                elevation: 6,
                shadowColor: const Color(0x55000000),
                shape: const StadiumBorder(),
                child: SizedBox(
                  width: _w,
                  height: _h,
                  child: Stack(
                    children: [
                      AnimatedBuilder(
                        animation: _x,
                        builder: (context, child) => Transform.translate(
                          offset: Offset(_pad + _x.value * (_w - thumbW - _pad * 2), _pad),
                          child: child,
                        ),
                        child: Container(
                            width: thumbW,
                            height: _h - _pad * 2,
                            decoration: BoxDecoration(
                              color: cs.primary,
                              borderRadius: BorderRadius.circular(22),
                              boxShadow: const [
                                BoxShadow(color: Color(0x401E2850), blurRadius: 8, offset: Offset(0, 2)),
                              ],
                            ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(_pad),
                        child: Row(children: [seg(false), seg(true)]),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
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

// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:vibe/config/setting_keys.dart';
import 'package:vibe/l10n/l10n.dart';
import 'package:vibe/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:vibe/vibe/screens/chat_list/chat_list.dart';
import 'package:vibe/vibe/vibe_archive.dart';
import 'package:vibe/vibe/vibe_chat_actions.dart';
import 'package:vibe/vibe/vibe_communities.dart';
import 'package:vibe/vibe/vibe_glass.dart';
import 'package:vibe/vibe/vibe_groups.dart';
import 'package:vibe/vibe/vibe_haptics.dart';
import 'package:vibe/vibe/vibe_lock.dart';
import 'package:vibe/widgets/avatar.dart';
import 'package:vibe/widgets/matrix.dart';

/// Dial, an experimental look: no home screen (Keepr opens on your last
/// chat), one line down the middle of a chat (theirs left, yours right),
/// and the people you talk to on a dial at the bottom. All chats sit on
/// rings, one swipe up from the dial. Switch it on in Settings; the app
/// restarts into it. Off, nothing here is used.
abstract class VibeDial {
  static bool get on => AppSettings.vibeDialUi.value;

  // colours: near black, one lime accent
  static const bg = Color(0xFF07080A);
  static const ink = Color(0xFFECEDEF);
  static const dim = Color(0xFF7C8089);
  static const faint = Color(0xFF2A2D33);
  static const card = Color(0xFF101215);
  static const lime = Color(0xFFC8FF3D);
  static const pink = Color(0xFFFF8FB1);

  static const font = 'SpaceGrotesk';
  static const mono = 'JetBrainsMono';

  static TextStyle label({Color color = dim, double size = 10}) => TextStyle(
    fontFamily: mono,
    fontSize: size,
    letterSpacing: size * 0.14,
    color: color,
  );

  static const ColorScheme scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: lime,
    onPrimary: bg,
    primaryContainer: Color(0xFF3A4A12),
    onPrimaryContainer: Color(0xFFE8FFB0),
    secondary: dim,
    onSecondary: bg,
    secondaryContainer: Color(0xFF1C2010),
    onSecondaryContainer: ink,
    tertiary: Color(0xFF7FD4FF),
    onTertiary: bg,
    tertiaryContainer: Color(0xFF15262F),
    onTertiaryContainer: ink,
    error: Color(0xFFFF6B6B),
    onError: bg,
    errorContainer: Color(0xFF3A1515),
    onErrorContainer: Color(0xFFFFDAD9),
    surface: bg,
    onSurface: ink,
    surfaceContainerLowest: Color(0xFF050607),
    surfaceContainerLow: Color(0xFF0C0D10),
    surfaceContainer: card,
    surfaceContainerHigh: Color(0xFF14161A),
    surfaceContainerHighest: Color(0xFF1B1E23),
    onSurfaceVariant: dim,
    outline: faint,
    outlineVariant: Color(0xFF1E2126),
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: ink,
    onInverseSurface: bg,
    inversePrimary: Color(0xFF4F6B00),
  );

  /// The chat Keepr opens on.
  static String? get lastRoom {
    final id = AppSettings.vibeDialLast.value;
    return id.isEmpty ? null : id;
  }

  /// A chat was opened: remember it for next time.
  static void remember(String roomId) {
    if (!on || AppSettings.vibeDialLast.value == roomId) return;
    AppSettings.vibeDialLast.setItem(roomId);
  }

  /// Opened the last chat this run already (only once, at start).
  static bool _openedLast = false;

  /// Chats on the dial and rings: pinned first, then by last activity.
  static List<Room> chats(Client client) => VibeChatActions.pinnedFirst(
    client.rooms
        .where(
          (r) =>
              !r.isSpace &&
              r.membership == Membership.join &&
              !VibeLock.isLocked(r.id) &&
              !VibeArchive.hidden(r),
        )
        .toList(),
  );

  /// Turn the look on or off: a dark curtain comes down, the app rebuilds
  /// in the new look under it (a quick restart), and the curtain lifts.
  static Future<void> setOn(BuildContext context, bool value) async {
    final overlay = Overlay.of(context, rootOverlay: true);
    final router = GoRouter.of(context);
    final curtain = GlobalKey<_CurtainState>();
    final entry = OverlayEntry(builder: (_) => _Curtain(key: curtain));
    overlay.insert(entry);
    VibeHaptics.medium();
    await Future<void>.delayed(const Duration(milliseconds: 360));
    await AppSettings.vibeDialUi.setItem(value);
    _openedLast = false;
    VibeGlass.version.value++; // rebuilds the theme
    router.go('/rooms');
    await Future<void>.delayed(const Duration(milliseconds: 650));
    await curtain.currentState?.lift();
    entry.remove();
  }
}

class _Curtain extends StatefulWidget {
  const _Curtain({super.key});

  @override
  State<_Curtain> createState() => _CurtainState();
}

class _CurtainState extends State<_Curtain>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  )..forward();

  Future<void> lift() => _c.reverse();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _c,
    child: const Material(
      color: VibeDial.bg,
      child: Center(
        child: Text(
          'KEEPR',
          style: TextStyle(
            fontFamily: VibeDial.mono,
            fontSize: 13,
            letterSpacing: 6,
            color: VibeDial.lime,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    ),
  );
}

/// The dial under a chat: the people you talk to on an arc, the open chat
/// in the middle. Drag sideways to turn it (a tick per person), let go to
/// open who's in the middle; tap someone to open them; swipe up for all
/// chats.
class VibeDialBar extends StatefulWidget {
  final Room room;
  const VibeDialBar({required this.room, super.key});

  @override
  State<VibeDialBar> createState() => _VibeDialBarState();
}

class _VibeDialBarState extends State<VibeDialBar> {
  double _drag = 0;
  int _steps = 0;
  static const _step = 56.0; // px of drag per person

  void _open(Room r) {
    if (r.id == widget.room.id) return;
    VibeHaptics.light();
    context.go('/rooms/${r.id}');
  }

  @override
  Widget build(BuildContext context) {
    final chats = VibeDial.chats(widget.room.client);
    var i = chats.indexWhere((r) => r.id == widget.room.id);
    if (i < 0) {
      chats.insert(0, widget.room);
      i = 0;
    }
    final name = widget.room.getLocalizedDisplayname(
      MatrixLocals(L10n.of(context)),
    );
    // the arc turns with the finger; each person sits 17° apart
    final turn = -(_drag / _step) * 17.0;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (d) {
        setState(() => _drag += d.delta.dx);
        final s = -(_drag / _step).round();
        if (s != _steps) {
          _steps = s;
          VibeHaptics.selection();
        }
      },
      onHorizontalDragEnd: (_) {
        final target = (i + _steps).clamp(0, chats.length - 1);
        setState(() {
          _drag = 0;
          _steps = 0;
        });
        _open(chats[target]);
      },
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) < -250) context.go('/rooms');
      },
      child: SizedBox(
        height: 132,
        child: LayoutBuilder(
          builder: (context, box) {
            final w = box.maxWidth;
            final cx = w / 2;
            const r = 250.0;
            const cy = 290.0; // centre of the big circle, below the bar
            return Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _Arc(turn: turn, cx: cx, cy: cy, r: r),
                  ),
                ),
                for (var k = -2; k <= 2; k++)
                  if (i + k >= 0 && i + k < chats.length)
                    _person(
                      chats[i + k],
                      angle: k * 17.0 + turn,
                      center: k == 0,
                      cx: cx,
                      cy: cy,
                      r: r - 50,
                    ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 22,
                  child: Text(
                    name,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: VibeDial.ink,
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 6,
                  child: Text(
                    'TURN TO SWITCH · SWIPE UP FOR ALL',
                    textAlign: TextAlign.center,
                    style: VibeDial.label(size: 8.5),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _person(
    Room room, {
    required double angle,
    required bool center,
    required double cx,
    required double cy,
    required double r,
  }) {
    final a = (angle - 90) * math.pi / 180;
    final s = center ? 50.0 : 36.0;
    final x = cx + r * math.cos(a);
    final y = cy + r * math.sin(a);
    final unread = room.notificationCount > 0 || room.markedUnread;
    final name = room.getLocalizedDisplayname(MatrixLocals(L10n.of(context)));
    return Positioned(
      left: x - s / 2,
      top: y - s / 2,
      child: GestureDetector(
        onTap: () => _open(room),
        onLongPress: () => VibeChatActions.show(
          context,
          room,
          onOpen: () => _open(room),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: s,
              height: s,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: center ? VibeDial.lime : VibeDial.faint,
                  width: 1.5,
                ),
              ),
              child: Opacity(
                opacity: center ? 1 : 0.7,
                child: Avatar(
                  mxContent: room.avatar,
                  name: name,
                  size: s - 7,
                  client: room.client,
                ),
              ),
            ),
            if (unread && !center)
              const Positioned(
                right: 0,
                top: -2,
                child: CircleAvatar(radius: 4, backgroundColor: VibeDial.lime),
              ),
          ],
        ),
      ),
    );
  }
}

class _Arc extends CustomPainter {
  final double turn;
  final double cx;
  final double cy;
  final double r;
  const _Arc({
    required this.turn,
    required this.cx,
    required this.cy,
    required this.r,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final ring = Paint()
      ..color = VibeDial.faint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(Offset(cx, cy), r, ring);
    final tick = Paint()..strokeCap = StrokeCap.round;
    // ticks turn with the dial; the lime one marks the middle
    for (var d = -60; d <= 60; d += 4) {
      final deg = d + turn % 4;
      final a = (deg - 90) * math.pi / 180;
      final long = d % 20 == 0;
      final p1 = Offset(cx + (r - 2) * math.cos(a), cy + (r - 2) * math.sin(a));
      final len = long ? 11.0 : 6.0;
      final p2 = Offset(
        cx + (r - 2 - len) * math.cos(a),
        cy + (r - 2 - len) * math.sin(a),
      );
      tick
        ..color = const Color(0xFF3A3E46)
        ..strokeWidth = 1.5;
      canvas.drawLine(p1, p2, tick);
    }
    final top = Offset(cx, cy - r);
    canvas.drawLine(
      top.translate(0, -2),
      top.translate(0, 12),
      Paint()
        ..color = VibeDial.lime
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_Arc old) => old.turn != turn || old.cx != cx;
}

/// The home screen in Dial: every chat on rings (pinned and unread on the
/// inner ring, everyone else outside), Chats / Spaces in the middle, search
/// on top, Archive / Locked / New at the bottom. On start it opens the chat
/// you were in last.
class VibeDialHome extends StatefulWidget {
  final ChatListController controller;
  const VibeDialHome(this.controller, {super.key});

  @override
  State<VibeDialHome> createState() => _VibeDialHomeState();
}

class _VibeDialHomeState extends State<VibeDialHome> {
  bool _spaces = false;
  String _q = '';

  @override
  void initState() {
    super.initState();
    if (!VibeDial._openedLast) {
      VibeDial._openedLast = true;
      final id = VibeDial.lastRoom;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || id == null) return;
        final room = Matrix.of(context).client.getRoomById(id);
        if (room != null && room.membership == Membership.join) {
          widget.controller.onChatTap(room);
        }
      });
    }
  }

  void _openSpace(Room space) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) => Scaffold(
          backgroundColor: VibeDial.bg,
          body: VibeCommunityPane(
            space: space,
            onBack: () => Navigator.of(ctx).pop(),
            onOpenRoom: (room) {
              Navigator.of(ctx).pop();
              widget.controller.onChatTap(room);
            },
          ),
        ),
      ),
    );
  }

  void _openRoom(Room room) {
    if (room.isSpace) return _openSpace(room);
    widget.controller.onChatTap(room);
  }

  @override
  Widget build(BuildContext context) {
    final client = Matrix.of(context).client;
    return Scaffold(
      backgroundColor: VibeDial.bg,
      body: SafeArea(
        child: StreamBuilder<Object?>(
          stream: client.onSync.stream,
          builder: (context, _) {
            final all = _spaces
                ? [
                    ...VibeCommunities.joined(client),
                    ...VibeDial.chats(client).where(VibeGroups.isGroup),
                  ]
                : VibeDial.chats(client)
                      .where((r) => !VibeGroups.isGroup(r))
                      .toList();
            final unread = VibeDial.chats(client)
                .where((r) => r.notificationCount > 0 || r.markedUnread)
                .length;
            final q = _q.trim().toLowerCase();
            final found = q.isEmpty
                ? const <Room>[]
                : all
                      .where(
                        (r) => r
                            .getLocalizedDisplayname(
                              MatrixLocals(L10n.of(context)),
                            )
                            .toLowerCase()
                            .contains(q),
                      )
                      .toList();
            final inner = all
                .where(
                  (r) =>
                      r.isFavourite ||
                      r.notificationCount > 0 ||
                      r.markedUnread,
                )
                .take(6)
                .toList();
            if (inner.length < 4) {
              inner.addAll(
                all.where((r) => !inner.contains(r)).take(4 - inner.length),
              );
            }
            final outer = all.where((r) => !inner.contains(r)).toList();
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 8, 0),
                  child: Row(
                    children: [
                      Text(
                        unread > 0 ? 'KEEPR · $unread UNREAD' : 'KEEPR · ALL',
                        style: VibeDial.label(size: 10.5),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Settings',
                        icon: const Icon(
                          Icons.settings_outlined,
                          color: VibeDial.dim,
                          size: 20,
                        ),
                        onPressed: () => context.go('/rooms/settings'),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: TextField(
                    onChanged: (v) => setState(() => _q = v),
                    style: const TextStyle(fontSize: 16, color: VibeDial.ink),
                    decoration: const InputDecoration(
                      hintText: 'Find someone or a space',
                      hintStyle: TextStyle(color: VibeDial.dim),
                      prefixIcon: Icon(
                        Icons.search,
                        color: VibeDial.dim,
                        size: 20,
                      ),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: VibeDial.faint),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: VibeDial.lime),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: q.isNotEmpty || outer.length > 12
                      ? _list(q.isNotEmpty ? found : [...inner, ...outer], q)
                      : _rings(inner, outer),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Row(
                    children: [
                      _tile(
                        'Archive',
                        'archived chats',
                        () => VibeArchive.open(
                          context,
                          client,
                          onOpen: _openRoom,
                        ),
                      ),
                      const SizedBox(width: 10),
                      _tile(
                        'Locked',
                        'fingerprint',
                        () => VibeLock.openFolder(context, client, _openRoom),
                      ),
                      const SizedBox(width: 10),
                      _tile(
                        'New',
                        'chat · group · space',
                        () => VibeGroups.showNew(context),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _switch() => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: VibeDial.card,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: VibeDial.faint),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final sp in [false, true])
          GestureDetector(
            onTap: () {
              VibeHaptics.selection();
              setState(() => _spaces = sp);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: _spaces == sp ? VibeDial.lime : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                sp ? 'SPACES' : 'CHATS',
                style: VibeDial.label(
                  color: _spaces == sp ? VibeDial.bg : VibeDial.dim,
                ).copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _rings(List<Room> inner, List<Room> outer) => LayoutBuilder(
    builder: (context, box) {
      final w = box.maxWidth;
      final h = box.maxHeight;
      final c = Offset(w / 2, h / 2);
      final m = math.min(w, h);
      final r1 = m * 0.30;
      final r2 = m * 0.45;
      Widget place(Room room, double deg, double r, double size, bool big) {
        final a = (deg - 90) * math.pi / 180;
        final p = c + Offset(r * math.cos(a), r * math.sin(a));
        return Positioned(
          left: p.dx - 50,
          top: p.dy - size / 2,
          width: 100,
          child: _person(room, size, big),
        );
      }

      return Stack(
        children: [
          for (final r in [r1, r2])
            Positioned(
              left: c.dx - r,
              top: c.dy - r,
              child: Container(
                width: r * 2,
                height: r * 2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: VibeDial.faint),
                ),
              ),
            ),
          Center(child: _switch()),
          for (var k = 0; k < inner.length; k++)
            place(inner[k], k * 360 / inner.length, r1, 52, true),
          for (var k = 0; k < outer.length; k++)
            place(outer[k], 15 + k * 360 / math.max(outer.length, 1), r2, 36, false),
          if (inner.isEmpty)
            Positioned(
              left: 0,
              right: 0,
              top: c.dy + 44,
              child: Text(
                'NOBODY HERE YET · TAP NEW',
                textAlign: TextAlign.center,
                style: VibeDial.label(size: 9),
              ),
            ),
        ],
      );
    },
  );

  Widget _list(List<Room> rooms, String q) => Column(
    children: [
      const SizedBox(height: 10),
      if (q.isEmpty) _switch(),
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: rooms.length,
          itemBuilder: (context, i) {
            final room = rooms[i];
            final name = room.getLocalizedDisplayname(
              MatrixLocals(L10n.of(context)),
            );
            final unread = room.notificationCount;
            return ListTile(
              onTap: () => _openRoom(room),
              onLongPress: () => VibeChatActions.show(
                context,
                room,
                onOpen: () => _openRoom(room),
              ),
              leading: Avatar(
                mxContent: room.avatar,
                name: name,
                size: 38,
                client: room.client,
              ),
              title: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, color: VibeDial.ink),
              ),
              trailing: unread > 0
                  ? Text(
                      '+$unread',
                      style: VibeDial.label(color: VibeDial.lime, size: 11),
                    )
                  : null,
            );
          },
        ),
      ),
    ],
  );

  Widget _person(Room room, double size, bool big) {
    final name = room.getLocalizedDisplayname(MatrixLocals(L10n.of(context)));
    final unread = room.notificationCount;
    return GestureDetector(
      onTap: () => _openRoom(room),
      onLongPress: () => VibeChatActions.show(
        context,
        room,
        onOpen: () => _openRoom(room),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: size,
                height: size,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: unread > 0 ? VibeDial.lime : VibeDial.faint,
                    width: 1.5,
                  ),
                ),
                child: Avatar(
                  mxContent: room.avatar,
                  name: name,
                  size: size - 7,
                  client: room.client,
                  borderRadius: room.isSpace
                      ? BorderRadius.circular(size / 3.5)
                      : null,
                ),
              ),
              if (unread > 0)
                Positioned(
                  right: -6,
                  top: -6,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 18),
                    height: 18,
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: VibeDial.lime,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      unread > 99 ? '99+' : '$unread',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: VibeDial.bg,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (big) ...[
            const SizedBox(height: 4),
            Text(
              name.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: VibeDial.label(
                size: 8.5,
                color: unread > 0 ? VibeDial.ink : VibeDial.dim,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tile(String title, String sub, VoidCallback onTap) => Expanded(
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        height: 60,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: VibeDial.faint),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 15, color: VibeDial.ink),
            ),
            const SizedBox(height: 3),
            Text(
              sub.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: VibeDial.label(size: 8),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The line down the middle of a message row (Dial): drawn behind every
/// message so the rows join into one line; [hook] adds the small curve a
/// reply makes up to the words it quotes, on the [right] side or the left.
class VibeDialLine extends CustomPainter {
  final double dotY;
  final bool hook;
  final bool right;
  final Color hookColor;
  const VibeDialLine({
    required this.dotY,
    required this.hook,
    required this.right,
    required this.hookColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2;
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, size.height),
      Paint()
        ..color = VibeDial.faint
        ..strokeWidth = 1,
    );
    if (!hook) return;
    final s = right ? 1 : -1;
    final path = Path()
      ..moveTo(x + 4 * s, dotY)
      ..cubicTo(x + 16 * s, dotY, x + 16 * s, 6, x + 26 * s, 6);
    canvas.drawPath(
      path,
      Paint()
        ..color = hookColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(VibeDialLine old) =>
      old.dotY != dotY ||
      old.hook != hook ||
      old.right != right ||
      old.hookColor != hookColor;
}

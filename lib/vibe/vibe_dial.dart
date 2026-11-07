// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:vibe/config/setting_keys.dart';
import 'package:vibe/l10n/l10n.dart';
import 'package:vibe/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:vibe/vibe/screens/chat_list/chat_list.dart';
import 'package:vibe/vibe/vibe_archive.dart';
import 'package:vibe/vibe/vibe_chat_actions.dart';
import 'package:vibe/vibe/vibe_communities.dart';
import 'package:vibe/vibe/vibe_dm_detail.dart';
import 'package:vibe/vibe/vibe_glass.dart';
import 'package:vibe/vibe/vibe_groups.dart';
import 'package:vibe/vibe/vibe_haptics.dart';
import 'package:vibe/vibe/vibe_call.dart';
import 'package:vibe/vibe/vibe_lock.dart';
import 'package:vibe/vibe/vibe_strict.dart';
import 'package:vibe/vibe/vibe_threads.dart';
import 'package:vibe/vibe/vibe_user_sheet.dart';
import 'package:vibe/widgets/presence_builder.dart';
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

  /// Where the dial is on screen (so swiping it doesn't close the chat).
  static Rect? _dialRect;
  static bool covers(Offset p) => on && (_dialRect?.contains(p) ?? false);

  /// Screens turn like the dial: round a point far below the screen.
  static const pivot = Alignment(0, 2.4);

  /// Which way the last turn went: 1 = the next chat comes from the right.
  static int turnDir = 1;

  /// How far a chat coming in is still turned, at [v] (0 → 1).
  static double turnAngle(double v) =>
      (1 - Curves.easeOutCubic.transform(v.clamp(0.0, 1.0))) * 0.5 * turnDir;

  /// Switch to another chat from the dial: the chat you're in turns away
  /// one way (a picture of it) while the next one turns in from the other,
  /// like the dial itself. [dir] 1: the next one is to the right.
  static Future<void> switchTo(
    BuildContext context,
    Room room, {
    int dir = 1,
  }) async {
    final overlay = Overlay.of(context, rootOverlay: true);
    final router = GoRouter.of(context);
    turnDir = dir;
    final shot = await _shot(context);
    if (shot == null) {
      router.go('/rooms/${room.id}');
      return;
    }
    final done = Completer<void>();
    final entry = OverlayEntry(
      builder: (_) => _TurnOut(image: shot, dir: dir, onDone: done.complete),
    );
    overlay.insert(entry);
    router.go('/rooms/${room.id}');
    await done.future;
    entry.remove();
    shot.dispose();
  }

  /// A picture of the whole page [context] is on.
  static Future<ui.Image?> _shot(BuildContext context) async {
    final h = MediaQuery.sizeOf(context).height;
    final ratio = MediaQuery.devicePixelRatioOf(context) * 0.75;
    RenderObject? o = context.findRenderObject();
    while (o != null) {
      if (o is RenderRepaintBoundary && o.hasSize && o.size.height >= h * 0.9) {
        try {
          return await o.toImage(pixelRatio: ratio);
        } catch (_) {
          return null;
        }
      }
      o = o.parent;
    }
    return null;
  }

  /// The person's (or group's) page, sliding in from the left; swipe right
  /// or tap back to close it.
  static void openPerson(BuildContext context, Room room) {
    VibeHaptics.light();
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 380),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (ctx, _, _) => GestureDetector(
          onHorizontalDragEnd: (d) {
            if ((d.primaryVelocity ?? 0) > 300) Navigator.of(ctx).pop();
          },
          child: Scaffold(
            backgroundColor: bg,
            body: VibeDialPerson(
              room: room,
              onBack: () => Navigator.of(ctx).pop(),
            ),
          ),
        ),
        transitionsBuilder: (ctx, anim, _, child) => SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(-1, 0),
            end: Offset.zero,
          ).animate(
            CurvedAnimation(
              parent: anim,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            ),
          ),
          child: child,
        ),
      ),
    );
  }

  /// Where the last finger went down (the long-press menu opens there).
  static Offset? lastDown;
  static bool _tracking = false;
  static void track() {
    if (_tracking) return;
    _tracking = true;
    GestureBinding.instance.pointerRouter.addGlobalRoute((e) {
      if (e is PointerDownEvent) lastDown = e.position;
    });
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
/// in the middle, only chats of the same kind (people with people, groups
/// and channels with groups). Drag sideways to turn it (a tick per person);
/// let go and it settles on who's in the middle and opens them. Tap someone
/// to open them, tap the middle for their page, swipe up for all chats.
class VibeDialBar extends StatefulWidget {
  final Room room;

  /// The message box: while it has the keyboard the dial steps aside.
  final FocusNode typing;
  const VibeDialBar({required this.room, required this.typing, super.key});

  @override
  State<VibeDialBar> createState() => _VibeDialBarState();
}

class _VibeDialBarState extends State<VibeDialBar>
    with SingleTickerProviderStateMixin {
  double _drag = 0;
  int _steps = 0;
  static const _step = 56.0; // px of drag per person
  static const _gap = 15.0; // degrees between people

  // A–Z: hold the dial and slide to a letter; let go and the dial holds
  // everyone of this kind from that letter on (not just the recent ones)
  static const _abc = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ#';
  bool _picking = false;
  int _pick = 0;
  double _pickX = 0;
  int _pickBase = 0;
  String? _letter;

  static String _initial(String name) {
    final c = name.isEmpty ? '#' : name.characters.first.toUpperCase();
    return _abc.contains(c) && c != '#' ? c : '#';
  }

  String _name(Room r) =>
      r.getLocalizedDisplayname(MatrixLocals(L10n.of(context)));
  late final AnimationController _settle = AnimationController.unbounded(
    vsync: this,
  )..addListener(() => setState(() => _drag = _settle.value));

  @override
  void initState() {
    super.initState();
    VibeDial.track();
  }

  @override
  void dispose() {
    _settle.dispose();
    VibeDial._dialRect = null;
    super.dispose();
  }

  void _open(Room r, {int dir = 1}) {
    if (r.id == widget.room.id) return;
    VibeHaptics.light();
    VibeDial.switchTo(context, r, dir: dir);
  }

  List<Room> _chats() {
    final group = VibeGroups.isGroup(widget.room);
    final chats = VibeDial.chats(
      widget.room.client,
    ).where((r) => VibeGroups.isGroup(r) == group).toList();
    if (_letter != null) {
      // everyone, A to Z (names that don't start with a letter last)
      String key(Room r) {
        final n = _name(r).toLowerCase();
        return _initial(n) == '#' ? '~$n' : n;
      }
      chats.sort((a, b) => key(a).compareTo(key(b)));
      return chats;
    }
    // the dial is for the people you talk to now: pinned and the 15 most
    // recent; everyone else is a swipe up away (rings, list, search)
    final near = chats.take(15).toList();
    if (!near.any((r) => r.id == widget.room.id)) {
      near.insert(0, widget.room);
    }
    return near;
  }

  @override
  Widget build(BuildContext context) {
    // typing: the dial steps aside so the chat keeps its room
    return ListenableBuilder(
      listenable: widget.typing,
      builder: (context, _) {
        final typing = widget.typing.hasFocus;
        if (typing) VibeDial._dialRect = null;
        return AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: typing
              ? const SizedBox(width: double.infinity)
              : _dial(context),
        );
      },
    );
  }

  Widget _dial(BuildContext context) {
    // where the dial is, so the chat's swipe-back leaves it alone
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final box = context.findRenderObject();
      if (mounted && box is RenderBox && box.attached && box.hasSize) {
        VibeDial._dialRect = box.localToGlobal(Offset.zero) & box.size;
      }
    });
    final chats = _chats();
    var i = chats.indexWhere((r) => r.id == widget.room.id);
    if (_letter != null) {
      // start at the first name from the letter on
      final at = _abc.indexOf(_letter!);
      i = chats.indexWhere((r) => _abc.indexOf(_initial(_name(r))) >= at);
      if (i < 0) i = chats.length - 1;
    }
    if (i < 0) i = 0;
    final turn = -(_drag / _step) * _gap;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (_) => _settle.stop(),
      onHorizontalDragUpdate: (d) {
        setState(() => _drag += d.delta.dx);
        final s = (-(_drag / _step)).round();
        final clamped = s.clamp(-i, chats.length - 1 - i);
        if (clamped != _steps) {
          _steps = clamped;
          VibeHaptics.selection();
        }
      },
      onHorizontalDragEnd: (d) async {
        // a flick carries on a few people, like spinning a real dial
        final fling = (-d.velocity.pixelsPerSecond.dx / 900).round();
        _steps = (_steps + fling).clamp(-i, chats.length - 1 - i);
        if (fling != 0) VibeHaptics.selection();
        final target = chats[(i + _steps).clamp(0, chats.length - 1)];
        // settle on the person in the middle (a soft spring), then open
        _settle.value = _drag;
        await _settle.animateWith(
          SpringSimulation(
            const SpringDescription(mass: 1, stiffness: 320, damping: 30),
            _drag,
            -_steps * _step,
            d.velocity.pixelsPerSecond.dx,
          ),
        );
        if (!mounted) return;
        _open(target, dir: _steps < 0 ? -1 : 1);
      },
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) < -250) context.go('/rooms');
      },
      onLongPressStart: (d) {
        VibeHaptics.medium();
        setState(() {
          _picking = true;
          _pickX = d.localPosition.dx;
          _pickBase = _abc.indexOf(
            _letter ?? _initial(_name(widget.room)),
          );
          _pick = _pickBase;
        });
      },
      onLongPressMoveUpdate: (d) {
        final p = (_pickBase + (d.localPosition.dx - _pickX) / 18)
            .round()
            .clamp(0, _abc.length - 1);
        if (p != _pick) {
          VibeHaptics.selection();
          setState(() => _pick = p);
        }
      },
      onLongPressEnd: (_) {
        VibeHaptics.light();
        setState(() {
          _picking = false;
          _letter = _abc[_pick];
          _drag = 0;
          _steps = 0;
        });
      },
      child: SizedBox(
        height: 140,
        child: LayoutBuilder(
          builder: (context, box) {
            final cx = box.maxWidth / 2;
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
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: _letter == null || _picking
                      ? Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            _picking
                                ? 'SLIDE TO A LETTER · LET GO'
                                : 'TURN · HOLD FOR A–Z · SWIPE UP FOR ALL',
                            textAlign: TextAlign.center,
                            style: VibeDial.label(size: 8),
                          ),
                        )
                      : Center(
                          // which letter the dial is on; tap to go back to
                          // the recent ones
                          child: GestureDetector(
                            onTap: () => setState(() => _letter = null),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: VibeDial.lime),
                              ),
                              child: Text(
                                'A–Z · $_letter  ✕',
                                style: VibeDial.label(
                                  color: VibeDial.lime,
                                  size: 9,
                                ),
                              ),
                            ),
                          ),
                        ),
                ),
                // holding: letters round the arc instead of people
                if (_picking)
                  for (var k = -6; k <= 6; k++)
                    if (_pick + k >= 0 && _pick + k < _abc.length)
                      _letterAt(
                        _abc[_pick + k],
                        angle: k * 11.0,
                        big: k == 0,
                        cx: cx,
                        cy: cy,
                        r: r - 44,
                      ),
                if (!_picking)
                for (var k = -3; k <= 3; k++)
                  if (i + k >= 0 && i + k < chats.length)
                    _person(
                      chats[i + k],
                      angle: k * _gap + turn,
                      center: k == 0,
                      cx: cx,
                      cy: cy,
                      r: r - 50,
                    ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _letterAt(
    String l, {
    required double angle,
    required bool big,
    required double cx,
    required double cy,
    required double r,
  }) {
    final a = (angle - 90) * math.pi / 180;
    final s = big ? 50.0 : 26.0;
    return Positioned(
      left: cx + r * math.cos(a) - s / 2,
      top: cy + r * math.sin(a) - s / 2,
      width: s,
      height: s,
      child: Container(
        alignment: Alignment.center,
        decoration: big
            ? BoxDecoration(
                shape: BoxShape.circle,
                color: VibeDial.bg,
                border: Border.all(color: VibeDial.lime, width: 1.5),
              )
            : null,
        child: Text(
          l,
          style: TextStyle(
            fontFamily: VibeDial.mono,
            fontSize: big ? 22 : 13,
            fontWeight: big ? FontWeight.w700 : FontWeight.w400,
            color: big ? VibeDial.lime : VibeDial.dim,
          ),
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
    // grows as it nears the middle
    final near = (1 - (angle.abs() / _gap).clamp(0.0, 1.0));
    final s = 36.0 + 14 * near;
    final x = cx + r * math.cos(a);
    final y = cy + r * math.sin(a);
    final unread = room.notificationCount > 0 || room.markedUnread;
    final name = room.getLocalizedDisplayname(MatrixLocals(L10n.of(context)));
    return Positioned(
      left: x - s / 2,
      top: y - s / 2,
      child: GestureDetector(
        // the middle: the open chat's page, or open whoever is there
        onTap: () => center && room.id == widget.room.id
            ? VibeDial.openPerson(context, room)
            : _open(room, dir: angle < 0 ? -1 : 1),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: s,
              height: s,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: VibeDial.bg,
                border: Border.all(
                  color: Color.lerp(VibeDial.faint, VibeDial.lime, near)!,
                  width: 1.5,
                ),
              ),
              child: Opacity(
                opacity: 0.6 + 0.4 * near,
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

class _VibeDialHomeState extends State<VibeDialHome>
    with SingleTickerProviderStateMixin {
  bool _spaces = false;
  String _q = '';
  bool _searching = false;

  /// Everyone as a plain list instead of the rings.
  bool _listMode = false;

  /// The rings swing into place each time you come here or switch
  /// Chats / Spaces.
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();

  Animation<double>? _covered;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // back here from a chat: swing again
    final anim = ModalRoute.of(context)?.secondaryAnimation;
    if (anim == _covered) return;
    _covered?.removeStatusListener(_back);
    _covered = anim?..addStatusListener(_back);
  }

  void _back(AnimationStatus s) {
    if (s == AnimationStatus.dismissed && mounted) _spin.forward(from: 0);
  }

  @override
  void dispose() {
    _covered?.removeStatusListener(_back);
    _spin.dispose();
    super.dispose();
  }

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
                        tooltip: _listMode ? 'Rings' : 'List',
                        icon: Icon(
                          _listMode
                              ? Icons.blur_circular_outlined
                              : Icons.view_list_outlined,
                          color: VibeDial.dim,
                          size: 20,
                        ),
                        onPressed: () {
                          setState(() => _listMode = !_listMode);
                          if (!_listMode) _spin.forward(from: 0);
                        },
                      ),
                      if (!_searching)
                        IconButton(
                          tooltip: 'Search',
                          icon: const Icon(
                            Icons.search,
                            color: VibeDial.dim,
                            size: 20,
                          ),
                          onPressed: () => setState(() => _searching = true),
                        ),
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
                if (_searching)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: TextField(
                    autofocus: true,
                    onTapOutside: (_) {
                      FocusManager.instance.primaryFocus?.unfocus();
                      if (_q.isEmpty) setState(() => _searching = false);
                    },
                    onChanged: (v) => setState(() => _q = v),
                    style: const TextStyle(fontSize: 16, color: VibeDial.ink),
                    decoration: InputDecoration(
                      hintText: 'Find someone or a space',
                      hintStyle: const TextStyle(color: VibeDial.dim),
                      prefixIcon: const Icon(
                        Icons.search,
                        color: VibeDial.dim,
                        size: 20,
                      ),
                      enabledBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: VibeDial.faint),
                      ),
                      focusedBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: VibeDial.lime),
                      ),
                      suffixIcon: IconButton(
                        tooltip: 'Close',
                        icon: const Icon(Icons.close, color: VibeDial.dim),
                        onPressed: () => setState(() {
                          _q = '';
                          _searching = false;
                        }),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  // the rings hold the first 14 outside; the list has all
                  child: q.isNotEmpty || _listMode
                      ? _list(q.isNotEmpty ? found : [...inner, ...outer], q)
                      : _rings(inner, outer.take(14).toList()),
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
              if (_spaces == sp) return;
              VibeHaptics.selection();
              setState(() => _spaces = sp);
              _spin.forward(from: 0);
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

  Widget _rings(List<Room> inner, List<Room> outer) => AnimatedBuilder(
    animation: _spin,
    builder: (context, _) => LayoutBuilder(
    builder: (context, box) {
      // swing: the inner ring turns one way, the outer the other, settling
      final t = Curves.easeOutCubic.transform(_spin.value);
      final swing = (1 - t) * 70;
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
          child: Opacity(opacity: t, child: _person(room, size, big)),
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
            place(inner[k], swing + k * 360 / inner.length, r1, 52, true),
          for (var k = 0; k < outer.length; k++)
            place(
              outer[k],
              15 - swing + k * 360 / math.max(outer.length, 1),
              r2,
              36,
              false,
            ),
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
    ),
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

  /// The middle of the quoted line above a reply, where the curve ends.
  final double hookY;
  final bool hook;
  final bool right;
  final Color hookColor;
  const VibeDialLine({
    required this.dotY,
    required this.hookY,
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
    // from just above the dot, up the line and round into the quoted words
    final s = right ? 1 : -1;
    final path = Path()
      ..moveTo(x, dotY - 7)
      ..lineTo(x, hookY + 6)
      ..quadraticBezierTo(x, hookY, x + 6 * s, hookY)
      ..lineTo(x + 13 * s, hookY);
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
      old.hookY != hookY ||
      old.hook != hook ||
      old.right != right ||
      old.hookColor != hookColor;
}

/// Your message's dot on the middle line tells its state: it glows while
/// it's being encrypted, pulses while it goes out, turns blue once sent,
/// green once delivered, red if it couldn't be sent.
class VibeDialStatusDot extends StatefulWidget {
  final Event event;
  const VibeDialStatusDot(this.event, {super.key});

  static const sent = Color(0xFF4DA3FF);
  static const delivered = Color(0xFF3DDC84);
  static const failed = Color(0xFFFF5C5C);

  @override
  State<VibeDialStatusDot> createState() => _VibeDialStatusDotState();
}

class _VibeDialStatusDotState extends State<VibeDialStatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  final _born = DateTime.now();

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(VibeDialStatusDot old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final busy = widget.event.status == EventStatus.sending;
    if (busy && !_c.isAnimating) _c.repeat(reverse: true);
    if (!busy && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.event.status;
    if (status != EventStatus.sending) {
      final color = switch (status) {
        EventStatus.error => VibeDialStatusDot.failed,
        EventStatus.sent => VibeDialStatusDot.sent,
        _ => VibeDialStatusDot.delivered,
      };
      return AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        width: 9,
        height: 9,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
    }
    // the first moments of an encrypted message: glowing; then pulsing
    final encrypting = widget.event.room.encrypted &&
        DateTime.now().difference(_born).inMilliseconds < 700;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final v = Curves.easeInOut.transform(_c.value);
        return Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: VibeDial.lime.withValues(alpha: encrypting ? 1 : 0.5 + 0.5 * v),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: VibeDial.lime.withValues(alpha: encrypting ? 0.7 * v : 0.25 * v),
                blurRadius: encrypting ? 10 : 6,
                spreadRadius: encrypting ? 3 * v : 1.5 * v,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The person's (or group's) page in Dial: the middle line runs on from
/// the chat and everything hangs off it as a tree, theirs to the left and
/// yours to the right: Conversation, Shared, About, Actions.
class VibeDialPerson extends StatelessWidget {
  final Room room;
  final VoidCallback onBack;
  const VibeDialPerson({required this.room, required this.onBack, super.key});

  @override
  Widget build(BuildContext context) {
    final name = room.getLocalizedDisplayname(MatrixLocals(L10n.of(context)));
    final other = room.directChatMatrixID;
    final group = VibeGroups.isGroup(room);
    final strict = room.encrypted && VibeStrict.isOn(room);
    final shared = other == null || group
        ? const <String>[]
        : [
            for (final s in VibeCommunities.joined(room.client))
              if (s.getParticipants().any((u) => u.id == other))
                VibeGroups.nameOf(context, s),
          ];
    final muted = room.pushRuleState != PushRuleState.notify;
    void openShared(String k) => VibeDmDetail.openShared(context, room, k);
    final rows = <Widget>[
      _section('CONVERSATION'),
      _pair(
        _Leaf('Chat', meta: _ago(room), metaColor: VibeDial.lime, onTap: onBack),
        room.canSendDefaultMessages
            ? _Leaf(
                'Voice call',
                onTap: () => VibeCall.startFrom(context, room, video: false),
              )
            : null,
      ),
      if (room.canSendDefaultMessages)
        _pair(
          null,
          _Leaf(
            'Video call',
            onTap: () => VibeCall.startFrom(context, room, video: true),
          ),
        ),
      if (VibeThreads.ids(room.id).isNotEmpty) ...[
        _section('THREADS'),
        for (final id in VibeThreads.ids(room.id))
          _pair(
            null,
            _Leaf(
              VibeThreads.nameOf(room.id, id, null),
              onTap: () {
                VibeThreads.openNext(room.id, id);
                onBack();
              },
            ),
          ),
      ],
      _section('SHARED'),
      _pair(
        _Leaf('Media', onTap: () => openShared('media')),
        _Leaf('Files', onTap: () => openShared('files')),
      ),
      _pair(
        _Leaf('Links', onTap: () => openShared('links')),
        _Leaf('Voice', onTap: () => openShared('voice')),
      ),
      _pair(_Leaf('Starred', onTap: () => openShared('starred')), null),
      if (group) ...[
        _section('MEMBERS'),
        _pair(
          _Leaf(
            'Members',
            meta: '${VibeGroups.memberCount(room)}',
            onTap: () => VibeGroups.showMembers(context, room),
          ),
          room.canInvite
              ? _Leaf('Invite', onTap: () => VibeGroups.showInvite(context, room))
              : null,
        ),
      ],
      _section('ABOUT'),
      _pair(
        _Leaf(
          room.encrypted ? 'Strict encryption' : 'Not encrypted',
          meta: room.encrypted ? (strict ? 'ON' : 'OFF') : null,
          metaColor: strict ? VibeDial.lime : VibeDial.dim,
          onTap: room.encrypted
              ? () => ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(VibeStrict.describe(room))),
                )
              : null,
        ),
        shared.isNotEmpty ? _Leaf(shared.first, meta: 'IN') : null,
      ),
      if (other != null && !group)
        _pair(
          _Leaf(
            'Profile',
            onTap: () => VibeUserSheet.show(
              context,
              client: room.client,
              userId: other,
              displayName: name,
              avatarUrl: room.avatar,
              currentRoomId: room.id,
            ),
          ),
          shared.length > 1 ? _Leaf(shared[1], meta: 'IN') : null,
        ),
      _section('ACTIONS'),
      _pair(
        _Leaf(
          muted ? 'Unmute' : 'Mute',
          onTap: () => room.setPushRuleState(
            muted ? PushRuleState.notify : PushRuleState.mentionsOnly,
          ),
        ),
        _Leaf(
          VibeLock.isLocked(room.id) ? 'Unlock chat' : 'Lock chat',
          onTap: () => VibeLock.toggle(context, room),
        ),
      ),
      _pair(
        _Leaf(
          'More',
          onTap: () => VibeChatActions.show(context, room, onOpen: onBack),
        ),
        null,
      ),
    ];
    return Scaffold(
      backgroundColor: VibeDial.bg,
      body: SafeArea(
        child: StreamBuilder<Object?>(
          stream: room.client.onSync.stream.where(
            (u) => u.rooms?.join?.containsKey(room.id) ?? false,
          ),
          builder: (context, _) => CustomPaint(
            painter: const _Spine(top: 236),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 40),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: onBack,
                    child: Text(
                      '← BACK TO CHAT',
                      style: VibeDial.label(color: VibeDial.ink),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Center(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 88,
                        height: 88,
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: VibeDial.bg,
                          border: Border.all(color: VibeDial.pink, width: 1.5),
                        ),
                        child: Avatar(
                          mxContent: room.avatar,
                          name: name,
                          size: 80,
                          client: room.client,
                        ),
                      ),
                      if (other != null && !group)
                        Positioned(
                          right: 2,
                          bottom: 4,
                          child: PresenceBuilder(
                            client: room.client,
                            userId: other,
                            builder: (context, p) => Container(
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: p?.presence.isOnline == true
                                    ? VibeDial.lime
                                    : VibeDial.faint,
                                border: Border.all(color: VibeDial.bg, width: 3),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  name,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: VibeDial.ink,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  (group
                          ? '${VibeGroups.memberCount(room)} members'
                          : (other ?? ''))
                      .toUpperCase(),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: VibeDial.label(size: 9),
                ),
                const SizedBox(height: 12),
                ...rows,
                const SizedBox(height: 20),
                Text(
                  'SWIPE RIGHT TO GO BACK',
                  textAlign: TextAlign.center,
                  style: VibeDial.label(size: 9),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String? _ago(Room room) {
    final t = room.lastEvent?.originServerTs;
    if (t == null) return null;
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'NOW';
    if (d.inHours < 1) return '${d.inMinutes}M';
    if (d.inDays < 1) return '${d.inHours}H';
    return '${d.inDays}D';
  }

  static Widget _section(String text) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 8),
    child: Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: VibeDial.bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: VibeDial.faint),
        ),
        child: Text(text, style: VibeDial.label(size: 9)),
      ),
    ),
  );

  static Widget _pair(_Leaf? left, _Leaf? right) => SizedBox(
    height: 38,
    child: CustomPaint(
      painter: _Elbows(left: left != null, right: right != null),
      child: Row(
        children: [
          Expanded(
            child: left == null
                ? const SizedBox.shrink()
                : Align(
                    alignment: Alignment.centerRight,
                    child: left.build(end: true),
                  ),
          ),
          const SizedBox(width: 72),
          Expanded(
            child: right == null
                ? const SizedBox.shrink()
                : Align(
                    alignment: Alignment.centerLeft,
                    child: right.build(end: false),
                  ),
          ),
        ],
      ),
    ),
  );
}

class _Leaf {
  final String label;
  final String? meta;
  final Color metaColor;
  final VoidCallback? onTap;
  const _Leaf(
    this.label, {
    this.meta,
    this.metaColor = VibeDial.dim,
    this.onTap,
  });

  Widget build({required bool end}) {
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 15,
        color: onTap == null ? VibeDial.dim : VibeDial.ink,
      ),
    );
    final m = meta == null
        ? null
        : Text(meta!, style: VibeDial.label(color: metaColor, size: 10));
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap == null
          ? null
          : () {
              VibeHaptics.selection();
              onTap!();
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: end
              ? [Flexible(child: text), if (m != null) ...[const SizedBox(width: 8), m]]
              : [if (m != null) ...[m, const SizedBox(width: 8)], Flexible(child: text)],
        ),
      ),
    );
  }
}

/// The line down the middle of the tree page, from under the header.
class _Spine extends CustomPainter {
  final double top;
  const _Spine({required this.top});

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2;
    canvas.drawLine(
      Offset(x, top),
      Offset(x, size.height),
      Paint()
        ..color = VibeDial.faint
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_Spine old) => old.top != top;
}

/// A row's branches: from the line, a curve out to each side that has one.
class _Elbows extends CustomPainter {
  final bool left;
  final bool right;
  const _Elbows({required this.left, required this.right});

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2;
    final y = size.height / 2;
    final paint = Paint()
      ..color = VibeDial.faint
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final s in [if (left) -1, if (right) 1]) {
      final path = Path()
        ..moveTo(x, y - 14)
        ..quadraticBezierTo(x, y, x + 12.0 * s, y)
        ..lineTo(x + 30.0 * s, y);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_Elbows old) => old.left != left || old.right != right;
}


/// A picture of the chat you left, turning away round the dial's centre
/// (far below the screen) while the next chat turns in.
class _TurnOut extends StatefulWidget {
  final ui.Image image;
  final int dir;
  final VoidCallback onDone;
  const _TurnOut({required this.image, required this.dir, required this.onDone});

  @override
  State<_TurnOut> createState() => _TurnOutState();
}

class _TurnOutState extends State<_TurnOut>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );

  @override
  void initState() {
    super.initState();
    _c.forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = Curves.easeInCubic.transform(_c.value);
        return Transform(
          alignment: VibeDial.pivot,
          transform: Matrix4.rotationZ(-0.5 * widget.dir * t),
          child: Opacity(
            opacity: 1 - 0.4 * t,
            child: RawImage(
              image: widget.image,
              fit: BoxFit.fill,
              width: double.infinity,
              height: double.infinity,
            ),
          ),
        );
      },
    ),
  );
}

/// A page turning away round the dial's centre as [animation] goes 0 → 1
/// (all chats, while a chat turns in over it).
class VibeDialTurn extends StatelessWidget {
  final Animation<double> animation;
  final bool out;
  final Widget child;
  const VibeDialTurn({
    required this.animation,
    required this.child,
    this.out = true,
    super.key,
  });

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    child: child,
    builder: (context, child) {
      final t = Curves.easeInOutCubic.transform(
        animation.value.clamp(0.0, 1.0),
      );
      return Transform(
        alignment: VibeDial.pivot,
        transform: Matrix4.rotationZ(-0.5 * VibeDial.turnDir * t),
        child: child,
      );
    },
  );
}

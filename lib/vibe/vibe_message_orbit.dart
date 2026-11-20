// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:vibe/l10n/l10n.dart';
import 'package:vibe/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:vibe/vibe/screens/chat/chat.dart';
import 'package:vibe/vibe/vibe_emoji_sheet.dart';
import 'package:vibe/vibe/vibe_event_body.dart';
import 'package:vibe/vibe/vibe_haptics.dart';
import 'package:vibe/vibe/vibe_message_menu.dart';
import 'package:vibe/vibe/vibe_starred.dart';
import 'package:vibe/vibe/vibe_threads.dart';
import 'package:vibe/vibe/buddy/bujji_life.dart';

/// Long-press menu as an orbit: the held message lifts, the chat blurs, and
/// its actions float round the message's end as small glass buttons on a
/// thin dotted arc, with quick reactions on a closer inner arc. Slide
/// without lifting and let go on one, or lift and tap.
abstract class VibeMessageOrbit {
  static Rect? _anchor;
  static DateTime? _at;

  /// Where the held message is on screen (set by the message as it's held).
  static void hold(Rect r) {
    _anchor = r;
    _at = DateTime.now();
  }

  /// The finger that opened the menu, still down: where it moves and where
  /// it lifts. The held message's own gesture reports it, so the menu
  /// follows it even though it opened on top.
  static final _finger = StreamController<(Offset, bool)>.broadcast();

  static void move(Offset global) => _finger.add((global, false));

  static void release(Offset global) => _finger.add((global, true));

  /// The orbit for [event], or the plain sheet when the message's place
  /// isn't known (photo stacks and the like).
  static Future<void> show(
    BuildContext context,
    ChatController controller,
    Event event,
  ) {
    final at = _at, anchor = _anchor;
    _anchor = null;
    if (anchor == null ||
        at == null ||
        DateTime.now().difference(at).inMilliseconds > 1500 ||
        controller.timeline == null) {
      return VibeMessageMenu.sheet(context, controller, event);
    }
    final done = Completer<void>();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _Orbit(
        controller: controller,
        event: event,
        anchor: anchor,
        onClosed: () {
          entry.remove();
          if (!done.isCompleted) done.complete();
        },
      ),
    );
    // on top of the chat, not a new page: opening a page cancels every
    // finger that's down, so the one still holding the message couldn't
    // glide onto an action
    Overlay.of(context, rootOverlay: true).insert(entry);
    return done.future;
  }
}

class _Action {
  final IconData icon;
  final String label;
  final VoidCallback run;
  final bool danger;

  /// Struck through (Unpin): the same icon with a line across it.
  final bool off;
  const _Action(
    this.icon,
    this.label,
    this.run, {
    this.danger = false,
    this.off = false,
  });
}

/// An icon with a slash across it and a thin gap either side of the slash,
/// so taking something back (Unpin) looks different from doing it.
class _OffIcon extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color color;
  const _OffIcon(this.icon, {required this.size, required this.color});

  @override
  Widget build(BuildContext context) => Center(
    child: SizedBox.square(
      dimension: size,
      child: Stack(
        children: [
          ClipPath(
            clipper: const _SlashGap(),
            child: Icon(icon, size: size, color: color),
          ),
          CustomPaint(size: Size.square(size), painter: _SlashLine(color)),
        ],
      ),
    ),
  );
}

class _SlashGap extends CustomClipper<Path> {
  const _SlashGap();

  @override
  Path getClip(Size size) {
    final s = size.width, h = s * 0.11 / math.sqrt2;
    final band = Path()
      ..moveTo(s * 0.1 + h, s * 0.1 - h)
      ..lineTo(s * 0.9 + h, s * 0.9 - h)
      ..lineTo(s * 0.9 - h, s * 0.9 + h)
      ..lineTo(s * 0.1 - h, s * 0.1 + h)
      ..close();
    return Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      band,
    );
  }

  @override
  bool shouldReclip(_SlashGap old) => false;
}

class _SlashLine extends CustomPainter {
  final Color color;
  const _SlashLine(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    canvas.drawLine(
      Offset(s * 0.14, s * 0.14),
      Offset(s * 0.86, s * 0.86),
      Paint()
        ..color = color
        ..strokeWidth = s * 0.085
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_SlashLine old) => old.color != color;
}

const _reactions = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

class _Orbit extends StatefulWidget {
  final ChatController controller;
  final Event event;
  final Rect anchor;
  final VoidCallback onClosed;
  const _Orbit({
    required this.controller,
    required this.event,
    required this.anchor,
    required this.onClosed,
  });

  @override
  State<_Orbit> createState() => _OrbitState();
}

class _OrbitState extends State<_Orbit> with SingleTickerProviderStateMixin {
  static const _r = 118.0; // actions
  static const _rIn = 64.0; // reactions
  static const _btn = 44.0;

  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    reverseDuration: const Duration(milliseconds: 220),
  )..forward();

  /// The action under the finger (0 and up), or a reaction (-1 and down).
  int? _hover;
  Offset? _finger;
  bool _following = true;
  bool _closing = false;
  List<Offset> _spots = const [];
  List<Offset> _rSpots = const [];

  /// A new finger after the menu opened: where it went down, and whether it
  /// has slid (then letting go on an action picks it).
  Offset? _down;
  bool _slid = false;

  ChatController get c => widget.controller;
  Event get e => widget.event;

  StreamSubscription<(Offset, bool)>? _follow;

  /// Where the finger was first seen, and whether it has really glided.
  Offset? _start;
  bool _glided = false;

  @override
  void initState() {
    super.initState();
    // the finger that opened the menu is still down: follow it until it
    // lifts, so you can slide onto an action and let go
    _follow = VibeMessageOrbit._finger.stream.listen(_onFinger);
  }

  @override
  void dispose() {
    _stopFollowing();
    _anim.dispose();
    super.dispose();
  }

  void _stopFollowing() {
    if (!_following) return;
    _following = false;
    _follow?.cancel();
  }

  /// The nearest action (or quick reaction, as -1 - i) within reach of
  /// [p], if any.
  int? _near(Offset p) {
    int? hit;
    var best = _btn * 0.95;
    for (var i = 0; i < _spots.length; i++) {
      final d = (_spots[i] - p).distance;
      if (d < best) {
        best = d;
        hit = i;
      }
    }
    for (var i = 0; i < _rSpots.length; i++) {
      final d = (_rSpots[i] - p).distance;
      if (d < best && d < 26) {
        best = d;
        hit = -1 - i;
      }
    }
    return hit;
  }

  Offset? _spot(int? i) => i == null
      ? null
      : i >= 0
      ? _spots[i]
      : _rSpots[-1 - i];

  /// The finger slid onto something new: light it up with a tick.
  void _hoverAt(Offset p) {
    final hit = _near(p);
    if (hit != _hover && hit != null) VibeHaptics.selection();
    setState(() {
      _hover = hit;
      _finger = p;
    });
  }

  // a new finger on the open menu: slide across the actions, let go on one
  void _onDown(PointerDownEvent p) {
    if (_closing) return;
    _stopFollowing();
    _down = p.position;
    _slid = false;
  }

  void _onMove(PointerMoveEvent p) {
    final d = _down;
    if (d == null || _closing) return;
    if (!_slid && (p.position - d).distance < 12) return;
    _slid = true;
    _hoverAt(p.position);
  }

  void _onUp(PointerUpEvent p) {
    final slid = _slid;
    _down = null;
    _slid = false;
    if (!slid || _closing) return;
    // a tap is left to the buttons; a slide picks where it lets go
    final picked = _near(p.position);
    setState(() {
      _finger = null;
      _hover = null;
    });
    if (picked != null) _pick(picked);
  }

  void _onFinger((Offset, bool) f) {
    if (!mounted || _closing) return;
    final (p, up) = f;
    _start ??= p;
    if ((p - _start!).distance > 18) _glided = true;
    if (!up) {
      _hoverAt(p);
      return;
    }
    // lifted: on an action, that's the pick; anywhere else the menu stays
    // open for a tap
    _stopFollowing();
    // only a glide picks; a plain hold and lift leaves the menu open
    final picked = _glided ? (_near(p) ?? _hover) : null;
    setState(() => _finger = null);
    if (picked != null) _pick(picked);
  }

  late final List<_Action> _actions = _build();

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    _stopFollowing();
    setState(() {
      _hover = null;
      _finger = null;
    });
    _anim.reverse().whenComplete(widget.onClosed);
  }

  void _pick(int i) {
    if (i < 0) {
      _react(_reactions[-1 - i]);
      return;
    }
    VibeHaptics.medium();
    final a = _actions[i];
    _close().then((_) => a.run());
  }

  Future<void> _withSelection(FutureOr<void> Function() action) async {
    c.selectedEvents
      ..clear()
      ..add(e);
    try {
      await action();
    } finally {
      c.selectedEvents.clear();
    }
  }

  void _edit() {
    final timeline = c.timeline;
    if (timeline == null) return;
    BujjiLife.use('edit', e.eventId);
    final text = e
        .getDisplayEvent(timeline)
        .vibeBodyFallback(
          MatrixLocals(L10n.of(c.context)),
          withSenderNamePrefix: false,
          hideReply: true,
        );
    // ignore: invalid_use_of_protected_member
    c.setState(() {
      if (c.editEvent == null) c.pendingText = c.sendController.text;
      c.replyEvent = null;
      c.replyQuote = null;
      c.editEvent = e;
      c.sendController.text = text;
      c.sendController.selection = TextSelection.collapsed(
        offset: text.length,
      );
    });
    c.inputFocus.requestFocus();
  }

  List<_Action> _build() {
    final own = e.senderId == e.room.client.userID;
    final canSend = e.room.canSendDefaultMessages;
    final text = {
      MessageTypes.Text,
      MessageTypes.Notice,
      MessageTypes.Emote,
    }.contains(e.messageType);
    c.selectedEvents
      ..clear()
      ..add(e);
    final canRedact = c.canRedactSelectedEvents;
    final canPin = c.canPinSelectedEvents;
    c.selectedEvents.clear();
    final canEdit =
        own &&
        !c.isArchived &&
        e.type == EventTypes.Message &&
        !e.redacted &&
        text &&
        e.status != EventStatus.error &&
        e.status != EventStatus.sending;
    final pinned = e.room.pinnedEventIds.contains(e.eventId);
    final starred = VibeStarred.isStarred(e.room.id, e.eventId);
    final parent = c.context;
    return [
      if (canSend)
        _Action(
          Icons.reply_rounded,
          'Reply',
          () => c.replyAction(replyTo: e),
        ),
      if (canEdit) _Action(Icons.edit_outlined, 'Edit', _edit),
      // pick some words to copy or quote; its numbers to copy
      if (text && !e.redacted)
        _Action(
          Icons.select_all_rounded,
          'Select',
          () => c.quotePartAction(e),
        ),
      _Action(
        Icons.content_copy_rounded,
        'Copy',
        () => _withSelection(c.copyEventsAction),
      ),
      _Action(
        Icons.shortcut_rounded,
        'Forward',
        () => _withSelection(c.forwardEventsAction),
      ),
      if (!own && canSend && c.activeThreadId == null)
        _Action(
          VibeThreads.icon,
          VibeThreads.isPinned(e.room.id, e.eventId) ? 'Open thread' : 'Thread',
          () => c.createThread(e),
        ),
      if (canPin)
        _Action(
          Icons.push_pin_outlined,
          pinned ? 'Unpin' : 'Pin',
          () => _withSelection(c.pinEvent),
          off: pinned,
        ),
      if (!own)
        _Action(
          starred ? Icons.star_rounded : Icons.star_outline_rounded,
          starred ? 'Unstar' : 'Star',
          () => VibeStarred.toggle(e.room.id, e.eventId),
        ),
      if (own && canRedact)
        _Action(
          Icons.delete_outline_rounded,
          'Delete',
          () => _withSelection(c.redactEventsAction),
          danger: true,
        ),
      // everything else (info, report, hide, star on yours) in the sheet
      _Action(
        Icons.more_horiz_rounded,
        'More',
        () {
          if (parent.mounted) VibeMessageMenu.sheet(parent, c, e);
        },
      ),
    ];
  }

  Future<void> _react(String emoji) async {
    VibeHaptics.light();
    await _close();
    await e.room.sendReaction(e.eventId, emoji);
  }

  Future<void> _allEmoji() async {
    final parent = c.context;
    await _close();
    if (!parent.mounted) return;
    final emoji = await VibeEmojiSheet.pick(parent, room: e.room);
    if (emoji != null) await e.room.sendReaction(e.eventId, emoji);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final route = _anim;
    final own = e.senderId == e.room.client.userID;
    final side = own ? -1.0 : 1.0; // the orbit opens away from the edge

    // the held message, lifted (opened if it's post-quantum)
    final timeline = c.timeline!;
    final body = e
        .getDisplayEvent(timeline)
        .vibeBodyFallback(
          MatrixLocals(L10n.of(context)),
          hideReply: true,
          plaintextBody: true,
        );
    const inset = 45.0, gap = 10.0;
    final room = _r + _btn / 2 + 8;
    final maxW = math.max(
      120.0,
      math.min(size.width * 0.62, size.width - inset - gap - room),
    );
    final style = TextStyle(
      fontSize: 15.5,
      height: 1.35,
      color: cs.onSurface,
    );
    final tp = TextPainter(
      text: TextSpan(text: body, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 6,
      ellipsis: '…',
    )..layout(maxWidth: maxW - 30);
    final bw = tp.width + 30, bh = tp.height + 20;
    tp.dispose();
    final cy = widget.anchor.center.dy.clamp(
      pad.top + room + 30,
      size.height - pad.bottom - room - 10,
    );
    final bubbleLeft = own ? size.width - inset - bw : inset;
    final cx = own
        ? (bubbleLeft - gap).clamp(room, size.width - 100)
        : (inset + bw + gap).clamp(100.0, size.width - room);
    final center = Offset(cx.toDouble(), cy.toDouble());

    Offset at(double radius, double deg) {
      final a = deg * math.pi / 180;
      return center + Offset(side * radius * math.cos(a), radius * math.sin(a));
    }

    final n = _actions.length;
    final span = n <= 1 ? 0.0 : math.min(168.0, 28.0 * (n - 1));
    _spots = [
      for (var i = 0; i < n; i++)
        at(_r, n <= 1 ? 0 : -span / 2 + i * span / (n - 1)),
    ];
    final reacts = e.room.canSendDefaultMessages;
    _rSpots = [
      if (reacts)
        for (var i = 0; i < _reactions.length; i++)
          at(_rIn, -70 + i * 140 / (_reactions.length - 1)),
    ];
    final glass = dark
        ? const Color(0xDC262932)
        : cs.surfaceContainerHighest.withValues(alpha: 0.95);
    final iconInk = dark ? const Color(0xFFDADDE8) : cs.onSurface;
    final hi = Color.lerp(cs.primary, Colors.white, 0.45)!;

    final orbit = AnimatedBuilder(
      animation: route,
      builder: (context, _) {
        final t = Curves.easeOut.transform(route.value);
        return Material(
          type: MaterialType.transparency,
          child: Stack(
          children: [
            // the chat blurs and dims; tap anywhere to close
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _close,
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 7 * t, sigmaY: 7 * t),
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: (dark ? .7 : .45) * t),
                  ),
                ),
              ),
            ),
            // a soft glow of the theme colour behind the orbit
            Positioned(
              left: center.dx - 170,
              top: center.dy - 170,
              width: 340,
              height: 340,
              child: IgnorePointer(
                child: Opacity(
                  opacity: t,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        colors: [
                          cs.primary.withValues(alpha: 0.22),
                          cs.primary.withValues(alpha: 0),
                        ],
                        stops: const [0, 0.62],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // the dotted orbit, the reactions' track and the finger's trail
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _OrbitPainter(
                    center: center,
                    side: side,
                    r: _r,
                    rIn: _rIn,
                    span: span,
                    t: t,
                    line: hi.withValues(alpha: 0.3),
                    track: (dark ? Colors.white : Colors.black).withValues(
                      alpha: 0.07,
                    ),
                    finger: _finger,
                    target: _spot(_hover),
                    trail: cs.primary,
                  ),
                ),
              ),
            ),
            // the held message, lifted a little
            Positioned(
              left: bubbleLeft,
              top: center.dy - bh / 2,
              child: Transform.scale(
                scale: 1 + 0.03 * t,
                alignment: own ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: bw,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: own
                        ? Color.alphaBlend(
                            cs.primaryContainer,
                            dark ? const Color(0xFF1B1B1F) : Colors.white,
                          )
                        : cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5 * t),
                        blurRadius: 30,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Text(
                    body,
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                    style: style.copyWith(
                      color: own ? cs.onPrimaryContainer : cs.onSurface,
                    ),
                  ),
                ),
              ),
            ),
            // quick reactions on the inner arc; hold one for all emoji
            if (reacts)
              for (var i = 0; i < _reactions.length; i++)
                _place(
                  Offset.lerp(
                    center,
                    at(_rIn, -70 + i * 140 / (_reactions.length - 1)),
                    Curves.easeOutBack.transform(
                      _stagger(route.value, i, _reactions.length),
                    ),
                  )!,
                  32,
                  Opacity(
                    opacity: t,
                    child: GestureDetector(
                      onTap: () => _react(_reactions[i]),
                      onLongPress: _allEmoji,
                      child: Center(
                        // grows while a sliding finger is on it
                        child: AnimatedScale(
                          scale: _hover == -1 - i ? 1.45 : 1,
                          duration: const Duration(milliseconds: 140),
                          child: Text(
                            _reactions[i],
                            style: const TextStyle(fontSize: 19),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            // the actions, flying out of the message one after another
            for (var i = 0; i < n; i++)
              _button(i, center, route.value, glass, iconInk, cs),
          ],
          ),
        );
      },
    );
    // Back closes it; once closing, touches go through to the chat
    return BackButtonListener(
      onBackButtonPressed: () async {
        _close();
        return true;
      },
      child: IgnorePointer(
        ignoring: _closing,
        child: Listener(
          onPointerDown: _onDown,
          onPointerMove: _onMove,
          onPointerUp: _onUp,
          onPointerCancel: (_) => _down = null,
          child: orbit,
        ),
      ),
    );
  }

  double _stagger(double v, int i, int n) =>
      ((v - i * 0.35 / n) / 0.65).clamp(0.0, 1.0);

  Widget _place(Offset p, double d, Widget child) => Positioned(
    left: p.dx - d / 2,
    top: p.dy - d / 2,
    width: d,
    height: d,
    child: child,
  );

  Widget _button(
    int i,
    Offset center,
    double v,
    Color glass,
    Color iconInk,
    ColorScheme cs,
  ) {
    final a = _actions[i];
    final on = _hover == i;
    final p = Offset.lerp(
      center,
      _spots[i],
      Curves.easeOutBack.transform(_stagger(v, i, _actions.length)),
    )!;
    final d = on ? 56.0 : _btn;
    final ink = a.danger ? const Color(0xFFF87171) : iconInk;
    final button = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      width: d,
      height: d,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: on ? null : glass,
        gradient: on
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(cs.primary, Colors.white, 0.45)!,
                  cs.primary,
                ],
              )
            : null,
        border: on
            ? null
            : Border.all(color: Colors.white.withValues(alpha: 0.07)),
        boxShadow: [
          on
              ? BoxShadow(
                  color: cs.primary.withValues(alpha: 0.45),
                  blurRadius: 26,
                  spreadRadius: 2,
                )
              : const BoxShadow(
                  color: Color(0x73000000),
                  blurRadius: 18,
                  offset: Offset(0, 6),
                ),
        ],
      ),
      child: a.off
          ? _OffIcon(
              a.icon,
              size: on ? 25 : 21,
              color: on ? cs.onPrimary : ink,
            )
          : Icon(
              a.icon,
              size: on ? 25 : 21,
              color: on ? cs.onPrimary : ink,
            ),
    );
    return Stack(
      children: [
        _place(
          p,
          56,
          Opacity(
            opacity: _stagger(v, i, _actions.length),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _pick(i),
              child: Center(child: button),
            ),
          ),
        ),
        // its name floats just above it while it's chosen
        if (on)
          Positioned(
            left: p.dx - 70,
            width: 140,
            top: p.dy - 28 - 38,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xF0141619),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                      color: cs.primary.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    a.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color.lerp(cs.primary, Colors.white, 0.5),
                      decoration: TextDecoration.none,
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

class _OrbitPainter extends CustomPainter {
  final Offset center;
  final double side, r, rIn, span, t;
  final Color line, track, trail;
  final Offset? finger, target;
  const _OrbitPainter({
    required this.center,
    required this.side,
    required this.r,
    required this.rIn,
    required this.span,
    required this.t,
    required this.line,
    required this.track,
    required this.trail,
    this.finger,
    this.target,
  });

  Offset _at(double radius, double deg) {
    final a = deg * math.pi / 180;
    return center + Offset(side * radius * math.cos(a), radius * math.sin(a));
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0) return;
    // the reactions' soft track
    final band = Paint()
      ..color = track.withValues(alpha: track.a * t)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 30
      ..strokeCap = StrokeCap.round;
    final rect = Rect.fromCircle(center: center, radius: rIn);
    const sweep = 140 * math.pi / 180;
    final start = side > 0 ? -70 * math.pi / 180 : math.pi - 70 * math.pi / 180;
    canvas.drawArc(rect, start, sweep, false, band);
    // the dotted orbit
    final dot = Paint()..color = line.withValues(alpha: line.a * t);
    final half = span / 2 + 6;
    for (var d = -half; d <= half; d += 4.2) {
      canvas.drawCircle(_at(r, d), 0.9, dot);
    }
    // the finger's light trail to the chosen action
    final f = finger, g = target;
    if (f != null && g != null) {
      final mid = Offset((f.dx + g.dx) / 2 + side * 30, (f.dy + g.dy) / 2);
      final path = Path()
        ..moveTo(f.dx, f.dy)
        ..quadraticBezierTo(mid.dx, mid.dy, g.dx, g.dy);
      canvas.drawPath(
        path,
        Paint()
          ..shader = ui.Gradient.linear(f, g, [
            trail.withValues(alpha: 0.1),
            trail,
          ])
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawCircle(f, 16, Paint()..color = trail.withValues(alpha: 0.18));
      canvas.drawCircle(f, 5, Paint()..color = trail);
    }
  }

  @override
  bool shouldRepaint(covariant _OrbitPainter old) =>
      old.center != center ||
      old.t != t ||
      old.finger != finger ||
      old.target != target ||
      old.span != span;
}

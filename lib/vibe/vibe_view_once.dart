// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:matrix/matrix.dart';
import 'package:vibe/config/setting_keys.dart';
import 'package:vibe/vibe/screens/chat/events/message_content.dart';
import 'package:vibe/vibe/vibe_haptics.dart';

/// View once: a message or photo the other person can open one time. Once
/// they close it, it turns to dust and is gone; the sender's app then
/// deletes it for everyone.
abstract class VibeViewOnce {
  static const key = 'chat.keepr.view_once';

  /// Sent by whoever opened it, pointing at the message.
  static const viewedType = 'chat.keepr.viewed';
  static const _store = 'chat.keepr.viewed_once';

  static bool of(Event e) => e.content[key] == true;

  static Set<String> _viewed() =>
      (AppSettings.store.getStringList(_store) ?? const []).toSet();

  static bool viewed(Event e) => _viewed().contains(e.eventId);

  static Future<void> _markViewed(Event e) async {
    final list = _viewed()..add(e.eventId);
    // keep the list short
    final keep = list.length > 500 ? list.skip(list.length - 500) : list;
    await AppSettings.store.setStringList(_store, keep.toList());
    try {
      await e.room.sendEvent({
        'm.relates_to': {'rel_type': 'm.reference', 'event_id': e.eventId},
      }, type: viewedType);
    } catch (_) {}
  }

  /// A text message that can be opened once.
  static Future<void> sendText(Room room, String text) => room.sendEvent({
    'msgtype': MessageTypes.Text,
    'body': text,
    key: true,
  });

  static StreamSubscription? _sub;
  static final _deleting = <String>{};

  /// Your app deletes your view-once message once someone has opened it.
  static void start(Client client) {
    _sub?.cancel();
    _sub = client.onTimelineEvent.stream.listen((e) async {
      if (e.type != viewedType || e.senderId == client.userID) return;
      final id = e.relationshipEventId;
      if (id == null || !_deleting.add(id)) return;
      try {
        final original = await e.room.getEventById(id);
        if (original != null &&
            original.senderId == client.userID &&
            of(original) &&
            !original.redacted) {
          await e.room.redactEvent(id, reason: 'Viewed once');
        }
      } catch (_) {
        _deleting.remove(id);
      }
    });
  }
}

/// What a view-once message shows in the chat: a small pill. Yours says it
/// was sent; theirs opens it full screen, then it turns to dust.
class VibeViewOnceTile extends StatefulWidget {
  final Event event;
  final Timeline timeline;
  final bool own;
  final Color color;
  final Color ink;
  const VibeViewOnceTile({
    required this.event,
    required this.timeline,
    required this.own,
    required this.color,
    required this.ink,
    super.key,
  });

  @override
  State<VibeViewOnceTile> createState() => _VibeViewOnceTileState();
}

class _VibeViewOnceTileState extends State<VibeViewOnceTile> {
  final _key = GlobalKey();
  late bool _gone = !widget.own && VibeViewOnce.viewed(widget.event);

  String get _what => switch (widget.event.messageType) {
    MessageTypes.Image => 'Photo',
    MessageTypes.Video => 'Video',
    MessageTypes.Audio => 'Voice message',
    MessageTypes.File => 'File',
    _ => 'Message',
  };

  Future<void> _open() async {
    VibeHaptics.medium();
    await Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, a, _) => FadeTransition(
          opacity: a,
          child: _OnceViewer(event: widget.event, timeline: widget.timeline),
        ),
      ),
    );
    if (!mounted) return;
    VibeHaptics.light();
    await VibeDust.vanish(context, _key);
    if (!mounted) return;
    setState(() => _gone = true);
    unawaited(VibeViewOnce._markViewed(widget.event));
  }

  @override
  Widget build(BuildContext context) {
    if (_gone) return const SizedBox.shrink();
    final own = widget.own;
    return RepaintBoundary(
      key: _key,
      child: Material(
        color: widget.color,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: own ? null : _open,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: widget.ink, width: 1.6),
                  ),
                  child: Text(
                    '1',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: widget.ink,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  own ? '$_what · view once' : '$_what · tap to view once',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: widget.ink,
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

/// The message full screen, once.
class _OnceViewer extends StatelessWidget {
  final Event event;
  final Timeline timeline;
  const _OnceViewer({required this.event, required this.timeline});

  @override
  Widget build(BuildContext context) {
    final text = !{
      MessageTypes.Image,
      MessageTypes.Video,
      MessageTypes.Audio,
      MessageTypes.File,
    }.contains(event.messageType);
    final content = MessageContent(
      event,
      timeline: timeline,
      textColor: Colors.white,
      linkColor: Colors.white,
      borderRadius: BorderRadius.circular(16),
      selected: false,
      bigEmojis: const {},
    );
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 64, 24, 40),
                child: text
                    ? SingleChildScrollView(
                        child: DefaultTextStyle.merge(
                          style: const TextStyle(fontSize: 22, height: 1.4),
                          child: content,
                        ),
                      )
                    : event.messageType == MessageTypes.Image
                    // no tap-through to the normal viewer (no saving)
                    ? InteractiveViewer(
                        maxScale: 5,
                        child: AbsorbPointer(child: content),
                      )
                    : content,
              ),
            ),
            Positioned(
              left: 8,
              top: 8,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            const Positioned(
              right: 20,
              top: 20,
              child: Text(
                'View once',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Turns a widget to dust: it breaks into specks that drift up and to the
/// side and fade, sweeping across it.
abstract class VibeDust {
  /// [key] is on a [RepaintBoundary] around what should vanish. Returns once
  /// the dust has gone (hide the widget when it returns).
  static Future<void> vanish(BuildContext context, GlobalKey key) async {
    final box = key.currentContext?.findRenderObject();
    if (box is! RenderRepaintBoundary || !box.hasSize) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final ui.Image image;
    try {
      image = await box.toImage(pixelRatio: ratio);
    } catch (_) {
      return;
    }
    final at = box.localToGlobal(Offset.zero);
    final size = box.size;
    final done = Completer<void>();
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Positioned(
        left: at.dx,
        top: at.dy,
        width: size.width,
        height: size.height,
        child: IgnorePointer(
          child: _Dust(
            image: image,
            ratio: ratio,
            onDone: () {
              entry.remove();
              image.dispose();
              if (!done.isCompleted) done.complete();
            },
          ),
        ),
      ),
    );
    overlay.insert(entry);
    // the widget can go now: the dust is drawn on top in its place
    await Future<void>.delayed(const Duration(milliseconds: 16));
    return done.future;
  }
}

class _Dust extends StatefulWidget {
  final ui.Image image;
  final double ratio;
  final VoidCallback onDone;
  const _Dust({required this.image, required this.ratio, required this.onDone});

  @override
  State<_Dust> createState() => _DustState();
}

class _DustState extends State<_Dust> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..forward().whenComplete(widget.onDone);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _DustPainter(widget.image, widget.ratio, _c),
    size: Size.infinite,
  );
}

class _DustPainter extends CustomPainter {
  final ui.Image image;
  final double ratio;
  final Animation<double> t;
  late final List<_Speck> _specks = _make();
  _DustPainter(this.image, this.ratio, this.t) : super(repaint: t);

  List<_Speck> _make() {
    final rnd = math.Random(image.width * 31 + image.height);
    const cell = 3.0;
    final w = image.width / ratio, h = image.height / ratio;
    final out = <_Speck>[];
    for (var y = 0.0; y < h; y += cell) {
      for (var x = 0.0; x < w; x += cell) {
        out.add(
          _Speck(
            Rect.fromLTWH(x * ratio, y * ratio, cell * ratio, cell * ratio),
            Offset(x, y),
            // the sweep goes left to right, with some scatter
            (x / w) * 0.55 + rnd.nextDouble() * 0.2,
            Offset(
              18 + rnd.nextDouble() * 50,
              -(12 + rnd.nextDouble() * 46),
            ),
            (rnd.nextDouble() - 0.5) * 2,
          ),
        );
      }
    }
    return out;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final v = t.value;
    final transforms = <RSTransform>[];
    final rects = <Rect>[];
    final colors = <Color>[];
    for (final s in _specks) {
      final p = ((v - s.delay) / 0.45).clamp(0.0, 1.0);
      if (p >= 1) continue;
      final e = Curves.easeIn.transform(p);
      final pos = s.at + s.drift * e;
      transforms.add(
        RSTransform.fromComponents(
          rotation: s.spin * e,
          scale: (1 / ratio) * (1 - 0.4 * e),
          anchorX: 0,
          anchorY: 0,
          translateX: pos.dx,
          translateY: pos.dy,
        ),
      );
      rects.add(s.src);
      colors.add(Colors.white.withValues(alpha: 1 - e));
    }
    if (rects.isEmpty) return;
    canvas.drawAtlas(
      image,
      transforms,
      rects,
      colors,
      BlendMode.modulate,
      null,
      Paint()..filterQuality = FilterQuality.low,
    );
  }

  @override
  bool shouldRepaint(covariant _DustPainter old) => old.image != image;
}

class _Speck {
  final Rect src;
  final Offset at;
  final double delay;
  final Offset drift;
  final double spin;
  const _Speck(this.src, this.at, this.delay, this.drift, this.spin);
}

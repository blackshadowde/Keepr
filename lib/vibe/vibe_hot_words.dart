// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math' as math;

import 'package:vibe/vibe/vibe_haptics.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

/// Hot words: some words fill the whole screen when they're sent or arrive,
/// like in Google Messages and iMessage, each with its own little scene.
enum VibeScene {
  laugh(2.8), // hahaha: big "HA"s pop all over and shake with laughter
  congrats(3.2), // congratulations: a gold shimmer, curly streamers, a trophy
  kiss(2.8), // kiss: lips fly in, stamp the middle, hearts puff out
  hug(3.0), // hug: two warm arms close around the middle and squeeze
  party(3.4), // party: disco ball, sweeping coloured beams, confetti
  birthday(3.6), // happy birthday: balloons float past a glowing cake
  goodNight(3.4), // good night: night falls, moon, stars, Zz
  love(3.0), // love you: a big heart beats twice and breaks into little ones
  missYou(3.4), // miss you: a paper plane carries a heart across and drops it
  goodMorning(3.4), // good morning: the sun rises, birds fly by
  thanks(3.0), // thank you: a flower blooms around 🙏, petals drift down
  sorry(3.4), // sorry: "Sorry" writes itself in one soft handwritten stroke
  wow(2.4), // wow / omg: a comic burst with speed lines behind "WOW!"
  sweetDreams(3.6), // sweet dreams: a soft dusk, a moon on a cloud, hearts and stars float up
  welcome(3.2), // welcome: golden rays, a ribbon with "WELCOME", stars fall
  bye(2.8), // bye: a big hand waves goodbye and floats away
  hi(2.6), // hi / hello / namaste: a hand waves in, ripples and a "Hi!" bubble
  rain(3.4), // rain / thunder / storm: the sky darkens, rain pours, lightning flashes
  summer(3.2), // sunny / summer / so hot: a blazing sun, heat waves rising
  winter(3.6); // winter / cold / chali: a cold blue tint, snowflakes drift down

  const VibeScene(this.seconds);
  final double seconds;
}

abstract class VibeHotWords {
  static RegExp _r(String p) => RegExp(p, caseSensitive: false, unicode: true);

  static final List<(VibeScene, RegExp)> _rules = [
    (VibeScene.birthday, _r(r'happy\s*b(irth)?day|\bhbd\b|🎂|janmadin|जन्मदिन|పుట్టినరోజు')),
    (VibeScene.congrats, _r(r'congrat|\bcongo\b|badhai|बधाई|అభినందన')),
    (VibeScene.goodMorning, _r(r'good\s*m(o|or)ning|\bgud\s*m(o|or)?n(i|n)?ng\b|\bgm\b|suprabhat|सुप्रभात|శుభోదయం|🌅')),
    (VibeScene.sweetDreams, _r(r'sweet\s*dreams?|\bswt\s*drms?\b|मीठे\s*सपने')),
    (VibeScene.goodNight, _r(r'good\s*night|\bgud\s*n(i|y)te?\b|\bgn8\b|shubh\s*ratri|शुभ\s*रात्रि|శుభ\s*రాత్రి|😴|🌙')),
    (VibeScene.missYou, _r(r'\bmiss(ed|ing)?\s*(you|u|ya)\b|🥺')),
    (VibeScene.love, _r(r'\bi\s*love\s*(you|u)\b|\blove\s*(you|u)\b|\bily\b|\bluv\s*(you|u)\b|❤️❤️|💖|💗')),
    (VibeScene.kiss, _r(r'\bkiss(es|y)?\b|\bmwa+h*\b|\bumm?ah+\b|😘|💋|😚')),
    (VibeScene.hug, _r(r'\bhugs?\b|\*hug|\bjhappi\b|🤗|🫂')),
    (VibeScene.party, _r(r'\bpart(y|ee)+\b|\bcelebrat|🥳|🪩')),
    (VibeScene.thanks, _r(r'\bthank(s|\s*you|\s*u|q)\b|\bthanx\b|\bthx\b|\bty\b|dhanyavaa?d|धन्यवाद|ధన్యవాదాలు|🙏')),
    (VibeScene.sorry, _r(r'\bsorry\b|\bsry\b|\bmy\s*bad\b|\bmaaf\b|माफ़|క్షమించు')),
    (VibeScene.wow, _r(r'\bwo+w+\b|\bomg\b|\bwh?oa+h?\b|😮|🤯|😱')),
    (VibeScene.welcome, _r(r"(?<!you'?re\s)(?<!your\s)(?<!ur\s)\bwelcome\b|\bswagat|स्वागत|స్వాగతం")),
    (VibeScene.bye, _r(r'\b(good\s*)?by+e+\b|\bbye\s*bye\b|\bta\s*ta\b|\bcya\b|\bsee\s*(you|ya|u)\b|अलविदा')),
    (VibeScene.hi, _r(r'^\s*(hi+|hel+o+|hey+|hai+|namaste|namaskar|नमस्ते|నమస్తే|👋)(\s|[!.,]|$)')),
    (VibeScene.rain, _r(r'\brain(s|ing|y|ed)?\b|\bthunder\w*|\bstorm\w*|\bstrom\b|\blightning\b|\bbaa?rish\b|बारिश|వర్షం|⛈|🌧')),
    (VibeScene.summer, _r(r'\bsunny\b|\by?enda+\b|\bfull\s*hot\b|\bso\s*hot\b|\bsummer\b|\bgarmi\b|गर्मी|ఎండ|🥵|☀️')),
    (VibeScene.winter, _r(r'\bchali\b|\bwinter\b|\bso\s*cold\b|\bfreezing\b|\bcool\s*(weather|breeze|day|morning|night|climate)\b|\bthand\b|ठंड|सर्दी|చలి|❄|🥶|⛄')),
    (VibeScene.laugh, _r(r'\b(ha){3,}h?\b|\b(he){3,}\b|\blo+l+\b|\blmf?a+o+\b|\brofl\b|😂|🤣')),
  ];

  static VibeScene? match(String text) {
    final all = matchAll(text);
    return all.isEmpty ? null : all.first;
  }

  /// Every hot word in the text (up to 3, in the rules' order), so
  /// "good morning, love you, hahaha" plays all three together.
  static List<VibeScene> matchAll(String text) {
    final t = text.trim();
    if (t.isEmpty || t.length > 400) return const [];
    return [
      for (final (scene, re) in _rules)
        if (re.hasMatch(t)) scene,
    ].take(3).toList();
  }

  static final Set<String> _played = {};

  /// Scenes with a full-screen tint (night sky, sunrise, disco...): only one
  /// of them tints at a time, the others play on top of it.
  static const _backdrops = {
    VibeScene.hug,
    VibeScene.party,
    VibeScene.goodNight,
    VibeScene.sweetDreams,
    VibeScene.missYou,
    VibeScene.goodMorning,
    VibeScene.rain,
    VibeScene.summer,
    VibeScene.winter,
  };

  static OverlayEntry? _entry;
  static final _stage = GlobalKey<_StageState>();
  static final List<_Layer> _queue = [];

  /// Plays the scene for a text message that was just sent or just arrived, once.
  static void maybePlay(BuildContext context, Event event) {
    if (event.type != EventTypes.Message || event.redacted) return;
    if (event.messageType != MessageTypes.Text) return;
    final ids = {event.eventId, ?event.transactionId};
    if (ids.any(_played.contains)) return;
    final fresh = DateTime.now().difference(event.originServerTs).inSeconds.abs() < 30;
    if (!fresh) return;
    final scenes = matchAll(event.body);
    if (scenes.isEmpty) return;
    _played.addAll(ids);
    Future<void>.delayed(const Duration(milliseconds: 520), () {
      if (context.mounted) playAll(context, scenes);
    });
  }

  static void play(BuildContext context, VibeScene scene) =>
      playAll(context, [scene]);

  /// Smart merging: scenes join whatever is already playing instead of
  /// waiting. Several in one message come in one after another; the same
  /// scene twice is shown once; only one full-screen tint at a time.
  static void playAll(BuildContext context, List<VibeScene> scenes) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    final active = [...?_stage.currentState?._layers, ..._queue];
    var tinted = active.any((l) => l.bg);
    var delay = 0;
    final add = <_Layer>[];
    for (final scene in scenes) {
      if (active.any((l) => l.scene == scene) ||
          add.any((l) => l.scene == scene)) {
        continue; // already on screen
      }
      if (active.length + add.length >= 4) break; // keep it readable
      final bg = !tinted && _backdrops.contains(scene);
      if (bg) tinted = true;
      add.add(
        _Layer(
          scene,
          bg: bg,
          // one set of buzzes at a time
          haptics: active.isEmpty && add.isEmpty,
          delay: Duration(milliseconds: delay),
        ),
      );
      delay += 450;
    }
    if (add.isEmpty) return;
    final stage = _stage.currentState;
    if (stage != null) {
      stage._add(add);
      return;
    }
    _queue.addAll(add);
    if (_entry != null) return;
    _entry = OverlayEntry(
      builder: (_) => IgnorePointer(
        child: _Stage(
          key: _stage,
          onEmpty: () {
            _entry?.remove();
            _entry = null;
          },
        ),
      ),
    );
    overlay.insert(_entry!);
  }
}

class _Layer {
  _Layer(this.scene, {required this.bg, required this.haptics, required this.delay});
  final VibeScene scene;
  final bool bg;
  final bool haptics;
  final Duration delay;
  final Key key = UniqueKey();
}

/// All scenes playing right now, painted on top of each other.
class _Stage extends StatefulWidget {
  const _Stage({required this.onEmpty, super.key});
  final VoidCallback onEmpty;

  @override
  State<_Stage> createState() => _StageState();
}

class _StageState extends State<_Stage> {
  final List<_Layer> _layers = [];

  @override
  void initState() {
    super.initState();
    _layers.addAll(VibeHotWords._queue);
    VibeHotWords._queue.clear();
  }

  void _add(List<_Layer> add) => setState(() => _layers.addAll(add));

  void _done(_Layer l) {
    if (!mounted) return;
    setState(() => _layers.remove(l));
    if (_layers.isEmpty) widget.onEmpty();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      for (final l in _layers)
        _ScenePlayer(
          key: l.key,
          scene: l.scene,
          bg: l.bg,
          haptics: l.haptics,
          delay: l.delay,
          onDone: () => _done(l),
        ),
    ],
  );
}

class _ScenePlayer extends StatefulWidget {
  const _ScenePlayer({
    required this.scene,
    required this.onDone,
    this.bg = true,
    this.haptics = true,
    this.delay = Duration.zero,
    super.key,
  });
  final VibeScene scene;
  final VoidCallback onDone;
  final bool bg;
  final bool haptics;
  final Duration delay;

  @override
  State<_ScenePlayer> createState() => _ScenePlayerState();
}

class _ScenePlayerState extends State<_ScenePlayer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: (widget.scene.seconds * 1000).round()),
  );
  final int _seed = math.Random().nextInt(1 << 30);

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(widget.delay, () {
      if (!mounted) return;
      if (widget.haptics) _haptics();
      _c.forward().whenComplete(widget.onDone);
    });
  }

  Future<void> _haptics() async {
    Future<void> wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));
    switch (widget.scene) {
      case VibeScene.laugh:
        for (var i = 0; i < 5; i++) {
          VibeHaptics.light();
          await wait(140);
        }
      case VibeScene.kiss:
        await wait(900);
        VibeHaptics.medium();
      case VibeScene.hug:
        await wait(500);
        VibeHaptics.light();
        await wait(450);
        VibeHaptics.heavy();
      case VibeScene.party:
        for (var i = 0; i < 8; i++) {
          VibeHaptics.selection();
          await wait(260);
        }
      case VibeScene.love:
        for (var i = 0; i < 2; i++) {
          VibeHaptics.light();
          await wait(150);
          VibeHaptics.medium();
          await wait(550);
        }
      case VibeScene.wow:
        VibeHaptics.heavy();
        await wait(120);
        VibeHaptics.light();
      case VibeScene.thanks:
        await wait(300);
        VibeHaptics.light();
        await wait(200);
        VibeHaptics.light();
      case VibeScene.sorry:
        await wait(1500);
        VibeHaptics.light();
      case VibeScene.missYou:
        await wait(1700);
        VibeHaptics.medium();
      case VibeScene.bye:
      case VibeScene.hi:
        for (var i = 0; i < 3; i++) {
          await wait(i == 0 ? 300 : 260);
          VibeHaptics.light();
        }
      case VibeScene.sweetDreams:
        await wait(500);
        VibeHaptics.light();
      case VibeScene.welcome:
        await wait(350);
        VibeHaptics.medium();
      case VibeScene.rain:
        // thunder with each flash
        await wait(700);
        VibeHaptics.heavy();
        await wait(1000);
        VibeHaptics.medium();
      case VibeScene.summer:
        await wait(400);
        VibeHaptics.light();
      case VibeScene.winter:
        for (var i = 0; i < 3; i++) {
          await wait(500);
          VibeHaptics.selection();
        }
      default:
        VibeHaptics.medium();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.expand(
    child: CustomPaint(
      painter: _ScenePainter(widget.scene, _c, _seed, bg: widget.bg),
    ),
  );
}

// ---- helpers ----

double _seg(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);
double _smooth(double t) => t * t * (3 - 2 * t);
double _fadeInOut(double t, double inEnd, double outStart) => math.min(_seg(t, 0, inEnd), 1 - _seg(t, outStart, 1));
double _backOut(double t) {
  const c1 = 1.9;
  const c3 = c1 + 1;
  final x = t - 1;
  return 1 + c3 * x * x * x + c1 * x * x;
}

Path _heart(Offset c, double w) => Path()
  ..moveTo(c.dx, c.dy + w * 0.36)
  ..cubicTo(c.dx - w * 0.62, c.dy - w * 0.02, c.dx - w * 0.36, c.dy - w * 0.6, c.dx, c.dy - w * 0.24)
  ..cubicTo(c.dx + w * 0.36, c.dy - w * 0.6, c.dx + w * 0.62, c.dy - w * 0.02, c.dx, c.dy + w * 0.36)
  ..close();

Path _sparkle(Offset c, double r) => Path()
  ..moveTo(c.dx, c.dy - r)
  ..quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy)
  ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
  ..quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy)
  ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r)
  ..close();

Paint _fill(Color c) => Paint()..color = c;
Paint _stroke(Color c, double w) => Paint()
  ..color = c
  ..style = PaintingStyle.stroke
  ..strokeWidth = w
  ..strokeCap = StrokeCap.round;

Color _a(Color c, double a) => c.withValues(alpha: (c.a * a.clamp(0.0, 1.0)));

class _ScenePainter extends CustomPainter {
  _ScenePainter(this.scene, this.anim, this.seed, {this.bg = true})
      : super(repaint: anim);
  final VibeScene scene;

  /// Paints the full-screen tint (only one merged scene does).
  final bool bg;
  final Animation<double> anim;
  final int seed;
  final Map<String, TextPainter> _text = {};
  static final _hasWord = RegExp(r'[A-Za-z0-9]');

  void _glyph(Canvas canvas, String s, double size, Offset at, {double alpha = 1, double scale = 1, double deg = 0, bool bold = false, Color color = Colors.white}) {
    if (alpha <= 0 || scale <= 0) return;
    // only words ("HA", "WOW!", "Hi!", "Zz"...): no emojis over the scenes,
    // the full-screen animation is the effect
    // (the kiss keeps its lips)
    if (!_hasWord.hasMatch(s) && s != '💋') return;
    final key = '$s|$size|$bold|${color.toARGB32()}';
    final tp = _text.putIfAbsent(key, () => TextPainter(
          text: TextSpan(
            text: s,
            style: TextStyle(fontSize: size, fontWeight: bold ? FontWeight.w900 : null, color: bold ? color : null),
          ),
          textDirection: TextDirection.ltr,
        )..layout());
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(deg * math.pi / 180);
    canvas.scale(scale);
    canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, alpha.clamp(0.0, 1.0)));
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = anim.value;
    final r = math.Random(seed);
    final w = size.width, h = size.height;
    switch (scene) {
      case VibeScene.laugh:
        _laugh(canvas, t, r, w, h);
      case VibeScene.congrats:
        _congrats(canvas, t, r, w, h);
      case VibeScene.kiss:
        _kiss(canvas, t, r, w, h);
      case VibeScene.hug:
        _hug(canvas, t, r, w, h);
      case VibeScene.party:
        _party(canvas, t, r, w, h);
      case VibeScene.birthday:
        _birthday(canvas, t, r, w, h);
      case VibeScene.goodNight:
        _goodNight(canvas, t, r, w, h);
      case VibeScene.love:
        _love(canvas, t, r, w, h);
      case VibeScene.missYou:
        _missYou(canvas, t, r, w, h);
      case VibeScene.goodMorning:
        _goodMorning(canvas, t, r, w, h);
      case VibeScene.thanks:
        _thanks(canvas, t, r, w, h);
      case VibeScene.sorry:
        _sorry(canvas, t, r, w, h);
      case VibeScene.wow:
        _wow(canvas, t, r, w, h);
      case VibeScene.sweetDreams:
        _sweetDreams(canvas, t, r, w, h);
      case VibeScene.welcome:
        _welcome(canvas, t, r, w, h);
      case VibeScene.bye:
        _wave(canvas, t, r, w, h, bye: true);
      case VibeScene.hi:
        _wave(canvas, t, r, w, h, bye: false);
      case VibeScene.rain:
        _rain(canvas, t, r, w, h);
      case VibeScene.summer:
        _summer(canvas, t, r, w, h);
      case VibeScene.winter:
        _winter(canvas, t, r, w, h);
    }
  }

  void _laugh(Canvas c, double t, math.Random r, double w, double h) {
    const colors = [Color(0xFFFFC83D), Color(0xFFFF8A3D), Color(0xFFFF5FA2), Color(0xFF8C96F6), Color(0xFF4FC3F7)];
    for (var i = 0; i < 14; i++) {
      final x = w * (0.12 + r.nextDouble() * 0.76);
      final y = h * (0.16 + r.nextDouble() * 0.62);
      final size = 34 + r.nextDouble() * 34;
      final tilt = (r.nextDouble() - 0.5) * 36;
      final col = colors[r.nextInt(colors.length)];
      final word = r.nextInt(4) == 0 ? 'HA!' : 'HA';
      final u = _seg(t, i * 0.035, i * 0.035 + 0.62);
      if (u <= 0 || u >= 1) continue;
      final shake = math.sin(u * 40 + i) * 8 * (1 - u);
      _glyph(c, word, size, Offset(x, y - u * 40), alpha: 1 - _seg(u, 0.7, 1), scale: _backOut(_seg(u, 0, 0.22)), deg: tilt + shake, bold: true, color: col);
    }
    for (var i = 0; i < 4; i++) {
      final u = _seg(t, 0.05 + i * 0.08, 0.95);
      if (u <= 0 || u >= 1) continue;
      final k = u * 3;
      final n = k.floorToDouble();
      final f = k - n;
      final peak = h * 0.38 * math.pow(0.55, n);
      final y = h * 0.86 - peak * 4 * f * (1 - f);
      _glyph(c, '😂', 44, Offset(w * (0.15 + 0.23 * i) + u * 30 * (i.isEven ? 1 : -1), y), alpha: 1 - _seg(u, 0.8, 1), scale: (f < 0.08 || f > 0.92) ? 0.85 : 1, deg: math.sin(u * 12) * 14);
    }
  }

  void _congrats(Canvas c, double t, math.Random r, double w, double h) {
    const gold = Color(0xFFFFD54F);
    final s = _seg(t, 0.05, 0.55);
    if (s > 0 && s < 1) {
      final x = -w * 0.6 + s * w * 2.2;
      c.drawRect(Offset.zero & Size(w, h), Paint()
        ..shader = LinearGradient(colors: [Colors.transparent, _a(gold, 0.38), _a(Colors.white, 0.45), _a(gold, 0.38), Colors.transparent])
            .createShader(Rect.fromPoints(Offset(x, 0), Offset(x + w * 0.5, h * 0.35))));
    }
    const colors = [Color(0xFFFF5252), Color(0xFFFFD740), Color(0xFF69F0AE), Color(0xFF40C4FF), Color(0xFFE040FB), gold];
    for (var i = 0; i < 16; i++) {
      final x0 = w * r.nextDouble();
      final d = r.nextDouble() * 0.3;
      final len = 60 + r.nextDouble() * 60;
      final col = colors[r.nextInt(colors.length)];
      final ph = r.nextDouble() * 6;
      final u = _seg(t, d, d + 0.7);
      if (u <= 0 || u >= 1) continue;
      final y0 = -len + u * (h + len * 2);
      final p = Path();
      for (var k = 0; k <= 14; k++) {
        final q = k / 14;
        final x = x0 + math.sin(ph + q * 7 + u * 10) * 12;
        final y = y0 + q * len;
        k == 0 ? p.moveTo(x, y) : p.lineTo(x, y);
      }
      c.drawPath(p, _stroke(_a(col, 1 - _seg(u, 0.8, 1)), 5));
    }
    for (var i = 0; i < 18; i++) {
      final at = Offset(w * r.nextDouble(), h * (0.1 + r.nextDouble() * 0.8));
      final st = r.nextDouble() * 0.6;
      final u = _seg(t, st, st + 0.3);
      if (u <= 0 || u >= 1) continue;
      final tw = math.sin(u * math.pi);
      c.drawPath(_sparkle(at, 6 + 10 * tw), _fill(_a(i % 3 == 0 ? Colors.white : gold, tw)));
    }
    final u = _seg(t, 0.12, 0.85);
    if (u > 0 && u < 1) _glyph(c, '🏆', 96, Offset(w / 2, h * 0.45), alpha: 1 - _seg(u, 0.75, 1), scale: _backOut(_seg(u, 0, 0.25)), deg: math.sin(u * 10) * 4);
  }

  void _kiss(Canvas c, double t, math.Random r, double w, double h) {
    final center = Offset(w / 2, h * 0.45);
    final fly = _seg(t, 0, 0.32);
    final start = Offset(-60, h * 0.92), ctrl = Offset(w * 0.1, h * 0.2);
    final e = 1 - math.pow(1 - fly, 3).toDouble();
    final pos = Offset(
      (1 - e) * (1 - e) * start.dx + 2 * (1 - e) * e * ctrl.dx + e * e * center.dx,
      (1 - e) * (1 - e) * start.dy + 2 * (1 - e) * e * ctrl.dy + e * e * center.dy,
    );
    final stamp = _seg(t, 0.32, 0.42);
    final ring = _seg(t, 0.34, 0.7);
    if (ring > 0 && ring < 1) {
      c.drawCircle(center, 40 + 160 * ring, _stroke(_a(const Color(0xFFFF4F8B), 0.55 * (1 - ring)), 10 * (1 - ring) + 1));
      final gr = 180 * ring + 1;
      c.drawCircle(center, gr, Paint()..shader = RadialGradient(colors: [const Color(0x55FF4F8B), Colors.transparent]).createShader(Rect.fromCircle(center: center, radius: gr)));
    }
    _glyph(c, '💋', 88, pos, alpha: 1 - _seg(t, 0.8, 1), scale: fly < 1 ? 0.6 + 0.5 * fly : 1.6 - 0.6 * _smooth(stamp), deg: fly < 1 ? (1 - fly) * -40 : 0);
    for (var i = 0; i < 12; i++) {
      final a = i / 12 * 2 * math.pi + r.nextDouble() * 0.3;
      final sp = 110 + r.nextDouble() * 90;
      final u = _seg(t, 0.38, 0.38 + 0.5 + r.nextDouble() * 0.1);
      if (u <= 0 || u >= 1) continue;
      final k = 1 - (1 - u) * (1 - u);
      final p = Offset(center.dx + math.cos(a) * sp * k, center.dy + math.sin(a) * sp * k - 60 * u * u);
      c.drawPath(_heart(p, 14 + 8 * math.sin(u * math.pi)), _fill(_a(i.isEven ? const Color(0xFFFF4F8B) : const Color(0xFFFF8FB1), 1 - _seg(u, 0.6, 1))));
    }
  }

  void _hug(Canvas c, double t, math.Random r, double w, double h) {
    final center = Offset(w / 2, h * 0.45);
    final warm = _fadeInOut(t, 0.2, 0.75);
    if (bg) c.drawRect(Offset.zero & Size(w, h), Paint()
      ..shader = RadialGradient(colors: [_a(const Color(0x66FFB74D), warm), _a(const Color(0x33FF8A65), warm), Colors.transparent])
          .createShader(Rect.fromCircle(center: center, radius: math.max(w, h) * 0.75)));
    final close = _smooth(_seg(t, 0.1, 0.45));
    final sq = 1 - 0.12 * math.sin(_seg(t, 0.45, 0.62) * math.pi);
    final rad = (150 - 30 * close) * sq;
    final arms = 1 - _seg(t, 0.78, 0.95);
    if (arms > 0) {
      final rect = Rect.fromCircle(center: center, radius: rad);
      final sweep = 150 * close * math.pi / 180;
      Paint arm(double width, double a) => Paint()
        ..shader = const LinearGradient(colors: [Color(0xFFFFB74D), Color(0xFFFF7A9A)]).createShader(rect)
        ..color = _a(Colors.white, a)
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round;
      c.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, arms));
      c.drawArc(rect, math.pi, -sweep, false, arm(22, 1));
      c.drawArc(rect, 0, sweep, false, arm(22, 1));
      c.drawArc(rect, math.pi, sweep * 0.9, false, arm(12, 0.5));
      c.drawArc(rect, 0, -sweep * 0.9, false, arm(12, 0.5));
      c.restore();
    }
    final face = _seg(t, 0.05, 0.9);
    if (face > 0 && face < 1) _glyph(c, '🤗', 92, center, alpha: 1 - _seg(face, 0.8, 1), scale: _backOut(_seg(face, 0, 0.3)) * sq);
    for (var i = 0; i < 10; i++) {
      final u = _seg(t, 0.55 + r.nextDouble() * 0.1, 1);
      final x = center.dx + (r.nextDouble() - 0.5) * w * 0.7;
      final hs = 12 + r.nextDouble() * 10;
      if (u <= 0 || u >= 1) continue;
      c.drawPath(_heart(Offset(x + math.sin(u * 8 + i) * 10, center.dy + 80 - u * h * 0.4), hs), _fill(_a(const Color(0xFFFF8A65), 1 - u)));
    }
  }

  void _party(Canvas c, double t, math.Random r, double w, double h) {
    final on = _fadeInOut(t, 0.12, 0.82);
    if (bg) c.drawRect(Offset.zero & Size(w, h), _fill(_a(Colors.black, 0.32 * on)));
    final ball = Offset(w / 2, h * 0.12);
    const beams = [Color(0xFFFF4081), Color(0xFF40C4FF), Color(0xFFFFD740), Color(0xFF69F0AE), Color(0xFFE040FB), Color(0xFFFF6E40)];
    for (var i = 0; i < beams.length; i++) {
      final ang = (i * 60 + t * 260) * math.pi / 180;
      Offset at(double a) => Offset(ball.dx + math.cos(a) * h, ball.dy + math.sin(a).abs() * h + h * 0.2);
      final tip = at(ang);
      final p = Path()
        ..moveTo(ball.dx, ball.dy)
        ..lineTo(at(ang - 0.12).dx, at(ang - 0.12).dy)
        ..lineTo(at(ang + 0.12).dx, at(ang + 0.12).dy)
        ..close();
      c.drawPath(p, Paint()..shader = LinearGradient(colors: [_a(beams[i], 0.42 * on), Colors.transparent]).createShader(Rect.fromPoints(ball, tip)));
      c.drawCircle(tip, 70, Paint()..shader = RadialGradient(colors: [_a(beams[i], 0.5 * on), Colors.transparent]).createShader(Rect.fromCircle(center: tip, radius: 70)));
    }
    if (on > 0) {
      const br = 30.0;
      c.drawLine(Offset(ball.dx, 0), Offset(ball.dx, ball.dy - br), _stroke(_a(Colors.white, 0.6 * on), 2));
      c.drawCircle(ball, br, Paint()..shader = RadialGradient(colors: [_a(const Color(0xFFF5F5F5), on), _a(const Color(0xFF9E9E9E), on)]).createShader(Rect.fromCircle(center: ball, radius: br)));
      for (var k = 0; k < 14; k++) {
        final a = k * 0.9 + t * 9;
        final f = Offset(ball.dx + math.cos(a) * br * 0.65 * ((k % 3) / 3 + 0.4), ball.dy + math.sin(a * 1.3) * br * 0.65);
        c.drawPath(_sparkle(f, 3 + 3 * math.sin(a * 2 + t * 20).abs()), _fill(_a(Colors.white, on)));
      }
    }
    for (var i = 0; i < 40; i++) {
      final x0 = w * r.nextDouble();
      final st = r.nextDouble() * 0.5;
      final col = beams[r.nextInt(beams.length)];
      final spin = r.nextDouble() * 10;
      final u = _seg(t, st, st + 0.55);
      if (u <= 0 || u >= 1) continue;
      final x = x0 + math.sin(u * 8 + spin) * 18;
      final y = -20 + u * (h + 40);
      final sy = math.cos(spin + u * 14).abs() * 0.8 + 0.2;
      c.save();
      c.translate(x, y);
      c.rotate((spin * 40 + u * 600) * math.pi / 180);
      c.drawRect(Rect.fromCenter(center: Offset.zero, width: 12, height: 6 * sy), _fill(_a(col, 1 - _seg(u, 0.85, 1))));
      c.restore();
    }
    final u = _seg(t, 0.15, 0.8);
    if (u > 0 && u < 1) _glyph(c, '🥳', 96, Offset(w / 2, h * 0.5), alpha: 1 - _seg(u, 0.75, 1), scale: _backOut(_seg(u, 0, 0.25)), deg: math.sin(u * 14) * 10);
  }

  void _birthday(Canvas c, double t, math.Random r, double w, double h) {
    final center = Offset(w / 2, h * 0.5);
    final cake = _seg(t, 0.05, 0.92);
    if (cake > 0 && cake < 1) {
      final glow = 0.6 + 0.4 * math.sin(t * 40);
      final g = Offset(center.dx, center.dy - 30);
      c.drawCircle(g, 160, Paint()..shader = RadialGradient(colors: [_a(const Color(0xFFFFC107), 0.4 * glow * (1 - _seg(cake, 0.8, 1))), Colors.transparent]).createShader(Rect.fromCircle(center: g, radius: 160)));
      _glyph(c, '🎂', 104, center, alpha: 1 - _seg(cake, 0.8, 1), scale: _backOut(_seg(cake, 0, 0.25)));
    }
    const colors = [Color(0xFFFF5252), Color(0xFF40C4FF), Color(0xFFFFD740), Color(0xFF69F0AE), Color(0xFFE040FB), Color(0xFFFF8A65)];
    for (var i = 0; i < 11; i++) {
      final x0 = w * (0.06 + r.nextDouble() * 0.88);
      final st = r.nextDouble() * 0.35;
      final col = colors[i % colors.length];
      final bw = 38 + r.nextDouble() * 18;
      final u = _seg(t, st, st + 0.62);
      if (u <= 0 || u >= 1) continue;
      final x = x0 + math.sin(u * 5 + i) * 22;
      final y = h + bw * 2 - u * (h + bw * 5);
      final s = Path()..moveTo(x, y + bw * 0.62);
      for (var k = 1; k <= 6; k++) {
        s.lineTo(x + math.sin(u * 10 + k) * 5, y + bw * 0.62 + k * 14);
      }
      c.drawPath(s, _stroke(_a(Colors.white, 0.7), 1.5));
      c.drawOval(Rect.fromLTWH(x - bw / 2, y - bw * 0.62, bw, bw * 1.22), _fill(col));
      c.drawOval(Rect.fromLTWH(x - bw * 0.3, y - bw * 0.48, bw * 0.22, bw * 0.36), _fill(_a(Colors.white, 0.35)));
      c.drawPath(Path()..moveTo(x - 5, y + bw * 0.66)..lineTo(x + 5, y + bw * 0.66)..lineTo(x, y + bw * 0.56)..close(), _fill(col));
    }
  }

  void _goodNight(Canvas c, double t, math.Random r, double w, double h) {
    final night = _fadeInOut(t, 0.18, 0.8);
    if (bg) c.drawRect(Offset.zero & Size(w, h), Paint()
      ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_a(const Color(0xFF0B1033), 0.78 * night), _a(const Color(0xFF1A1F4A), 0.45 * night), Colors.transparent])
          .createShader(Offset.zero & Size(w, h)));
    for (var i = 0; i < 34; i++) {
      final at = Offset(w * r.nextDouble(), h * r.nextDouble() * 0.75);
      final ph = r.nextDouble() * 6;
      final rr = 1.5 + r.nextDouble() * 2.5;
      final sparkle = r.nextInt(4) == 0;
      final tw = 0.5 + 0.5 * math.sin(t * 18 + ph);
      if (sparkle) {
        c.drawPath(_sparkle(at, rr * 3 * tw), _fill(_a(Colors.white, night * tw)));
      } else {
        c.drawCircle(at, rr, _fill(_a(Colors.white, night * (0.4 + 0.6 * tw))));
      }
    }
    final mc = Offset(w * 0.72, h * 0.28 - 30 * _smooth(_seg(t, 0.05, 0.45)));
    const mr = 48.0;
    final moon = Path.combine(PathOperation.difference, Path()..addOval(Rect.fromCircle(center: mc, radius: mr)),
        Path()..addOval(Rect.fromCircle(center: Offset(mc.dx + mr * 0.45, mc.dy - mr * 0.25), radius: mr * 0.9)));
    c.drawCircle(mc, mr * 2.4, Paint()..shader = RadialGradient(colors: [_a(const Color(0x55FFF3B0), night), Colors.transparent]).createShader(Rect.fromCircle(center: mc, radius: mr * 2.4)));
    c.drawPath(moon, _fill(_a(const Color(0xFFFFF3B0), night)));
    for (var i = 0; i < 4; i++) {
      final u = _seg(t, 0.25 + i * 0.12, 0.7 + i * 0.12);
      if (u <= 0 || u >= 1) continue;
      _glyph(c, i.isEven ? 'Z' : 'z', 26.0 + i * 6, Offset(mc.dx - mr * 0.8 - u * 60 + math.sin(u * 6) * 10, mc.dy + mr - u * 110), alpha: math.sin(u * math.pi) * night, deg: -12, bold: true);
    }
  }

  void _sweetDreams(Canvas c, double t, math.Random r, double w, double h) {
    final dusk = _fadeInOut(t, 0.16, 0.82);
    if (bg) c.drawRect(Offset.zero & Size(w, h), Paint()
      ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_a(const Color(0xFF2A1B4D), 0.72 * dusk), _a(const Color(0xFF6B3F8F), 0.35 * dusk), Colors.transparent])
          .createShader(Offset.zero & Size(w, h)));
    // moon resting on a cloud, rocking gently
    final mc = Offset(w * 0.5, h * 0.3 - 24 * _smooth(_seg(t, 0.05, 0.4)) + math.sin(t * 9) * 4);
    const mr = 44.0;
    c.drawCircle(mc, mr * 2.6, Paint()..shader = RadialGradient(colors: [_a(const Color(0x55FFE3F1), dusk), Colors.transparent]).createShader(Rect.fromCircle(center: mc, radius: mr * 2.6)));
    final moon = Path.combine(PathOperation.difference, Path()..addOval(Rect.fromCircle(center: mc, radius: mr)),
        Path()..addOval(Rect.fromCircle(center: Offset(mc.dx + mr * 0.45, mc.dy - mr * 0.25), radius: mr * 0.9)));
    c.drawPath(moon, _fill(_a(const Color(0xFFFFF1C9), dusk)));
    final cloud = _fill(_a(const Color(0xFFF3E8FF), 0.95 * dusk));
    for (final (dx, dy, rr) in [(-38.0, 0.0, 26.0), (-6.0, -12.0, 32.0), (30.0, -2.0, 26.0), (56.0, 8.0, 18.0), (-60.0, 10.0, 18.0)]) {
      c.drawCircle(Offset(mc.dx + dx, mc.dy + mr * 0.9 + dy), rr, cloud);
    }
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(mc.dx - 78, mc.dy + mr * 0.9, 156, 26), const Radius.circular(13)), cloud);
    // little hearts and stars drift up slowly
    for (var i = 0; i < 16; i++) {
      final x = w * (0.08 + r.nextDouble() * 0.84);
      final st = 0.1 + r.nextDouble() * 0.45;
      final u = _seg(t, st, st + 0.45);
      final s = 10 + r.nextDouble() * 12;
      if (u <= 0 || u >= 1) continue;
      final at = Offset(x + math.sin(u * 7 + i) * 16, h * (0.95 - u * 0.6));
      final a = math.sin(u * math.pi) * dusk;
      if (i.isEven) {
        c.drawPath(_heart(at, s), _fill(_a(const Color(0xFFFF9CC7), a)));
      } else {
        c.drawPath(_sparkle(at, s * 0.7), _fill(_a(const Color(0xFFFFF3B0), a)));
      }
    }
    final txt = _seg(t, 0.22, 0.4);
    if (txt > 0) _glyph(c, 'Sweet dreams', 34, Offset(w / 2, h * 0.56), alpha: txt * (1 - _seg(t, 0.8, 0.95)), scale: 0.9 + 0.1 * _smooth(txt), bold: true, color: const Color(0xFFFFE3F1));
  }

  void _welcome(Canvas c, double t, math.Random r, double w, double h) {
    final glow = _fadeInOut(t, 0.12, 0.8);
    final center = Offset(w / 2, h * 0.42);
    // golden rays turning slowly behind the ribbon
    c.save();
    c.translate(center.dx, center.dy);
    c.rotate(t * 0.8);
    for (var i = 0; i < 12; i++) {
      final a = i * math.pi / 6;
      final p = Path()
        ..moveTo(0, 0)
        ..lineTo(math.cos(a - 0.09) * h, math.sin(a - 0.09) * h)
        ..lineTo(math.cos(a + 0.09) * h, math.sin(a + 0.09) * h)
        ..close();
      c.drawPath(p, _fill(_a(const Color(0xFFFFD54F), 0.16 * glow)));
    }
    c.restore();
    c.drawCircle(center, 160, Paint()..shader = RadialGradient(colors: [_a(const Color(0x88FFE082), glow), Colors.transparent]).createShader(Rect.fromCircle(center: center, radius: 160)));
    // the ribbon unrolls from the middle
    final open = _smooth(_seg(t, 0.08, 0.32)) * (1 - _seg(t, 0.84, 0.96));
    if (open > 0) {
      final rw = (w * 0.82) * open, rh = 64.0;
      final rect = Rect.fromCenter(center: center, width: rw, height: rh);
      for (final side in [-1.0, 1.0]) {
        final ex = center.dx + side * rw / 2;
        c.drawPath(Path()
          ..moveTo(ex, center.dy - rh * 0.3)
          ..lineTo(ex + side * 34, center.dy - rh * 0.3)
          ..lineTo(ex + side * 22, center.dy + rh * 0.2)
          ..lineTo(ex + side * 34, center.dy + rh * 0.7)
          ..lineTo(ex, center.dy + rh * 0.7)
          ..close(), _fill(_a(const Color(0xFFC62828), open)));
      }
      c.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(6)), Paint()
        ..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFF5252), Color(0xFFD32F2F)]).createShader(rect));
      c.drawRect(Rect.fromLTWH(rect.left, rect.top + 6, rect.width, 2), _fill(_a(const Color(0xFFFFD54F), 0.8)));
      c.drawRect(Rect.fromLTWH(rect.left, rect.bottom - 8, rect.width, 2), _fill(_a(const Color(0xFFFFD54F), 0.8)));
      final tx = _seg(t, 0.24, 0.38);
      if (tx > 0) _glyph(c, 'WELCOME', 34, center, alpha: tx * open, scale: _backOut(tx), bold: true, color: Colors.white);
    }
    // gold stars fall
    for (var i = 0; i < 22; i++) {
      final x = w * r.nextDouble();
      final st = 0.2 + r.nextDouble() * 0.4;
      final u = _seg(t, st, st + 0.4);
      if (u <= 0 || u >= 1) continue;
      c.drawPath(_sparkle(Offset(x + math.sin(u * 8 + i) * 12, -20 + u * h * 0.9), 6 + r.nextDouble() * 6), _fill(_a(i % 3 == 0 ? Colors.white : const Color(0xFFFFD54F), 1 - u)));
    }
  }

  /// bye: the hand waves in the middle and floats up and away;
  /// hi: it rises from the bottom, waves, ripples and a "Hi!" bubble pops.
  // Handwritten "hi" and "bye" (one continuous line each, like a pen),
  // drawn in a 520 x 400 box with the baseline at y = 300.
  static final Path _hiPath = Path()
      ..moveTo(40, 300)
      ..cubicTo(90, 300, 150, 250, 170, 170)
      ..cubicTo(190, 90, 170, 30, 140, 40)
      ..cubicTo(110, 50, 115, 150, 125, 300)
      ..cubicTo(140, 230, 180, 190, 215, 195)
      ..cubicTo(255, 200, 250, 260, 255, 295)
      ..cubicTo(262, 320, 300, 300, 330, 250)
      ..cubicTo(345, 225, 350, 215, 355, 215)
      ..cubicTo(360, 250, 355, 290, 375, 300)
      ..cubicTo(400, 310, 440, 290, 470, 260);
  static final Path _byePath = Path()
      ..moveTo(40, 300)
      ..cubicTo(80, 300, 130, 250, 150, 170)
      ..cubicTo(170, 90, 150, 30, 122, 40)
      ..cubicTo(95, 52, 100, 170, 110, 295)
      ..cubicTo(120, 230, 170, 200, 195, 230)
      ..cubicTo(215, 260, 185, 305, 150, 290)
      ..cubicTo(175, 285, 205, 250, 235, 215)
      ..cubicTo(240, 260, 255, 300, 285, 295)
      ..cubicTo(310, 285, 315, 240, 320, 215)
      ..cubicTo(325, 300, 320, 390, 290, 395)
      ..cubicTo(260, 398, 270, 340, 330, 300)
      ..cubicTo(360, 280, 380, 240, 410, 250)
      ..cubicTo(440, 260, 420, 215, 395, 225)
      ..cubicTo(365, 240, 370, 300, 410, 300)
      ..cubicTo(440, 300, 470, 280, 500, 255);

  /// Hi / bye: the word writes itself in one flowing stroke, with a soft
  /// gradient glow and a bright pen tip. "hi" then floats up and fades;
  /// "bye" lifts away in tiny sparks.
  void _wave(Canvas c, double t, math.Random r, double w, double h, {required bool bye}) {
    final src = bye ? _byePath : _hiPath;
    final scale = math.min(w * 0.78, 460.0) / 520;
    final lift = bye ? 0.0 : -40 * _smooth(_seg(t, 0.72, 1));
    final origin = Offset(w / 2 - 260 * scale, h * 0.42 - 220 * scale + lift);
    final m = Matrix4.diagonal3Values(scale, scale, 1)
      ..setTranslationRaw(origin.dx, origin.dy, 0);
    final path = src.transform(m.storage);
    final metric = path.computeMetrics().first;
    final write = Curves.easeInOutCubic.transform(_seg(t, 0.06, bye ? 0.52 : 0.6));
    final fade = bye ? 1 - _seg(t, 0.62, 0.86) : 1 - _seg(t, 0.78, 1);
    final bounds = path.getBounds();
    final colors = bye
        ? const [Color(0xFF8C96F6), Color(0xFFEB459E), Color(0xFFFFA45B)]
        : const [Color(0xFF5BC0FF), Color(0xFF8C96F6), Color(0xFFEB459E)];
    // a soft colour bloom behind the word
    final bloom = _fadeInOut(t, 0.2, 0.75);
    if (bg && bloom > 0) {
      final cc = bounds.center;
      c.drawCircle(cc, bounds.width * 0.9, Paint()
        ..shader = RadialGradient(colors: [_a(colors[1], 0.22 * bloom), Colors.transparent])
            .createShader(Rect.fromCircle(center: cc, radius: bounds.width * 0.9)));
    }
    if (write <= 0 || fade <= 0) return;
    final part = metric.extractPath(0, metric.length * write);
    final shader = LinearGradient(colors: colors).createShader(bounds.inflate(20));
    final width = 13 * scale;
    // glow, then the ink
    c.drawPath(part, Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = width * 2.6
      ..shader = shader
      ..color = Colors.white.withValues(alpha: 0.35 * fade)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
    c.drawPath(part, Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = width
      ..shader = shader
      ..color = Colors.white.withValues(alpha: fade));
    // the pen tip while writing
    if (write < 1) {
      final tip = metric.getTangentForOffset(metric.length * write)?.position;
      if (tip != null) {
        c.drawCircle(tip, width * 1.6, Paint()
          ..color = Colors.white.withValues(alpha: 0.6 * fade)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
        c.drawCircle(tip, width * 0.55, _fill(Colors.white.withValues(alpha: fade)));
      }
    }
    // the dot on the i pops in once the word is written
    if (!bye) {
      final dot = _backOut(_seg(t, 0.58, 0.68));
      if (dot > 0) {
        final p = origin + Offset(348 * scale, 150 * scale);
        c.drawCircle(p, width * 0.95 * dot, Paint()..shader = shader..color = Colors.white.withValues(alpha: fade));
      }
    }
    // bye: sparks lift off the word as it fades
    if (bye) {
      final u0 = _seg(t, 0.58, 1);
      if (u0 > 0) {
        for (var i = 0; i < 26; i++) {
          final at = metric.getTangentForOffset(metric.length * r.nextDouble())?.position;
          if (at == null) continue;
          final delay = r.nextDouble() * 0.3;
          final u = _seg(u0, delay, delay + 0.7);
          if (u <= 0 || u >= 1) continue;
          final p = at + Offset((r.nextDouble() - 0.5) * 30 * u, -90 * scale * u);
          c.drawCircle(p, (2 + r.nextDouble() * 3) * (1 - u) + 1, _fill(_a(colors[i % 3], 1 - u)));
        }
      }
    }
  }

  void _love(Canvas c, double t, math.Random r, double w, double h) {
    final center = Offset(w / 2, h * 0.45);
    double beat(double at, double s) => s * math.sin(_seg(t, at, at + 0.09) * math.pi);
    final pulse = beat(0.16, 0.12) + beat(0.24, 0.2) + beat(0.42, 0.12) + beat(0.50, 0.22);
    final size = 150 * _backOut(_seg(t, 0, 0.14)) * (1 + pulse) * (1 - _seg(t, 0.62, 0.72));
    if (size > 1) {
      c.drawCircle(center, size * 1.6, Paint()..shader = RadialGradient(colors: [const Color(0x66FF3B5C), Colors.transparent]).createShader(Rect.fromCircle(center: center, radius: size * 1.6)));
      c.drawPath(_heart(center, size), Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFF6B8B), Color(0xFFE91E63)]).createShader(Rect.fromCircle(center: center, radius: size * 0.6)));
      c.drawPath(_heart(Offset(center.dx - size * 0.16, center.dy - size * 0.12), size * 0.26), _fill(_a(Colors.white, 0.25)));
    }
    for (final at in [0.24, 0.50]) {
      final u = _seg(t, at, at + 0.35);
      if (u > 0 && u < 1) c.drawPath(_heart(center, 150 * (1 + u * 1.3)), _stroke(_a(const Color(0xFFFF3B5C), 0.5 * (1 - u)), 3));
    }
    for (var i = 0; i < 18; i++) {
      final a = r.nextDouble() * 2 * math.pi;
      final sp = 60 + r.nextDouble() * 150;
      final u = _seg(t, 0.64, 0.94 + r.nextDouble() * 0.06);
      final hs = 16 + r.nextDouble() * 14;
      if (u <= 0 || u >= 1) continue;
      final k = 1 - (1 - u) * (1 - u);
      c.drawPath(_heart(Offset(center.dx + math.cos(a) * sp * k, center.dy + math.sin(a) * sp * k - 90 * u), hs), _fill(_a(i % 3 == 0 ? const Color(0xFFFF8FB1) : const Color(0xFFFF3B5C), 1 - u)));
    }
  }

  void _missYou(Canvas c, double t, math.Random r, double w, double h) {
    final tint = _fadeInOut(t, 0.2, 0.8);
    if (bg) c.drawRect(Offset.zero & Size(w, h), Paint()
      ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_a(const Color(0x335C7CFA), tint), _a(const Color(0x22A0B4FF), tint), Colors.transparent])
          .createShader(Offset.zero & Size(w, h)));
    Offset planeAt(double u) {
      final loop = _seg(u, 0.38, 0.62);
      final a = loop * 2 * math.pi;
      final on = loop > 0 && loop < 1;
      return Offset(-60 + u * (w + 120) + (on ? -math.sin(a) * 70 : 0), h * 0.32 + math.sin(u * 6) * 18 + (on ? -(1 - math.cos(a)) * 70 : 0));
    }
    final fly = _seg(t, 0, 0.75);
    if (fly < 1) {
      for (var k = 0; k < 26; k++) {
        final u = fly - k * 0.012;
        if (u <= 0) continue;
        c.drawCircle(planeAt(u), 2.2, _fill(_a(Colors.white, 0.55 * (1 - k / 26) * math.max(tint, 0.3))));
      }
    }
    if (fly > 0 && fly < 1) {
      final pos = planeAt(fly);
      final ahead = planeAt(math.min(fly + 0.01, 1));
      c.save();
      c.translate(pos.dx, pos.dy);
      c.rotate(math.atan2(ahead.dy - pos.dy, ahead.dx - pos.dx));
      const s = 22.0;
      c.drawPath(Path()..moveTo(s, 0)..lineTo(-s, -s * 0.7)..lineTo(-s * 0.45, 0)..lineTo(-s, s * 0.7)..close(), _fill(Colors.white));
      c.drawLine(const Offset(-s * 0.45, 0), const Offset(s, 0), _stroke(const Color(0xFFB0BEC5), 1.5));
      c.restore();
    }
    final drop = _seg(t, 0.55, 0.85);
    final hang = planeAt(math.max(math.min(fly, 0.55), 0.001)).translate(0, 34);
    final center = Offset(w / 2, h * 0.48);
    final hp = drop <= 0 ? hang : Offset(hang.dx + (center.dx - hang.dx) * _smooth(drop) + math.sin(drop * 9) * 16 * (1 - drop), hang.dy + (center.dy - hang.dy) * _smooth(drop));
    final beat = 1 + 0.12 * math.sin(_seg(t, 0.85, 0.95) * math.pi);
    if (drop > 0.9) c.drawCircle(hp, 90, Paint()..shader = RadialGradient(colors: [_a(const Color(0x55FF6B8B), 1 - _seg(t, 0.9, 1)), Colors.transparent]).createShader(Rect.fromCircle(center: hp, radius: 90)));
    if (t > 0.04) c.drawPath(_heart(hp, (drop > 0 ? 30 + 40 * _smooth(drop) : 30) * beat), _fill(_a(const Color(0xFFFF6B8B), 1 - _seg(t, 0.9, 1))));
    final face = _seg(t, 0.82, 1);
    if (face > 0 && face < 1) _glyph(c, '🥺', 46, Offset(center.dx, center.dy + 70), alpha: 1 - _seg(face, 0.7, 1), scale: _backOut(_seg(face, 0, 0.4)));
  }

  void _goodMorning(Canvas c, double t, math.Random r, double w, double h) {
    final warm = _fadeInOut(t, 0.2, 0.8);
    if (bg) c.drawRect(Offset.zero & Size(w, h), Paint()
      ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, stops: const [0.3, 0.65, 1], colors: [Colors.transparent, _a(const Color(0x33FFB74D), warm), _a(const Color(0x77FF8A65), warm)])
          .createShader(Offset.zero & Size(w, h)));
    final sun = Offset(w / 2, h * 0.78 - _smooth(_seg(t, 0.02, 0.5)) * h * 0.36);
    const sr = 56.0;
    if (warm > 0) {
      c.drawCircle(sun, sr * 3.2, Paint()..shader = RadialGradient(colors: [_a(const Color(0x88FFD54F), warm), Colors.transparent]).createShader(Rect.fromCircle(center: sun, radius: sr * 3.2)));
      for (var k = 0; k < 12; k++) {
        final a = k / 12 * 2 * math.pi + t * 70 * math.pi / 180;
        final outer = sr * (1.9 + 0.25 * math.sin(t * 20 + k));
        c.drawLine(sun + Offset(math.cos(a), math.sin(a)) * sr * 1.3, sun + Offset(math.cos(a), math.sin(a)) * outer, _stroke(_a(const Color(0xFFFFC107), 0.85 * warm), 6));
      }
      c.drawCircle(sun, sr, Paint()..shader = RadialGradient(colors: [_a(const Color(0xFFFFF59D), warm), _a(const Color(0xFFFFB300), warm)]).createShader(Rect.fromCircle(center: sun, radius: sr)));
    }
    for (var i = 0; i < 5; i++) {
      final y0 = h * (0.18 + r.nextDouble() * 0.2);
      final st = 0.15 + r.nextDouble() * 0.25;
      final s = 10 + r.nextDouble() * 6;
      final u = _seg(t, st, st + 0.6);
      if (u <= 0 || u >= 1) continue;
      final x = -30 + u * (w + 60);
      final y = y0 + math.sin(u * 5 + i) * 10;
      final flap = math.sin(t * 60 + i) * 0.6;
      c.drawPath(Path()
        ..moveTo(x - s, y - s * flap)
        ..quadraticBezierTo(x - s * 0.5, y - s * 0.4, x, y)
        ..quadraticBezierTo(x + s * 0.5, y - s * 0.4, x + s, y - s * flap), _stroke(_a(const Color(0xFF37474F), 0.8 * (1 - _seg(u, 0.85, 1))), 2.5));
    }
    final u = _seg(t, 0.35, 0.95);
    if (u > 0 && u < 1) _glyph(c, '☕', 56, Offset(w / 2, h * 0.62), alpha: 1 - _seg(u, 0.75, 1), scale: _backOut(_seg(u, 0, 0.3)));
  }

  void _thanks(Canvas c, double t, math.Random r, double w, double h) {
    final center = Offset(w / 2, h * 0.45);
    final bloom = _backOut(_seg(t, 0.05, 0.4));
    final fade = 1 - _seg(t, 0.75, 0.95);
    const petals = [Color(0xFFFF8FB1), Color(0xFFFFB3C7)];
    for (var ring = 0; ring < 2; ring++) {
      final n = ring == 0 ? 8 : 6;
      final len = (ring == 0 ? 92.0 : 62.0) * bloom;
      final wid = (ring == 0 ? 40.0 : 30.0) * bloom;
      for (var k = 0; k < n; k++) {
        c.save();
        c.translate(center.dx, center.dy);
        c.rotate((t * 30 + ring * 30 + k * 360 / n) * math.pi / 180);
        c.drawOval(Rect.fromLTWH(-wid / 2, -len, wid, len), _fill(_a(petals[ring], fade)));
        c.restore();
      }
    }
    c.drawCircle(center, 30 * bloom, _fill(_a(const Color(0xFFFFD54F), fade)));
    _glyph(c, '🙏', 44, center, alpha: fade, scale: bloom);
    for (var i = 0; i < 16; i++) {
      final x0 = w * r.nextDouble();
      final st = 0.25 + r.nextDouble() * 0.35;
      final spin = r.nextDouble() * 6;
      final pw = 10 + r.nextDouble() * 6;
      final u = _seg(t, st, st + 0.55);
      if (u <= 0 || u >= 1) continue;
      c.save();
      c.translate(x0 + math.sin(u * 6 + spin) * 26, -20 + u * h * 0.9);
      c.rotate((spin * 50 + u * 300) * math.pi / 180);
      c.drawOval(Rect.fromLTWH(-pw / 2, -pw, pw, pw * 2), _fill(_a(petals[i % 2], 1 - _seg(u, 0.75, 1))));
      c.restore();
    }
  }

  // Handwritten "Sorry", from the Hershey script lettering (made by Dr.
  // A. V. Hershey at the U.S. National Bureau of Standards; the font data
  // format by James Hurt, Cognition, Inc.), smoothed into curves in the same
  // 520 x 400 box as "hi" and "bye".
  static final Path _sorryPath = Path()
      ..moveTo(40.0, 226.4)
      ..cubicTo(42.0, 225.4, 47.8, 223.4, 51.7, 220.5)
      ..cubicTo(55.6, 217.6, 58.6, 214.7, 63.5, 208.8)
      ..cubicTo(68.4, 202.9, 76.2, 192.2, 81.1, 185.3)
      ..cubicTo(86.0, 178.5, 88.9, 174.5, 92.8, 167.7)
      ..cubicTo(96.7, 160.9, 101.6, 151.1, 104.5, 144.3)
      ..cubicTo(107.4, 137.5, 109.4, 132.6, 110.4, 126.7)
      ..cubicTo(111.4, 120.8, 111.4, 113.0, 110.4, 109.1)
      ..cubicTo(109.4, 105.2, 106.5, 104.2, 104.5, 103.2)
      ..cubicTo(102.5, 102.2, 100.7, 102.2, 98.7, 103.2)
      ..cubicTo(96.8, 104.2, 94.8, 106.2, 92.8, 109.1)
      ..cubicTo(90.8, 112.0, 87.9, 116.9, 86.9, 120.8)
      ..cubicTo(85.9, 124.7, 85.9, 128.6, 86.9, 132.5)
      ..cubicTo(87.9, 136.4, 89.9, 140.4, 92.8, 144.3)
      ..cubicTo(95.7, 148.2, 99.6, 152.1, 104.5, 156.0)
      ..cubicTo(109.4, 159.9, 117.2, 163.8, 122.1, 167.7)
      ..cubicTo(127.0, 171.6, 131.0, 175.6, 133.9, 179.5)
      ..cubicTo(136.8, 183.4, 138.7, 187.3, 139.7, 191.2)
      ..cubicTo(140.7, 195.1, 140.7, 199.0, 139.7, 202.9)
      ..cubicTo(138.7, 206.8, 135.8, 211.8, 133.9, 214.7)
      ..cubicTo(132.0, 217.6, 131.9, 218.6, 128.0, 220.5)
      ..cubicTo(124.1, 222.4, 117.2, 225.4, 110.4, 226.4)
      ..cubicTo(103.6, 227.4, 93.8, 227.4, 86.9, 226.4)
      ..cubicTo(80.1, 225.4, 74.2, 223.4, 69.3, 220.5)
      ..cubicTo(64.4, 217.6, 60.5, 212.7, 57.6, 208.8)
      ..cubicTo(54.7, 204.9, 52.7, 201.0, 51.7, 197.1)
      ..cubicTo(50.7, 193.2, 51.7, 187.3, 51.7, 185.3)
      ..moveTo(192.5, 173.6)
      ..cubicTo(190.6, 173.6, 184.7, 172.6, 180.8, 173.6)
      ..cubicTo(176.9, 174.6, 172.0, 177.6, 169.1, 179.5)
      ..cubicTo(166.2, 181.4, 165.2, 182.4, 163.2, 185.3)
      ..cubicTo(161.2, 188.2, 158.3, 193.2, 157.3, 197.1)
      ..cubicTo(156.3, 201.0, 156.3, 204.9, 157.3, 208.8)
      ..cubicTo(158.3, 212.7, 160.3, 217.6, 163.2, 220.5)
      ..cubicTo(166.1, 223.4, 171.0, 225.4, 174.9, 226.4)
      ..cubicTo(178.8, 227.4, 182.8, 227.4, 186.7, 226.4)
      ..cubicTo(190.6, 225.4, 195.5, 222.4, 198.4, 220.5)
      ..cubicTo(201.3, 218.6, 202.4, 217.6, 204.3, 214.7)
      ..cubicTo(206.2, 211.8, 209.1, 206.8, 210.1, 202.9)
      ..cubicTo(211.1, 199.0, 211.1, 195.1, 210.1, 191.2)
      ..cubicTo(209.1, 187.3, 207.2, 182.4, 204.3, 179.5)
      ..cubicTo(201.4, 176.6, 195.4, 173.6, 192.5, 173.6)
      ..cubicTo(189.6, 173.6, 187.7, 176.6, 186.7, 179.5)
      ..cubicTo(185.7, 182.4, 185.7, 187.3, 186.7, 191.2)
      ..cubicTo(187.7, 195.1, 189.6, 200.0, 192.5, 202.9)
      ..cubicTo(195.4, 205.8, 199.4, 207.8, 204.3, 208.8)
      ..cubicTo(209.2, 209.8, 217.0, 209.8, 221.9, 208.8)
      ..cubicTo(226.8, 207.8, 230.7, 204.9, 233.6, 202.9)
      ..cubicTo(236.5, 200.9, 238.5, 198.1, 239.5, 197.1)
      ..moveTo(239.5, 197.1)
      ..cubicTo(241.4, 194.2, 248.3, 184.4, 251.2, 179.5)
      ..cubicTo(254.1, 174.6, 256.1, 167.7, 257.1, 167.7)
      ..cubicTo(258.1, 167.7, 254.2, 177.5, 257.1, 179.5)
      ..cubicTo(260.0, 181.5, 270.8, 178.5, 274.7, 179.5)
      ..cubicTo(278.6, 180.5, 279.5, 182.4, 280.5, 185.3)
      ..cubicTo(281.5, 188.2, 281.5, 192.2, 280.5, 197.1)
      ..cubicTo(279.5, 202.0, 275.7, 210.8, 274.7, 214.7)
      ..cubicTo(273.7, 218.6, 273.7, 218.6, 274.7, 220.5)
      ..cubicTo(275.7, 222.4, 278.6, 225.4, 280.5, 226.4)
      ..cubicTo(282.4, 227.4, 283.5, 227.4, 286.4, 226.4)
      ..cubicTo(289.3, 225.4, 295.2, 222.4, 298.1, 220.5)
      ..cubicTo(301.0, 218.6, 301.1, 218.6, 304.0, 214.7)
      ..cubicTo(306.9, 210.8, 313.8, 200.0, 315.7, 197.1)
      ..moveTo(315.7, 197.1)
      ..cubicTo(317.7, 194.2, 324.6, 184.4, 327.5, 179.5)
      ..cubicTo(330.4, 174.6, 332.3, 167.7, 333.3, 167.7)
      ..cubicTo(334.3, 167.7, 330.4, 177.5, 333.3, 179.5)
      ..cubicTo(336.2, 181.5, 347.0, 178.5, 350.9, 179.5)
      ..cubicTo(354.8, 180.5, 355.8, 182.4, 356.8, 185.3)
      ..cubicTo(357.8, 188.2, 357.8, 192.2, 356.8, 197.1)
      ..cubicTo(355.8, 202.0, 351.9, 210.8, 350.9, 214.7)
      ..cubicTo(349.9, 218.6, 349.9, 218.6, 350.9, 220.5)
      ..cubicTo(351.9, 222.4, 354.8, 225.4, 356.8, 226.4)
      ..cubicTo(358.8, 227.4, 359.8, 227.4, 362.7, 226.4)
      ..cubicTo(365.6, 225.4, 371.5, 222.4, 374.4, 220.5)
      ..cubicTo(377.3, 218.6, 377.4, 218.6, 380.3, 214.7)
      ..cubicTo(383.2, 210.8, 390.1, 200.0, 392.0, 197.1)
      ..moveTo(392.0, 197.1)
      ..cubicTo(393.9, 193.2, 403.7, 171.6, 403.7, 173.6)
      ..cubicTo(403.7, 175.6, 393.9, 201.0, 392.0, 208.8)
      ..cubicTo(390.1, 216.6, 391.0, 217.6, 392.0, 220.5)
      ..cubicTo(393.0, 223.4, 395.0, 225.4, 397.9, 226.4)
      ..cubicTo(400.8, 227.4, 405.7, 227.4, 409.6, 226.4)
      ..cubicTo(413.5, 225.4, 417.4, 223.4, 421.3, 220.5)
      ..cubicTo(425.2, 217.6, 429.2, 213.7, 433.1, 208.8)
      ..cubicTo(437.0, 203.9, 442.9, 194.1, 444.8, 191.2)
      ..moveTo(450.7, 173.6)
      ..cubicTo(444.8, 191.2, 422.4, 259.6, 415.5, 279.2)
      ..cubicTo(408.6, 298.8, 412.5, 288.0, 409.6, 290.9)
      ..cubicTo(406.7, 293.8, 400.8, 296.8, 397.9, 296.8)
      ..cubicTo(395.0, 296.8, 393.0, 293.8, 392.0, 290.9)
      ..cubicTo(391.0, 288.0, 391.0, 284.1, 392.0, 279.2)
      ..cubicTo(393.0, 274.3, 394.0, 267.5, 397.9, 261.6)
      ..cubicTo(401.8, 255.7, 409.6, 248.9, 415.5, 244.0)
      ..cubicTo(421.4, 239.1, 428.2, 235.2, 433.1, 232.3)
      ..cubicTo(438.0, 229.4, 439.9, 229.3, 444.8, 226.4)
      ..cubicTo(449.7, 223.5, 456.5, 219.6, 462.4, 214.7)
      ..cubicTo(468.3, 209.8, 477.1, 200.0, 480.0, 197.1);

  /// Sorry: the word writes itself in soft blue and lilac with the same glow
  /// and pen tip as hi and bye, then sinks a little and fades.
  void _sorry(Canvas c, double t, math.Random r, double w, double h) {
    final scale = math.min(w * 0.78, 460.0) / 520;
    final sink = 18 * _smooth(_seg(t, 0.72, 1));
    final origin = Offset(w / 2 - 260 * scale, h * 0.42 - 200 * scale + sink);
    final m = Matrix4.diagonal3Values(scale, scale, 1)
      ..setTranslationRaw(origin.dx, origin.dy, 0);
    final path = _sorryPath.transform(m.storage);
    final metrics = path.computeMetrics().toList();
    final total = metrics.fold<double>(0, (sum, x) => sum + x.length);
    final write = Curves.easeInOutCubic.transform(_seg(t, 0.06, 0.62));
    final fade = 1 - _seg(t, 0.78, 1);
    final bounds = path.getBounds();
    const colors = [Color(0xFF8FB3D9), Color(0xFF8C96F6), Color(0xFFB39DDB)];
    // a soft colour bloom behind the word
    final bloom = _fadeInOut(t, 0.2, 0.75);
    if (bg && bloom > 0) {
      final cc = bounds.center;
      c.drawCircle(cc, bounds.width * 0.9, Paint()
        ..shader = RadialGradient(colors: [_a(colors[1], 0.22 * bloom), Colors.transparent])
            .createShader(Rect.fromCircle(center: cc, radius: bounds.width * 0.9)));
    }
    if (write <= 0 || fade <= 0) return;
    // what's written so far, letter after letter
    final part = Path();
    var left = total * write;
    Offset? tip;
    for (final x in metrics) {
      if (left <= 0) break;
      final take = math.min(left, x.length);
      part.addPath(x.extractPath(0, take), Offset.zero);
      if (take < x.length) tip = x.getTangentForOffset(take)?.position;
      left -= take;
    }
    final shader = LinearGradient(colors: colors).createShader(bounds.inflate(20));
    final width = 11 * scale;
    // glow, then the ink
    c.drawPath(part, Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = width * 2.6
      ..shader = shader
      ..color = Colors.white.withValues(alpha: 0.35 * fade)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
    c.drawPath(part, Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = width
      ..shader = shader
      ..color = Colors.white.withValues(alpha: fade));
    // the pen tip while writing
    if (write < 1 && tip != null) {
      c.drawCircle(tip, width * 1.6, Paint()
        ..color = Colors.white.withValues(alpha: 0.6 * fade)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
      c.drawCircle(tip, width * 0.55, _fill(Colors.white.withValues(alpha: fade)));
    }
  }

  void _rain(Canvas c, double t, math.Random r, double w, double h) {
    final dark = _fadeInOut(t, 0.15, 0.82);
    final full = Offset.zero & Size(w, h);
    if (bg) c.drawRect(full, Paint()
      ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_a(const Color(0xAA263238), dark), _a(const Color(0x55455A64), dark)]).createShader(full));
    // lightning: two flashes with a bolt
    for (final at in const [0.22, 0.52]) {
      final f = 1 - _seg(t, at, at + 0.07);
      if (t < at || f <= 0) continue;
      c.drawRect(full, _fill(_a(const Color(0x66FFFFFF), f * dark)));
      final x0 = w * (at < 0.4 ? 0.35 : 0.62);
      final bolt = Path()..moveTo(x0, h * 0.08);
      var x = x0, y = h * 0.08;
      final br = math.Random(seed + (at * 100).round());
      for (var k = 0; k < 6; k++) {
        x += (br.nextDouble() - 0.5) * 70;
        y += h * 0.07;
        bolt.lineTo(x, y);
      }
      c.drawPath(bolt, _stroke(_a(const Color(0xFFFFF59D), f), 5)..strokeJoin = StrokeJoin.round);
    }
    // dark clouds along the top
    final ca = _fadeInOut(t, 0.12, 0.85);
    for (var i = 0; i < 5; i++) {
      final cx = w * (i + 0.5) / 5 + math.sin(t * 2 + i) * 10;
      final cy = h * 0.07 + (i.isEven ? 0 : 18);
      final p = _fill(_a(const Color(0xFF455A64), 0.95 * ca));
      c.drawCircle(Offset(cx - 28, cy + 8), 34, p);
      c.drawCircle(Offset(cx + 6, cy - 6), 44, p);
      c.drawCircle(Offset(cx + 40, cy + 10), 30, p);
    }
    // heavy rain, slanting a little
    for (var i = 0; i < 90; i++) {
      final x0 = r.nextDouble() * (w + 80);
      final st = 0.05 + r.nextDouble() * 0.6;
      final len = 18 + r.nextDouble() * 16;
      final u = _seg(t, st, st + 0.22);
      if (u <= 0 || u >= 1) continue;
      final y = h * 0.08 + u * h * 0.95;
      final x = x0 - u * 60;
      c.drawLine(Offset(x, y), Offset(x - 6, y + len), _stroke(_a(const Color(0xFF90CAF9), 0.75 * dark), 2.2));
    }
    final u = _seg(t, 0.3, 0.9);
    if (u > 0 && u < 1) _glyph(c, '☔', 64, Offset(w / 2, h * 0.55), alpha: 1 - _seg(u, 0.75, 1), scale: _backOut(_seg(u, 0, 0.3)));
  }

  void _summer(Canvas c, double t, math.Random r, double w, double h) {
    final hot = _fadeInOut(t, 0.15, 0.8);
    final full = Offset.zero & Size(w, h);
    if (bg) c.drawRect(full, Paint()
      ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_a(const Color(0x66FF9800), hot), _a(const Color(0x33FFEB3B), hot), _a(const Color(0x55FF7043), hot)]).createShader(full));
    final sun = Offset(w / 2, h * 0.26);
    final sr = 70.0 * _backOut(_seg(t, 0.02, 0.3));
    if (hot > 0 && sr > 0) {
      c.drawCircle(sun, sr * 3.4, Paint()..shader = RadialGradient(colors: [_a(const Color(0xAAFFC107), hot), Colors.transparent]).createShader(Rect.fromCircle(center: sun, radius: sr * 3.4)));
      for (var k = 0; k < 16; k++) {
        final a = k / 16 * 2 * math.pi + t * 1.4;
        final outer = sr * (2.0 + 0.35 * math.sin(t * 24 + k));
        c.drawLine(sun + Offset(math.cos(a), math.sin(a)) * sr * 1.25, sun + Offset(math.cos(a), math.sin(a)) * outer, _stroke(_a(const Color(0xFFFF9800), 0.9 * hot), 7));
      }
      c.drawCircle(sun, sr, Paint()..shader = RadialGradient(colors: [_a(const Color(0xFFFFF59D), hot), _a(const Color(0xFFFF8F00), hot)]).createShader(Rect.fromCircle(center: sun, radius: sr)));
    }
    // heat waves rising from the bottom
    for (var i = 0; i < 7; i++) {
      final x0 = w * (i + 0.5) / 7;
      final st = 0.1 + r.nextDouble() * 0.3;
      final u = _seg(t, st, st + 0.55);
      if (u <= 0 || u >= 1) continue;
      final path = Path();
      final yb = h * (0.95 - u * 0.4);
      for (var k = 0; k <= 12; k++) {
        final y = yb - k * 10.0;
        final x = x0 + math.sin(k * 0.9 + t * 18 + i) * 8;
        k == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      c.drawPath(path, _stroke(_a(const Color(0xFFFFFFFF), 0.5 * (1 - u) * hot), 3));
    }
    final u = _seg(t, 0.3, 0.9);
    if (u > 0 && u < 1) _glyph(c, '😎', 64, Offset(w / 2, h * 0.58), alpha: 1 - _seg(u, 0.75, 1), scale: _backOut(_seg(u, 0, 0.3)));
  }

  void _winter(Canvas c, double t, math.Random r, double w, double h) {
    final cold = _fadeInOut(t, 0.15, 0.82);
    final full = Offset.zero & Size(w, h);
    if (bg) c.drawRect(full, Paint()
      ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_a(const Color(0x664FC3F7), cold), _a(const Color(0x22E1F5FE), cold), _a(const Color(0x66B3E5FC), cold)]).createShader(full));
    // frost creeping in from the corners
    for (final corner in [Offset.zero, Offset(w, 0), Offset(0, h), Offset(w, h)]) {
      c.drawCircle(corner, 170 * _smooth(_seg(t, 0.05, 0.4)), Paint()..shader = RadialGradient(colors: [_a(const Color(0x99FFFFFF), cold), Colors.transparent]).createShader(Rect.fromCircle(center: corner, radius: 170)));
    }
    // snowflakes drifting down
    for (var i = 0; i < 40; i++) {
      final x0 = r.nextDouble() * w;
      final st = r.nextDouble() * 0.55;
      final size = 8 + r.nextDouble() * 14;
      final sway = r.nextDouble() * 6;
      final u = _seg(t, st, st + 0.45);
      if (u <= 0 || u >= 1) continue;
      final p = Offset(x0 + math.sin(u * 7 + sway) * 24, -20 + u * (h + 40));
      final a = (1 - _seg(u, 0.8, 1)) * cold;
      final paint = _stroke(_a(Colors.white, 0.9 * a), size > 15 ? 2.6 : 1.8);
      for (var k = 0; k < 3; k++) {
        final ang = k * math.pi / 3 + u * 3 + sway;
        final d = Offset(math.cos(ang), math.sin(ang)) * size / 2;
        c.drawLine(p - d, p + d, paint);
      }
    }
    final u = _seg(t, 0.3, 0.9);
    if (u > 0 && u < 1) _glyph(c, '🥶', 64, Offset(w / 2, h * 0.5), alpha: 1 - _seg(u, 0.75, 1), scale: _backOut(_seg(u, 0, 0.3)), deg: math.sin(t * 60) * 4);
  }

  void _wow(Canvas c, double t, math.Random r, double w, double h) {
    final center = Offset(w / 2, h * 0.45);
    final fade = 1 - _seg(t, 0.75, 1);
    for (var i = 0; i < 28; i++) {
      final a = i / 28 * 2 * math.pi + r.nextDouble() * 0.1;
      final st = r.nextDouble() * 0.25;
      final u = _seg(t, st, st + 0.35);
      if (u <= 0 || u >= 1) continue;
      final r0 = 90 + u * 260, r1 = r0 + 60 * (1 - u);
      c.drawLine(center + Offset(math.cos(a), math.sin(a)) * r0, center + Offset(math.cos(a), math.sin(a)) * r1, _stroke(_a(const Color(0xFF313338), 0.35 * (1 - u)), 3));
    }
    final pop = _backOut(_seg(t, 0, 0.22));
    if (pop > 0) {
      final wob = 1 + 0.04 * math.sin(t * 40);
      final outer = 130 * pop * wob, inner = 92 * pop * wob;
      final burst = Path();
      for (var k = 0; k < 28; k++) {
        final a = k * math.pi / 14 + t * 0.6;
        final rr = k.isEven ? outer : inner;
        final p = center + Offset(math.cos(a), math.sin(a)) * rr;
        k == 0 ? burst.moveTo(p.dx, p.dy) : burst.lineTo(p.dx, p.dy);
      }
      burst.close();
      c.drawPath(burst, Paint()..shader = RadialGradient(colors: [_a(const Color(0xFFFFF176), fade), _a(const Color(0xFFFFB300), fade)]).createShader(Rect.fromCircle(center: center, radius: math.max(outer, 1))));
      c.drawPath(burst, _stroke(_a(const Color(0xFF313338), fade), 6)..strokeJoin = StrokeJoin.round);
    }
    _glyph(c, 'WOW!', 46, center, alpha: fade, scale: _backOut(_seg(t, 0.08, 0.3)), deg: -8 + math.sin(t * 30) * 3, bold: true, color: const Color(0xFFE53935));
  }

  @override
  bool shouldRepaint(covariant _ScenePainter old) => old.scene != scene;
}

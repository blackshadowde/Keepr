// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:vibe/vibe/vibe_slash.dart';

/// The samurai who deletes a message, move by move. He drops in at the end
/// of the message, crouches with his hand on the hilt and cuts it in one
/// dash; it falls apart behind his back. He never looks back: he spins the
/// blade into a backhand grip, drives it into the ground behind him,
/// springs clear of the dust and walks away slowly.
///
/// Everything is worked out from the time alone (in ms), so any frame can be
/// painted on its own.
abstract class VibeSamurai {
  static const total = 3400.0;

  /// He draws (a light buzz).
  static const draw = 772.0;

  /// The message starts to fall apart.
  static const split = 1110.0;

  /// The sword hits the ground (a heavy buzz).
  static const impact = 1920.0;
}

// ---- easing

typedef _Ease = double Function(double u);
double _lin(double u) => u;
double _inQuad(double u) => u * u;
double _outQuad(double u) => 1 - (1 - u) * (1 - u);
double _inCubic(double u) => u * u * u;
double _outCubic(double u) => 1 - (1 - u) * (1 - u) * (1 - u);
double _inOutCubic(double u) =>
    u < 0.5 ? 4 * u * u * u : 1 - math.pow(-2 * u + 2, 3).toDouble() / 2;
double _inOutSine(double u) => -(math.cos(math.pi * u) - 1) / 2;
double _outExpo(double u) => u >= 1 ? 1 : 1 - math.pow(2, -10 * u).toDouble();
double _inExpo(double u) => u <= 0 ? 0 : math.pow(2, 10 * u - 10).toDouble();
double _back(double u, double c1) {
  final v = u - 1;
  return 1 + (c1 + 1) * v * v * v + c1 * v * v;
}

double _outBack(double u) => _back(u, 1.70158);
double _outBackSoft(double u) => _back(u, 0.9);

double _seg(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);
double _lerp(double a, double b, double u) => a + (b - a) * u;

// ---- the moves

/// The planted blade's angle, held facing left (wound once round so the
/// slam turns the short way).
const _plantL = -math.pi - 1.3509;

class _K {
  final double t;
  final _Ease ease;
  final Map<String, double> v;
  const _K(this.t, this.ease, this.v);
}

// Each channel goes from one key that sets it to the next, with the ease of
// the key it is heading to. Positions are in body heights, x forward (the
// way he faces), y down, feet at 0.
const _keys = <_K>[
  _K(0, _lin, {'Y': -3.4, 'sx': 0.9, 'sy': 1.14, 'hipH': 0.56, 'hipX': 0.0, 'lean': -0.06, 'bend': -0.04, 'tilt': -0.2, 'fFx': 0.1, 'fFy': 0.16, 'bFx': -0.1, 'bFy': 0.08, 'h1x': 0.2, 'h1y': -0.8, 'h2x': -0.2, 'h2y': -0.84, 'sheathGrip': 0.0, 'mouthGrip': 0.0, 'swA': -3.44, 'grip': 0.0}),
  _K(232, _inQuad, {'Y': -0.03}),
  _K(232, _outQuad, {'fFx': 0.13, 'fFy': 0.03, 'bFx': -0.13, 'bFy': 0.02, 'h1y': -0.86, 'h2y': -0.9}),
  _K(232, _lin, {'sx': 0.9, 'sy': 1.16}),
  _K(262, _outQuad, {'Y': 0.0, 'sx': 1.16, 'sy': 0.8, 'hipH': 0.3, 'lean': 0.34, 'bend': 0.18, 'tilt': 0.18, 'fFx': 0.21, 'fFy': 0.0, 'bFx': -0.19, 'bFy': 0.0, 'h1x': 0.26, 'h1y': -0.3, 'h2x': -0.14, 'h2y': -0.28}),
  _K(385, _outCubic, {'sx': 0.97, 'sy': 1.05, 'hipH': 0.5, 'lean': 0.06, 'bend': 0.03, 'tilt': -0.04, 'fFx': 0.12, 'bFx': -0.12, 'h1x': 0.1, 'h1y': -0.32, 'h2x': -0.05, 'h2y': -0.34}),
  _K(480, _inOutSine, {'sx': 1.0, 'sy': 1.0, 'hipH': 0.48, 'lean': 0.1, 'bend': 0.04, 'tilt': 0.0, 'sheathGrip': 0.0, 'mouthGrip': 0.0}),
  _K(600, _inOutCubic, {'sheathGrip': 1.0, 'mouthGrip': 1.0, 'fFx': 0.22}),
  _K(600, _inOutSine, {'fFy': 0.07}),
  _K(700, _inOutCubic, {'hipH': 0.34, 'hipX': -0.03, 'lean': 0.42, 'bend': 0.14, 'tilt': -0.2, 'fFx': 0.33, 'fFy': 0.0, 'bFx': -0.28}),
  _K(765, _outCubic, {'hipH': 0.31, 'hipX': -0.1, 'lean': 0.34, 'sheathGrip': 1.0, 'mouthGrip': 1.0, 'swA': -3.44, 'h1x': 0.1, 'h1y': -0.32, 'h2x': -0.05, 'h2y': -0.34, 'fFx': 0.33, 'bFx': -0.28, 'sx': 1.0, 'sy': 1.0, 'tilt': -0.2}),
  _K(800, _outExpo, {'sheathGrip': 0.0, 'mouthGrip': 0.0, 'h1x': 0.52, 'h1y': -0.36, 'h2x': -0.42, 'h2y': -0.46, 'swA': 0.05, 'hipH': 0.27, 'hipX': 0.05, 'lean': 0.88, 'bend': 0.02, 'tilt': -0.38, 'fFx': 0.5, 'fFy': 0.1, 'bFx': -0.42, 'bFy': 0.03, 'sx': 1.28, 'sy': 0.84}),
  _K(1010, _outCubic, {'hipH': 0.27, 'hipX': 0.02, 'lean': 0.5, 'bend': 0.1, 'tilt': -0.14, 'fFx': 0.4, 'fFy': 0.0, 'bFx': -0.44, 'bFy': 0.0, 'h1x': 0.47, 'h1y': -0.5, 'h2x': -0.3, 'h2y': -0.52, 'swA': 0.18, 'sx': 1.0, 'sy': 1.0}),
  _K(1090, _outBackSoft, {'hipH': 0.3, 'lean': 0.46}),
  _K(1300, _lin, {'hipH': 0.3, 'lean': 0.46, 'hipX': 0.02, 'bend': 0.1, 'tilt': -0.14, 'fFx': 0.4, 'bFx': -0.44, 'h1x': 0.47, 'h1y': -0.5, 'h2x': -0.3, 'h2y': -0.52, 'swA': 0.18, 'Y': 0.0, 'fFy': 0.0, 'bFy': 0.0, 'grip': 0.0, 'sx': 1.0, 'sy': 1.0}),
  _K(1360, _outCubic, {'h1x': 0.3, 'h1y': -0.8, 'swA': -1.0, 'lean': 0.3, 'hipH': 0.34}),
  _K(1420, _inCubic, {'h1x': 0.46, 'h1y': -0.58, 'swA': 0.62, 'lean': 0.44, 'hipH': 0.3}),
  _K(1480, _outBack, {'h1x': 0.4, 'h1y': -0.54, 'swA': 0.5}),
  _K(1525, _inOutSine, {'bFy': 0.07}),
  _K(1570, _inOutCubic, {'hipH': 0.46, 'hipX': 0.0, 'lean': 0.1, 'bend': 0.04, 'tilt': -0.04, 'fFx': 0.16, 'bFx': -0.16, 'bFy': 0.0, 'h1x': 0.3, 'h1y': -0.52, 'swA': 0.35, 'h2x': -0.05, 'h2y': -0.38}),
  _K(1640, _outCubic, {'h1x': 0.1, 'h1y': -0.95, 'swA': -0.6, 'h2x': 0.12, 'h2y': -0.55}),
  _K(1730, _outBack, {'h1x': 0.02, 'h1y': -1.18, 'swA': -3.88, 'h2x': 0.3, 'h2y': -0.7, 'hipH': 0.5, 'lean': -0.04, 'bend': -0.03, 'tilt': -0.12, 'fFx': 0.18, 'bFx': -0.18}),
  _K(1840, _lin, {'h1x': 0.02, 'h1y': -1.18, 'swA': -3.88, 'h2x': 0.3, 'h2y': -0.7, 'hipH': 0.5, 'lean': -0.04, 'bend': -0.03, 'tilt': -0.12, 'fFx': 0.18, 'bFx': -0.18, 'grip': 0.0}),
  _K(1920, _inExpo, {'h1x': -0.209, 'h1y': -0.857, 'swA': _plantL, 'grip': 1.0, 'hipH': 0.36, 'lean': 0.12, 'bend': 0.1, 'tilt': -0.06, 'fFx': 0.26, 'bFx': -0.24}),
  _K(1960, _outQuad, {'hipH': 0.35, 'lean': 0.15, 'sx': 1.02, 'sy': 0.97, 'fFy': 0.0, 'bFy': 0.0}),
  _K(2040, _outQuad, {'Y': -0.1, 'sx': 0.96, 'sy': 1.06, 'hipH': 0.44, 'lean': 0.3, 'fFx': 0.22, 'fFy': 0.1, 'bFx': -0.26, 'bFy': 0.08, 'h1x': -0.12, 'h1y': -0.42, 'h2x': -0.06, 'h2y': -0.44, 'tilt': -0.1}),
  _K(2130, _inQuad, {'Y': 0.0, 'fFy': 0.0, 'bFy': 0.0}),
  _K(2130, _outQuad, {'sx': 1.07, 'sy': 0.9, 'hipH': 0.36, 'lean': 0.22, 'fFx': 0.2, 'bFx': -0.2}),
  _K(2260, _outBack, {'sx': 1.0, 'sy': 1.0, 'hipH': 0.47, 'lean': 0.07, 'bend': 0.03, 'tilt': 0.0, 'fFx': 0.12, 'bFx': -0.12, 'h1x': 0.06, 'h1y': -0.34, 'h2x': -0.02, 'h2y': -0.35}),
];

final Map<String, List<_K>> _tracks = () {
  final m = <String, List<_K>>{};
  for (final k in _keys) {
    for (final c in k.v.keys) {
      (m[c] ??= []).add(k);
    }
  }
  for (final l in m.values) {
    l.sort((a, b) => a.t.compareTo(b.t));
  }
  return m;
}();

double _track(String c, double t) {
  final k = _tracks[c]!;
  if (t <= k.first.t) return k.first.v[c]!;
  for (var i = 1; i < k.length; i++) {
    if (t <= k[i].t) {
      final a = k[i - 1], b = k[i];
      final u = b.t == a.t ? 1.0 : (t - a.t) / (b.t - a.t);
      return _lerp(a.v[c]!, b.v[c]!, b.ease(u));
    }
  }
  return k.last.v[c]!;
}

const _walkAt = 2380.0;
const _walkV = 0.30 / 250; // body heights per ms: a slow walk

Offset _footCycle(double ph) {
  ph = ((ph % 1) + 1) % 1;
  if (ph < 0.5) return Offset(0.15 - 0.30 * (ph / 0.5), 0);
  final u = (ph - 0.5) / 0.5;
  return Offset(-0.15 + 0.30 * _inOutSine(u), math.sin(math.pi * u) * 0.07);
}

/// Where things are, from the message's card.
class _Geo {
  final Rect bubble;
  late final double ground = bubble.bottom;
  late final double sword = bubble.height.clamp(26.0, 58.0);
  late final double h = sword / 1.22;
  late final double endX = bubble.right - 0.18 * h;
  late final double dashX = bubble.left - 0.12 * h;
  late final double plantX = dashX + 0.40 * h; // behind him
  late final double cutY = ground - 0.42 * h;
  _Geo(this.bubble);

  double rootX(double t) {
    var x = endX;
    if (t > 765) x = _lerp(endX, dashX, _outExpo(_seg(t, 765, 1010)));
    // springs forward, away from the sword
    x -= h * 0.45 * _outCubic(_seg(t, 1965, 2130));
    if (t > _walkAt) {
      final tau = t - _walkAt, v = _walkV * h;
      x -= tau < 200 ? v * tau * tau / 400 : v * (tau - 100);
    }
    return x;
  }

  /// A point on the planted sword, [yy] along it (negative is up).
  Offset plantPoint(double t, double yy) {
    final th = -0.22 + _wobble(t);
    return Offset(plantX - yy * math.sin(th), ground + yy * math.cos(th));
  }
}

/// The planted sword's jolt on impact and its quiver after he lets go.
double _wobble(double t) {
  var w = 0.0;
  final a = _seg(t, VibeSamurai.impact, VibeSamurai.impact + 80);
  if (a > 0 && a < 1) w += 0.025 * math.sin(a * math.pi * 4) * (1 - a);
  final b = _seg(t, 1995, 2300);
  if (b > 0 && b < 1) {
    w += 0.07 * math.sin(b * math.pi * 7) * math.pow(1 - b, 1.5).toDouble();
  }
  return w;
}

class _Pose {
  final double t;
  late double y = _track('Y', t),
      sx = _track('sx', t),
      sy = _track('sy', t),
      hipH = _track('hipH', t),
      hipX = _track('hipX', t),
      lean = _track('lean', t),
      bend = _track('bend', t),
      tilt = _track('tilt', t),
      fFx = _track('fFx', t),
      fFy = _track('fFy', t),
      bFx = _track('bFx', t),
      bFy = _track('bFy', t),
      h1x = _track('h1x', t),
      h1y = _track('h1y', t),
      h2x = _track('h2x', t),
      h2y = _track('h2y', t),
      sheathGrip = _track('sheathGrip', t),
      mouthGrip = _track('mouthGrip', t),
      swA = _track('swA', t),
      grip = _track('grip', t);
  final double x;
  late final double op = 1 - _seg(t, 3050, 3400);

  _Pose(this.t, _Geo g) : x = g.rootX(t) {
    // breathing while he holds still
    if (t > 1090 && t < 1300) hipH += 0.006 * math.sin((t - 1090) / 70);
    // a tremble with the blade held high
    if (t > 1730 && t < 1845) {
      final a = _seg(t, 1730, 1780);
      h1x += 0.004 * math.sin(t * 0.9) * a;
      h1y += 0.004 * math.cos(t * 1.3) * a;
    }
    // walking away
    final w = _inOutSine(_seg(t, _walkAt - 20, _walkAt + 110));
    if (w > 0) {
      final ph = math.max(0.0, t - _walkAt) / 500;
      final a = _footCycle(ph), b = _footCycle(ph + 0.5);
      final s = math.sin(math.pi * 2 * ph);
      fFx = _lerp(fFx, a.dx, w);
      fFy = _lerp(fFy, a.dy, w);
      bFx = _lerp(bFx, b.dx, w);
      bFy = _lerp(bFy, b.dy, w);
      h1x = _lerp(h1x, 0.05 + 0.07 * s, w);
      h1y = _lerp(h1y, -0.35, w);
      h2x = _lerp(h2x, 0.03 - 0.07 * s, w);
      h2y = _lerp(h2y, -0.37, w);
      hipH = _lerp(hipH, 0.475 + 0.014 * math.cos(math.pi * 4 * (ph - 0.25)), w);
      lean = _lerp(lean, 0.06, w);
    }
  }
}

// two-bone reach from a toward b; [sign] picks the side the joint bends to
(Offset, Offset) _ik(Offset a, Offset b, double l1, double l2, double sign) {
  final d0 = b - a;
  final d = math.max(1e-6, d0.distance);
  final dd = d.clamp((l1 - l2).abs() + 1e-3, l1 + l2 - 1e-3);
  final ang = math.atan2(d0.dy, d0.dx);
  final c = ((l1 * l1 + dd * dd - l2 * l2) / (2 * l1 * dd)).clamp(-1.0, 1.0);
  final th = ang + sign * math.acos(c);
  final mid = a + Offset(math.cos(th), math.sin(th)) * l1;
  final end = d > dd ? a + d0 / d * dd : b;
  return (mid, end);
}

Offset _bez(Offset a, Offset c, Offset b, double u) =>
    a * ((1 - u) * (1 - u)) + c * (2 * (1 - u) * u) + b * (u * u);

// along the scabbard, toward its end (in his own frame)
final _sb = Offset(-math.cos(0.42), math.sin(0.42));

/// The figure's joints, in the row's coordinates.
class _Sk {
  late final Offset hip, neck, ctrl, head, sh;
  late final double headR;
  late final Offset kneeF, footF, kneeB, footB, elbowF, handF, elbowB, handB;
  late final Offset mouth, scabEnd, pommel, dir, knot, eye;
  late final List<Offset> hat, band;

  _Sk(_Pose p, _Geo g) {
    final h = g.h, sh2 = g.sword / h;
    final fx = -p.sx * h, fy = p.sy * h, ox = p.x, oy = g.ground + p.y * h;
    Offset w(Offset q) => Offset(ox + fx * q.dx, oy + fy * q.dy);
    Offset toL(Offset q) => Offset((q.dx - ox) / fx, (q.dy - oy) / fy);
    final hipL = Offset(p.hipX, -p.hipH);
    final up = Offset(math.sin(p.lean), -math.cos(p.lean));
    final neckL = hipL + up * 0.34;
    final back = Offset(-math.cos(p.lean), -math.sin(p.lean));
    final ctrlL = (hipL + neckL) / 2 + back * (p.bend * 0.34);
    final ha = p.lean + p.tilt;
    final hu = Offset(math.sin(ha), -math.cos(ha));
    final hf = Offset(math.cos(ha), math.sin(ha));
    const r = 0.13;
    final headL = neckL + hu * (0.05 + r);
    final shL = _bez(hipL, ctrlL, neckL, 0.86);
    final legF = _ik(hipL, Offset(p.fFx, -p.fFy), 0.27, 0.27, -1);
    final legB = _ik(hipL, Offset(p.bFx, -p.bFy), 0.27, 0.27, -1);
    final mouthL = hipL + const Offset(0.10, 0.03);
    var h1 = Offset(p.h1x, p.h1y), h2 = Offset(p.h2x, p.h2y);
    h1 = Offset.lerp(h1, mouthL - _sb * (0.08 * sh2), p.sheathGrip)!;
    h2 = Offset.lerp(h2, mouthL + _sb * 0.04, p.mouthGrip)!;
    final dL = Offset(math.cos(p.swA), math.sin(p.swA));
    if (p.t >= VibeSamurai.impact) {
      final rel = _inOutCubic(_seg(p.t, 1958, 2010));
      h1 = Offset.lerp(toL(g.plantPoint(p.t, -0.72 * g.sword)), h1, rel)!;
      h2 = Offset.lerp(toL(g.plantPoint(p.t, -0.86 * g.sword)), h2, rel)!;
    } else {
      h2 = Offset.lerp(h2, h1 - dL * (0.14 * sh2), p.grip)!;
    }
    final armF = _ik(shL, h1, 0.22, 0.22, 1);
    final armB = _ik(shL, h2, 0.22, 0.22, 1);
    final dw = Offset(fx * dL.dx, fy * dL.dy);
    Offset onHead(double ax, double ay) => w(headL + hf * ax - hu * ay);
    hip = w(hipL);
    neck = w(neckL);
    ctrl = w(ctrlL);
    head = w(headL);
    sh = w(shL);
    headR = r * h * math.sqrt((p.sx * p.sy).abs());
    kneeF = w(legF.$1);
    footF = w(legF.$2);
    kneeB = w(legB.$1);
    footB = w(legB.$2);
    elbowF = w(armF.$1);
    handF = w(armF.$2);
    elbowB = w(armB.$1);
    handB = w(armB.$2);
    mouth = w(mouthL);
    scabEnd = w(mouthL + _sb * 0.6);
    pommel = w(mouthL - _sb * (0.34 * sh2));
    dir = dw / math.max(1e-6, dw.distance);
    hat = [onHead(-1.9 * r, -0.5 * r), onHead(0, -1.6 * r), onHead(1.9 * r, -0.5 * r)];
    band = [onHead(-r, -0.1 * r), onHead(r, -0.1 * r)];
    knot = onHead(-0.95 * r, -0.1 * r);
    eye = onHead(0.55 * r, -0.12 * r);
  }

  /// Where the held blade would meet the ground if planted, and its guard.
  (Offset, Offset) sword(_Geo g) {
    final guard = handF + dir * (0.08 * g.sword);
    return (guard + dir * (0.64 * g.sword), guard);
  }
}

/// Paints the samurai over the message's row at [t] ms. [row] is a picture
/// of the row taken when he arrived; from [VibeSamurai.split] on it is cut
/// in two and crumbles away (the row itself is hidden then).
class VibeSamuraiPainter extends CustomPainter {
  final double t;
  final Rect bubble;
  final ui.Image? row;
  final Color ink, crumb;
  final bool dark;
  VibeSamuraiPainter({
    required this.t,
    required this.bubble,
    required this.row,
    required this.ink,
    required this.crumb,
    required this.dark,
  });

  static const _band = Color(0xFFE53935);
  static const _straw = Color(0xFFCDAA6D);
  static const _hilt = Color(0xFFF2F2F2);
  static const _wrap = Color(0xFF1E1E1E);
  static const _guard = Color(0xFF2B2B2B);
  Color get _glint => dark ? const Color(0xFFFFD27A) : const Color(0xFFF2B33D);
  Color get _saya => dark ? const Color(0xFFA9876F) : const Color(0xFF3B2B2B);
  Color get _petal => dark ? const Color(0xFFE58FA5) : const Color(0xFFF2A3B6);

  late final _Geo g = _Geo(bubble);
  final _poses = <double, _Pose>{};
  _Pose _p(double tt) => _poses[tt] ??= _Pose(tt, g);
  final _sks = <double, _Sk>{};
  _Sk _s(double tt) => _sks[tt] ??= _Sk(_p(tt), g);

  Paint _line(Color c, double w, {double a = 1}) => Paint()
    ..color = c.withValues(alpha: c.a * a.clamp(0.0, 1.0))
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke;
  Paint _fill(Color c, {double a = 1}) => Paint()..color = c.withValues(alpha: c.a * a.clamp(0.0, 1.0));

  @override
  void paint(Canvas canvas, Size size) {
    final b = bubble, h = g.h;
    if (t >= VibeSamurai.split) _pieces(canvas, size);
    _cut(canvas);
    // landing puffs
    final lw = _seg(t, 262, 620);
    if (lw > 0 && lw < 1) {
      for (final s in [-1.0, 1.0]) {
        final r = _lerp(0.07, 0.26, _outCubic(lw)) * h;
        final cx = g.endX + s * _lerp(0.15, 0.62, _outCubic(lw)) * h;
        canvas.drawCircle(Offset(cx, g.ground - r * 0.6), r, _fill(ink, a: 0.14 * (1 - lw)));
        for (var i = 0; i < 3; i++) {
          canvas.drawCircle(
            Offset(g.endX + s * (0.2 + i * 0.18 + lw * 0.6) * h,
                g.ground - (0.05 + i * 0.07) * h * math.sin(math.pi * lw)),
            1.1,
            _fill(ink, a: 0.4 * (1 - lw)),
          );
        }
      }
    }
    // the dash: speed lines and afterimages
    if (t > 770 && t < 1040) {
      final v = (g.rootX(t - 16) - g.rootX(t)) / 16;
      final x0 = g.rootX(t) + 0.35 * h;
      const lines = [0.14, 0.32, 0.5, 0.66, 0.82, 0.98];
      for (var i = 0; i < lines.length; i++) {
        final len = math.min(3.6 * h, v * (70 + i * 13 % 40));
        if (len < 2) continue;
        final st = x0 + ((i * 7) % 5) * 2;
        final y = g.ground - lines[i] * h;
        canvas.drawLine(Offset(st, y), Offset(st + len, y),
            _line(ink, i.isOdd ? 1.2 : 1.8, a: (v * 1.4).clamp(0.0, 0.42)));
      }
      for (var k = 5; k >= 1; k--) {
        final tt = t - k * 16;
        if (tt < 768) continue;
        _figure(canvas, tt, 0.3 * (1 - k / 6), plain: true);
      }
    }
    // skid dust
    for (final st in const [900.0, 950.0, 1000.0]) {
      final u = _seg(t, st, st + 360);
      if (u <= 0 || u >= 1) continue;
      final r = _lerp(0.06, 0.2, _outCubic(u)) * h;
      final foot = _s(st).footB;
      canvas.drawCircle(Offset(foot.dx + u * 0.3 * h, g.ground - r * 0.7 - u * 0.12 * h), r,
          _fill(ink, a: 0.13 * (1 - u)));
    }
    _smear(canvas, 772, 850, 0.8);
    _smear(canvas, 1372, 1425, 0.7);
    _smear(canvas, 1600, 1720, 0.4);
    _smear(canvas, 1852, VibeSamurai.impact, 0.75);
    // planted, with the grass growing round it
    if (t >= VibeSamurai.impact) {
      canvas.save();
      canvas.translate(g.plantX, g.ground);
      canvas.rotate(_wobble(t));
      paintPlantedSword(canvas, g.sword, ink, grass: _outBack(_seg(t, 2150, 2600)));
      canvas.restore();
    }
    final sk = _figure(canvas, t, 1);
    // sparks off the blade in the dash
    if (t > 772 && t < 1030) {
      final tip = _s(t).sword(g).$1;
      final rnd = math.Random((t / 33).floor() + 3);
      final fade = 1 - _seg(t, 900, 1030);
      for (var i = 0; i < 6; i++) {
        final sx = tip.dx + rnd.nextDouble() * h * 1.4, sy = g.cutY - rnd.nextDouble() * h * 0.45;
        final dx = 3 + rnd.nextDouble() * 4, dy = 1 + rnd.nextDouble() * 2, a = 0.5 + rnd.nextDouble() * 0.5;
        if (sx > b.right) continue;
        canvas.drawLine(Offset(sx, sy), Offset(sx + dx, sy - dy), _line(_glint, 1.3, a: fade * a));
      }
    }
    // a glint in his eye before the dash
    final eg = _seg(t, 705, 790);
    if (sk != null && eg > 0 && eg < 1) {
      final s = math.sin(math.pi * eg);
      canvas.drawLine(sk.eye + const Offset(2, 0), sk.eye + const Offset(-2.5, -0.5), _line(Colors.white, 1.4, a: s));
      _star(canvas, sk.eye + const Offset(-3, -1), 0.28 * h * s, eg * 1.2, s);
    }
    // the glint on the blade, held high
    final gl = _seg(t, 1740, 1850);
    if (gl > 0 && gl < 1) {
      final tip = _s(t).sword(g).$1;
      final s = math.sin(math.pi * gl);
      canvas.drawCircle(tip, h * 0.6, Paint()
        ..shader = ui.Gradient.radial(tip, h * 0.6, [_glint.withValues(alpha: 0.35 * s), _glint.withValues(alpha: 0)]));
      _star(canvas, tip, h * 0.5 * s, gl * math.pi * 0.5, s);
    }
    _impact(canvas);
    // petals
    for (var i = 0; i < 4; i++) {
      final rnd = math.Random(40 + i);
      final x0 = _lerp(b.left, b.right + h, rnd.nextDouble());
      final start = 2250 + i * 160 + rnd.nextDouble() * 80, dur = 1200 + rnd.nextDouble() * 500;
      final sway = 6 + rnd.nextDouble() * 8, ph = rnd.nextDouble() * math.pi * 2;
      final u = (t - start) / dur;
      if (u <= 0 || u >= 1) continue;
      final x = x0 - u * 2.6 * h + math.sin(u * 6 + ph) * sway;
      final y = _lerp(g.ground - 2.4 * h, g.ground - 2, u);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(u * 7 + ph);
      canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: 6.8, height: 3.6),
          _fill(_petal, a: 0.9 * math.min(1.0, math.min(u * 6, (1 - u) * 5))));
      canvas.restore();
    }
  }

  // the picture of the message, cut along the line and crumbling away
  void _pieces(Canvas canvas, Size size) {
    final b = bubble;
    final u = _outCubic(_seg(t, VibeSamurai.split, 1290));
    final from = b.left < size.width * 0.3 ? -8.0 : b.left - 8;
    final ex = _lerp(from, b.right + 8, _inOutSine(_seg(t, 1180, 1420)));
    final img = row;
    if (img != null && ex < b.right + 8) {
      final c = Offset(b.center.dx, 0);
      for (final top in [true, false]) {
        canvas.save();
        final d = top ? Offset(3 * u, -5 * u) : Offset(-2 * u, 4 * u);
        final rot = top ? -0.025 * u : 0.02 * u;
        final cy = top ? (b.top + g.cutY) / 2 : (g.cutY + b.bottom) / 2;
        canvas.translate(c.dx + d.dx, cy + d.dy);
        canvas.rotate(rot);
        canvas.translate(-c.dx, -cy);
        canvas.clipRect(top
            ? Rect.fromLTRB(-20, -400, size.width + 20, g.cutY)
            : Rect.fromLTRB(-20, g.cutY, size.width + 20, size.height + 400));
        // what has crumbled is gone; a ragged edge sweeps across
        final edge = Path()..moveTo(size.width + 40, -400);
        for (var y = -10.0; y <= size.height + 10; y += 4) {
          edge.lineTo(ex + math.sin(y * 1.7) * 2.5 + math.sin(y * 0.6) * 2, y);
        }
        edge
          ..lineTo(size.width + 40, size.height + 400)
          ..close();
        canvas.clipPath(edge);
        canvas.drawImageRect(
          img,
          Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
          Offset.zero & size,
          Paint()..filterQuality = FilterQuality.medium,
        );
        canvas.restore();
      }
    }
    // crumbs
    final rnd = math.Random(7);
    for (var i = 0; i < 90; i++) {
      final x = _lerp(b.left + 2, b.right - 2, rnd.nextDouble());
      final y = _lerp(b.top + 2, b.bottom - 2, rnd.nextDouble());
      final spawn = 1180 + (x - b.left) / math.max(1, b.width) * 240 + rnd.nextDouble() * 30;
      final vx = 0.025 + rnd.nextDouble() * 0.07, vy = -0.05 + rnd.nextDouble() * 0.045;
      final life = 420 + rnd.nextDouble() * 220, sz = 1.2 + rnd.nextDouble() * 1.6;
      final rot = rnd.nextDouble() * math.pi * 2, spin = (rnd.nextDouble() - 0.5) * 0.02;
      final isInk = rnd.nextDouble() < 0.32;
      final age = t - spawn;
      if (age < 0 || age > life) continue;
      final top = y < g.cutY;
      final off = top ? Offset(3 * u, -5 * u) : Offset(-2 * u, 4 * u);
      canvas.save();
      canvas.translate(x + off.dx + vx * age, y + off.dy + vy * age + 0.00012 * age * age);
      canvas.rotate(rot + spin * age);
      canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: sz, height: sz),
          _fill(isInk ? ink : crumb, a: 1 - math.pow(age / life, 1.6).toDouble()));
      canvas.restore();
    }
  }

  // the cut across the message: it follows the blade, flashes, then fades
  void _cut(Canvas canvas) {
    if (t < VibeSamurai.draw || t >= 1260) return;
    final b = bubble;
    var left = b.left - 4;
    if (t < 1010) left = math.max(left, _s(t).sword(g).$1.dx);
    final right = b.right + 4;
    if (left >= right) return;
    final fade = 1 - _seg(t, VibeSamurai.split, 1260);
    final a = Offset(left, g.cutY), z = Offset(right, g.cutY);
    canvas.drawLine(a, z, _line(ink, 6, a: 0.16 * fade));
    canvas.drawLine(a, z, _line(ink, 2.8, a: 0.45 * fade));
    canvas.drawLine(a, z, _line(Colors.white, 1.5, a: 0.95 * fade));
    final fu = _seg(t, 1080, 1170);
    if (fu > 0 && fu < 1) {
      final fx = _lerp(b.left, b.right, _inOutSine(fu));
      final p = Paint()
        ..shader = ui.Gradient.linear(Offset(fx - 34, 0), Offset(fx + 34, 0), [
          Colors.white.withValues(alpha: 0),
          Colors.white.withValues(alpha: math.sin(math.pi * fu)),
          Colors.white.withValues(alpha: 0),
        ], [0, 0.5, 1])
        ..strokeWidth = 3.2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(fx - 34, g.cutY), Offset(fx + 34, g.cutY), p);
    }
  }

  // the blade's tip and guard over the last few frames, as a filled smear
  void _smear(Canvas canvas, double from, double to, double strength) {
    if (t < from || t > to + 60) return;
    final tips = <Offset>[], guards = <Offset>[];
    for (var k = 0; k <= 7; k++) {
      final tt = t - k * 9;
      if (tt < from) break;
      final s = _s(math.min(tt, to)).sword(g);
      tips.add(s.$1);
      guards.add(s.$2);
    }
    if (tips.length < 2) return;
    final fade = 1 - _seg(t, to, to + 60);
    final c = ink.withValues(alpha: 0.6);
    final path = Path()..moveTo(tips.first.dx, tips.first.dy);
    for (final q in tips.skip(1)) {
      path.lineTo(q.dx, q.dy);
    }
    for (final q in guards.reversed) {
      path.lineTo(q.dx, q.dy);
    }
    path.close();
    canvas.drawPath(path, _fill(c, a: 0.28 * strength * fade));
    final edge = Path()..moveTo(tips.first.dx, tips.first.dy);
    for (final q in tips.skip(1)) {
      edge.lineTo(q.dx, q.dy);
    }
    canvas.drawPath(edge, _line(c, 1.4, a: 0.55 * strength * fade));
  }

  void _star(Canvas canvas, Offset c, double r, double rot, double a) {
    if (r <= 0.2) return;
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final rr = i.isEven ? r : r * 0.18;
      final an = rot + i / 8 * math.pi * 2;
      final p = c + Offset(math.cos(an), math.sin(an)) * rr;
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(path, _fill(_glint, a: a));
    canvas.drawCircle(c, r * 0.16, _fill(Colors.white, a: a));
  }

  void _impact(Canvas canvas) {
    final h = g.h, base = Offset(g.plantX, g.ground);
    const at = VibeSamurai.impact;
    final iw = _seg(t, at, at + 150);
    if (iw > 0 && iw < 1) {
      final r = h * _lerp(0.5, 1.9, _outCubic(iw));
      canvas.drawCircle(base, r, Paint()
        ..shader = ui.Gradient.radial(base, r, [_glint.withValues(alpha: 0.55 * (1 - iw)), _glint.withValues(alpha: 0)]));
      for (var i = 0; i < 9; i++) {
        final an = math.pi + (i + 0.5) / 9 * math.pi;
        final r1 = _lerp(0.3, 1.1, _outCubic(iw)) * h, r2 = _lerp(0.5, 1.45, _outCubic(iw)) * h;
        final d = Offset(math.cos(an), math.sin(an) * 0.8);
        canvas.drawLine(base + d * r1, base + d * r2, _line(ink, 1.7 * (1 - iw) + 0.3, a: 0.7 * (1 - iw)));
      }
    }
    final rw = _seg(t, at, at + 290);
    if (rw > 0 && rw < 1) {
      final wd = _lerp(0.4, 3.4, _outCubic(rw)) * h;
      canvas.drawOval(Rect.fromCenter(center: base, width: wd, height: wd * 0.18), _line(ink, 1.4, a: 0.55 * (1 - rw)));
    }
    final cw = _seg(t, at, at + 660);
    if (cw > 0 && cw < 1) {
      final grow = _outCubic(_seg(t, at, at + 60));
      final rnd = math.Random(5);
      final p = _line(ink, 1, a: 0.5 * (1 - _seg(t, at + 260, at + 660)));
      for (final dir in const [-1.0, 1.0, -1.0, 1.0]) {
        final pts = [Offset.zero];
        var x = 0.0;
        final n = 4 + rnd.nextInt(2);
        for (var i = 0; i < n; i++) {
          x += dir * (3 + rnd.nextDouble() * 5);
          pts.add(Offset(x, (rnd.nextDouble() - 0.6) * 2.4));
        }
        final m = math.max(2, (pts.length * grow).ceil());
        final path = Path()..moveTo(base.dx, base.dy + 1);
        for (final q in pts.take(m).skip(1)) {
          path.lineTo(base.dx + q.dx, base.dy + 1 + q.dy);
        }
        canvas.drawPath(path, p);
      }
    }
    final age = t - at;
    if (age >= 0) {
      final rnd = math.Random(11);
      for (var i = 0; i < 18; i++) {
        final ang = math.pi + 0.15 + rnd.nextDouble() * (math.pi - 0.3);
        final sp = 0.05 + rnd.nextDouble() * 0.11;
        final r = 0.8 + rnd.nextDouble() * 1.4, life = 300 + rnd.nextDouble() * 260;
        if (age > life) continue;
        final k = age / life;
        canvas.drawCircle(
          base + Offset(math.cos(ang) * sp * age * h / 30, math.sin(ang) * sp * age * h / 30 + 0.00035 * age * age),
          r * (1 - k * 0.5),
          _fill(ink, a: 0.55 * (1 - k)),
        );
      }
    }
    // a flash on the frame it lands
    if (t >= at && t < at + 35) {
      final c = base - Offset(0, 0.1 * h);
      canvas.drawCircle(c, h * 0.55, Paint()
        ..shader = ui.Gradient.radial(c, h * 0.55, [
          Colors.white.withValues(alpha: 0.75 * (1 - _seg(t, at, at + 35))),
          _glint.withValues(alpha: 0.75 * (1 - _seg(t, at, at + 35))),
          _glint.withValues(alpha: 0),
        ], [0, 0.35, 1]));
    }
  }

  // headband tails: each piece trails where the knot was a moment before
  List<Offset> _tails(double tt, bool second) {
    const n = 7, lag = 15.0;
    final l = 0.085 * g.h;
    Offset knotAt(double x) => _s(math.max(0.0, x)).knot;
    final pts = [knotAt(tt)];
    final k1 = knotAt(tt - lag);
    final amp = 0.12 + math.min(0.32, (pts[0] - k1).distance / lag / g.h * 10);
    for (var i = 1; i < n; i++) {
      final k = knotAt(tt - i * lag);
      final prev = pts[i - 1];
      final raw = Offset(k.dx + i * l * 0.95, k.dy + i * l * (second ? 0.30 : 0.16));
      final th = math.atan2(raw.dy - prev.dy, raw.dx - prev.dx) +
          math.sin(tt * 0.02 + i * 0.95 + (second ? 1.7 : 0)) * amp * 0.9 * (0.4 + i / n);
      pts.add(prev + Offset(math.cos(th), math.sin(th)) * l);
    }
    return pts;
  }

  _Sk? _figure(Canvas canvas, double tt, double alpha, {bool plain = false}) {
    final p = _p(tt);
    final a = alpha * p.op;
    if (a <= 0.003) return null;
    final sk = _s(tt);
    final h = g.h, s = g.sword;
    final lw = math.max(2.4, h * 0.105);
    if (!plain) {
      for (final second in [true, false]) {
        final pts = _tails(tt, second);
        for (var i = 1; i < pts.length; i++) {
          canvas.drawLine(pts[i - 1], pts[i], _line(_band, math.max(1.2, h * 0.06) * (1 - i / (pts.length + 2)), a: a));
        }
      }
    }
    void limb(List<Offset> pts, double al) {
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (final q in pts.skip(1)) {
        path.lineTo(q.dx, q.dy);
      }
      canvas.drawPath(path, _line(ink, lw, a: al));
    }

    // the far side, a touch lighter
    limb([sk.hip, sk.kneeB, sk.footB], a * 0.72);
    limb([sk.sh, sk.elbowB, sk.handB], a * 0.72);
    // the scabbard, with the sword in it before the draw
    canvas.drawLine(sk.mouth, sk.scabEnd, _line(_saya, math.max(2.0, h * 0.07), a: a));
    if (tt < VibeSamurai.draw) {
      canvas.drawLine(sk.mouth, sk.pommel, _line(_hilt, math.max(2.6, s * 0.085), a: a));
      final along = sk.pommel - sk.mouth;
      final n = Offset(-along.dy, along.dx) / math.max(1e-6, along.distance) * (s * 0.035);
      for (var i = 0; i < 3; i++) {
        final c = Offset.lerp(sk.mouth, sk.pommel, (i + 0.6) / 3.4)!;
        canvas.drawLine(c - n, c + n, _line(_wrap, 1.1, a: a)..strokeCap = StrokeCap.butt);
      }
      canvas.drawCircle(sk.mouth, math.max(2.2, s * 0.05), _fill(_guard, a: a));
    }
    // a curved back
    canvas.drawPath(
      Path()
        ..moveTo(sk.hip.dx, sk.hip.dy)
        ..quadraticBezierTo(sk.ctrl.dx, sk.ctrl.dy, sk.neck.dx, sk.neck.dy),
      _line(ink, lw, a: a),
    );
    limb([sk.hip, sk.kneeF, sk.footF], a);
    canvas.drawCircle(sk.head, sk.headR, _fill(ink, a: a));
    final hat = Path()
      ..moveTo(sk.hat[0].dx, sk.hat[0].dy)
      ..lineTo(sk.hat[1].dx, sk.hat[1].dy)
      ..lineTo(sk.hat[2].dx, sk.hat[2].dy)
      ..close();
    if (!plain) {
      canvas.drawLine(sk.band[0], sk.band[1], _line(_band, math.max(1.8, h * 0.06), a: a));
      canvas.drawPath(hat, _fill(_straw, a: a));
      canvas.drawPath(hat, _line(ink, 1.2, a: 0.7 * a));
    } else {
      canvas.drawPath(hat, _fill(ink, a: a));
    }
    // the sword in his hands
    if (tt >= VibeSamurai.draw && tt < VibeSamurai.impact) {
      final origin = sk.sword(g).$1;
      canvas.save();
      canvas.translate(origin.dx, origin.dy);
      canvas.rotate(math.atan2(-sk.dir.dx, sk.dir.dy) + 0.22);
      paintPlantedSword(canvas, s, ink, opacity: a, grass: 0);
      canvas.restore();
    }
    limb([sk.sh, sk.elbowF, sk.handF], a);
    return sk;
  }

  @override
  bool shouldRepaint(VibeSamuraiPainter old) =>
      old.t != t || old.bubble != bubble || old.row != row || old.ink != ink || old.dark != dark;
}

// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' show Distance, LatLng;
import 'package:maplibre/maplibre.dart' as ml;
import 'package:url_launcher/url_launcher_string.dart';

import 'package:vibe/config/setting_keys.dart';
import 'package:vibe/utils/platform_infos.dart';

/// The map's look: OpenFreeMap's styles (OpenStreetMap drawn by the phone's
/// graphics chip), light or dark with the app. No key, nothing to sign up.
abstract class VibeMapStyle {
  static const _base = 'https://tiles.openfreemap.org/styles/';
  static const _light = ['${_base}liberty', '${_base}positron', '${_base}bright'];
  static const _dark = ['${_base}dark', '${_base}liberty'];

  /// When OpenFreeMap can't be reached: OpenStreetMap's own pictures.
  static const backup =
      '{"version":8,"sources":{"osm":{"type":"raster","tiles":'
      '["https://tile.openstreetmap.org/{z}/{x}/{y}.png"],"tileSize":256,'
      '"maxzoom":19,"attribution":"© OpenStreetMap contributors"}},'
      '"layers":[{"id":"osm","type":"raster","source":"osm"}]}';

  /// Which look (the layers button moves to the next one).
  static int pick = 0;

  static String of(BuildContext context) {
    final list = Theme.of(context).brightness == Brightness.dark
        ? _dark
        : _light;
    return list[pick % list.length];
  }
}

/// Metres between two places.
double vibeMeters(LatLng a, LatLng b) => const Distance().distance(a, b);

/// "350 m", "2.4 km", "18 km".
String vibeDistance(double m) => m < 1000
    ? '${(m / 10).round() * 10} m'
    : m < 10000
    ? '${(m / 1000).toStringAsFixed(1)} km'
    : '${(m / 1000).round()} km';

/// Something on the map at a place: a picture, a pin, your dot.
@immutable
class VibeMapMark {
  final String id;
  final LatLng at;
  final Widget child;
  final Size size;

  /// Which point of [child] sits on [at] (bottom centre for pins).
  final Alignment anchor;

  /// A soft circle this many metres round [at]: how accurate it is.
  final double? meters;
  final Color? halo;

  /// Which way they're heading (degrees from north): a soft beam.
  final double? heading;

  const VibeMapMark({
    required this.id,
    required this.at,
    required this.child,
    this.size = const Size(44, 44),
    this.anchor = Alignment.center,
    this.meters,
    this.halo,
    this.heading,
  });
}

/// A line on the map: a route, someone's trail, the way from you.
@immutable
class VibeMapLine {
  final List<LatLng> points;
  final Color color;
  final int width;
  final bool dotted;
  const VibeMapLine(
    this.points, {
    required this.color,
    this.width = 4,
    this.dotted = true,
  });
}

/// The map. Smooth pinch, pan, turn and tilt; pictures for people; a
/// shimmer while it loads; another map server if the first can't be
/// reached. Places you've looked at stay saved on the phone.
class VibeMap extends StatefulWidget {
  final LatLng center;
  final double zoom;
  final double pitch;
  final bool interactive;
  final List<VibeMapMark> marks;
  final List<VibeMapLine> lines;

  /// The map stopped moving: what's in the middle now.
  final ValueChanged<LatLng>? onIdle;

  /// You started moving the map with your finger.
  final VoidCallback? onDrag;

  /// Keeps the map credit clear of panels on top of the map.
  final EdgeInsets padding;

  const VibeMap({
    required this.center,
    this.zoom = 15.5,
    this.pitch = 0,
    this.interactive = true,
    this.marks = const [],
    this.lines = const [],
    this.onIdle,
    this.onDrag,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  /// Phones (and the web) draw the map; elsewhere a plain stand-in.
  static bool get supported => kIsWeb || PlatformInfos.isMobile;

  @override
  State<VibeMap> createState() => VibeMapState();
}

class VibeMapState extends State<VibeMap> {
  ml.MapController? _c;
  bool _ready = false;
  bool _backup = false;
  String? _style;
  Timer? _fallback;

  bool get _still => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  static ml.Geographic _g(LatLng p) =>
      ml.Geographic(lon: p.longitude, lat: p.latitude);

  /// What's in the middle of the map now.
  LatLng? get center {
    try {
      final c = _c?.camera?.center;
      return c == null ? null : LatLng(c.lat, c.lon);
    } catch (_) {
      return null;
    }
  }

  double get pitch => _c?.camera?.pitch ?? widget.pitch;

  /// Glides to [to]; jumps when the phone asks for less motion.
  Future<void> glide(
    LatLng to, {
    double? zoom,
    double? pitch,
    double? bearing,
  }) async {
    final c = _c;
    if (c == null) return;
    try {
      if (_still) {
        await c.moveCamera(
          center: _g(to),
          zoom: zoom,
          pitch: pitch,
          bearing: bearing,
        );
      } else {
        await c.animateCamera(
          center: _g(to),
          zoom: zoom,
          pitch: pitch,
          bearing: bearing,
          nativeDuration: const Duration(milliseconds: 900),
        );
      }
    } catch (_) {}
  }

  /// Tilts the map (3D) or flattens it.
  Future<void> tilt(double pitch) async {
    final c = _c;
    if (c == null) return;
    try {
      await c.animateCamera(
        pitch: pitch,
        nativeDuration: Duration(milliseconds: _still ? 1 : 700),
      );
    } catch (_) {}
  }

  /// Everything in [points] on screen at once.
  Future<void> fit(
    List<LatLng> points, {
    EdgeInsets padding = const EdgeInsets.fromLTRB(64, 120, 64, 64),
  }) async {
    final c = _c;
    if (c == null || points.isEmpty) return;
    final far = points.any((p) => vibeMeters(p, points.first) > 60);
    if (!far) return glide(points.first, zoom: 16);
    try {
      await c.fitBounds(
        bounds: ml.LngLatBounds.fromPoints(points.map(_g).toList()),
        padding: padding,
        nativeDuration: Duration(milliseconds: _still ? 1 : 900),
      );
    } catch (_) {}
  }

  /// The next look (streets, light, bright).
  void nextStyle() {
    VibeMapStyle.pick++;
    final s = VibeMapStyle.of(context);
    _style = s;
    _backup = false;
    try {
      _c?.setStyle(s);
    } catch (_) {}
    setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // light and dark follow the app
    final s = VibeMapStyle.of(context);
    if (_style != null && s != _style && !_backup) {
      try {
        _c?.setStyle(s);
      } catch (_) {}
    }
    _style = s;
  }

  @override
  void dispose() {
    _fallback?.cancel();
    super.dispose();
  }

  void _useBackup() {
    if (!mounted || _backup) return;
    setState(() => _backup = true);
    try {
      _c?.setStyle(VibeMapStyle.backup);
    } catch (_) {}
  }

  void _onEvent(ml.MapEvent e) {
    switch (e) {
      case ml.MapEventIdle():
        if (!_ready && mounted) setState(() => _ready = true);
      case ml.MapEventStartMoveCamera(:final reason):
        if (reason == ml.CameraChangeReason.apiGesture) widget.onDrag?.call();
      case ml.MapEventCameraIdle():
        final c = center;
        if (c != null) widget.onIdle?.call(c);
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget map;
    if (!VibeMap.supported) {
      map = _Plain(marks: widget.marks);
    } else {
      map = ml.MapLibreMap(
        options: ml.MapOptions(
          initStyle: _style ?? VibeMapStyle.of(context),
          initCenter: _g(widget.center),
          initZoom: widget.zoom,
          initPitch: widget.pitch,
          maxPitch: 60,
          gestures: widget.interactive
              ? const ml.MapGestures.all()
              : const ml.MapGestures.none(),
        ),
        // inside a sheet or a list the map keeps your finger
        gestureRecognizers: widget.interactive
            ? {
                Factory<OneSequenceGestureRecognizer>(
                  EagerGestureRecognizer.new,
                ),
              }
            : null,
        onMapCreated: (c) {
          _c = c;
          _fallback = Timer(const Duration(seconds: 8), _useBackup);
        },
        onStyleLoaded: (_) {
          _fallback?.cancel();
          Future.delayed(const Duration(milliseconds: 900), () {
            if (mounted && !_ready) setState(() => _ready = true);
          });
        },
        onEvent: _onEvent,
        layers: [
          for (final l in widget.lines)
            if (l.points.length > 1)
              ml.PolylineLayer(
                polylines: [
                  ml.Feature(
                    geometry: ml.LineString.from(l.points.map(_g).toList()),
                  ),
                ],
                color: l.color,
                width: l.width,
                dashArray: l.dotted ? const [1, 2] : null,
              ),
        ],
        children: [_Marks(widget.marks)],
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.interactive ? map : IgnorePointer(child: map),
        IgnorePointer(
          child: AnimatedOpacity(
            opacity: _ready || !VibeMap.supported ? 0 : 1,
            duration: const Duration(milliseconds: 400),
            child: const VibeMapShimmer(),
          ),
        ),
        Positioned(
          left: 8 + widget.padding.left,
          bottom: 6 + widget.padding.bottom,
          child: _Credit(backup: _backup, small: !widget.interactive),
        ),
      ],
    );
  }
}

/// Pictures and dots placed on the map; they glide between updates
/// instead of jumping.
class _Marks extends StatefulWidget {
  final List<VibeMapMark> marks;
  const _Marks(this.marks);

  @override
  State<_Marks> createState() => _MarksState();
}

class _MarksState extends State<_Marks> with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
    value: 1,
  );
  final _from = <String, LatLng>{};
  final _to = <String, LatLng>{};

  LatLng _now(String id) {
    final a = _from[id], b = _to[id];
    if (a == null || b == null) return b ?? a ?? const LatLng(0, 0);
    final v = Curves.easeInOutCubic.transform(_t.value);
    return LatLng(
      a.latitude + (b.latitude - a.latitude) * v,
      a.longitude + (b.longitude - a.longitude) * v,
    );
  }

  @override
  void initState() {
    super.initState();
    for (final m in widget.marks) {
      _to[m.id] = m.at;
    }
  }

  @override
  void didUpdateWidget(_Marks old) {
    super.didUpdateWidget(old);
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final cur = {for (final id in _to.keys) id: _now(id)};
    var moved = false;
    for (final m in widget.marks) {
      final was = cur[m.id];
      if (was == null || still) {
        _from.remove(m.id);
      } else {
        _from[m.id] = was;
        if (_to[m.id] != m.at) moved = true;
      }
      _to[m.id] = m.at;
    }
    if (moved) _t.forward(from: 0);
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _t,
    builder: (context, _) {
      final c = ml.MapController.maybeOf(context);
      final cam = ml.MapCamera.maybeOf(context);
      final marks = widget.marks;
      if (c == null || cam == null || marks.isEmpty) {
        return const SizedBox.shrink();
      }
      final at = [for (final m in marks) _now(m.id)];
      List<Offset> px;
      var mpp = 0.0;
      try {
        px = c.toScreenLocations([
          for (final p in at) ml.Geographic(lon: p.longitude, lat: p.latitude),
        ]);
        if (marks.any((m) => m.meters != null)) {
          mpp = c.getMetersPerPixelAtLatitude(at.first.latitude);
        }
      } catch (_) {
        return const SizedBox.shrink();
      }
      final cs = Theme.of(context).colorScheme;
      return IgnorePointer(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (var i = 0; i < marks.length; i++)
              if (marks[i].meters != null && mpp > 0)
                _place(
                  px[i],
                  Size.square(
                    2 * (marks[i].meters! / mpp).clamp(14.0, 700.0),
                  ),
                  Alignment.center,
                  _Halo(key: ValueKey('h${marks[i].id}'), color: marks[i].halo ?? cs.primary),
                ),
            for (var i = 0; i < marks.length; i++)
              if (marks[i].heading != null)
                _place(
                  px[i],
                  const Size.square(110),
                  Alignment.center,
                  Transform.rotate(
                    angle: (marks[i].heading! - cam.bearing) * math.pi / 180,
                    child: CustomPaint(
                      painter: _Beam(marks[i].halo ?? cs.primary),
                    ),
                  ),
                ),
            for (var i = 0; i < marks.length; i++)
              _place(
                px[i],
                marks[i].size,
                marks[i].anchor,
                KeyedSubtree(
                  key: ValueKey('m${marks[i].id}'),
                  child: marks[i].child,
                ),
              ),
          ],
        ),
      );
    },
  );

  Widget _place(Offset p, Size s, Alignment a, Widget child) => Positioned(
    left: p.dx - s.width * (a.x + 1) / 2,
    top: p.dy - s.height * (a.y + 1) / 2,
    width: s.width,
    height: s.height,
    child: child,
  );
}

/// How accurate a place is: a soft circle that breathes.
class _Halo extends StatefulWidget {
  final Color color;
  const _Halo({required this.color, super.key});

  @override
  State<_Halo> createState() => _HaloState();
}

class _HaloState extends State<_Halo> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, _) => DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: widget.color.withValues(alpha: 0.10 + 0.07 * _c.value),
        border: Border.all(
          color: widget.color.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
    ),
  );
}

/// The way someone is heading: a soft beam out of their picture.
class _Beam extends CustomPainter {
  final Color color;
  _Beam(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final rect = Rect.fromCircle(center: c, radius: r);
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [color.withValues(alpha: 0.45), color.withValues(alpha: 0)],
      ).createShader(rect);
    // 70° wide, pointing up (north before turning)
    canvas.drawArc(rect, -math.pi / 2 - 0.61, 1.22, true, paint);
  }

  @override
  bool shouldRepaint(_Beam old) => old.color != color;
}

/// The map's credit, small in a corner. Tap for the details.
class _Credit extends StatelessWidget {
  final bool backup;
  final bool small;
  const _Credit({required this.backup, required this.small});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = backup
        ? '© OpenStreetMap'
        : small
        ? '© OpenFreeMap © OSM'
        : '© OpenFreeMap  © OpenMapTiles  © OpenStreetMap';
    return GestureDetector(
      onTap: small
          ? null
          : () => launchUrlString(
              'https://www.openstreetmap.org/copyright',
              mode: LaunchMode.externalApplication,
            ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: cs.surface.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          text,
          style: TextStyle(fontSize: small ? 8.5 : 9.5, color: cs.onSurfaceVariant),
        ),
      ),
    );
  }
}

/// While the map loads: its colours with a soft light passing over.
class VibeMapShimmer extends StatefulWidget {
  const VibeMapShimmer({super.key});

  @override
  State<VibeMapShimmer> createState() => _VibeMapShimmerState();
}

class _VibeMapShimmerState extends State<VibeMapShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = cs.surfaceContainerHigh;
    final light = Color.lerp(base, cs.surface, 0.6)!;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment(-1.6 + 3.2 * _c.value, -0.4),
            end: Alignment(-0.6 + 3.2 * _c.value, 0.4),
            colors: [base, light, base],
          ),
        ),
        child: CustomPaint(painter: _Streets(cs.outlineVariant)),
      ),
    );
  }
}

/// A few faint streets, so loading already looks like a map.
class _Streets extends CustomPainter {
  final Color color;
  _Streets(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawLine(
        Offset(0, size.height * 0.38),
        Offset(size.width, size.height * 0.30),
        p,
      )
      ..drawLine(
        Offset(size.width * 0.3, 0),
        Offset(size.width * 0.26, size.height),
        p,
      );
    p.strokeWidth = 3;
    canvas
      ..drawLine(
        Offset(0, size.height * 0.75),
        Offset(size.width, size.height * 0.62),
        p,
      )
      ..drawLine(
        Offset(size.width * 0.72, 0),
        Offset(size.width * 0.8, size.height),
        p,
      );
  }

  @override
  bool shouldRepaint(_Streets old) => old.color != color;
}

/// Where the map can't be drawn (computers): the loading look with the
/// first mark in the middle.
class _Plain extends StatelessWidget {
  final List<VibeMapMark> marks;
  const _Plain({required this.marks});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final m = marks.firstOrNull;
    return ColoredBox(
      color: cs.surfaceContainerHigh,
      child: CustomPaint(
        painter: _Streets(cs.outlineVariant),
        child: m == null
            ? const SizedBox.expand()
            : Center(
                child: SizedBox.fromSize(size: m.size, child: m.child),
              ),
      ),
    );
  }
}

/// Their picture as a pin: round, a white edge, a point underneath and a
/// little shadow on the ground. [lift] raises it (while you drag the map).
class VibePicturePin extends StatelessWidget {
  final Widget picture;
  final double size;
  final double lift;
  final Color? ring;
  const VibePicturePin({
    required this.picture,
    this.size = 40,
    this.lift = 0,
    this.ring,
    super.key,
  });

  /// The room it takes on the map; it stands on its bottom centre.
  static Size box(double size) => Size(size + 16, size + 30);

  @override
  Widget build(BuildContext context) {
    final edge = ring ?? Colors.white;
    return SizedBox.fromSize(
      size: box(size),
      child: Stack(
        alignment: Alignment.bottomCenter,
        clipBehavior: Clip.none,
        children: [
          // its shadow on the ground, smaller as it lifts
          Positioned(
            bottom: 0,
            child: Container(
              width: 16 - 6 * lift,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.28 - 0.12 * lift),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          Positioned(
            bottom: 2 + 12 * lift,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: size + 6,
                  height: size + 6,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: edge,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25 + 0.1 * lift),
                        blurRadius: 8 + 8 * lift,
                        offset: Offset(0, 3 + 5 * lift),
                      ),
                    ],
                  ),
                  child: ClipOval(child: picture),
                ),
                CustomPaint(
                  size: const Size(12, 8),
                  painter: _Point(edge),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Point extends CustomPainter {
  final Color color;
  _Point(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_Point old) => old.color != color;
}

/// You, on the map: a dot in the theme colour with a white edge.
class VibeMeDot extends StatelessWidget {
  const VibeMeDot({super.key});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primary,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 3),
      boxShadow: const [
        BoxShadow(color: Color(0x40000000), blurRadius: 6, offset: Offset(0, 2)),
      ],
    ),
  );
}

/// Someone sharing live: their picture with a ring that shrinks as their
/// time runs out.
class VibeLivePicture extends StatelessWidget {
  final Widget picture;
  final double left;
  final Color color;
  final double size;
  const VibeLivePicture({
    required this.picture,
    required this.left,
    required this.color,
    this.size = 40,
    super.key,
  });

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size + 8,
    child: CustomPaint(
      painter: _Ring(left.clamp(0.0, 1.0), color),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Color(0x40000000),
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          ),
          padding: const EdgeInsets.all(2),
          child: ClipOval(child: picture),
        ),
      ),
    ),
  );
}

class _Ring extends CustomPainter {
  final double left;
  final Color color;
  _Ring(this.left, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(1.5);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, p..color = Colors.white);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * left,
      false,
      p..color = color,
    );
  }

  @override
  bool shouldRepaint(_Ring old) => old.left != left || old.color != color;
}

/// A round button over the map.
class VibeMapButton extends StatelessWidget {
  final IconData icon;
  final String tip;
  final VoidCallback onTap;
  final double size;
  const VibeMapButton({
    required this.icon,
    required this.tip,
    required this.onTap,
    this.size = 46,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerLowest,
      shape: const CircleBorder(),
      elevation: 3,
      shadowColor: Colors.black38,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Tooltip(
          message: tip,
          child: SizedBox.square(
            dimension: size,
            child: Icon(icon, size: 22, color: cs.onSurface),
          ),
        ),
      ),
    );
  }
}

/// Street names for a spot, from Photon (OpenStreetMap's place search).
/// Only when you've turned it on, since it sends the spot to
/// photon.komoot.io.
abstract class VibePlaces {
  static bool get on => AppSettings.vibeMapNames.value;
  static final _cache = <String, (String, String)?>{};

  static Future<(String, String)?> lookup(LatLng p) async {
    if (!on) return null;
    final key =
        '${p.latitude.toStringAsFixed(4)},${p.longitude.toStringAsFixed(4)}';
    if (_cache.containsKey(key)) return _cache[key];
    try {
      final r = await http
          .get(
            Uri.https('photon.komoot.io', '/reverse', {
              'lat': '${p.latitude}',
              'lon': '${p.longitude}',
              'limit': '1',
            }),
            headers: const {'User-Agent': 'Keepr'},
          )
          .timeout(const Duration(seconds: 6));
      if (r.statusCode != 200) return null;
      final f = ((jsonDecode(r.body) as Map)['features'] as List?)?.firstOrNull;
      final pr = f is Map ? f['properties'] : null;
      if (pr is! Map) return _cache[key] = null;
      String? s(String k) {
        final v = pr[k];
        return v is String && v.trim().isNotEmpty ? v.trim() : null;
      }

      final street = [s('street'), s('housenumber')].nonNulls.join(' ');
      final name = s('name') ?? (street.isEmpty ? null : street);
      if (name == null) return _cache[key] = null;
      final area = <String>{
        if (s('name') != null && street.isNotEmpty) street,
        ?(s('district') ?? s('locality')),
        ?s('city'),
      }.where((x) => x != name).take(2).join(', ');
      return _cache[key] = (name, area);
    } catch (_) {
      return null;
    }
  }
}

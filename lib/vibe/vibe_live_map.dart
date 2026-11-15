// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:matrix/matrix.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:vibe/l10n/l10n.dart';
import 'package:vibe/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:vibe/utils/string_color.dart';
import 'package:vibe/vibe/vibe_haptics.dart';
import 'package:vibe/vibe/vibe_live_location.dart';
import 'package:vibe/vibe/vibe_map.dart';
import 'package:vibe/vibe/vibe_pq.dart';
import 'package:vibe/widgets/avatar.dart';
import 'package:vibe/widgets/matrix.dart';

/// Someone sharing their live location, as the live map knows them.
class _Sharer {
  final String eventId;
  final User user;
  final int start;
  LatLng at;
  int until;
  int? ts;
  int? heading;
  int? kmh;
  double? acc;
  final List<LatLng> trail;

  _Sharer(
    this.eventId,
    this.user,
    this.start,
    this.at,
    this.until, {
    this.ts,
    this.heading,
    this.kmh,
    this.acc,
    List<LatLng>? trail,
  }) : trail = trail ?? [];

  static _Sharer? from(Event e, String id, List<LatLng> trail) {
    final geoUri = e.content.tryGet<String>('geo_uri');
    final at = VibeLive.parse(geoUri);
    final l = VibeLive.live(e);
    if (at == null || l == null) return null;
    return _Sharer(
      id,
      e.senderFromMemoryOrFallback,
      e.originServerTs.millisecondsSinceEpoch,
      at,
      l['ended'] == true ? 0 : (l.tryGet<int>('until') ?? 0),
      ts: l.tryGet<int>('ts'),
      heading: l.tryGet<int>('heading'),
      kmh: l.tryGet<int>('kmh'),
      acc: VibeLive.accuracy(geoUri),
      trail: trail,
    );
  }

  /// How much of their time is left, 0 to 1.
  double get left {
    final now = DateTime.now().millisecondsSinceEpoch;
    final all = until - start;
    return all <= 0 ? 0 : ((until - now) / all).clamp(0.0, 1.0);
  }

  String get mode => kmh == null
      ? ''
      : kmh! < 2
      ? 'still'
      : kmh! < 10
      ? 'walking'
      : 'driving';
}

/// Everyone sharing their live location in a chat, on one map: their
/// pictures with a ring for the time left, a beam for the way they're
/// heading and a trail; a list underneath. Pictures glide between updates.
class VibeLiveMap extends StatefulWidget {
  final Room room;
  final String focus;
  final LatLng at;
  final Event? event;
  final Timeline? timeline;
  const VibeLiveMap({
    required this.room,
    required this.focus,
    required this.at,
    this.event,
    this.timeline,
    super.key,
  });

  @override
  State<VibeLiveMap> createState() => _VibeLiveMapState();
}

class _VibeLiveMapState extends State<VibeLiveMap> {
  final _map = GlobalKey<VibeMapState>();
  final _people = <String, _Sharer>{};
  StreamSubscription<Event>? _sub;
  Timer? _tick;

  /// Whose updates the map follows (after you tap them in the list).
  String? _follow;

  @override
  void initState() {
    super.initState();
    _collect();
    if (_people.length == 1) _follow = widget.focus;
    _sub = widget.room.client.onTimelineEvent.stream.listen(_onEvent);
    _tick = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() {});
    });
    VibeLive.whereAmI();
    Future.delayed(const Duration(milliseconds: 900), _fitAll);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  void _collect() {
    final t = widget.timeline;
    if (t != null) {
      for (final e in t.events) {
        if (e.type != EventTypes.Message ||
            e.relationshipType == RelationshipTypes.edit) {
          continue;
        }
        final d = VibePq.open(e.getDisplayEvent(t));
        if (d.messageType != MessageTypes.Location) continue;
        if (!VibeLive.isLive(d) && e.eventId != widget.focus) continue;
        // where they've been: the first place and every update since
        final trail = <(int, LatLng)>[];
        final first = VibeLive.parse(
          VibePq.open(e).content.tryGet<String>('geo_uri'),
        );
        if (first != null) {
          trail.add((e.originServerTs.millisecondsSinceEpoch, first));
        }
        for (final edit in e.aggregatedEvents(t, RelationshipTypes.edit)) {
          final n = VibePq.open(
            edit,
          ).content.tryGetMap<String, Object?>('m.new_content');
          final p = VibeLive.parse(n?.tryGet<String>('geo_uri'));
          if (p != null) {
            trail.add((edit.originServerTs.millisecondsSinceEpoch, p));
          }
        }
        trail.sort((a, b) => a.$1.compareTo(b.$1));
        final s = _Sharer.from(d, e.eventId, [for (final x in trail) x.$2]);
        if (s == null) continue;
        if (s.trail.isNotEmpty && s.trail.last == s.at) s.trail.removeLast();
        _people[e.eventId] = s;
      }
    }
    final ev = widget.event;
    if (!_people.containsKey(widget.focus) && ev != null) {
      final s = _Sharer.from(ev, widget.focus, []);
      if (s != null) _people[widget.focus] = s;
    }
  }

  void _onEvent(Event raw) {
    if (raw.room.id != widget.room.id || !mounted) return;
    final e = VibePq.open(raw);
    final rel = e.relationshipEventId;
    if (e.relationshipType == RelationshipTypes.edit && rel != null) {
      final s = _people[rel];
      final n = e.content.tryGetMap<String, Object?>('m.new_content');
      if (s == null || n == null) return;
      final geoUri = n.tryGet<String>('geo_uri');
      final p = VibeLive.parse(geoUri);
      final l = n.tryGetMap<String, Object?>(VibeLive.liveKey);
      if (p == null || l == null) return;
      setState(() {
        if (vibeMeters(s.at, p) > 3) {
          s.trail.add(s.at);
          if (s.trail.length > 60) s.trail.removeAt(0);
        }
        s
          ..at = p
          ..ts = l.tryGet<int>('ts')
          ..heading = l.tryGet<int>('heading')
          ..kmh = l.tryGet<int>('kmh')
          ..acc = VibeLive.accuracy(geoUri)
          ..until = l['ended'] == true ? 0 : (l.tryGet<int>('until') ?? s.until);
      });
      if (_follow == rel) _map.currentState?.glide(p);
    } else if (rel == null && VibeLive.isLive(e)) {
      final s = _Sharer.from(e, e.eventId, []);
      if (s != null) setState(() => _people[e.eventId] = s);
    }
  }

  List<_Sharer> get _on {
    final now = DateTime.now().millisecondsSinceEpoch;
    // one row a person: their newest
    final by = <String, _Sharer>{};
    for (final s in _people.values) {
      if (s.until <= now) continue;
      final o = by[s.user.id];
      if (o == null || (s.ts ?? 0) > (o.ts ?? 0)) by[s.user.id] = s;
    }
    final me = widget.room.client.userID;
    return by.values.toList()..sort(
      (a, b) => (a.user.id == me ? 1 : 0).compareTo(b.user.id == me ? 1 : 0),
    );
  }

  void _fitAll() {
    if (!mounted) return;
    final me = VibeLive.me.value;
    _map.currentState?.fit(
      [for (final s in _on) s.at, ?me],
      padding: const EdgeInsets.fromLTRB(70, 150, 70, 70),
    );
  }

  Color _color(_Sharer s, ColorScheme cs) =>
      s.user.id == widget.room.client.userID
      ? cs.primary
      : s.user.calcDisplayname().colorScheme.primary;

  Widget _picture(_Sharer s, ColorScheme cs, {double size = 36}) =>
      VibeLivePicture(
        picture: Avatar(
          mxContent: s.user.avatarUrl,
          name: s.user.calcDisplayname(),
          size: size,
        ),
        left: s.left,
        color: _color(s, cs),
        size: size + 4,
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final on = _on;
    final myId = widget.room.client.userID;
    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      body: ValueListenableBuilder<LatLng?>(
        valueListenable: VibeLive.me,
        builder: (context, me, _) => Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: VibeMap(
                      key: _map,
                      center: widget.at,
                      zoom: 15,
                      padding: const EdgeInsets.only(bottom: 24),
                      onDrag: () => _follow = null,
                      lines: [
                        for (final s in on)
                          if (s.trail.isNotEmpty)
                            VibeMapLine(
                              [
                                ...s.trail.skip(math.max(0, s.trail.length - 30)),
                                s.at,
                              ],
                              color: _color(s, cs).withValues(alpha: 0.85),
                              width: 3,
                            ),
                      ],
                      marks: [
                        if (me != null)
                          VibeMapMark(
                            id: 'me',
                            at: me,
                            size: const Size.square(20),
                            meters: (VibeLive.meAccuracy ?? 0.0).clamp(0.0, 200.0),
                            child: const VibeMeDot(),
                          ),
                        for (final s in on)
                          VibeMapMark(
                            id: s.eventId,
                            at: s.at,
                            heading: s.heading?.toDouble(),
                            meters: s.acc?.clamp(0, 150).toDouble(),
                            halo: _color(s, cs),
                            size: const Size.square(48),
                            child: _picture(s, cs),
                          ),
                      ],
                    ),
                  ),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 36),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              VibeMapButton(
                                icon: Icons.arrow_back,
                                tip: 'Back',
                                onTap: () => Navigator.of(context).pop(),
                              ),
                              const SizedBox(width: 10),
                              VibeMapPill(
                                leading: const VibeLiveDot(),
                                text: 'Live · ${on.length} sharing',
                              ),
                            ],
                          ),
                          const Spacer(),
                          Align(
                            alignment: Alignment.centerRight,
                            child: VibeMapButton(
                              icon: Icons.fit_screen_rounded,
                              tip: 'Fit everyone',
                              onTap: () {
                                _follow = null;
                                _fitAll();
                              },
                            ),
                          ),
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerRight,
                            child: VibeMapButton(
                              icon: Icons.my_location_rounded,
                              tip: 'Find me',
                              onTap: () {
                                _follow = null;
                                if (me != null) {
                                  _map.currentState?.glide(me, zoom: 16);
                                } else {
                                  VibeLive.whereAmI();
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Transform.translate(
              offset: const Offset(0, -24),
              child: Container(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLowest,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),
                ),
                padding: EdgeInsets.fromLTRB(
                  14,
                  10,
                  14,
                  MediaQuery.paddingOf(context).bottom - 8,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const VibeSheetHandle(),
                    const SizedBox(height: 8),
                    if (on.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(18),
                        child: Text(
                          'No one is sharing right now',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      ),
                    for (final s in on) _row(context, s, me, s.user.id == myId),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, _Sharer s, LatLng? me, bool mine) {
    final cs = Theme.of(context).colorScheme;
    final sub = mine
        ? 'Sharing · ${VibeLive.left(s.until)} left'
        : [
            if (me != null) vibeDistance(vibeMeters(me, s.at)),
            if (s.mode.isNotEmpty) s.mode,
            'updated ${VibeLive.ago(s.ts)}',
          ].join(' · ');
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () {
        VibeHaptics.selection();
        _follow = s.eventId;
        _map.currentState?.glide(s.at, zoom: 16);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
        child: Row(
          children: [
            _picture(s, cs, size: 38),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mine ? 'You' : s.user.calcDisplayname(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                  Text(
                    sub,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (mine && VibeLive.sharing(s.eventId)) ...[
              ActionChip(
                avatar: const Icon(Icons.add_rounded, size: 18),
                label: const Text('30 min'),
                shape: const StadiumBorder(),
                onPressed: () {
                  VibeHaptics.light();
                  VibeLive.extendLive(s.eventId, const Duration(minutes: 30));
                },
              ),
              const SizedBox(width: 6),
              VibeStopButton(
                onTap: () => VibeLive.stopLive(widget.room.id, s.eventId),
              ),
            ] else if (!mine)
              IconButton.filledTonal(
                tooltip: 'Directions',
                onPressed: () => launchUrlString(
                  'https://www.google.com/maps/dir/?api=1&destination=${s.at.latitude},${s.at.longitude}',
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.directions_rounded),
              ),
          ],
        ),
      ),
    );
  }
}

/// Your check-in, full screen: the way there, how far and how long, who is
/// told, +15 min and I'm here. Then a happy "You're home".
class VibeCheckInView extends StatefulWidget {
  final String eventId;
  const VibeCheckInView({required this.eventId, super.key});

  static Future<void> open(BuildContext context, String eventId) {
    VibeHaptics.light();
    return Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => VibeCheckInView(eventId: eventId)),
    );
  }

  @override
  State<VibeCheckInView> createState() => _VibeCheckInViewState();
}

class _VibeCheckInViewState extends State<VibeCheckInView> {
  final _map = GlobalKey<VibeMapState>();
  VibeLiveSession? _s;
  Timer? _tick;

  /// When it finished well (arrived or you said you're OK).
  DateTime? _done;

  @override
  void initState() {
    super.initState();
    _s = VibeLive.session(widget.eventId);
    VibeLive.arrived.addListener(_onArrived);
    VibeLive.whereAmI();
    _tick = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
    Future.delayed(const Duration(milliseconds: 900), _fit);
  }

  @override
  void dispose() {
    VibeLive.arrived.removeListener(_onArrived);
    _tick?.cancel();
    super.dispose();
  }

  void _onArrived() {
    if (VibeLive.arrived.value == widget.eventId && mounted) {
      setState(() => _done = DateTime.now());
    }
  }

  void _fit() {
    final s = _s;
    if (!mounted || s == null) return;
    _map.currentState?.fit(
      [?s.place, ?VibeLive.me.value],
      padding: const EdgeInsets.fromLTRB(70, 140, 70, 70),
    );
  }

  Future<void> _here() async {
    VibeHaptics.medium();
    await VibeLive.arrive(widget.eventId);
    if (mounted) setState(() => _done = DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = _s;
    if (s == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('This check-in is over')),
      );
    }
    final room = Matrix.of(context).client.getRoomById(s.roomId);
    final chat = room?.getLocalizedDisplayname(MatrixLocals(L10n.of(context)));
    final dm = room?.isDirectChat ?? false;
    final them = dm ? (chat ?? 'They') : 'Everyone in ${chat ?? 'the chat'}';
    final they = dm ? them : 'they';
    if (_done != null) return _arrived(context, s, them);
    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      body: ValueListenableBuilder<LatLng?>(
        valueListenable: VibeLive.me,
        builder: (context, me, _) {
          final now = DateTime.now().millisecondsSinceEpoch;
          final dest = s.place;
          final late = now > s.until;
          final dist = me != null && dest != null ? vibeMeters(me, dest) : null;
          final speed = VibeLive.meSpeed;
          final eta = dist != null && speed != null && speed > 0.8
              ? (dist / speed / 60).ceil()
              : null;
          final progress = dest != null && dist != null && (s.d0 ?? 0) > 0
              ? (1 - dist / s.d0!).clamp(0.0, 1.0)
              : ((now - s.t0) / math.max(1, s.until - s.t0)).clamp(0.0, 1.0);
          final title = late
              ? 'Check-in is late'
              : dest != null
              ? 'Checking in to ${s.name ?? 'the place'}'
              : 'Check-in at ${VibeLive.time(s.until)}';
          final sub = dest != null
              ? [
                  if (eta != null) 'About $eta min',
                  if (dist != null) '${vibeDistance(dist)} to go',
                  if (dist == null) 'by ${VibeLive.time(s.until)}',
                ].join(' · ')
              : late
              ? 'Due at ${VibeLive.time(s.until)}'
              : '${VibeLive.left(s.until)} left';
          final info = dest != null
              ? '$them ${dm ? 'is' : 'are'} told when you arrive. If you '
                    "don't by ${VibeLive.time(s.until)}, $they get${dm ? 's' : ''} "
                    'your live location for an hour.'
              : "If you don't check in by ${VibeLive.time(s.until)}, $they "
                    'get${dm ? 's' : ''} your live location for an hour.';
          const green = Color(0xFF2E9E5B);
          return Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: VibeMap(
                        key: _map,
                        center: me ?? dest ?? const LatLng(20, 0),
                        zoom: me == null && dest == null ? 2 : 15,
                        padding: const EdgeInsets.only(bottom: 24),
                        lines: [
                          if (me != null && dest != null)
                            VibeMapLine([me, dest], color: cs.primary, width: 4),
                        ],
                        marks: [
                          if (dest != null)
                            VibeMapMark(
                              id: 'dest',
                              at: dest,
                              meters: VibeLive.arriveMeters,
                              halo: green,
                              size: const Size.square(48),
                              child: _Place(
                                icon: (s.name ?? '').toLowerCase() == 'home'
                                    ? Icons.home_rounded
                                    : Icons.flag_rounded,
                              ),
                            ),
                          if (me != null)
                            VibeMapMark(
                              id: 'me',
                              at: me,
                              size: const Size.square(50),
                              child: VibeLivePicture(
                                picture: _MyPicture(room: room),
                                left: progress,
                                color: cs.primary,
                                size: 42,
                              ),
                            ),
                        ],
                      ),
                    ),
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: VibeMapButton(
                          icon: Icons.arrow_back,
                          tip: 'Back',
                          onTap: () => Navigator.of(context).pop(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Transform.translate(
                offset: const Offset(0, -24),
                child: Container(
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLowest,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                  ),
                  padding: EdgeInsets.fromLTRB(
                    18,
                    10,
                    18,
                    MediaQuery.paddingOf(context).bottom - 8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const VibeSheetHandle(),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: (late ? cs.error : green).withValues(
                                alpha: 0.14,
                              ),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              late ? Icons.priority_high_rounded : Icons.flag_rounded,
                              color: late ? cs.error : green,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    color: cs.onSurface,
                                  ),
                                ),
                                Text(
                                  sub,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(end: progress),
                          duration: const Duration(milliseconds: 600),
                          builder: (context, v, _) => LinearProgressIndicator(
                            value: v,
                            minHeight: 8,
                            color: late ? cs.error : cs.primary,
                            backgroundColor: cs.surfaceContainerHigh,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox.square(
                            dimension: 22,
                            child: ClipOval(
                              child: Avatar(
                                mxContent: room?.avatar,
                                name: chat,
                                size: 22,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              info,
                              style: TextStyle(
                                fontSize: 13.5,
                                height: 1.35,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: FilledButton.tonalIcon(
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(0, 54),
                                shape: const StadiumBorder(),
                              ),
                              onPressed: () {
                                VibeHaptics.light();
                                VibeLive.extend(
                                  widget.eventId,
                                  const Duration(minutes: 15),
                                ).then((_) {
                                  if (mounted) setState(() {});
                                });
                              },
                              icon: const Icon(Icons.schedule_rounded),
                              label: const Text('+15 min'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 3,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(0, 54),
                                shape: const StadiumBorder(),
                              ),
                              onPressed: _here,
                              icon: const Icon(Icons.check_circle_rounded),
                              label: Text(
                                dest == null || late ? "I'm OK" : "I'm here",
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _arrived(BuildContext context, VibeLiveSession s, String them) {
    final cs = Theme.of(context).colorScheme;
    final at = s.place ?? VibeLive.me.value;
    final name = s.name;
    final title = s.place == null
        ? 'Glad you\'re OK'
        : (name ?? '').toLowerCase() == 'home'
        ? "You're home"
        : name == null
        ? "You've arrived"
        : "You're at $name";
    final dm = them.startsWith('Everyone') == false;
    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      body: Stack(
        children: [
          Positioned.fill(
            child: at == null
                ? const VibeMapShimmer()
                : VibeMap(
                    center: at,
                    zoom: 15.5,
                    interactive: false,
                    marks: [
                      VibeMapMark(
                        id: 'done',
                        at: at,
                        size: const Size.square(170),
                        child: const _ArrivedBadge(),
                      ),
                    ],
                  ),
          ),
          const Positioned.fill(child: IgnorePointer(child: _Confetti())),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16 + MediaQuery.paddingOf(context).bottom,
            child: Material(
              color: cs.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(28),
              elevation: 4,
              shadowColor: Colors.black26,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$them ${dm ? 'was' : 'were'} told at '
                      '${VibeLive.time(_done!.millisecondsSinceEpoch)}.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.35,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        shape: const StadiumBorder(),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.check_circle_rounded, size: 18),
                      label: const Text('Done'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Your own picture.
class _MyPicture extends StatelessWidget {
  final Room? room;
  const _MyPicture({required this.room});

  @override
  Widget build(BuildContext context) {
    final client = Matrix.of(context).client;
    final me = room?.unsafeGetUserFromMemoryOrFallback(client.userID!);
    return Avatar(
      mxContent: me?.avatarUrl,
      name: me?.calcDisplayname() ?? client.userID,
      size: 38,
    );
  }
}

/// The place you're checking in to: a green round mark.
class _Place extends StatelessWidget {
  final IconData icon;
  const _Place({required this.icon});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: const Color(0xFF2E9E5B),
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 3),
      boxShadow: const [
        BoxShadow(color: Color(0x40000000), blurRadius: 8, offset: Offset(0, 3)),
      ],
    ),
    child: Icon(icon, color: Colors.white, size: 22),
  );
}

/// A big green tick that pops in, with a soft ring round it.
class _ArrivedBadge extends StatelessWidget {
  const _ArrivedBadge();

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: still ? 1 : 0, end: 1),
      duration: const Duration(milliseconds: 900),
      curve: Curves.elasticOut,
      builder: (context, v, child) => Transform.scale(scale: v, child: child),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF2E9E5B).withValues(alpha: 0.14),
        ),
        alignment: Alignment.center,
        child: Container(
          width: 112,
          height: 112,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF2E9E5B).withValues(alpha: 0.18),
          ),
          alignment: Alignment.center,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFF2E9E5B),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 4),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x40000000),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(Icons.check_rounded, color: Colors.white, size: 40),
          ),
        ),
      ),
    );
  }
}

/// A short burst of confetti from the middle (none with reduce motion).
class _Confetti extends StatefulWidget {
  const _Confetti();

  @override
  State<_Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<_Confetti>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );
  final _bits = List.generate(46, (i) {
    final r = math.Random(i * 7 + 3);
    return (
      angle: -math.pi / 2 + (r.nextDouble() - 0.5) * math.pi * 1.5,
      speed: 260 + r.nextDouble() * 320,
      spin: (r.nextDouble() - 0.5) * 14,
      kind: r.nextInt(5),
      w: 5 + r.nextDouble() * 6,
    );
  });

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!(MediaQuery.maybeDisableAnimationsOf(context) ?? false) &&
        !_c.isAnimating &&
        _c.value == 0) {
      _c.forward();
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
    final colors = [
      cs.primary,
      cs.tertiary,
      const Color(0xFF2E9E5B),
      const Color(0xFFF2994A),
      const Color(0xFFE5484D),
    ];
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => CustomPaint(
        painter: _ConfettiPainter(_c.value, _bits, colors),
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  final double t;
  final List<({double angle, double speed, double spin, int kind, double w})>
  bits;
  final List<Color> colors;
  _ConfettiPainter(this.t, this.bits, this.colors);

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    final o = Offset(size.width / 2, size.height * 0.42);
    final p = Paint();
    final secs = t * 2.6;
    for (final b in bits) {
      final x = o.dx + math.cos(b.angle) * b.speed * secs * 0.6;
      final y = o.dy + math.sin(b.angle) * b.speed * secs * 0.6 +
          0.5 * 520 * secs * secs * 0.5;
      p.color = colors[b.kind].withValues(alpha: (1 - t).clamp(0.0, 1.0));
      canvas
        ..save()
        ..translate(x, y)
        ..rotate(b.spin * secs);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: b.w, height: b.w * 0.45),
          const Radius.circular(1.5),
        ),
        p,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}

/// On the home screen while you share your live location or have a
/// check-in on: who with, how long is left, and Stop.
class VibeLiveBar extends StatelessWidget {
  const VibeLiveBar({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: VibeLive.changed,
    builder: (context, _, _) {
      if (VibeLive.mine.isEmpty) return const SizedBox.shrink();
      return StreamBuilder<void>(
        stream: Stream<void>.periodic(const Duration(seconds: 30)),
        builder: (context, _) {
          final now = DateTime.now().millisecondsSinceEpoch;
          final mine = VibeLive.mine.where((s) => s.until > now || s.kind != 'live');
          final live = mine.where((s) => s.kind == 'live').toList();
          final s = live.firstOrNull ?? mine.firstOrNull;
          if (s == null) return const SizedBox.shrink();
          final cs = Theme.of(context).colorScheme;
          final room = Matrix.of(context).client.getRoomById(s.roomId);
          final name =
              room?.getLocalizedDisplayname(MatrixLocals(L10n.of(context))) ??
              'a chat';
          final isLive = s.kind == 'live';
          final text = !isLive
              ? 'Checking in to ${s.name ?? name}'
              : live.length > 1
              ? 'Sharing live in ${live.length} chats'
              : 'Sharing live with $name';
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Material(
              color: cs.primaryContainer.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(22),
              child: InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: () => isLive
                    ? context.go('/rooms/${s.roomId}')
                    : VibeCheckInView.open(context, s.eventId),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
                  child: Row(
                    children: [
                      const VibeLiveDot(),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: cs.onPrimaryContainer,
                          ),
                        ),
                      ),
                      Text(
                        '  · ${VibeLive.left(s.until)}',
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onPrimaryContainer.withValues(alpha: 0.75),
                        ),
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: cs.onPrimaryContainer,
                          foregroundColor: cs.primaryContainer,
                          shape: const StadiumBorder(),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () {
                          VibeHaptics.medium();
                          if (isLive) {
                            for (final l in live) {
                              VibeLive.stopLive(l.roomId, l.eventId);
                            }
                          } else {
                            VibeLive.arrive(s.eventId);
                          }
                        },
                        icon: Icon(
                          isLive ? Icons.stop_rounded : Icons.check_rounded,
                          size: 16,
                        ),
                        label: Text(isLive ? 'Stop' : "I'm here"),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

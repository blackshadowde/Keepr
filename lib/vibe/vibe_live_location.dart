// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:matrix/matrix.dart';
import 'package:vibe/config/setting_keys.dart';
import 'package:vibe/utils/platform_infos.dart';
import 'package:vibe/utils/url_launcher.dart';
import 'package:vibe/vibe/screens/chat/events/map_bubble.dart';
import 'package:vibe/vibe/vibe_haptics.dart';

/// Live location and check-in.
///
/// Live location is a normal location message that is edited with your new
/// position as you move, until the time you picked; then it says it ended.
/// Check-in is a card: "I'll let you know when I reach this place" or "…in
/// 30 minutes". Reach the place and it says you arrived. Don't, and the app
/// asks if you're OK; no answer within 10 minutes and the chat gets your
/// live location for an hour, with a missed check-in message.
abstract class VibeLive {
  static const liveKey = 'chat.keepr.live';
  static const checkKey = 'chat.keepr.checkin';
  static const _store = 'chat.keepr.live_sessions';

  /// How close counts as arrived.
  static const arriveMeters = 150.0;
  static const grace = Duration(minutes: 10);

  static Map<String, Object?>? live(Event e) =>
      e.content.tryGetMap<String, Object?>(liveKey);
  static Map<String, Object?>? checkIn(Event e) =>
      e.content.tryGetMap<String, Object?>(checkKey);

  /// Live and not over yet.
  static bool isLive(Event e) {
    final l = live(e);
    if (l == null || l['ended'] == true) return false;
    final until = l.tryGet<int>('until') ?? 0;
    return DateTime.now().millisecondsSinceEpoch < until;
  }

  static String time(int ms) =>
      DateFormat.jm().format(DateTime.fromMillisecondsSinceEpoch(ms));

  static String geo(double lat, double lon, [double? acc]) =>
      'geo:$lat,$lon${acc == null ? '' : ';u=${acc.round()}'}';

  static LatLng? parse(String? uri) {
    final u = Uri.tryParse(uri ?? '');
    if (u == null || u.scheme != 'geo') return null;
    final p = u.path.split(';').first.split(',').map(double.tryParse).toList();
    if (p.length < 2 || p[0] == null || p[1] == null) return null;
    return LatLng(p[0]!, p[1]!);
  }

  static String _osm(double lat, double lon) =>
      'https://www.openstreetmap.org/?mlat=$lat&mlon=$lon#map=16/$lat/$lon';

  // ---- sessions (kept across restarts) ----

  static final List<_Session> _sessions = [];
  static Client? _client;
  static Timer? _tick;
  static StreamSubscription<Position>? _gps;
  static Position? _last;
  static final _lastSent = <String, (int, Position)>{};

  /// Changes whenever sessions start or stop (cards update).
  static final changed = ValueNotifier<int>(0);

  static bool sharing(String eventId) =>
      _sessions.any((s) => s.eventId == eventId);

  static void start(Client client) {
    _client = client;
    _sessions
      ..clear()
      ..addAll(
        (AppSettings.store.getStringList(_store) ?? const [])
            .map((s) => _Session.fromJson(jsonDecode(s)))
            .whereType<_Session>(),
      );
    _sync();
  }

  static Future<void> _save() async {
    await AppSettings.store.setStringList(
      _store,
      _sessions.map((s) => jsonEncode(s.toJson())).toList(),
    );
    changed.value++;
    _sync();
  }

  /// GPS and the clock run only while something needs them.
  static void _sync() {
    if (_sessions.isEmpty) {
      _tick?.cancel();
      _tick = null;
      _gps?.cancel();
      _gps = null;
      return;
    }
    _tick ??= Timer.periodic(const Duration(seconds: 15), (_) => _check());
    if (_gps != null) return;
    final kinds = _sessions.map((s) => s.kind).toSet();
    final text = kinds.contains('live')
        ? 'Sharing your live location'
        : 'Check-in is on';
    final LocationSettings settings = PlatformInfos.isAndroid
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10,
            intervalDuration: const Duration(seconds: 10),
            foregroundNotificationConfig: ForegroundNotificationConfig(
              notificationTitle: 'Keepr',
              notificationText: text,
              enableWakeLock: true,
              setOngoing: true,
            ),
          )
        : const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10,
          );
    _gps = Geolocator.getPositionStream(locationSettings: settings).listen(
      _onPosition,
      onError: (_) {
        _gps = null;
      },
    );
  }

  static Future<void> _onPosition(Position p) async {
    _last = p;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final s in List.of(_sessions)) {
      if (s.kind == 'live') {
        final prev = _lastSent[s.eventId];
        final moved = prev == null
            ? 1e9
            : Geolocator.distanceBetween(
                prev.$2.latitude,
                prev.$2.longitude,
                p.latitude,
                p.longitude,
              );
        // a new position every 15 s while moving, every minute when not
        if (prev != null &&
            !(now - prev.$1 >= 15000 && moved > 15) &&
            now - prev.$1 < 60000) {
          continue;
        }
        _lastSent[s.eventId] = (now, p);
        await _editLive(s, p, ended: false);
      } else if (s.kind == 'arrive' && s.lat != null && s.lon != null) {
        final d = Geolocator.distanceBetween(
          p.latitude,
          p.longitude,
          s.lat!,
          s.lon!,
        );
        if (d <= arriveMeters) await _finishCheckIn(s, 'arrived');
      }
    }
  }

  static Future<void> _check() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final s in List.of(_sessions)) {
      if (s.kind == 'live') {
        if (now >= s.until) await stopLive(s.roomId, s.eventId);
        continue;
      }
      if (now < s.until) continue;
      if (s.asked == null) {
        s.asked = now;
        await _save();
        await _askOk(s);
      } else if (now >= s.asked! + grace.inMilliseconds) {
        await _missed(s);
      }
    }
  }

  static Room? _room(String id) => _client?.getRoomById(id);

  static Future<void> _edit(
    Room room,
    String eventId,
    Map<String, Object?> content,
  ) => room.sendEvent({
    ...content,
    'body': '* ${content['body']}',
    'm.new_content': content,
    'm.relates_to': {'rel_type': 'm.replace', 'event_id': eventId},
  });

  // ---- live location ----

  static Map<String, Object?> _liveContent(
    Position p,
    int until, {
    bool ended = false,
    String? note,
  }) => {
    'msgtype': MessageTypes.Location,
    'body':
        '${note ?? (ended ? 'Live location ended' : 'Live location until ${time(until)}')}: '
        '${_osm(p.latitude, p.longitude)}',
    'geo_uri': geo(p.latitude, p.longitude, p.accuracy),
    liveKey: {
      'until': until,
      'ended': ended,
      'ts': DateTime.now().millisecondsSinceEpoch,
      'note': ?note,
    },
  };

  static Future<Position?> _here() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return null;
    }
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
    } catch (_) {
      return _last ?? await Geolocator.getLastKnownPosition();
    }
  }

  /// Starts sharing your live location in [room] until [until].
  static Future<bool> startLive(
    Room room,
    DateTime until, {
    String? note,
  }) async {
    final p = await _here();
    if (p == null) return false;
    final ms = until.millisecondsSinceEpoch;
    final id = await room.sendEvent(_liveContent(p, ms, note: note));
    if (id == null) return false;
    _lastSent[id] = (DateTime.now().millisecondsSinceEpoch, p);
    _sessions.add(_Session('live', room.id, id, ms));
    await _save();
    return true;
  }

  static Future<void> _editLive(
    _Session s,
    Position p, {
    required bool ended,
  }) async {
    final room = _room(s.roomId);
    if (room == null) return;
    try {
      await _edit(room, s.eventId, _liveContent(p, s.until, ended: ended));
    } catch (_) {}
  }

  static Future<void> stopLive(String roomId, String eventId) async {
    final s = _sessions.where((s) => s.eventId == eventId).firstOrNull;
    _sessions.removeWhere((s) => s.eventId == eventId);
    await _save();
    final p = _last ?? _lastSent[eventId]?.$2;
    _lastSent.remove(eventId);
    if (s != null && p != null) await _editLive(s, p, ended: true);
  }

  // ---- check-in ----

  static Map<String, Object?> _checkContent(
    _Session s,
    String state, {
    Position? at,
  }) {
    final by = time(s.until);
    final what = s.kind == 'arrive'
        ? "I'll check in when I get to ${s.name ?? 'the place'} (by $by)"
        : "I'll check in at $by";
    final body = switch (state) {
      'arrived' => 'Arrived at ${s.name ?? 'the place'}',
      'ended' => 'Check-in ended',
      'missed' => 'Missed check-in: no answer since $by',
      _ => 'Check-in: $what',
    };
    return {
      'msgtype': MessageTypes.Text,
      'body': body,
      checkKey: {
        'kind': s.kind,
        'state': state,
        'until': s.until,
        if (s.lat != null) 'place': geo(s.lat!, s.lon!),
        'name': ?s.name,
        if (at != null) 'at': geo(at.latitude, at.longitude, at.accuracy),
        'ts': DateTime.now().millisecondsSinceEpoch,
      },
    };
  }

  /// Starts a check-in in [room]: arrive at [place] by [until], or (no
  /// place) check in at [until].
  static Future<bool> startCheckIn(
    Room room,
    DateTime until, {
    LatLng? place,
    String? name,
  }) async {
    final p = await _here();
    if (p == null) return false;
    final s = _Session(
      place == null ? 'timer' : 'arrive',
      room.id,
      '',
      until.millisecondsSinceEpoch,
      lat: place?.latitude,
      lon: place?.longitude,
      name: name,
    );
    final id = await room.sendEvent(_checkContent(s, 'on'));
    if (id == null) return false;
    s.eventId = id;
    _sessions.add(s);
    await _save();
    return true;
  }

  static _Session? _find(String eventId) =>
      _sessions.where((s) => s.eventId == eventId).firstOrNull;

  /// More time for a check-in.
  static Future<void> extend(String eventId, Duration more) async {
    final s = _find(eventId);
    if (s == null) return;
    final base = DateTime.now().millisecondsSinceEpoch > s.until
        ? DateTime.now().millisecondsSinceEpoch
        : s.until;
    s.until = base + more.inMilliseconds;
    s.asked = null;
    await _save();
    final room = _room(s.roomId);
    if (room != null) await _edit(room, s.eventId, _checkContent(s, 'on'));
  }

  /// "I'm OK" / end: closes the check-in.
  static Future<void> endCheckIn(String eventId) async {
    final s = _find(eventId);
    if (s == null) return;
    await _finishCheckIn(s, 'ended');
  }

  static Future<void> _finishCheckIn(_Session s, String state) async {
    _sessions.remove(s);
    await _save();
    final room = _room(s.roomId);
    if (room == null) return;
    try {
      await _edit(room, s.eventId, _checkContent(s, state, at: _last));
    } catch (_) {}
    if (state == 'arrived') VibeHaptics.medium();
  }

  static Future<void> _missed(_Session s) async {
    await _finishCheckIn(s, 'missed');
    final room = _room(s.roomId);
    if (room == null) return;
    await startLive(
      room,
      DateTime.now().add(const Duration(hours: 1)),
      note: 'Missed check-in, sharing live location for an hour',
    );
  }

  static Future<void> _askOk(_Session s) async {
    try {
      await FlutterLocalNotificationsPlugin().show(
        id: s.eventId.hashCode,
        title: 'Check-in',
        body: s.kind == 'arrive'
            ? "You haven't reached ${s.name ?? 'the place'} yet. Are you OK? "
                  'Open the chat to add time or end it.'
            : 'Time to check in. Are you OK? Open the chat to end it or add '
                  'time.',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'keepr_checkin',
            'Check-in',
            importance: Importance.max,
            priority: Priority.max,
            category: AndroidNotificationCategory.alarm,
          ),
        ),
      );
    } catch (_) {}
  }
}

class _Session {
  final String kind; // live, arrive, timer
  final String roomId;
  String eventId;
  int until;
  final double? lat, lon;
  final String? name;

  /// When we asked if you're OK.
  int? asked;
  _Session(
    this.kind,
    this.roomId,
    this.eventId,
    this.until, {
    this.lat,
    this.lon,
    this.name,
    this.asked,
  });

  Map<String, Object?> toJson() => {
    'kind': kind,
    'room': roomId,
    'event': eventId,
    'until': until,
    'lat': lat,
    'lon': lon,
    'name': name,
    'asked': asked,
  };

  static _Session? fromJson(Object? j) {
    if (j is! Map) return null;
    try {
      return _Session(
        j['kind'] as String,
        j['room'] as String,
        j['event'] as String,
        j['until'] as int,
        lat: (j['lat'] as num?)?.toDouble(),
        lon: (j['lon'] as num?)?.toDouble(),
        name: j['name'] as String?,
        asked: j['asked'] as int?,
      );
    } catch (_) {
      return null;
    }
  }
}

/// A location in the chat: the map card, live or not. Tap opens the map.
class VibeLocationCard extends StatelessWidget {
  final Event event;
  final String eventId;
  const VibeLocationCard({
    required this.event,
    required this.eventId,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final at = VibeLive.parse(event.content.tryGet<String>('geo_uri'));
    if (at == null) return const SizedBox.shrink();
    final l = VibeLive.live(event);
    final own = event.senderId == event.room.client.userID;
    return ValueListenableBuilder<int>(
      valueListenable: VibeLive.changed,
      builder: (context, _, _) => StreamBuilder<void>(
        // "updated 2 min ago" and the end time keep themselves right
        stream: l == null
            ? null
            : Stream<void>.periodic(const Duration(seconds: 30)),
        builder: (context, _) {
          final live = VibeLive.isLive(event);
          final cs = Theme.of(context).colorScheme;
          String? sub;
          if (l != null) {
            final ts = l.tryGet<int>('ts');
            final ago = ts == null
                ? null
                : DateTime.now().difference(
                    DateTime.fromMillisecondsSinceEpoch(ts),
                  );
            final upd = ago == null
                ? ''
                : ago.inMinutes < 1
                ? ' · updated just now'
                : ' · updated ${ago.inMinutes} min ago';
            sub = live
                ? 'Until ${VibeLive.time(l.tryGet<int>('until') ?? 0)}$upd'
                : 'Ended';
          }
          return MapBubble(
            latitude: at.latitude,
            longitude: at.longitude,
            title: l == null
                ? 'Location'
                : l['note'] is String && live
                ? 'Missed check-in · live'
                : live
                ? 'Live location'
                : 'Live location ended',
            sub: sub,
            live: live,
            action: own && live && VibeLive.sharing(eventId)
                ? TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: cs.error,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () =>
                        VibeLive.stopLive(event.room.id, eventId),
                    child: const Text('Stop'),
                  )
                : null,
            onTap: () => VibeMapView.open(
              context,
              room: event.room,
              eventId: eventId,
              at: at,
              title: l == null ? 'Location' : 'Live location',
              live: live,
            ),
          );
        },
      ),
    );
  }
}

/// A check-in in the chat: what it's waiting for, then arrived / ended /
/// missed. The one who started it gets End and +30 min, and "I'm OK" once
/// the time is up.
class VibeCheckInCard extends StatelessWidget {
  final Event event;
  final String eventId;
  final Color color;
  final Color ink;
  const VibeCheckInCard({
    required this.event,
    required this.eventId,
    required this.color,
    required this.ink,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final c = VibeLive.checkIn(event)!;
    final cs = Theme.of(context).colorScheme;
    final own = event.senderId == event.room.client.userID;
    final state = c.tryGet<String>('state') ?? 'on';
    final until = c.tryGet<int>('until') ?? 0;
    final name = c.tryGet<String>('name') ?? 'the place';
    final place = VibeLive.parse(c.tryGet<String>('place'));
    final at = VibeLive.parse(c.tryGet<String>('at'));
    return ValueListenableBuilder<int>(
      valueListenable: VibeLive.changed,
      builder: (context, _, _) => StreamBuilder<void>(
        stream: state == 'on'
            ? Stream<void>.periodic(const Duration(seconds: 30))
            : null,
        builder: (context, _) {
          final late =
              state == 'on' && DateTime.now().millisecondsSinceEpoch > until;
          final mine = own && VibeLive._find(eventId) != null;
          final (IconData icon, String title, String sub, Color tint) =
              switch (state) {
                'arrived' => (
                  Icons.where_to_vote_rounded,
                  'Arrived',
                  'Got to $name',
                  const Color(0xFF34C759),
                ),
                'ended' => (
                  Icons.check_circle_rounded,
                  'Check-in ended',
                  'All good',
                  cs.primary,
                ),
                'missed' => (
                  Icons.warning_amber_rounded,
                  'Missed check-in',
                  'No answer since ${VibeLive.time(until)}',
                  cs.error,
                ),
                _ => (
                  Icons.shield_moon_outlined,
                  late ? 'Check-in is late' : 'Check-in',
                  c['kind'] == 'arrive'
                      ? 'Will check in on reaching $name by ${VibeLive.time(until)}'
                      : 'Will check in at ${VibeLive.time(until)}',
                  late ? cs.error : cs.primary,
                ),
              };
          final map = at ?? place;
          return ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 290),
            child: Material(
              color: color,
              borderRadius: BorderRadius.circular(22),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: map == null
                    ? null
                    : () => VibeMapView.open(
                        context,
                        room: event.room,
                        eventId: eventId,
                        at: map,
                        title: at != null ? 'Last location' : name,
                        live: false,
                      ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: tint,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(icon, color: Colors.white, size: 21),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w700,
                                    color: ink,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  sub,
                                  style: TextStyle(
                                    fontSize: 13,
                                    height: 1.3,
                                    color: ink.withValues(alpha: 0.75),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (mine) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: late ? cs.error : tint,
                                  foregroundColor: Colors.white,
                                  shape: const StadiumBorder(),
                                  minimumSize: const Size(0, 38),
                                ),
                                onPressed: () =>
                                    VibeLive.endCheckIn(eventId),
                                child: Text(late ? "I'm OK" : 'End'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: ink,
                                side: BorderSide(
                                  color: ink.withValues(alpha: 0.4),
                                ),
                                shape: const StadiumBorder(),
                                minimumSize: const Size(0, 38),
                              ),
                              onPressed: () => VibeLive.extend(
                                eventId,
                                const Duration(minutes: 30),
                              ),
                              child: const Text('+30 min'),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A place (or someone's live location) full screen on a map you can move,
/// zoom and turn; it follows live updates as they come in.
class VibeMapView extends StatefulWidget {
  final Room room;
  final String eventId;
  final LatLng at;
  final String title;
  final bool live;
  const VibeMapView({
    required this.room,
    required this.eventId,
    required this.at,
    required this.title,
    required this.live,
    super.key,
  });

  static Future<void> open(
    BuildContext context, {
    required Room room,
    required String eventId,
    required LatLng at,
    required String title,
    required bool live,
  }) {
    VibeHaptics.light();
    return Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => VibeMapView(
          room: room,
          eventId: eventId,
          at: at,
          title: title,
          live: live,
        ),
      ),
    );
  }

  @override
  State<VibeMapView> createState() => _VibeMapViewState();
}

class _VibeMapViewState extends State<VibeMapView> {
  final _map = MapController();
  late LatLng _at = widget.at;
  StreamSubscription<Event>? _sub;

  @override
  void initState() {
    super.initState();
    if (widget.live) {
      _sub = widget.room.client.onTimelineEvent.stream
          .where(
            (e) =>
                e.room.id == widget.room.id &&
                e.relationshipEventId == widget.eventId,
          )
          .listen((e) {
            final n = e.content.tryGetMap<String, Object?>('m.new_content');
            final p = VibeLive.parse(n?.tryGet<String>('geo_uri'));
            if (p == null || !mounted) return;
            setState(() => _at = p);
            try {
              _map.move(p, _map.camera.zoom);
            } catch (_) {}
          });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget round(IconData icon, String tip, VoidCallback onTap) => Material(
      color: cs.surfaceContainerHigh,
      shape: const CircleBorder(),
      elevation: 2,
      child: IconButton(tooltip: tip, icon: Icon(icon), onPressed: onTap),
    );
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: vibeMapTiles(
              context,
              map: FlutterMap(
                mapController: _map,
                options: MapOptions(initialCenter: _at, initialZoom: 16),
                children: [
                  vibeTileLayer(),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _at,
                        width: 40,
                        height: 60,
                        child: const VibeMapPin(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      round(
                        Icons.arrow_back,
                        'Back',
                        () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Material(
                          color: cs.surfaceContainerHigh,
                          shape: const StadiumBorder(),
                          elevation: 2,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (widget.live) ...[
                                  const _LiveDot(),
                                  const SizedBox(width: 8),
                                ],
                                Flexible(
                                  child: Text(
                                    widget.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: cs.onSurface,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      round(Icons.center_focus_strong_rounded, 'Back to it', () {
                        try {
                          _map.move(_at, 16);
                          _map.rotate(0);
                        } catch (_) {}
                      }),
                      const Spacer(),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          shape: const StadiumBorder(),
                          minimumSize: const Size(0, 48),
                        ),
                        onPressed: () => UrlLauncher(
                          context,
                          VibeLive.geo(_at.latitude, _at.longitude),
                        ).launchUrl(),
                        icon: const Icon(Icons.directions_rounded),
                        label: const Text('Open in maps'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A small dot that pulses: live.
class _LiveDot extends StatefulWidget {
  const _LiveDot();

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween(begin: 0.35, end: 1.0).animate(_c),
    child: Container(
      width: 9,
      height: 9,
      decoration: const BoxDecoration(
        color: Color(0xFF34C759),
        shape: BoxShape.circle,
      ),
    ),
  );
}

/// The live dot for other files (map card).
class VibeLiveDot extends StatelessWidget {
  const VibeLiveDot({super.key});

  @override
  Widget build(BuildContext context) => const _LiveDot();
}

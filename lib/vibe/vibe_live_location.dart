// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:matrix/matrix.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:vibe/config/setting_keys.dart';
import 'package:vibe/l10n/l10n.dart';
import 'package:vibe/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:vibe/utils/platform_infos.dart';
import 'package:vibe/utils/url_launcher.dart';
import 'package:vibe/utils/vibe_share.dart';
import 'package:vibe/vibe/buddy/bujji_live.dart';
import 'package:vibe/vibe/screens/chat/events/map_bubble.dart';
import 'package:vibe/vibe/vibe_haptics.dart';
import 'package:vibe/vibe/vibe_live_map.dart';
import 'package:vibe/vibe/vibe_map.dart';
import 'package:vibe/widgets/avatar.dart';

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

  /// How accurate a place is, in metres (geo:…;u=8).
  static double? accuracy(String? uri) {
    final m = RegExp(r';u=([0-9.]+)').firstMatch(uri ?? '');
    return m == null ? null : double.tryParse(m.group(1)!);
  }

  static const placeKey = 'chat.keepr.place';

  /// The place's name and area, when the sender looked them up.
  static (String, String)? place(Event e) {
    final p = e.content.tryGetMap<String, Object?>(placeKey);
    final n = p?.tryGet<String>('name');
    if (n == null || n.isEmpty) return null;
    return (n, p?.tryGet<String>('area') ?? '');
  }

  /// "42 min", "1 h 20 min".
  static String left(int until) {
    final m = ((until - DateTime.now().millisecondsSinceEpoch) / 60000)
        .ceil()
        .clamp(0, 100000);
    return m < 60 ? '$m min' : '${m ~/ 60} h${m % 60 == 0 ? '' : ' ${m % 60} min'}';
  }

  /// "just now", "20 s ago", "3 min ago".
  static String ago(int? ts) {
    if (ts == null) return '';
    final s = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(ts))
        .inSeconds;
    return s < 5
        ? 'just now'
        : s < 60
        ? '$s s ago'
        : s < 3600
        ? '${s ~/ 60} min ago'
        : 'at ${time(ts)}';
  }

  /// Sends a place: [at], how accurate, and its name when looked up.
  static Future<String?> sendPlace(
    Room room,
    LatLng at, {
    double? acc,
    (String, String)? name,
  }) => room.sendEvent({
    'msgtype': MessageTypes.Location,
    'body': '${name?.$1 ?? 'Location'}: ${_osm(at.latitude, at.longitude)}',
    'geo_uri': geo(at.latitude, at.longitude, acc),
    if (name != null)
      placeKey: {'name': name.$1, if (name.$2.isNotEmpty) 'area': name.$2},
  });

  // ---- where you are (for "2.4 km away"; never asks for permission) ----

  static final me = ValueNotifier<LatLng?>(null);
  static double? meAccuracy;
  static int _meAt = 0;

  static Future<void> whereAmI() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _meAt < 60000) return;
    _meAt = now;
    try {
      final perm = await Geolocator.checkPermission();
      if (perm != LocationPermission.always &&
          perm != LocationPermission.whileInUse) {
        return;
      }
      final last = _last ?? await Geolocator.getLastKnownPosition();
      if (last != null) _setMe(last);
      _setMe(
        await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 12),
          ),
        ),
      );
    } catch (_) {}
  }

  /// How fast you're going (metres a second), when moving.
  static double? meSpeed;

  static void _setMe(Position p) {
    meAccuracy = p.accuracy;
    meSpeed = p.speed > 0 ? p.speed : null;
    me.value = LatLng(p.latitude, p.longitude);
  }

  // ---- sessions (kept across restarts) ----

  static final List<VibeLiveSession> _sessions = [];
  static Client? _client;
  static Timer? _tick;
  static StreamSubscription<Position>? _gps;
  static Position? _last;
  static final _lastSent = <String, (int, Position)>{};

  /// Changes whenever sessions start or stop (cards update).
  static final changed = ValueNotifier<int>(0);

  static bool sharing(String eventId) =>
      _sessions.any((s) => s.eventId == eventId);

  /// Your live locations and check-ins that are on.
  static List<VibeLiveSession> get mine => List.unmodifiable(_sessions);

  static VibeLiveSession? session(String eventId) => _find(eventId);

  static void start(Client client) {
    _client = client;
    BujjiLive.watch(client);
    _sessions
      ..clear()
      ..addAll(
        (AppSettings.store.getStringList(_store) ?? const [])
            .map((s) => VibeLiveSession.fromJson(jsonDecode(s)))
            .whereType<VibeLiveSession>(),
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
      _ongoingText = '';
      // in case the sharing notification outlived the location service
      Future.delayed(const Duration(seconds: 2), () {
        if (_sessions.isEmpty && PlatformInfos.isAndroid) {
          FlutterLocalNotificationsPlugin().cancel(id: _ongoingId).ignore();
        }
      });
      return;
    }
    Future.delayed(const Duration(seconds: 2), _ongoing);
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
    _setMe(p);
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
        if (now >= s.until) {
          await stopLive(s.roomId, s.eventId);
          continue;
        }
        // Bujji: about to end, or on for a long time
        if (s.until - now <= 5 * 60000 && s.told.add('end')) {
          await _save();
          BujjiLive.liveEnding(s.roomId, s.eventId, s.until);
        }
        if (now - s.t0 >= 2 * 3600000 &&
            s.until - now > 30 * 60000 &&
            s.told.add('long')) {
          await _save();
          BujjiLive.liveLong(s.roomId, s.eventId, s.until);
        }
        continue;
      }
      if (now < s.until) {
        if (s.until - now <= 5 * 60000 && s.told.add('due')) {
          await _save();
          BujjiLive.checkInDue(
            s.roomId,
            s.eventId,
            s.name,
            s.until,
            arrive: s.kind == 'arrive',
          );
        }
        continue;
      }
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

  // ---- the sharing notification: Stop / +30 min / Open ----

  /// The location service's own notification, which this one updates.
  static const _ongoingId = 75415;
  static String _ongoingText = '';

  static Future<void> _ongoing() async {
    if (!PlatformInfos.isAndroid || _sessions.isEmpty) return;
    final s =
        _sessions.where((s) => s.kind == 'live').firstOrNull ??
        _sessions.first;
    final name = _room(s.roomId)?.getLocalizedDisplayname() ?? 'the chat';
    final live = s.kind == 'live';
    final title = live ? 'Sharing your live location' : 'Check-in is on';
    final body = live
        ? 'With $name · ${left(s.until)} left'
        : '${s.name ?? 'Check in'} by ${time(s.until)} · $name';
    if ('$title|$body' == _ongoingText) return;
    _ongoingText = '$title|$body';
    try {
      await FlutterLocalNotificationsPlugin().show(
        id: _ongoingId,
        title: title,
        body: body,
        payload: 'keepr-live|${s.roomId}|${s.eventId}',
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            'geolocator_channel_01',
            'Background Location',
            importance: Importance.low,
            priority: Priority.low,
            ongoing: true,
            autoCancel: false,
            onlyAlertOnce: true,
            silent: true,
            showWhen: false,
            actions: live
                ? const [
                    AndroidNotificationAction(
                      'live_stop',
                      'Stop',
                      showsUserInterface: true,
                      cancelNotification: false,
                    ),
                    AndroidNotificationAction(
                      'live_more',
                      '+30 min',
                      showsUserInterface: true,
                      cancelNotification: false,
                    ),
                    AndroidNotificationAction(
                      'live_open',
                      'Open',
                      showsUserInterface: true,
                      cancelNotification: false,
                    ),
                  ]
                : const [
                    AndroidNotificationAction(
                      'check_done',
                      "I'm here",
                      showsUserInterface: true,
                      cancelNotification: false,
                    ),
                    AndroidNotificationAction(
                      'check_more',
                      '+15 min',
                      showsUserInterface: true,
                      cancelNotification: false,
                    ),
                    AndroidNotificationAction(
                      'live_open',
                      'Open',
                      showsUserInterface: true,
                      cancelNotification: false,
                    ),
                  ],
          ),
        ),
      );
    } catch (_) {}
  }

  /// A tap on the sharing notification or one of its buttons. True when
  /// it was one of ours.
  static Future<bool> onNotification(
    NotificationResponse r,
    GoRouter? router,
  ) async {
    final parts = (r.payload ?? '').split('|');
    if (parts.length != 3 || parts.first != 'keepr-live') return false;
    final roomId = parts[1], eventId = parts[2];
    switch (r.actionId) {
      case 'live_stop':
        await stopLive(roomId, eventId);
      case 'live_more':
        await extendLive(eventId, const Duration(minutes: 30));
      case 'check_done':
        await arrive(eventId);
      case 'check_more':
        await extend(eventId, const Duration(minutes: 15));
      default:
        router?.go('/rooms/$roomId');
    }
    return true;
  }

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
      // whole numbers only: some servers refuse fractions in messages
      if (p.speed > 0.7 && p.heading >= 0) 'heading': p.heading.round(),
      if (p.speed >= 0) 'kmh': (p.speed * 3.6).round(),
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
    _sessions.add(VibeLiveSession('live', room.id, id, ms));
    await _save();
    return true;
  }

  /// More time for your live location.
  static Future<void> extendLive(String eventId, Duration more) async {
    final s = _find(eventId);
    if (s == null || s.kind != 'live') return;
    s.until += more.inMilliseconds;
    s.told.remove('end');
    await _save();
    _ongoing();
    final p = _last ?? _lastSent[eventId]?.$2;
    if (p != null) await _editLive(s, p, ended: false);
  }

  static Future<void> _editLive(
    VibeLiveSession s,
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
    VibeLiveSession s,
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
  static Future<String?> startCheckIn(
    Room room,
    DateTime until, {
    LatLng? place,
    String? name,
  }) async {
    final p = await _here();
    if (p == null) return null;
    final s = VibeLiveSession(
      place == null ? 'timer' : 'arrive',
      room.id,
      '',
      until.millisecondsSinceEpoch,
      lat: place?.latitude,
      lon: place?.longitude,
      name: name,
      d0: place == null
          ? null
          : Geolocator.distanceBetween(
              p.latitude,
              p.longitude,
              place.latitude,
              place.longitude,
            ).round(),
    );
    final id = await room.sendEvent(_checkContent(s, 'on'));
    if (id == null) return null;
    s.eventId = id;
    _sessions.add(s);
    await _save();
    return id;
  }

  static VibeLiveSession? _find(String eventId) =>
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
    s.told.remove('due');
    await _save();
    _ongoing();
    final room = _room(s.roomId);
    if (room != null) await _edit(room, s.eventId, _checkContent(s, 'on'));
  }

  /// "I'm OK" / end: closes the check-in.
  static Future<void> endCheckIn(String eventId) async {
    final s = _find(eventId);
    if (s == null) return;
    await _finishCheckIn(s, 'ended');
  }

  /// "I'm here": arrived (or, for a timer, all good).
  static Future<void> arrive(String eventId) async {
    final s = _find(eventId);
    if (s == null) return;
    await _finishCheckIn(s, s.kind == 'arrive' ? 'arrived' : 'ended');
  }

  /// Fires with the event id when one of your check-ins finishes on arrival.
  static final arrived = ValueNotifier<String?>(null);

  static Future<void> _finishCheckIn(VibeLiveSession s, String state) async {
    _sessions.remove(s);
    await _save();
    final room = _room(s.roomId);
    if (room == null) return;
    try {
      await _edit(room, s.eventId, _checkContent(s, state, at: _last));
    } catch (_) {}
    if (state == 'arrived') {
      VibeHaptics.medium();
      arrived.value = s.eventId;
    }
  }

  static Future<void> _missed(VibeLiveSession s) async {
    await _finishCheckIn(s, 'missed');
    final room = _room(s.roomId);
    if (room == null) return;
    await startLive(
      room,
      DateTime.now().add(const Duration(hours: 1)),
      note: 'Missed check-in, sharing live location for an hour',
    );
    final live = _sessions.where((x) => x.kind == 'live' && x.roomId == s.roomId).lastOrNull;
    if (live != null) BujjiLive.youMissed(s.roomId, live.eventId);
  }

  static Future<void> _askOk(VibeLiveSession s) async {
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

/// One of your live locations or check-ins.
class VibeLiveSession {
  final String kind; // live, arrive, timer
  final String roomId;
  String eventId;
  int until;
  final double? lat, lon;
  final String? name;

  /// When it started.
  final int t0;

  /// How far the place was when the check-in started, in metres.
  final int? d0;

  /// What Bujji already said about it.
  final Set<String> told;

  /// When we asked if you're OK.
  int? asked;
  VibeLiveSession(
    this.kind,
    this.roomId,
    this.eventId,
    this.until, {
    this.lat,
    this.lon,
    this.name,
    this.asked,
    this.d0,
    int? t0,
    Set<String>? told,
  }) : t0 = t0 ?? DateTime.now().millisecondsSinceEpoch,
       told = told ?? {};

  LatLng? get place => lat == null || lon == null ? null : LatLng(lat!, lon!);

  Map<String, Object?> toJson() => {
    'kind': kind,
    'room': roomId,
    'event': eventId,
    'until': until,
    'lat': lat,
    'lon': lon,
    'name': name,
    'asked': asked,
    'd0': d0,
    't0': t0,
    'told': told.toList(),
  };

  static VibeLiveSession? fromJson(Object? j) {
    if (j is! Map) return null;
    try {
      return VibeLiveSession(
        j['kind'] as String,
        j['room'] as String,
        j['event'] as String,
        j['until'] as int,
        lat: (j['lat'] as num?)?.toDouble(),
        lon: (j['lon'] as num?)?.toDouble(),
        name: j['name'] as String?,
        asked: j['asked'] as int?,
        d0: j['d0'] as int?,
        t0: j['t0'] as int?,
        told: {...(j['told'] as List? ?? const []).whereType<String>()},
      );
    } catch (_) {
      return null;
    }
  }
}

/// A location in the chat: a card the shape of a bubble with the sender's
/// picture as the pin, the place and how far it is. Live ones say how long
/// is left and when they last moved; yours has Stop. Tap opens the map.
class VibeLocationCard extends StatelessWidget {
  final Event event;
  final String eventId;
  final Timeline? timeline;
  const VibeLocationCard({
    required this.event,
    required this.eventId,
    this.timeline,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final geoUri = event.content.tryGet<String>('geo_uri');
    final at = VibeLive.parse(geoUri);
    if (at == null) return const SizedBox.shrink();
    final l = VibeLive.live(event);
    final own = event.senderId == event.room.client.userID;
    final acc = VibeLive.accuracy(geoUri) ?? 0;
    final rough = acc >= 500;
    final place = VibeLive.place(event);
    final sender = event.senderFromMemoryOrFallback;
    final who = sender.calcDisplayname();
    VibeLive.whereAmI();
    return ValueListenableBuilder<int>(
      valueListenable: VibeLive.changed,
      builder: (context, _, _) => ValueListenableBuilder<LatLng?>(
        valueListenable: VibeLive.me,
        builder: (context, me, _) => StreamBuilder<void>(
          // "updated 20 s ago" and the time left keep themselves right
          stream: l == null
              ? null
              : Stream<void>.periodic(const Duration(seconds: 10)),
          builder: (context, _) {
            final cs = Theme.of(context).colorScheme;
            final live = VibeLive.isLive(event);
            final far = me == null || own
                ? null
                : '${vibeDistance(vibeMeters(me, at))} away';
            final until = l?.tryGet<int>('until') ?? 0;
            final String title;
            final String sub;
            String? tag;
            if (l == null) {
              title = place?.$1 ?? (rough ? 'Around here' : 'Location');
              sub = [
                if (rough) 'within ${vibeDistance(acc)}',
                ?far,
                DateFormat.jm().format(event.originServerTs),
              ].join(' · ');
            } else if (live) {
              tag =
                  '${l['note'] is String ? 'Missed check-in' : 'Live'} · '
                  '${VibeLive.left(until)} left';
              title = own
                  ? 'Sharing live with ${event.room.getLocalizedDisplayname(MatrixLocals(L10n.of(context)))}'
                  : '$who is sharing live';
              sub = [
                'Updated ${VibeLive.ago(l.tryGet<int>('ts'))}',
                ?far,
              ].join(' · ');
            } else {
              title = 'Live location ended';
              sub = ['Last here ${VibeLive.ago(l.tryGet<int>('ts'))}', ?far]
                  .join(' · ');
            }
            return MapBubble(
              latitude: at.latitude,
              longitude: at.longitude,
              title: title,
              sub: sub,
              tag: tag,
              live: live,
              meters: rough ? acc : null,
              picture: Avatar(
                mxContent: sender.avatarUrl,
                name: who,
                size: 34,
              ),
              color: own ? cs.primaryContainer : null,
              ink: own ? cs.onPrimaryContainer : null,
              action: own && live && VibeLive.sharing(eventId)
                  ? VibeStopButton(
                      onTap: () => VibeLive.stopLive(event.room.id, eventId),
                    )
                  : null,
              onTap: () => VibeMapView.open(
                context,
                room: event.room,
                eventId: eventId,
                at: at,
                title: place?.$1 ?? (l == null ? 'Location' : 'Live location'),
                live: live,
                event: event,
                timeline: timeline,
              ),
            );
          },
        ),
      ),
    );
  }
}

/// "■ Stop", soft red.
class VibeStopButton extends StatelessWidget {
  final VoidCallback onTap;
  final String label;
  const VibeStopButton({required this.onTap, this.label = 'Stop', super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.errorContainer,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () {
          VibeHaptics.medium();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 14, 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.stop_rounded, size: 16, color: cs.error),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: cs.error,
                ),
              ),
            ],
          ),
        ),
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
                onTap: mine
                    ? () => VibeCheckInView.open(context, eventId)
                    : map == null
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

/// A shared place full screen: the map with a dotted line from you, how
/// far it is, and Google Maps, Waze and the coordinates underneath. Live
/// locations open the live map instead.
class VibeMapView extends StatefulWidget {
  final Room room;
  final String eventId;
  final LatLng at;
  final String title;
  final Event? event;
  const VibeMapView({
    required this.room,
    required this.eventId,
    required this.at,
    required this.title,
    this.event,
    super.key,
  });

  static Future<void> open(
    BuildContext context, {
    required Room room,
    required String eventId,
    required LatLng at,
    required String title,
    required bool live,
    Event? event,
    Timeline? timeline,
  }) {
    VibeHaptics.light();
    return Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => live
            ? VibeLiveMap(
                room: room,
                focus: eventId,
                at: at,
                event: event,
                timeline: timeline,
              )
            : VibeMapView(
                room: room,
                eventId: eventId,
                at: at,
                title: title,
                event: event,
              ),
      ),
    );
  }

  @override
  State<VibeMapView> createState() => _VibeMapViewState();
}

class _VibeMapViewState extends State<VibeMapView> {
  final _map = GlobalKey<VibeMapState>();

  @override
  void initState() {
    super.initState();
    VibeLive.whereAmI();
    Future.delayed(const Duration(milliseconds: 900), _fit);
  }

  void _fit() {
    if (!mounted) return;
    final me = VibeLive.me.value;
    _map.currentState?.fit(
      [widget.at, if (me != null && vibeMeters(me, widget.at) < 300000) me],
      padding: const EdgeInsets.fromLTRB(70, 160, 70, 90),
    );
  }

  void _open(String url) =>
      launchUrlString(url, mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final e = widget.event;
    final at = widget.at;
    final sender = e?.senderFromMemoryOrFallback;
    final who = sender?.calcDisplayname();
    final own = e != null && e.senderId == e.room.client.userID;
    final place = e == null ? null : VibeLive.place(e);
    final acc = VibeLive.accuracy(e?.content.tryGet<String>('geo_uri')) ?? 0;
    final rough = acc >= 500;
    final title = place?.$1 ?? (rough ? 'Around here' : widget.title);
    final sub = [
      if (place != null && place.$2.isNotEmpty) place.$2,
      if (rough) 'within ${vibeDistance(acc)}',
      if (e != null) 'sent ${DateFormat.jm().format(e.originServerTs)}',
    ].join(' · ');
    final ll = '${at.latitude.toStringAsFixed(4)}, ${at.longitude.toStringAsFixed(4)}';
    final picture = Avatar(
      mxContent: sender?.avatarUrl,
      name: who ?? title,
      size: 44,
    );
    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      body: ValueListenableBuilder<LatLng?>(
        valueListenable: VibeLive.me,
        builder: (context, me, _) {
          final d = me == null ? null : vibeMeters(me, at);
          return Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: VibeMap(
                        key: _map,
                        center: at,
                        zoom: rough ? 13 : 15.5,
                        padding: const EdgeInsets.only(bottom: 24),
                        lines: [
                          if (me != null && d! < 300000)
                            VibeMapLine([me, at], color: cs.primary, width: 3),
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
                          VibeMapMark(
                            id: 'place',
                            at: at,
                            meters: rough ? acc : null,
                            size: VibePicturePin.box(44),
                            anchor: Alignment.bottomCenter,
                            child: VibePicturePin(picture: picture, size: 44),
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
                                Flexible(
                                  child: VibeMapPill(
                                    leading: SizedBox.square(
                                      dimension: 28,
                                      child: ClipOval(
                                        child: Avatar(
                                          mxContent: sender?.avatarUrl,
                                          name: who ?? title,
                                          size: 28,
                                        ),
                                      ),
                                    ),
                                    text: own
                                        ? 'Your location'
                                        : who == null
                                        ? title
                                        : "$who's location",
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Align(
                              alignment: Alignment.centerRight,
                              child: VibeMapButton(
                                icon: Icons.layers_outlined,
                                tip: 'Map style',
                                onTap: () => _map.currentState?.nextStyle(),
                              ),
                            ),
                            const Spacer(),
                            Align(
                              alignment: Alignment.centerRight,
                              child: VibeMapButton(
                                icon: Icons.gps_fixed_rounded,
                                tip: 'Show both',
                                onTap: _fit,
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
                    18,
                    10,
                    18,
                    MediaQuery.paddingOf(context).bottom - 8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const VibeSheetHandle(),
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
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
                                if (sub.isNotEmpty)
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
                          if (d != null) ...[
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  vibeDistance(d),
                                  style: TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w800,
                                    color: cs.primary,
                                  ),
                                ),
                                Text(
                                  'from you',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            flex: 5,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(0, 52),
                                shape: const StadiumBorder(),
                              ),
                              onPressed: () => _open(
                                'https://www.google.com/maps/search/?api=1&query=${at.latitude},${at.longitude}',
                              ),
                              icon: const Icon(Icons.map_rounded),
                              label: const Text('Google Maps'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 4,
                            child: FilledButton.tonalIcon(
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(0, 52),
                                shape: const StadiumBorder(),
                              ),
                              onPressed: () => _open(
                                'https://waze.com/ul?ll=${at.latitude},${at.longitude}&navigate=yes',
                              ),
                              icon: const Icon(Icons.navigation_rounded),
                              label: const Text('Waze'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          IconButton.filledTonal(
                            tooltip: 'Copy coordinates',
                            style: IconButton.styleFrom(
                              minimumSize: const Size.square(52),
                              backgroundColor: cs.surfaceContainerHigh,
                            ),
                            onPressed: () => _copy(context, at),
                            icon: const Icon(Icons.copy_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ActionChip(
                            avatar: const Icon(Icons.directions_rounded, size: 18),
                            label: const Text('Directions'),
                            onPressed: () => UrlLauncher(
                              context,
                              VibeLive.geo(at.latitude, at.longitude),
                            ).launchUrl(),
                          ),
                          Builder(
                            builder: (context) => ActionChip(
                              avatar: const Icon(Icons.share_rounded, size: 18),
                              label: const Text('Share'),
                              onPressed: () => VibeShare.share(
                                '$title\nhttps://www.openstreetmap.org/?mlat=${at.latitude}&mlon=${at.longitude}#map=16/${at.latitude}/${at.longitude}',
                                context,
                              ),
                            ),
                          ),
                          ActionChip(
                            label: Text(ll),
                            onPressed: () => _copy(context, at),
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

  static void _copy(BuildContext context, LatLng at) {
    Clipboard.setData(ClipboardData(text: '${at.latitude}, ${at.longitude}'));
    VibeHaptics.light();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Coordinates copied')),
    );
  }
}

/// The small grabber on top of a panel.
class VibeSheetHandle extends StatelessWidget {
  const VibeSheetHandle({super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.outlineVariant,
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );
}

/// A rounded label over the map: a picture or dot, then the words.
class VibeMapPill extends StatelessWidget {
  final Widget? leading;
  final String text;
  const VibeMapPill({required this.text, this.leading, super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerLowest,
      shape: const StadiumBorder(),
      elevation: 3,
      shadowColor: Colors.black38,
      child: Padding(
        padding: EdgeInsets.fromLTRB(leading == null ? 18 : 8, 9, 18, 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 10)],
            Flexible(
              child: Text(
                text,
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
  Widget build(BuildContext context) {
    // still when the phone asks for less motion
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) _c.stop();
    return FadeTransition(
      opacity: Tween(begin: 0.35, end: 1.0).animate(_c),
      child: Container(
        width: 9,
        height: 9,
        decoration: const BoxDecoration(
          color: Color(0xFFE5484D),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

/// The live dot for other files (map card).
class VibeLiveDot extends StatelessWidget {
  const VibeLiveDot({super.key});

  @override
  Widget build(BuildContext context) => const _LiveDot();
}

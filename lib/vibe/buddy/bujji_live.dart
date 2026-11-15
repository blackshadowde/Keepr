// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:matrix/matrix.dart';

import 'package:vibe/utils/push_helper.dart';
import 'package:vibe/vibe/buddy/bujji.dart';
import 'package:vibe/vibe/buddy/vibe_buddy.dart';
import 'package:vibe/vibe/vibe_live_location.dart';
import 'package:vibe/vibe/vibe_map.dart';
import 'package:vibe/vibe/vibe_pq.dart';

/// Someone sharing their live location with you right now.
@immutable
class BujjiSharer {
  final String roomId;
  final String eventId;
  final String name;
  final int until;
  const BujjiSharer(this.roomId, this.eventId, this.name, this.until);
}

/// Bujji keeps an eye on live locations and check-ins, all on the phone:
/// who started or stopped sharing, who is close or a few minutes away,
/// check-ins that went well or were missed, and your own sharing running
/// out. It says so in its chat, above the typing bar of that chat, on the
/// home screen, and for what matters as a notification.
abstract class BujjiLive {
  static StreamSubscription<Event>? _sub;
  static Client? _client;

  /// Others sharing with you now (the home screen shows them).
  static final sharing = ValueNotifier<List<BujjiSharer>>(const []);

  static final _told = <String>{};

  /// Last distance to each sharer, to tell if they're coming closer.
  static final _near = <String, double>{};

  static void watch(Client client) {
    _client = client;
    _sub?.cancel();
    _sub = client.onTimelineEvent.stream.listen(_on);
  }

  static int get _now => DateTime.now().millisecondsSinceEpoch;

  static bool _once(String key) {
    if (_told.length > 2000) _told.clear();
    return _told.add(key);
  }

  static String _in(Room room) => room.isDirectChat
      ? ''
      : ' in ${room.getLocalizedDisplayname()}';

  static void _on(Event raw) {
    try {
      final c = _client;
      if (c == null || raw.senderId == c.userID) return;
      // only what just happened, not old messages caught up on later
      if (DateTime.now().difference(raw.originServerTs).inMinutes.abs() > 10) {
        return;
      }
      final e = VibePq.open(raw);
      final edit = e.relationshipType == RelationshipTypes.edit;
      final content = edit
          ? e.content.tryGetMap<String, Object?>('m.new_content')
          : e.content;
      final id = edit ? e.relationshipEventId : e.eventId;
      if (content == null || id == null) return;
      final who = e.senderFromMemoryOrFallback.calcDisplayname();
      final live = content.tryGetMap<String, Object?>(VibeLive.liveKey);
      final check = content.tryGetMap<String, Object?>(VibeLive.checkKey);
      if (live != null) _live(e.room, id, who, content, live, edit);
      if (check != null) _check(e.room, id, who, check, edit);
    } catch (_) {}
  }

  static void _live(
    Room room,
    String id,
    String who,
    Map<String, Object?> content,
    Map<String, Object?> l,
    bool edit,
  ) {
    final until = l.tryGet<int>('until') ?? 0;
    if (l['ended'] == true || until <= _now) {
      _drop(id);
      if (_told.contains('$id:start') && _once('$id:end')) {
        _say(room, id, '$who stopped sharing live location${_in(room)}.');
      }
      return;
    }
    _keep(BujjiSharer(room.id, id, who, until));
    if (!edit && _once('$id:start')) {
      final missed = l['note'] is String;
      _say(
        room,
        id,
        missed
            ? "$who missed a check-in, so their live location is on for an "
                  "hour${_in(room)}. I'll tell you if they get close."
            : '$who is sharing live location${_in(room)} until '
                  '${VibeLive.time(until)}.',
        notify: missed,
        urgent: missed,
      );
    }
    // close by, or a few minutes away
    VibeLive.whereAmI();
    final at = VibeLive.parse(content.tryGet<String>('geo_uri'));
    final me = VibeLive.me.value;
    if (at == null || me == null) return;
    final d = vibeMeters(me, at);
    final kmh = l.tryGet<int>('kmh') ?? 0;
    final before = _near[id];
    _near[id] = d;
    final eta = before != null && d < before && kmh >= 2
        ? (d / (kmh / 3.6) / 60).ceil()
        : null;
    if (d <= 400) {
      if (_once('$id:near')) {
        _say(room, id, '$who is close by, about ${vibeDistance(d)} away.',
            notify: true);
      }
    } else if (eta != null && eta <= 5 && _once('$id:eta')) {
      _say(room, id, '$who is about $eta min away (${vibeDistance(d)}).',
          notify: true);
    }
  }

  static void _check(
    Room room,
    String id,
    String who,
    Map<String, Object?> c,
    bool edit,
  ) {
    final state = c.tryGet<String>('state') ?? 'on';
    final name = c.tryGet<String>('name') ?? 'the place';
    final until = c.tryGet<int>('until') ?? 0;
    final arrive = c['kind'] == 'arrive';
    switch (state) {
      case 'on':
        if (!edit && _once('$id:on')) {
          _say(
            room,
            id,
            arrive
                ? '$who will check in on reaching $name by '
                      "${VibeLive.time(until)}${_in(room)}. I'll tell you "
                      'when they do.'
                : '$who will check in by ${VibeLive.time(until)}'
                      "${_in(room)}. I'll tell you how it goes.",
          );
        }
      case 'arrived':
        if (_once('$id:arrived')) {
          _say(room, id, '$who got to $name at ${VibeLive.time(_now)}.',
              notify: true);
        }
      case 'ended':
        if (_once('$id:ended')) {
          _say(room, id, '$who checked in${_in(room)}. All good.',
              notify: true);
        }
      case 'missed':
        if (_once('$id:missed')) {
          _say(
            room,
            id,
            '$who missed their check-in${arrive ? ' to $name' : ''}'
            '${_in(room)}. Their live location is on for an hour.',
            notify: true,
            urgent: true,
          );
        }
      default:
        break;
    }
  }

  static void _keep(BujjiSharer s) {
    final list = [
      s,
      ...sharing.value.where((x) => x.eventId != s.eventId && x.until > _now),
    ];
    sharing.value = list;
  }

  static void _drop(String id) {
    _near.remove(id);
    if (sharing.value.any((x) => x.eventId == id)) {
      sharing.value = sharing.value.where((x) => x.eventId != id).toList();
    }
  }

  // ---- your own ----

  static Room? _room(String id) => _client?.getRoomById(id);

  static void liveEnding(String roomId, String eventId, int until) {
    final room = _room(roomId);
    if (room == null) return;
    _say(
      room,
      eventId,
      'Your live location with ${room.getLocalizedDisplayname()} ends at '
      '${VibeLive.time(until)}. More time?',
      notify: true,
      choices: [
        BujjiChoice('+30 min', 'live:more:$eventId'),
        const BujjiChoice('Let it end', 'live:ok'),
      ],
    );
  }

  static void liveLong(String roomId, String eventId, int until) {
    final room = _room(roomId);
    if (room == null) return;
    _say(
      room,
      eventId,
      "You've been sharing your live location with "
      '${room.getLocalizedDisplayname()} for a while (until '
      '${VibeLive.time(until)}). Keep sharing?',
      notify: true,
      choices: [
        BujjiChoice('Stop now', 'live:stop:$eventId'),
        const BujjiChoice('Keep sharing', 'live:ok'),
      ],
    );
  }

  static void checkInDue(
    String roomId,
    String eventId,
    String? name,
    int until, {
    required bool arrive,
  }) {
    final room = _room(roomId);
    if (room == null) return;
    _say(
      room,
      eventId,
      arrive
          ? 'Your check-in to ${name ?? 'the place'} is due at '
                '${VibeLive.time(until)}. Need more time?'
          : 'Your check-in is due at ${VibeLive.time(until)}. All good?',
      notify: true,
      choices: [
        BujjiChoice('+15 min', 'check:more:$eventId'),
        BujjiChoice(arrive ? "I'm here" : "I'm OK", 'check:done:$eventId'),
      ],
    );
  }

  static void youMissed(String roomId, String eventId) {
    final room = _room(roomId);
    if (room == null) return;
    _say(
      room,
      eventId,
      'You missed your check-in, so ${room.getLocalizedDisplayname()} has '
      'your live location for an hour.',
      notify: true,
      urgent: true,
      choices: [BujjiChoice("I'm OK, stop", 'live:stop:$eventId')],
    );
  }

  /// A button under one of these: +30 min, Stop, I'm here…
  static Future<String> act(String id) async {
    final p = id.split(':');
    final eventId = p.length > 2 ? p.sublist(2).join(':') : '';
    final s = VibeLive.session(eventId);
    switch ('${p[0]}:${p[1]}') {
      case 'live:more':
        if (s == null) return "That's already over.";
        await VibeLive.extendLive(eventId, const Duration(minutes: 30));
        return 'Done, sharing until ${VibeLive.time(s.until)}.';
      case 'live:stop':
        if (s == null) return "It's already stopped.";
        await VibeLive.stopLive(s.roomId, eventId);
        return 'Stopped sharing your live location.';
      case 'check:more':
        if (s == null) return "That check-in is already over.";
        await VibeLive.extend(eventId, const Duration(minutes: 15));
        return 'Done, due at ${VibeLive.time(s.until)} now.';
      case 'check:done':
        if (s == null) return "That check-in is already over.";
        await VibeLive.arrive(eventId);
        return "Great, I've told them.";
      default:
        return 'Okay.';
    }
  }

  static void _say(
    Room room,
    String eventId,
    String text, {
    bool notify = false,
    bool urgent = false,
    List<BujjiChoice> choices = const [],
  }) {
    if (VibeBuddy.on) {
      Bujji.tell(text, roomId: room.id, choices: choices);
    }
    if (!notify) return;
    FlutterLocalNotificationsPlugin()
        .show(
          id: 'bujji_live_$eventId$text'.hashCode,
          title: VibeBuddy.on ? VibeBuddy.name : 'Keepr',
          body: text,
          payload: VibePushPayload(
            room.client.clientName,
            room.id,
            eventId,
          ).toString(),
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              urgent ? 'keepr_checkin' : 'keepr_bujji',
              urgent ? 'Check-in' : 'Bujji',
              importance: urgent ? Importance.max : Importance.high,
              priority: urgent ? Priority.max : Priority.high,
            ),
          ),
        )
        .catchError((_) {});
  }
}

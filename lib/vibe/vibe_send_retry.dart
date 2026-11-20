// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

/// Messages wait while there's no connection: Keepr keeps trying to send
/// them for two days (`AppSettings.sendTimelineEventTimeout`; a server that
/// says no still fails right away), and picks them up again after Keepr was
/// closed.
abstract class VibeSendRetry {
  static const _files = {
    MessageTypes.Image,
    MessageTypes.Video,
    MessageTypes.Audio,
    MessageTypes.File,
  };

  /// Once the first sync gets through, send again what was still waiting
  /// when Keepr closed.
  static void watch(Client client) {
    StreamSubscription<SyncStatusUpdate>? sub;
    sub = client.onSyncStatus.stream.listen((s) {
      if (s.status != SyncStatus.finished) return;
      sub?.cancel();
      for (final room in client.rooms) {
        if (room.membership == Membership.join) unawaited(_resume(room));
      }
    });
  }

  // in the order they were written
  static Future<void> _resume(Room room) async {
    final List<Event> waiting;
    try {
      waiting =
          (await room.client.database.getEventList(room, onlySending: true))
              .where((e) => e.status.isSending)
              .toList()
            ..sort((a, b) => a.originServerTs.compareTo(b.originServerTs));
    } catch (e, s) {
      Logs().w('Keepr: could not read waiting messages', e, s);
      return;
    }
    for (final e in waiting) {
      final txid = e.transactionId ?? e.eventId;
      if (room.sendingQueueEventsByTxId.contains(txid)) continue;
      final json = e.toJson();
      try {
        if (e.type == EventTypes.Message && _files.contains(e.messageType)) {
          // a photo or file comes back from the cache
          await Event.fromJson(_status(json, EventStatus.error), room)
              .sendAgain();
        } else {
          await room.sendEvent(e.content, type: e.type, txid: txid);
        }
      } catch (err, s) {
        Logs().w('Keepr: could not send a waiting message again', err, s);
        // shows "Could not be sent" with send again, instead of waiting on
        await room.client.handleSync(
          SyncUpdate(
            nextBatch: '',
            rooms: RoomsUpdate(
              join: {
                room.id: JoinedRoomUpdate(
                  timeline: TimelineUpdate(
                    events: [
                      MatrixEvent.fromJson(_status(json, EventStatus.error)),
                    ],
                  ),
                ),
              },
            ),
          ),
        );
      }
    }
  }

  static Map<String, dynamic> _status(
    Map<String, dynamic> json,
    EventStatus status,
  ) {
    final unsigned = Map<String, dynamic>.from(
      json['unsigned'] as Map? ?? const {},
    );
    unsigned[messageSendingStatusKey] = status.intValue;
    return Map<String, dynamic>.from(json)..['unsigned'] = unsigned;
  }
}

/// Without a connection, a waiting message would be tried every second.
/// This waits a little longer after each failed try (2, 4, 8 … up to 60
/// seconds) and lets them all go again as soon as anything gets through.
class VibePatientHttp extends http.BaseClient {
  final http.Client _inner;
  VibePatientHttp(this._inner);

  int _fails = 0;
  Completer<void>? _back;

  static bool _sending(Uri url) {
    final p = url.path;
    return p.contains('/send/') ||
        p.contains('/sendToDevice/') ||
        p.contains('/upload') ||
        p.contains('/keys/claim') ||
        p.contains('/keys/query') ||
        p.contains('/redact/');
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    try {
      final response = await _inner.send(request);
      _fails = 0;
      _back?.complete();
      _back = null;
      return response;
    } catch (_) {
      if (_sending(request.url)) {
        _fails++;
        final wait = Duration(seconds: min(60, 1 << min(_fails, 6)));
        final back = _back ??= Completer<void>();
        await Future.any([Future<void>.delayed(wait), back.future]);
      }
      rethrow;
    }
  }

  @override
  void close() => _inner.close();
}

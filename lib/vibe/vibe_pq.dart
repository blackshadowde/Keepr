// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:keepr_pq/keepr_pq.dart';
import 'package:matrix/encryption/utils/json_signature_check_extension.dart';
import 'package:matrix/matrix.dart';
// ignore: implementation_imports
import 'package:matrix/src/utils/markdown.dart';

/// Post-quantum layer for direct chats (ML-KEM-768, FIPS 203, from libcrux;
/// AES-256-GCM and HKDF-SHA256 from RustCrypto).
///
/// Each Keepr device has its own key pair, made once and kept in the
/// phone's secure storage. The public key is shared in each direct chat as
/// a state event, signed with the device's own Matrix key, so the other
/// side only uses keys that really belong to that device.
abstract class VibePq {
  static const keyType = 'chat.keepr.pq_key';
  static const version = 1;
  static const _storage = FlutterSecureStorage();

  static String _slot(Client c) => 'keepr_pq_${c.userID}_${c.deviceID}';

  /// Where a device's key sits in a room's state.
  static String stateKey(String userId, String deviceId) => '$userId|$deviceId';

  static final _cache =
      <String, ({Uint8List publicKey, Uint8List privateKey})>{};

  /// This device's key pair, made the first time it's needed.
  static Future<({Uint8List publicKey, Uint8List privateKey})?> mine(
    Client c,
  ) async {
    if (c.userID == null || c.deviceID == null) return null;
    final slot = _slot(c);
    final cached = _cache[slot];
    if (cached != null) return cached;
    try {
      final saved = await _storage.read(key: slot);
      if (saved != null) {
        final j = jsonDecode(saved) as Map<String, Object?>;
        final pair = (
          publicKey: base64Decode(j['pk'] as String),
          privateKey: base64Decode(j['sk'] as String),
        );
        if (pair.publicKey.length == MlKem768.publicKeyLength &&
            pair.privateKey.length == MlKem768.privateKeyLength) {
          return _cache[slot] = pair;
        }
      }
      final pair = MlKem768.generate();
      await _storage.write(
        key: slot,
        value: jsonEncode({
          'pk': base64Encode(pair.publicKey),
          'sk': base64Encode(pair.privateKey),
        }),
      );
      return _cache[slot] = pair;
    } catch (e, s) {
      Logs().w('[PQ] No key pair', e, s);
      return null;
    }
  }

  /// Shares this device's public key in a direct chat (once; again if the
  /// key changed).
  static Future<void> publishIn(Room r) async {
    final c = r.client;
    final enc = c.encryption;
    if (!r.isDirectChat ||
        !r.encrypted ||
        r.membership != Membership.join ||
        enc == null ||
        !c.encryptionEnabled) {
      return;
    }
    final pair = await mine(c);
    if (pair == null) return;
    final key = stateKey(c.userID!, c.deviceID!);
    final pk = base64Encode(pair.publicKey);
    if (r.getState(keyType, key)?.content['key'] == pk) return;
    try {
      final signed = enc.olmManager.signJson({
        'v': version,
        'alg': 'ML-KEM-768',
        'user': c.userID!,
        'device': c.deviceID!,
        'key': pk,
      });
      await c.setRoomStateWithKey(r.id, keyType, key, signed);
    } catch (e, s) {
      Logs().w('[PQ] Could not share the key', e, s);
    }
  }

  /// [userId]'s device keys in [r] that check out: published by that user,
  /// for a device they still have, not blocked, and signed by that device.
  static Map<String, Uint8List> keysOf(Room r, String userId) {
    final out = <String, Uint8List>{};
    final devices = r.client.userDeviceKeys[userId]?.deviceKeys;
    final states = r.states[keyType];
    if (devices == null || states == null) return out;
    for (final e in states.values) {
      final content = e.content;
      final device = content.tryGet<String>('device');
      final key = content.tryGet<String>('key');
      if (device == null ||
          key == null ||
          content.tryGet<String>('user') != userId ||
          content.tryGet<int>('v') != version ||
          e.senderId != userId ||
          e.stateKey != stateKey(userId, device)) {
        continue;
      }
      final dk = devices[device];
      final ed = dk?.ed25519Key;
      if (dk == null || ed == null || dk.blocked) continue;
      final copy = jsonDecode(jsonEncode(content)) as Map<String, dynamic>;
      if (!copy.checkJsonSignature(ed, userId, device)) continue;
      try {
        final bytes = base64Decode(key);
        if (bytes.length == MlKem768.publicKeyLength) out[device] = bytes;
      } catch (_) {}
    }
    return out;
  }

  /// Checks ML-KEM on this phone: wraps a secret to this device's own key
  /// and unwraps it again.
  static Future<String> selfTest(Client c) async {
    try {
      final pair = await mine(c);
      if (pair == null) return 'Not ready';
      final sent = MlKem768.encapsulate(pair.publicKey);
      final got = MlKem768.decapsulate(pair.privateKey, sent.ciphertext);
      var same = got.length == sent.secret.length;
      for (var i = 0; same && i < got.length; i++) {
        same = got[i] == sent.secret[i];
      }
      return same ? 'ML-KEM-768 · working' : 'ML-KEM-768 · mismatch';
    } catch (e) {
      return 'Not available ($e)';
    }
  }

  // ---- messages in direct chats ----
  //
  // When every device of both people has a checked key, text messages get
  // an inner layer: a chat key (32 random bytes) is wrapped for each of
  // those devices with ML-KEM and sent once as a share event; each message
  // is then sealed with AES-256-GCM under a key derived from it, bound to
  // the room, the sender and the chat key. The result still goes through
  // the normal Matrix encryption, so breaking it takes breaking both. If any
  // device can't do this (another app), messages go out as before, so no
  // one gets something they can't read.

  static const shareType = 'chat.keepr.pq_share';
  static const wrapKey = 'chat.keepr.pq';
  static const fallback =
      '🔒 Post-quantum message. Open it in Keepr to read it.';

  /// A new chat key after this many messages, or when the devices change.
  static const _rotateAfter = 100;

  /// Rebuilds what shows messages once a chat key arrives.
  static final changed = ValueNotifier<int>(0);

  static final _keys = <String, Uint8List>{};
  static final _opened = <String, Map<String, Object?>>{};

  /// Messages shown opened (their text must never be copied out).
  static final _openedIds = <String>{};
  static final _fetching = <String>{};

  /// Chat keys that couldn't be found lately (not asked again for a minute).
  static final _missing = <String, DateTime>{};

  static Uint8List _utf8(String s) => Uint8List.fromList(utf8.encode(s));

  /// Every device that must be able to read a direct chat, with its key; or
  /// null when any of them has none (then messages go out as before).
  static Map<String, Uint8List>? recipients(Room r) {
    final c = r.client;
    final me = c.userID, other = r.directChatMatrixID;
    if (!r.isDirectChat ||
        !r.encrypted ||
        !c.encryptionEnabled ||
        me == null ||
        other == null ||
        other == me) {
      return null;
    }
    final out = <String, Uint8List>{};
    for (final u in [me, other]) {
      final list = c.userDeviceKeys[u];
      if (list == null || list.deviceKeys.isEmpty) return null;
      final keys = keysOf(r, u);
      for (final d in list.deviceKeys.entries) {
        if (d.value.blocked) continue;
        final k = keys[d.key];
        if (k == null) return null;
        out[stateKey(u, d.key)] = k;
      }
    }
    return out.isEmpty ? null : out;
  }

  /// Whether new messages in [r] get the post-quantum layer.
  static bool on(Room r) {
    try {
      return recipients(r) != null;
    } catch (_) {
      return false;
    }
  }

  static Uint8List _msgKey(Uint8List chatKey) =>
      PqSymmetric.hkdf(chatKey, _utf8('keepr-pq-msg-v1'));

  static Uint8List _msgAad(String roomId, String sender, String session) =>
      _utf8('keepr-pq-msg-v1|$roomId|$sender|$session');

  static Uint8List _shareKey(Uint8List secret, String session, String to) =>
      PqSymmetric.hkdf(secret, _utf8('keepr-pq-share-v1|$session|$to'));

  static Uint8List _shareAad(String roomId, String session, String to) =>
      _utf8('keepr-pq-share-v1|$roomId|$session|$to');

  static Future<void> _saveKey(String session, Uint8List key) async {
    _keys[session] = key;
    try {
      await _storage.write(key: 'keepr_pq_s_$session', value: base64Encode(key));
    } catch (_) {}
  }

  /// The chat key for sending in [r]: the current one, or a new one shared
  /// with every device in [to].
  static Future<({String id, String share, Uint8List key})?> _outgoing(
    Room r,
    Map<String, Uint8List> to,
  ) async {
    final slot = 'keepr_pq_out_${r.id}';
    final who = jsonEncode(
      (to.keys.toList()..sort())
          .map((k) => '$k:${base64Encode(to[k]!).substring(0, 32)}')
          .toList(),
    );
    try {
      final saved = await _storage.read(key: slot);
      if (saved != null) {
        final j = jsonDecode(saved) as Map<String, Object?>;
        final n = j['n'] as int;
        if (j['who'] == who && n < _rotateAfter) {
          final key = base64Decode(j['key'] as String);
          j['n'] = n + 1;
          await _storage.write(key: slot, value: jsonEncode(j));
          _keys[j['id'] as String] = key;
          return (id: j['id'] as String, share: j['share'] as String, key: key);
        }
      }
    } catch (_) {}
    // a new chat key, wrapped for each device with ML-KEM
    final key = PqSymmetric.random(32);
    final id = base64UrlEncode(PqSymmetric.random(16)).replaceAll('=', '');
    final keys = <String, Object?>{};
    for (final e in to.entries) {
      final kem = MlKem768.encapsulate(e.value);
      final sealed = PqSymmetric.seal(
        _shareKey(kem.secret, id, e.key),
        _shareAad(r.id, id, e.key),
        key,
      );
      keys[e.key] = {
        'ct': base64Encode(kem.ciphertext),
        'n': base64Encode(sealed.nonce),
        'w': base64Encode(sealed.cipher),
      };
    }
    final share = await r.sendEvent({
      'v': version,
      'session': id,
      'keys': keys,
    }, type: shareType);
    if (share == null) return null;
    await _saveKey(id, key);
    await _storage.write(
      key: slot,
      value: jsonEncode({
        'id': id,
        'share': share,
        'key': base64Encode(key),
        'n': 1,
        'who': who,
      }),
    );
    return (id: id, share: share, key: key);
  }

  /// Sends a text message: with the post-quantum layer when the chat is
  /// ready for it, otherwise exactly as before.
  static Future<String?> sendText(
    Room r,
    String text, {
    Event? inReplyTo,
    String? editEventId,
    bool parseCommands = true,
    String? threadRootEventId,
  }) async {
    // a reply carries a copy of what it answers: for a post-quantum message
    // that copy is only the placeholder, never its words
    inReplyTo = safeReply(inReplyTo);
    Future<String?> plain() => r.sendTextEvent(
      text,
      inReplyTo: inReplyTo,
      editEventId: editEventId,
      parseCommands: parseCommands,
      threadRootEventId: threadRootEventId,
    );
    final me = r.client.userID;
    if (me == null || (parseCommands && text.startsWith('/'))) return plain();
    final to = recipients(r);
    if (to == null) return plain();
    final ({String id, String share, Uint8List key})? s;
    try {
      s = await _outgoing(r, to);
    } catch (e, st) {
      Logs().w('[PQ] No chat key, sending normally', e, st);
      return plain();
    }
    if (s == null) return plain();
    final inner = <String, Object?>{'msgtype': MessageTypes.Text, 'body': text};
    final html = markdown(
      text,
      getMention: r.getMention,
      convertLinebreaks: r.client.convertLinebreaksInFormatting,
    );
    if (_unescape(html.replaceAll(RegExp(r'<br />\n?'), '\n')) != text) {
      inner['format'] = 'org.matrix.custom.html';
      inner['formatted_body'] = html;
    }
    final sealed = PqSymmetric.seal(
      _msgKey(s.key),
      _msgAad(r.id, me, s.id),
      _utf8(jsonEncode(inner)),
    );
    return r.sendEvent(
      {
        'msgtype': MessageTypes.Text,
        'body': fallback,
        wrapKey: {
          'v': version,
          'session': s.id,
          'share': s.share,
          'n': base64Encode(sealed.nonce),
          'c': base64Encode(sealed.cipher),
        },
      },
      inReplyTo: inReplyTo,
      editEventId: editEventId,
      threadRootEventId: threadRootEventId,
    );
  }

  static Event? safeReply(Event? e) {
    if (e == null) return null;
    if (e.content[wrapKey] == null && !_openedIds.contains(e.eventId)) {
      return e;
    }
    return Event(
      content: {'msgtype': MessageTypes.Text, 'body': fallback},
      type: EventTypes.Message,
      eventId: e.eventId,
      senderId: e.senderId,
      originServerTs: e.originServerTs,
      room: e.room,
      status: e.status,
    );
  }

  static String _unescape(String s) => s
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&amp;', '&');

  /// [e] with its post-quantum layer opened, or [e] itself (not wrapped,
  /// or the chat key isn't here yet: then it's fetched, and [changed]
  /// fires when it is).
  static Event open(Event e) {
    final w = e.content.tryGetMap<String, Object?>(wrapKey);
    if (w == null) return e;
    final inner = _openContent(e.room.id, e.senderId, w);
    if (inner == null) {
      _fetch(e.room, w);
      return e;
    }
    final rel = e.content['m.relates_to'];
    if (_openedIds.length > 5000) _openedIds.clear();
    _openedIds.add(e.eventId);
    return Event(
      content: {...inner, 'm.relates_to': ?rel},
      type: e.type,
      eventId: e.eventId,
      senderId: e.senderId,
      originServerTs: e.originServerTs,
      unsigned: e.unsigned,
      stateKey: e.stateKey,
      room: e.room,
      status: e.status,
      originalSource: e.originalSource,
    );
  }

  /// Gets the chat key [e] needs, if it's wrapped (for notifications).
  static Future<void> ensure(Event e) async {
    final w = e.content.tryGetMap<String, Object?>(wrapKey);
    if (w == null) return;
    await _fetch(e.room, w);
  }

  static Map<String, Object?>? _openContent(
    String roomId,
    String sender,
    Map<String, Object?> w,
  ) {
    final session = w.tryGet<String>('session');
    final n = w.tryGet<String>('n');
    final c = w.tryGet<String>('c');
    if (session == null || n == null || c == null) return null;
    final cacheKey = '$roomId|$sender|$session|$n|${c.hashCode}';
    final hit = _opened[cacheKey];
    if (hit != null) return hit;
    final key = _keys[session];
    if (key == null) return null;
    try {
      final plain = PqSymmetric.open(
        _msgKey(key),
        _msgAad(roomId, sender, session),
        base64Decode(n),
        base64Decode(c),
      );
      if (plain == null) return null;
      final inner = jsonDecode(utf8.decode(plain));
      if (inner is! Map<String, Object?>) return null;
      // only message content comes from inside, never relations
      inner.remove('m.relates_to');
      inner.remove(wrapKey);
      if (_opened.length > 2000) _opened.clear();
      return _opened[cacheKey] = inner;
    } catch (_) {
      return null;
    }
  }

  /// Finds the chat key for a wrapped message: on this phone, or from its
  /// share event (unwrapped with this device's ML-KEM key).
  static Future<void> _fetch(Room r, Map<String, Object?> w) async {
    final session = w.tryGet<String>('session');
    final shareId = w.tryGet<String>('share');
    if (session == null || _keys.containsKey(session)) return;
    final miss = _missing[session];
    if (miss != null && DateTime.now().difference(miss).inMinutes < 1) return;
    if (!_fetching.add(session)) return;
    var found = false;
    try {
      final saved = await _storage.read(key: 'keepr_pq_s_$session');
      if (saved != null) {
        _keys[session] = base64Decode(saved);
        found = true;
        changed.value++;
        return;
      }
      final c = r.client;
      if (shareId == null || c.userID == null || c.deviceID == null) return;
      final share = await r.getEventById(shareId);
      if (share == null ||
          share.type != shareType ||
          share.content.tryGet<String>('session') != session ||
          !{c.userID, r.directChatMatrixID}.contains(share.senderId)) {
        return;
      }
      final me = stateKey(c.userID!, c.deviceID!);
      final mine = share.content.tryGetMap<String, Object?>('keys')?[me];
      if (mine is! Map) return;
      final pair = await VibePq.mine(c);
      if (pair == null) return;
      final secret = MlKem768.decapsulate(
        pair.privateKey,
        base64Decode(mine['ct'] as String),
      );
      final key = PqSymmetric.open(
        _shareKey(secret, session, me),
        _shareAad(r.id, session, me),
        base64Decode(mine['n'] as String),
        base64Decode(mine['w'] as String),
      );
      if (key == null || key.length != 32) return;
      await _saveKey(session, key);
      found = true;
      changed.value++;
    } catch (e, s) {
      Logs().w('[PQ] Could not get the chat key', e, s);
    } finally {
      _fetching.remove(session);
      if (!found) _missing[session] = DateTime.now();
    }
  }
}

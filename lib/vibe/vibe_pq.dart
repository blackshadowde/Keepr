// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:keepr_pq/keepr_pq.dart';
import 'package:matrix/encryption/utils/json_signature_check_extension.dart';
import 'package:matrix/matrix.dart';

/// Post-quantum keys (ML-KEM-768, FIPS 203, from libcrux).
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
}

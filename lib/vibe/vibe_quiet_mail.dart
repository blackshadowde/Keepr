// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

import 'package:vibe/config/setting_keys.dart';

/// Small things Keepr shares only with the people they're for (your status,
/// your local time, what you're listening to, your group tag). They go
/// encrypted straight to those people's devices: the servers pass them on
/// but can't read them, nothing piles up in the chats, and no phone is woken
/// for them.
abstract class VibeQuietMail {
  /// "Send me yours": a device that doesn't have someone's status or tag
  /// yet (just signed in) asks for it.
  static const ask = 'chat.keepr.ask';

  /// Bumped whenever something new arrives, so what shows it redraws.
  static final ValueNotifier<int> changes = ValueNotifier(0);

  /// Sends [content] as [type] to every device of [userIds] (your own other
  /// devices too, when your id is in the list).
  static Future<void> send(
    Client client,
    Iterable<String> userIds,
    String type,
    Map<String, Object?> content,
  ) async {
    if (!client.encryptionEnabled) return;
    final ids = userIds.toSet();
    if (ids.isEmpty) return;
    // people without a shared encrypted chat: look their devices up first
    final unknown = ids.where((u) => client.userDeviceKeys[u] == null).toSet();
    if (unknown.isNotEmpty) {
      await client.updateUserDeviceKeys(additionalUsers: unknown);
    }
    final devices = <DeviceKeys>[
      for (final u in ids) ...?client.userDeviceKeys[u]?.deviceKeys.values,
    ];
    if (devices.isEmpty) return;
    await client.sendToDeviceEncryptedChunked(
      devices,
      type,
      Map<String, dynamic>.from(content),
    );
  }

  /// What arrives as [type], only when it came encrypted.
  static Stream<ToDeviceEvent> on(Client client, String type) =>
      client.onToDeviceEvent.stream.where(
        (e) => e.type == type && e.encryptedContent != null,
      );

  // Kept on this phone: the newest of each person's, by user id.
  static Map<String, Map<String, Object?>> _load(String key) {
    try {
      final raw = AppSettings.store.getString(key);
      if (raw == null) return {};
      final m = jsonDecode(raw);
      if (m is! Map) return {};
      return {
        for (final e in m.entries)
          if (e.value is Map)
            '${e.key}': Map<String, Object?>.from(e.value as Map),
      };
    } catch (_) {
      return {};
    }
  }

  static final Map<String, Map<String, Map<String, Object?>>> _vaults = {};

  /// Someone's newest [kind] (status or tag), or null when none came yet.
  static Map<String, Object?>? get(String kind, String userId) =>
      (_vaults[kind] ??= _load('chat.keepr.quiet.$kind'))[userId];

  static bool has(String kind, String userId) =>
      (_vaults[kind] ??= _load('chat.keepr.quiet.$kind')).containsKey(userId);

  static Future<void> put(
    String kind,
    String userId,
    Map<String, Object?> content,
  ) async {
    final vault = _vaults[kind] ??= _load('chat.keepr.quiet.$kind');
    vault[userId] = content;
    changes.value++;
    try {
      await AppSettings.store.setString(
        'chat.keepr.quiet.$kind',
        jsonEncode(vault),
      );
    } catch (e) {
      Logs().d('Keepr: could not keep $kind', e);
    }
  }

  // asked once per person and kind while Keepr runs
  static final Set<String> _asked = {};

  /// Asks [userIds] for their [kind] when this phone doesn't have it yet.
  static Future<void> askMissing(
    Client client,
    String kind,
    Iterable<String> userIds,
  ) async {
    final want = [
      for (final u in userIds)
        if (!has(kind, u) && _asked.add('$kind|$u')) u,
    ];
    if (want.isEmpty) return;
    try {
      await send(client, want, ask, {'what': kind});
    } catch (e) {
      Logs().d('Keepr: could not ask for $kind', e);
    }
  }

  // answers at most once a minute to each person
  static final Map<String, DateTime> _answered = {};

  /// Whether to answer [userId]'s question about [kind] now.
  static bool mayAnswer(String kind, String userId) {
    final key = '$kind|$userId';
    final last = _answered[key];
    final now = DateTime.now();
    if (last != null && now.difference(last).inSeconds < 60) return false;
    _answered[key] = now;
    return true;
  }
}

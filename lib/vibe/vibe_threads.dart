// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:vibe/config/setting_keys.dart';

/// Threads made from a message (long-press > Create thread). They are
/// pinned in the chat's middle pane until closed. The list is kept on this
/// device; the replies themselves are normal Matrix thread replies.
abstract class VibeThreads {
  static final ValueNotifier<int> revision = ValueNotifier(0);

  static String _key(String roomId) => 'keepr.threads.$roomId';

  static List<String> ids(String roomId) =>
      AppSettings.store.getStringList(_key(roomId)) ?? const [];

  static bool isPinned(String roomId, String eventId) =>
      ids(roomId).contains(eventId);

  static Future<void> add(String roomId, String eventId) async {
    final list = List<String>.of(ids(roomId));
    if (list.contains(eventId)) return;
    list.insert(0, eventId);
    await AppSettings.store.setStringList(_key(roomId), list);
    revision.value++;
  }

  static Future<void> remove(String roomId, String eventId) async {
    final list = List<String>.of(ids(roomId))..remove(eventId);
    await AppSettings.store.setStringList(_key(roomId), list);
    revision.value++;
  }

  /// The chat opens straight into this thread next time it's shown.
  static final Map<String, String> _openNext = {};
  static void openNext(String roomId, String eventId) =>
      _openNext[roomId] = eventId;
  static String? takeOpen(String roomId) => _openNext.remove(roomId);

  /// "Close this thread?" Yes removes it from the pinned list for good.
  static Future<bool> confirmClose(
    BuildContext context,
    String roomId,
    String eventId,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Close this thread?'),
        content: const Text(
          'It will be removed from the chat\'s threads. The messages stay in '
          'the chat.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Yes, close'),
          ),
        ],
      ),
    );
    if (ok != true) return false;
    await remove(roomId, eventId);
    return true;
  }

  /// A short name for the thread: the start of its first message.
  static String title(Event? root) {
    if (root == null) return 'thread';
    final body = root
        .calcUnlocalizedBody(hideReply: true, plaintextBody: true)
        .replaceAll('\n', ' ')
        .trim();
    if (body.isEmpty) return 'thread';
    return body.length > 40 ? '${body.substring(0, 40)}…' : body;
  }
}

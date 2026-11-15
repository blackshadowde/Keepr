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
    await AppSettings.store.remove(_titleKey(roomId, eventId));
    revision.value++;
  }

  static String _titleKey(String roomId, String eventId) =>
      'keepr.thread_title.$roomId.$eventId';

  /// The name the user gave the thread, if any.
  static String? customTitle(String roomId, String eventId) {
    final t = AppSettings.store.getString(_titleKey(roomId, eventId))?.trim();
    return t == null || t.isEmpty ? null : t;
  }

  /// The thread's name: the one the user gave it, or else the start of its
  /// first message.
  static String nameOf(String roomId, String eventId, Event? root) =>
      customTitle(roomId, eventId) ?? title(root);

  /// Rename the thread. Left empty, it goes back to its first message.
  static Future<void> rename(
    BuildContext context,
    String roomId,
    String eventId,
    Event? root,
  ) async {
    final controller = TextEditingController(
      text: customTitle(roomId, eventId) ?? '',
    );
    final result = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Thread name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 60,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: title(root),
            helperText: 'Leave empty to use the first message',
          ),
          onSubmitted: (v) => Navigator.of(c).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(c).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null) return;
    final t = result.trim();
    if (t.isEmpty) {
      await AppSettings.store.remove(_titleKey(roomId, eventId));
    } else {
      await AppSettings.store.setString(_titleKey(roomId, eventId), t);
    }
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

  static final Map<String, Future<bool>> _any = {};

  /// Whether a chat has any threads (pinned here, or started anywhere).
  static Future<bool> hasAny(Room room) {
    if (ids(room.id).isNotEmpty) return Future.value(true);
    return _any[room.id] ??= room.client
        .getThreadRoots(room.id, limit: 1)
        .then((r) => r.chunk.isNotEmpty)
        .catchError((_) => false);
  }

  /// Every thread in a chat: the ones you pinned first, then all the others
  /// the server knows (started here or in other apps). Tap one to open it.
  static Future<void> showList(
    BuildContext context,
    Room room, {
    required void Function(String eventId) onOpen,
  }) async {
    final pinned = ids(room.id);
    Future<List<String>> others() async {
      try {
        final r = await room.client.getThreadRoots(room.id, limit: 50);
        return [
          for (final e in r.chunk)
            if (!pinned.contains(e.eventId)) e.eventId,
        ];
      } catch (_) {
        return const [];
      }
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        Widget row(String id, {required bool mine}) => FutureBuilder<Event?>(
          future: room.getEventById(id),
          builder: (context, snap) {
            final root = snap.data;
            final count = root?.unsigned
                ?.tryGetMap<String, Object?>('m.relations')
                ?.tryGetMap<String, Object?>('m.thread')
                ?.tryGet<int>('count');
            return ListTile(
              leading: badge(context, size: 40),
              title: Text(
                nameOf(room.id, id, root),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                [
                  if (root != null) root.senderFromMemoryOrFallback.calcDisplayname(),
                  if (count != null) count == 1 ? '1 reply' : '$count replies',
                ].join(' · '),
                maxLines: 1,
              ),
              trailing: mine
                  ? IconButton(
                      tooltip: 'Close thread',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => confirmClose(context, room.id, id),
                    )
                  : null,
              onTap: () {
                Navigator.of(context).pop();
                onOpen(id);
              },
            );
          },
        );
        return ValueListenableBuilder<int>(
          valueListenable: revision,
          builder: (context, _, _) => FutureBuilder<List<String>>(
            future: others(),
            builder: (context, snap) {
              final mine = ids(room.id);
              final rest = snap.data ?? const <String>[];
              return ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Text(
                      'Threads',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                    ),
                  ),
                  for (final id in mine) row(id, mine: true),
                  if (snap.connectionState != ConnectionState.done)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(child: CircularProgressIndicator.adaptive()),
                    )
                  else if (mine.isEmpty && rest.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                      child: Text(
                        'No threads yet. Hold a message and pick Thread to start one.',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ),
                  for (final id in rest) row(id, mine: false),
                ],
              );
            },
          ),
        );
      },
    );
  }

  /// The thread icon: a filled bubble pair on the theme's own colour.
  static const IconData icon = Icons.forum_rounded;

  static Widget badge(BuildContext context, {double size = 34}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: size * 0.55, color: cs.onPrimaryContainer),
    );
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

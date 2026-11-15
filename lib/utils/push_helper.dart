// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:vibe/vibe/vibe_event_body.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:collection/collection.dart';
import 'package:vibe/config/app_config.dart';
import 'package:vibe/config/setting_keys.dart';
import 'package:vibe/l10n/l10n.dart';
import 'package:vibe/utils/client_manager.dart';
import 'package:vibe/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:vibe/utils/notification_avatar_extension.dart';
import 'package:vibe/utils/notification_background_handler.dart';
import 'package:vibe/utils/platform_infos.dart';
import 'package:vibe/utils/start_push_foreground_service.dart';
import 'package:vibe/vibe/vibe_lock.dart';
import 'package:vibe/vibe/vibe_peek.dart';
import 'package:flutter/foundation.dart';
import 'package:vibe/vibe/vibe_mute.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:vibe/vibe/vibe_sound.dart';
import 'package:flutter_new_badger/flutter_new_badger.dart';
import 'package:flutter_shortcuts_new/flutter_shortcuts_new.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' hide Result;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synchronized/synchronized.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:vibe/utils/call_kit_params.dart';
import 'package:vibe/utils/matrix_live_kit_calls/matrix_live_kit_call.dart';

final Map<String, DateTime> lastReceivedPushNotification = {};

/// One push at a time, so two arriving together don't race on the database.
final _pushLock = Lock();

/// Events already notified (Direct connection and the Firebase backup can
/// both deliver the same message): each is shown once.
final Set<String> _shownEventIds = {};

/// Messages can reach Vibe twice: through its own always-on connection and
/// through Firebase, which may run in a separate background isolate (so the
/// in-memory set above doesn't see it). Shown event IDs are also kept in
/// shared preferences, which both see.
const _shownKey = 'vibe_shown_notification_events';

Future<bool> _shownElsewhere(String eventId) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return (prefs.getStringList(_shownKey) ?? const []).contains(eventId);
  } catch (_) {
    return false;
  }
}

Future<void> _markShown(String eventId) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final list = [...?prefs.getStringList(_shownKey)];
    if (list.contains(eventId)) return;
    list.add(eventId);
    if (list.length > 200) list.removeRange(0, list.length - 200);
    await prefs.setStringList(_shownKey, list);
  } catch (_) {}
}

Future<void> pushHelper(
  PushNotification notification, {
  Event? knownEvent,
  List<Client>? clients,
  L10n? l10n,
  String? activeRoomId,
  required FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin,
}) async {
  l10n ??= await lookupL10n(PlatformDispatcher.instance.locale);

  try {
    final strings = l10n;
    await _pushLock.synchronized(
      () => _tryPushHelper(
        notification,
        knownEvent: knownEvent,
        clients: clients,
        l10n: strings,
        activeRoomId: activeRoomId,
        flutterLocalNotificationsPlugin: flutterLocalNotificationsPlugin,
      ).timeout(const Duration(seconds: 30)),
    );
  } catch (e, s) {
    if (e.toString() == 'Exception: Client is not logged in.') {
      Logs().w('Ignore push notification, when not logged in', e);
      return;
    }
    if (PlatformInfos.isAndroid &&
        e is! TimeoutException &&
        e is! IOException &&
        e is! http.ClientException) {
      Logs().e('Push Helper has crashed! Writing into temporary file...', e, s);
      final store = await SharedPreferences.getInstance();
      await store.setStringList(AppConfig.pushHelperCrashReportKey, [
        e.toString(),
        s.toString(),
      ]);
    }

    if (notification.roomId != null) {
      await flutterLocalNotificationsPlugin.show(
        id: notification.notificationId,
        title: l10n.newMessageInFluffyChat,
        body: l10n.openAppToReadMessages,
        notificationDetails: NotificationDetails(
          iOS: DarwinNotificationDetails(
            threadIdentifier:
                '${notification.clientName}_${notification.roomId}',
          ),
          android: AndroidNotificationDetails(
            VibeSound.channelId,
            sound: VibeSound.sound,
            playSound: VibeSound.playSound,
            l10n.incomingMessages,
            number: notification.counts?.unread,
            ticker: l10n.unreadChatsInApp(
              AppSettings.applicationName.value,
              (notification.counts?.unread ?? 0).toString(),
            ),
            importance: Importance.high,
            priority: Priority.max,
            shortcutId: notification.roomId,
            category: AndroidNotificationCategory.message,
            groupKey: notification.clientName,
          ),
        ),
      );
    }
    rethrow;
  } finally {
    // another push still waiting keeps the service running
    if (!_pushLock.locked) ForegroundServices.stopService('background_push');
  }
}

Future<void> _tryPushHelper(
  PushNotification notification, {
  Event? knownEvent,
  List<Client>? clients,
  L10n? l10n,
  String? activeRoomId,
  required FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin,
}) async {
  final shownId = notification.eventId;
  if (shownId != null) {
    if (!_shownEventIds.add(shownId)) {
      Logs().v('Push helper: already shown $shownId');
      return;
    }
    if (_shownEventIds.length > 300) _shownEventIds.remove(_shownEventIds.first);
    if (await _shownElsewhere(shownId)) {
      Logs().v('Push helper: already shown elsewhere $shownId');
      return;
    }
  }

  final isBackgroundMessage = clients == null;
  Logs().v(
    'Push helper has been started (background=$isBackgroundMessage).',
    notification.toJson(),
  );

  if (notification.roomId != null &&
      activeRoomId == notification.roomId &&
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
    Logs().v('Room is in foreground. Stop push helper here.');
    return;
  }

  final clientName = notification.clientName;
  final store = await AppSettings.init();

  final client = clientName == null
      ? (clients?.first ??
            (await ClientManager.getClients(
              initialize: false,
              store: store,
            )).first)
      : (clients?.firstWhereOrNull(
              (client) => client.clientName == clientName,
            ) ??
            await ClientManager.createClient(clientName, store));

  lastReceivedPushNotification[client.clientName] = DateTime.now();

  l10n ??= await L10n.delegate.load(PlatformDispatcher.instance.locale);

  Logs().v('Load event...');
  // Vibe's own connection already has the (decrypted) event; only a push
  // wake-up needs to fetch it.
  Event? event = knownEvent;
  if (event == null) {
    try {
      event = await client.getEventByPushNotification(
        notification,
        storeInDatabase: false,
      );
    } catch (e) {
      // gone, redacted or not visible to us: nothing to show, not a crash
      Logs().w('Push helper: no event for this notification ($e)');
      return;
    }
  }

  updateAppBadge(notification.counts?.unread ?? 0);

  if (event == null) {
    Logs().v('Notification is a clearing indicator.');
    if (clients?.length == 1 && (notification.counts?.unread == 0)) {
      await flutterLocalNotificationsPlugin.cancelAll();
    } else {
      // Make sure client is fully loaded and synced before dismiss notifications:
      await client.roomsLoading;
      await client
          .oneShotSync()
          .timeout(const Duration(seconds: 8))
          .catchError((_) => null);

      final activeNotifications = await flutterLocalNotificationsPlugin
          .getActiveNotifications();
      activeNotifications.removeWhere(
        (notification) => notification.groupKey != client.clientName,
      );
      var needsUpdateForSummaryNotification = false;
      for (final activeNotification in activeNotifications) {
        final room = client.rooms.singleWhereOrNull(
          (room) =>
              '${client.clientName}_${room.id}'.hashCode ==
              activeNotification.id,
        );
        if (room != null && !room.isUnreadOrInvited) {
          flutterLocalNotificationsPlugin.cancel(id: activeNotification.id!);
          if (PlatformInfos.isAndroid) needsUpdateForSummaryNotification = true;
        }
      }
      if (needsUpdateForSummaryNotification) {
        await updateSummaryNotification(
          clientName: client.clientName,
          l10n: l10n,
          flutterLocalNotificationsPlugin: flutterLocalNotificationsPlugin,
        );
      }
    }
    return;
  }

  Logs().v('Push helper got notification event of type ${event.type}.');

  if (!client.pushruleEvaluator.match(event).notify) {
    Logs().i('Push helper: filtered by client-side push rules.');
    return;
  }

  // a native call ringing you (Element X, FluffyChat, Keepr): the phone's
  // own call screen
  if (event.type == RtcNotificationContent.eventType &&
      event.tryParseRtcNotificationContent()?.notificationType ==
          RtcNotificationType.ring &&
      PlatformInfos.isMobile &&
      AppSettings.vibeNativeCalls.value) {
    await _showIncomingCall(event, l10n);
    return;
  }

  // a muted chat stays quiet (calls still ring)
  if (!event.type.startsWith('m.call') && VibeMute.quiet(event.room)) {
    Logs().i('Push helper: muted chat, no notification.');
    return;
  }

  if (event.type.startsWith('m.call')) {
    // make sure bg sync is on (needed to update hold, unhold events)
    // prevent over write from app life cycle change
    client.backgroundSync = true;
  }

  if (event.type == EventTypes.CallHangup) {
    client.backgroundSync = false;
  }

  if (event.type.startsWith('m.call') && event.type != EventTypes.CallInvite) {
    Logs().v('Push message is a m.call but not invite. Do not display.');
    return;
  }

  if ((event.type.startsWith('m.call') &&
          event.type != EventTypes.CallInvite) ||
      event.type == 'org.matrix.call.sdp_stream_metadata_changed') {
    Logs().v('Push message was for a call, but not call invite.');
    return;
  }

  // Vibe: locked chats never show who wrote or what.
  // Also when the person turned on Notification privacy in settings: then
  // every notification only says the app name and "New message".
  final hideContent = AppSettings.vibeHideNotificationContent.value;
  if (VibeLock.isLocked(event.room.id) || hideContent) {
    await flutterLocalNotificationsPlugin.show(
      id: '${client.clientName}_${notification.roomId}'.hashCode,
      title: hideContent ? AppSettings.applicationName.value : 'Keepr',
      body: 'New message',
      // tapping opens the chat (not for locked chats, as before)
      payload: hideContent && !VibeLock.isLocked(event.room.id)
          ? VibePushPayload(
              client.clientName,
              event.room.id,
              event.eventId,
            ).toString()
          : null,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          VibeSound.channelId,
            sound: VibeSound.sound,
            playSound: VibeSound.playSound,
          'Incoming messages',
          importance: Importance.high,
          priority: Priority.max,
          category: AndroidNotificationCategory.message,
        ),
      ),
    );
    return;
  }

  // You're in another chat right now: their picture peeks in above the
  // typing bar instead of a notification popping up.
  if (clients != null &&
      activeRoomId != null &&
      activeRoomId != notification.roomId &&
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
    VibePeek.instance.message(event);
    await _markShown(event.eventId);
    return;
  }

  final matrixLocals = MatrixLocals(l10n);

  // Couldn't open the message here (a Firebase wake-up in the background):
  // give Vibe's own connection a moment to show it with the real text, and
  // don't add a second "New message" line if it did.
  if (event.type == EventTypes.Encrypted) {
    await Future<void>.delayed(const Duration(seconds: 4));
    if (await _shownElsewhere(event.eventId)) {
      Logs().v('Push helper: shown by the direct connection already');
      return;
    }
  }
  await _markShown(event.eventId);

  // Calculate the body
  final body = event.type == EventTypes.Encrypted
      ? l10n.newMessageInFluffyChat
      // a view-once message stays hidden until it's opened in the chat
      : event.content['chat.keepr.view_once'] == true
      ? 'View once message'
      : await event.vibeBody(
          matrixLocals,
          plaintextBody: true,
          withSenderNamePrefix: false,
          hideReply: true,
          hideEdit: true,
          removeMarkdown: true,
        );

  // The person object for the android message style notification
  final avatar = event.room.avatar;
  final senderAvatar = event.room.isDirectChat
      ? avatar
      : event.senderFromMemoryOrFallback.avatarUrl;

  final ownUser = event.room.unsafeGetUserFromMemoryOrFallback(client.userID!);

  final userAvatarFile = await client.tryDownloadNotificationAvatar(
    ownUser.avatarUrl,
  );
  final roomAvatarFile = await client.tryDownloadNotificationAvatar(avatar);
  final senderAvatarFile = await client.tryDownloadNotificationAvatar(
    senderAvatar,
  );

  final id = '${client.clientName}_${notification.roomId}'.hashCode;

  final senderName = event.senderFromMemoryOrFallback.calcDisplayname();
  // Show notification

  final newMessage = Message(
    body,
    event.originServerTs,
    Person(
      bot: event.messageType == MessageTypes.Notice,
      key: event.senderId,
      name: senderName,
      icon: senderAvatarFile == null
          ? null
          : ByteArrayAndroidIcon(senderAvatarFile),
    ),
  );

  final messagingStyleInformation = PlatformInfos.isAndroid
      ? await AndroidFlutterLocalNotificationsPlugin()
            .getActiveNotificationMessagingStyle(id: id)
      : null;
  messagingStyleInformation?.messages?.add(newMessage);

  final roomName = event.room.getLocalizedDisplayname(MatrixLocals(l10n));

  final notificationGroupId = event.room.isDirectChat
      ? 'directChats'
      : 'groupChats';
  final groupName = event.room.isDirectChat ? l10n.directChats : l10n.groups;

  final messageRooms = AndroidNotificationChannelGroup(
    notificationGroupId,
    groupName,
  );
  final roomsChannel = AndroidNotificationChannel(
    event.room.id,
    roomName,
    groupId: notificationGroupId,
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannelGroup(messageRooms);
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(roomsChannel);

  final androidPlatformChannelSpecifics = AndroidNotificationDetails(
    VibeSound.channelId,
            sound: VibeSound.sound,
            playSound: VibeSound.playSound,
    l10n.incomingMessages,
    number: notification.counts?.unread,
    category: AndroidNotificationCategory.message,
    shortcutId: event.room.id,
    styleInformation:
        messagingStyleInformation ??
        MessagingStyleInformation(
          Person(
            name: ownUser.calcDisplayname(),
            icon: userAvatarFile == null
                ? null
                : ByteArrayAndroidIcon(userAvatarFile),
            key: event.room.client.userID,
          ),
          conversationTitle: event.room.isDirectChat ? null : roomName,
          groupConversation: !event.room.isDirectChat,
          messages: [newMessage],
        ),
    ticker: event.content['chat.keepr.view_once'] == true
        ? 'View once message'
        : event.vibeBodyFallback(
      matrixLocals,
      plaintextBody: true,
      withSenderNamePrefix: !event.room.isDirectChat,
      hideReply: true,
      hideEdit: true,
      removeMarkdown: true,
    ),
    importance: Importance.high,
    priority: Priority.max,
    groupKey: client.clientName,
    actions: event.type == EventTypes.RoomMember
        ? null
        : <AndroidNotificationAction>[
            AndroidNotificationAction(
              VibeNotificationActions.reply.name,
              l10n.reply,
              inputs: [
                AndroidNotificationActionInput(label: l10n.writeAMessage),
              ],
              allowGeneratedReplies: true,
              semanticAction: SemanticAction.reply,
            ),
            AndroidNotificationAction(
              VibeNotificationActions.markAsRead.name,
              l10n.markAsRead,
              semanticAction: SemanticAction.markAsRead,
            ),
            // No "Mute" button here: it sat right next to Reply / Mark as read
            // and a stray tap silently muted the chat. Mute is in the chat menu.
          ],
  );
  final iOSAttachmentPath = PlatformInfos.isIOS
      ? await client.getIosNotificationAvatar(event.room.avatar)
      : null;
  final iOSPlatformChannelSpecifics = DarwinNotificationDetails(
    threadIdentifier: '${notification.clientName}_${notification.roomId}',
    attachments: iOSAttachmentPath == null
        ? null
        : [
            DarwinNotificationAttachment(
              iOSAttachmentPath,
              identifier: 'image',
            ),
          ],
  );
  final platformChannelSpecifics = NotificationDetails(
    android: androidPlatformChannelSpecifics,
    iOS: iOSPlatformChannelSpecifics,
  );

  final title = event.room.getLocalizedDisplayname(MatrixLocals(l10n));

  if (PlatformInfos.isAndroid && messagingStyleInformation == null) {
    await _setShortcut(event, l10n, title, roomAvatarFile);
  }

  final needsTitleAndBody = !PlatformInfos.isAndroid;

  await flutterLocalNotificationsPlugin.show(
    id: notification.notificationId,
    title: needsTitleAndBody ? title : null,
    body: needsTitleAndBody ? body : null,
    notificationDetails: platformChannelSpecifics,
    payload: VibePushPayload(
      client.clientName,
      event.room.id,
      event.eventId,
    ).toString(),
  );

  // Send summary notification on Android
  if (PlatformInfos.isAndroid) {
    await updateSummaryNotification(
      clientName: client.clientName,
      l10n: l10n,
      flutterLocalNotificationsPlugin: flutterLocalNotificationsPlugin,
    );
  }
  Logs().v('Push helper has been completed!');
}

void updateAppBadge(int unreadCount) {
  if (PlatformInfos.isAndroid || PlatformInfos.isMacOS || PlatformInfos.isIOS) {
    if (unreadCount == 0) {
      FlutterNewBadger.removeBadge();
    } else {
      FlutterNewBadger.setBadge(unreadCount);
    }
    return;
  }
}

Future<void> updateSummaryNotification({
  required FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin,
  required String clientName,
  required L10n l10n,
}) async {
  final activeNotifications =
      (await flutterLocalNotificationsPlugin.getActiveNotifications())
          .where((n) => n.groupKey == clientName)
          .toList();

  if (activeNotifications.length <= 1) {
    await flutterLocalNotificationsPlugin.cancel(id: clientName.hashCode);
    return;
  }

  if (activeNotifications.any(
    (notification) => notification.id == clientName.hashCode,
  )) {
    // Already have a visible summary notification!
    return;
  }

  await flutterLocalNotificationsPlugin.show(
    id: clientName.hashCode,
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        VibeSound.channelId,
            sound: VibeSound.sound,
            playSound: VibeSound.playSound,
        l10n.incomingMessages,
        groupKey: clientName,
        setAsGroupSummary: true,
        styleInformation: InboxStyleInformation(
          activeNotifications.map((n) => n.body ?? '').toList(),
        ),
        autoCancel: false,
      ),
    ),
  );
}

class VibePushPayload {
  final String? clientName, roomId, eventId;

  VibePushPayload(this.clientName, this.roomId, this.eventId);

  factory VibePushPayload.fromString(String payload) {
    final parts = payload.split('|');
    if (parts.length != 3) {
      return VibePushPayload(null, null, null);
    }
    return VibePushPayload(parts.first, parts[1], parts[2]);
  }

  @override
  String toString() => '$clientName|$roomId|$eventId';
}

/// Creates a shortcut for Android platform but does not block displaying the
/// notification. This is optional but provides a nicer view of the
/// notification popup.
Future<void> _setShortcut(
  Event event,
  L10n l10n,
  String title,
  Uint8List? avatarFile,
) async {
  final flutterShortcuts = FlutterShortcuts();
  await flutterShortcuts.initialize(debug: !kReleaseMode);
  await flutterShortcuts.pushShortcutItem(
    shortcut: ShortcutItem(
      id: event.room.id,
      action: AppConfig.inviteLinkPrefix + event.room.id,
      shortLabel: title,
      conversationShortcut: true,
      icon: avatarFile == null ? null : base64Encode(avatarFile),
      shortcutIconAsset: avatarFile == null
          ? ShortcutIconAsset.androidAsset
          : ShortcutIconAsset.memoryAsset,
      isImportant: event.room.isFavourite,
    ),
  );
}

extension on PushNotification {
  String? get clientName =>
      devices?.firstOrNull?.data?.tryGet<String>('client_name');
  int get notificationId {
    final roomId = this.roomId;
    if (roomId == null) return 0;
    final clientName = this.clientName;
    if (clientName == null) return roomId.hashCode;
    return '${clientName}_$roomId'.hashCode;
  }
}

/// When a chat is read (here or on another device), its notification goes
/// away. Called on every sync while Keepr is running.
Future<void> cancelNotificationsOnSync(
  SyncUpdate syncUpdate,
  String clientName,
  String userId,
  L10n l10n,
  FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin,
) async {
  if (!PlatformInfos.isMobile) return;
  bool readByMe(Object? value) =>
      value is Map<String, Object?> &&
      (value.tryGetMap<String, Object?>('m.read')?.keys.contains(userId) ==
              true ||
          value
                  .tryGetMap<String, Object?>('m.read.private')
                  ?.keys
                  .contains(userId) ==
              true);
  final readRoomIds =
      syncUpdate.rooms?.join?.entries
          .where(
            (entry) =>
                (entry.value.ephemeral?.any(
                      (event) =>
                          event.type == 'm.receipt' &&
                          event.content.values.any(readByMe),
                    ) ??
                    false) &&
                entry.value.unreadNotifications?.notificationCount == 0,
          )
          .map((entry) => entry.key)
          .toSet() ??
      {};
  if (readRoomIds.isEmpty) return;
  try {
    for (final roomId in readRoomIds) {
      await flutterLocalNotificationsPlugin.cancel(
        id: '${clientName}_$roomId'.hashCode,
      );
    }
    if (PlatformInfos.isAndroid) {
      await updateSummaryNotification(
        clientName: clientName,
        flutterLocalNotificationsPlugin: flutterLocalNotificationsPlugin,
        l10n: l10n,
      );
    }
  } catch (e) {
    Logs().w('Could not clear read notifications', e);
  }
}

/// Rings with the phone's call screen until it's answered (here or on
/// another device), declined, or the caller gives up.
Future<void> _showIncomingCall(Event event, L10n l10n) async {
  final callId = '${event.room.id}|${event.room.client.clientName}';
  final activeCalls = await FlutterCallkitIncoming.activeCalls();
  if (activeCalls.any((call) => call.id == callId)) {
    Logs().d('Already ringing for this call', callId);
    return;
  }
  final intentStr = event.content.tryGet<String>('m.call.intent');
  final intent =
      MatrixRtcCallIntent.values.singleWhereOrNull(
        (i) => i.name == intentStr,
      ) ??
      MatrixRtcCallIntent.video;
  final timeout =
      event.tryParseRtcNotificationContent()?.lifetime ??
      RtcNotificationContent.defaultLifetime;
  final params = await buildCallKitParams(
    event.room,
    l10n: l10n,
    intent: intent,
    timeout: timeout,
  );
  final until = DateTime.now().add(timeout);
  await FlutterCallkitIncoming.showCallkitIncoming(params);

  while (DateTime.now().isBefore(until)) {
    await event.room.client.oneShotSync();
    if (!event.room.hasActiveMatrixRtcCall) {
      Logs().i('The other side ended the call');
      await FlutterCallkitIncoming.endCall(params.id);
      break;
    }
    if (event.room.ownMatrixRtcMembership != null) break;
    if (event.room.getActiveMatrixRtcMembers().any(
      (member) =>
          member.senderId == event.room.client.userID! &&
          member.deviceId != event.room.client.deviceID!,
    )) {
      Logs().i('Answered on another device');
      await FlutterCallkitIncoming.endCall(params.id);
      break;
    }
  }
}

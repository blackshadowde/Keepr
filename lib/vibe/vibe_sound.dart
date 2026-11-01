// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:vibe/config/app_config.dart';
import 'package:vibe/config/setting_keys.dart';

/// Keepr's own notification sounds (android/app/src/main/res/raw), picked in
/// Settings > Notifications. Android fixes a channel's sound once it exists,
/// so every sound has its own channel.
abstract class VibeSound {
  static const options = <String, String>{
    'keepr_chime': 'Keepr chime',
    'keepr_pop': 'Pop',
    'keepr_bell': 'Bell',
    'keepr_pluck': 'Pluck',
    'system': 'Phone default',
    'silent': 'Silent',
  };

  static String get current {
    final v = AppSettings.vibeNotificationSound.value;
    return options.containsKey(v) ? v : 'keepr_chime';
  }

  static String get channelId => current == 'system'
      ? AppConfig.pushNotificationsChannelId
      : '${AppConfig.pushNotificationsChannelId}_$current';

  static bool get playSound => current != 'silent';

  static AndroidNotificationSound? get sound => current.startsWith('keepr_')
      ? RawResourceAndroidNotificationSound(current)
      : null;

  /// Plays the picked sound as a test notification.
  static Future<void> test() async {
    try {
      await FlutterLocalNotificationsPlugin().show(
        id: 4242,
        title: 'Keepr',
        body: 'This is how new messages sound.',
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            'Incoming messages',
            importance: Importance.high,
            sound: sound,
            playSound: playSound,
          ),
        ),
      );
    } catch (_) {}
  }
}

/// Settings row: pick the sound, hear it.
class VibeSoundTile extends StatefulWidget {
  const VibeSoundTile({super.key});

  @override
  State<VibeSoundTile> createState() => _VibeSoundTileState();
}

class _VibeSoundTileState extends State<VibeSoundTile> {
  @override
  Widget build(BuildContext context) => ListTile(
    title: const Text('Notification sound'),
    subtitle: Text(VibeSound.options[VibeSound.current]!),
    trailing: IconButton(
      tooltip: 'Play',
      icon: const Icon(Icons.play_arrow_rounded),
      onPressed: VibeSound.test,
    ),
    onTap: () async {
      final picked = await showDialog<String>(
        context: context,
        builder: (c) => SimpleDialog(
          title: const Text('Notification sound'),
          children: [
            for (final e in VibeSound.options.entries)
              RadioListTile<String>(
                value: e.key,
                groupValue: VibeSound.current,
                title: Text(e.value),
                onChanged: (v) => Navigator.of(c).pop(v),
              ),
          ],
        ),
      );
      if (picked == null) return;
      await AppSettings.vibeNotificationSound.setItem(picked);
      if (mounted) setState(() {});
      await VibeSound.test();
    },
  );
}

// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:matrix/matrix.dart';

import 'package:vibe/config/setting_keys.dart';
import 'package:vibe/utils/platform_infos.dart';
import 'package:vibe/vibe/vibe_settings_style.dart';

/// Keepr's sound packs: one set of sounds for calls (someone joins or
/// leaves, waiting, attention), for sending and receiving messages, and for
/// notifications. Picked in Settings > Notifications.
abstract class VibeSoundPack {
  static const packs = <String, String>{
    'glass': 'Glass',
    'wood': 'Wood',
    'air': 'Air',
    'classic': 'Classic',
  };

  static const about = <String, String>{
    'glass': 'Clear and light',
    'wood': 'Warm and round',
    'air': 'Soft and breathy',
    'classic': 'The earlier call sounds',
  };

  static String get current {
    final v = AppSettings.vibeSoundPack.value;
    return packs.containsKey(v) ? v : 'glass';
  }

  /// join, leave, wait, attention, notification, sent or received.
  static String asset(String kind, [String? pack]) =>
      'assets/sounds/${pack ?? current}/$kind.mp3';

  /// Message sounds only play on Android and the web for now: on iPhones
  /// they would stop music playing in other apps.
  static bool get messageSounds => !PlatformInfos.isIOS;

  static AudioPlayer? _player;
  static final Map<String, DateTime> _played = {};

  /// A short sound that plays along with music instead of pausing it, at
  /// the phone's notification volume (silent mode keeps it quiet).
  static Future<void> play(String kind, {String? pack}) async {
    if (!messageSounds) return;
    try {
      final player = _player ??= await _newPlayer();
      await player.setAsset(asset(kind, pack));
      await player.play();
    } catch (e) {
      Logs().v('Sound pack: could not play $kind', e);
    }
  }

  static Future<AudioPlayer> _newPlayer() async {
    final player = AudioPlayer(
      handleInterruptions: false,
      androidApplyAudioAttributes: false,
      handleAudioSessionActivation: false,
    );
    if (PlatformInfos.isAndroid) {
      await player.setAndroidAudioAttributes(
        const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.sonification,
          usage: AndroidAudioUsage.notificationEvent,
        ),
      );
    }
    await player.setVolume(0.8);
    return player;
  }

  /// A message that just appeared in the open chat: yours as it goes out,
  /// theirs as it comes in (unless the chat is muted). Edits and reactions
  /// stay quiet.
  static void onNewEvent(Event event) {
    if (!messageSounds) return;
    if (event.type != EventTypes.Message &&
        event.type != EventTypes.Sticker &&
        event.type != EventTypes.Encrypted) {
      return;
    }
    final rel = event.relationshipType;
    if (rel == RelationshipTypes.edit || rel == RelationshipTypes.reaction) {
      return;
    }
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    final room = event.room;
    if (event.senderId == room.client.userID) {
      if (!AppSettings.vibeSentSound.value) return;
      if (event.status != EventStatus.sending) return;
      _once('sent');
    } else {
      if (!AppSettings.vibeReceivedSound.value) return;
      if (room.pushRuleState != PushRuleState.notify) return;
      _once('received');
    }
  }

  // many messages at once (after being offline) make one sound
  static void _once(String kind) {
    final now = DateTime.now();
    final last = _played[kind];
    if (last != null && now.difference(last).inMilliseconds < 800) return;
    _played[kind] = now;
    unawaited(play(kind));
  }
}

/// Settings row: pick the sound pack, hear each one.
class VibeSoundPackTile extends StatefulWidget {
  /// Called after a pack is picked (the notification sound may follow it).
  final VoidCallback? onPicked;
  const VibeSoundPackTile({this.onPicked, super.key});

  @override
  State<VibeSoundPackTile> createState() => _VibeSoundPackTileState();
}

class _VibeSoundPackTileState extends State<VibeSoundPackTile> {
  @override
  Widget build(BuildContext context) => VibeSettingsRow(
    icon: Icons.library_music_rounded,
    title: 'Sound pack',
    subtitle:
        '${VibeSoundPack.packs[VibeSoundPack.current]}: calls, messages and '
        'notifications',
    onTap: () async {
      final picked = await showDialog<String>(
        context: context,
        builder: (c) => SimpleDialog(
          title: const Text('Sound pack'),
          children: [
            for (final e in VibeSoundPack.packs.entries)
              RadioListTile<String>(
                value: e.key,
                groupValue: VibeSoundPack.current,
                title: Text(e.value),
                subtitle: Text(VibeSoundPack.about[e.key]!),
                secondary: IconButton(
                  tooltip: 'Play',
                  icon: const Icon(Icons.play_arrow_rounded),
                  onPressed: () => VibeSoundPack.play('received', pack: e.key),
                ),
                onChanged: (v) => Navigator.of(c).pop(v),
              ),
          ],
        ),
      );
      if (picked == null) return;
      await AppSettings.vibeSoundPack.setItem(picked);
      if (mounted) setState(() {});
      widget.onPicked?.call();
      unawaited(VibeSoundPack.play('received'));
    },
  );
}

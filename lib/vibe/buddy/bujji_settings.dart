// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:vibe/config/setting_keys.dart';
import 'package:vibe/vibe/buddy/bujji.dart';
import 'package:vibe/vibe/buddy/vibe_buddy.dart' show VibeBuddyPage;
import 'package:vibe/vibe/vibe_backup.dart';
import 'package:vibe/vibe/vibe_settings_style.dart';
import 'package:vibe/vibe/vibe_swipe.dart';
import 'package:vibe/vibe/vibe_typing_style.dart';
import 'package:vibe/vibe/vibe_updates_page.dart';
import 'package:vibe/widgets/theme_builder.dart';
import 'package:vibe/widgets/vibe_app.dart';

/// A place in Settings Bujji knows: its name, the page it's on, other words
/// for it, how to get there, and the switch behind it when it has a simple
/// one.
@immutable
class BujjiSetting {
  final String name;
  final String page;
  final String words;
  final String? route;
  final void Function(BuildContext context)? open;
  final AppSettings<bool>? toggle;
  const BujjiSetting(
    this.name,
    this.page,
    this.words, {
    this.route,
    this.open,
    this.toggle,
  });
}

/// "@bujji open notifications settings", "@bujji turn on dark mode",
/// "@bujji search typing indicators in settings". Plain word matching on
/// the phone.
abstract class BujjiSettings {
  static const _s = '/rooms/settings';
  static const _style = 'Customisation';
  static const _chat = 'Chats & storage';
  static const _notif = 'Notifications';
  static const _sec = 'Security & sign-in';

  static void _typing(BuildContext c) => VibeTypingStylePage.open(c);
  static void _buddy(BuildContext c) => VibeBuddyPage.open(c);
  static void _updates(BuildContext c) => VibeUpdatesPage.open(c);
  static void _backup(BuildContext c) => Navigator.of(c).push(
    VibeSheetPageRoute(
      builder: (_) => const VibeSettingsTheme(child: VibeBackupPage()),
    ),
  );

  static const all = <BujjiSetting>[
    BujjiSetting('Settings', 'Settings', 'all preferences', route: _s),
    BujjiSetting(
      'Account',
      'Settings',
      'profile name display picture photo avatar',
      route: _s,
    ),
    // notifications
    BujjiSetting(
      'Notifications',
      _notif,
      'notification alerts push sound tone chime ringtone',
      route: '$_s/notifications',
    ),
    BujjiSetting(
      'Pop-ups for muted chats',
      _notif,
      'popup muted mute notification',
      route: '$_s/notifications',
      toggle: AppSettings.vibeMutedPopups,
    ),
    BujjiSetting(
      'Notification privacy',
      _notif,
      'hide content preview message text notification private',
      route: '$_s/notifications',
      toggle: AppSettings.vibeHideNotificationContent,
    ),
    // customisation
    BujjiSetting(
      _style,
      _style,
      'style look appearance theme design',
      route: '$_s/style',
    ),
    BujjiSetting(
      'Theme: light, dark or system',
      _style,
      'dark mode light mode night system theme',
      route: '$_s/style',
    ),
    BujjiSetting(
      'Colour',
      _style,
      'color colour accent theme wallpaper material glass',
      route: '$_s/style',
    ),
    BujjiSetting(
      'Chat wallpaper',
      _style,
      'wallpaper background chat',
      route: '$_s/style',
    ),
    BujjiSetting(
      'Text size',
      _style,
      'font size bigger smaller text letters zoom',
      route: '$_s/style',
    ),
    BujjiSetting(
      'Haptic feedback',
      _style,
      'haptics vibration vibrate taps',
      route: '$_s/style',
      toggle: AppSettings.vibeHaptics,
    ),
    BujjiSetting(
      'Keep the chat you leave docked',
      _style,
      'dock docked chat bubble',
      route: '$_s/style',
      toggle: AppSettings.vibeChatDock,
    ),
    BujjiSetting(
      'Start-up animation',
      _style,
      'startup intro splash animation boot',
      route: '$_s/style',
      toggle: AppSettings.vibeBootIntro,
    ),
    BujjiSetting(
      'Typing indicator',
      _style,
      'typing indicator dots emoji others see while you type style',
      open: _typing,
    ),
    BujjiSetting(
      'Typing buddy',
      _style,
      'bujji buddy typing outfits outfit mascot',
      open: _buddy,
    ),
    // chats & storage
    BujjiSetting(
      _chat,
      _chat,
      'chat chats storage messages',
      route: '$_s/chat',
    ),
    BujjiSetting(
      'Low data mode',
      _chat,
      'data saver mobile data low',
      route: '$_s/chat',
      toggle: AppSettings.vibeLowData,
    ),
    BujjiSetting(
      'Formatted messages',
      _chat,
      'formatting html markdown bold',
      route: '$_s/chat',
      toggle: AppSettings.renderHtml,
    ),
    BujjiSetting(
      'Hide deleted messages',
      _chat,
      'hide redacted deleted removed messages',
      route: '$_s/chat',
      toggle: AppSettings.hideRedactedEvents,
    ),
    BujjiSetting(
      'Hide chats that are in a space',
      _chat,
      'hide rooms spaces',
      route: '$_s/chat',
      toggle: AppSettings.hideRoomsInSpaces,
    ),
    BujjiSetting(
      'Hide unknown messages',
      _chat,
      'hide invalid unknown message formats events',
      route: '$_s/chat',
      toggle: AppSettings.hideUnknownEvents,
    ),
    BujjiSetting(
      'Autoplay animated stickers',
      _chat,
      'autoplay animated gif stickers emotes play',
      route: '$_s/chat',
      toggle: AppSettings.autoplayImages,
    ),
    BujjiSetting(
      'Save media to gallery',
      _chat,
      'save photos videos gallery download media',
      route: '$_s/chat',
    ),
    BujjiSetting(
      'Storage & cache',
      _chat,
      'storage cache space clear free memory media',
      route: '$_s/chat',
    ),
    BujjiSetting(
      'Status bubble in chats',
      _chat,
      'status bubble mood',
      route: '$_s/chat',
      toggle: AppSettings.vibeStatusBubble,
    ),
    BujjiSetting(
      'Send on Enter',
      _chat,
      'enter key send keyboard',
      route: '$_s/chat',
      toggle: AppSettings.sendOnEnter,
    ),
    BujjiSetting(
      'Swipe right to left to reply',
      _chat,
      'swipe reply gesture',
      route: '$_s/chat',
      toggle: AppSettings.swipeRightToLeftToReply,
    ),
    BujjiSetting(
      'Native calls',
      _chat,
      'calls calling voice video call',
      route: '$_s/chat',
    ),
    BujjiSetting(
      'Show thumbnails',
      _chat,
      'thumbnails previews images videos',
      route: '$_s/chat',
      toggle: AppSettings.showThumbnailsInTimeline,
    ),
    BujjiSetting(
      'Double tap to react',
      _chat,
      'double tap react reaction like',
      route: '$_s/chat',
      toggle: AppSettings.doubleTapToReact,
    ),
    BujjiSetting(
      'Custom emoji and stickers',
      _chat,
      'emoji emojis emotes stickers custom pack',
      route: '$_s/chat/emotes',
    ),
    BujjiSetting(
      'Text stickers while typing',
      _chat,
      'text stickers typing suggestions',
      route: '$_s/chat',
      toggle: AppSettings.vibeTextStickers,
    ),
    // security & sign-in
    BujjiSetting(
      _sec,
      _sec,
      'security privacy sign in login',
      route: '$_s/security',
    ),
    BujjiSetting(
      'Send typing notifications',
      _sec,
      'typing indicator indicators show typing others see you type privacy',
      route: '$_s/security',
      toggle: AppSettings.sendTypingNotifications,
    ),
    BujjiSetting(
      'Send read receipts',
      _sec,
      'read receipts seen ticks privacy',
      route: '$_s/security',
      toggle: AppSettings.sendPublicReadReceipts,
    ),
    BujjiSetting(
      'Link previews',
      _sec,
      'link previews url preview',
      route: '$_s/security',
      toggle: AppSettings.vibeLinkPreviews,
    ),
    BujjiSetting(
      'Link previews in encrypted chats',
      _sec,
      'link previews encrypted',
      route: '$_s/security',
    ),
    BujjiSetting(
      'Blocked users',
      _sec,
      'block blocked ignore ignored people',
      route: '$_s/security/ignorelist',
    ),
    BujjiSetting(
      'App lock',
      _sec,
      'lock pin passcode password biometric fingerprint face unlock',
      route: '$_s/security',
    ),
    BujjiSetting(
      'Password and email',
      _sec,
      'password email change',
      route: '$_s/security/password',
    ),
    BujjiSetting(
      'Delete account',
      _sec,
      'delete deactivate account remove',
      route: '$_s/security',
    ),
    BujjiSetting(
      'Encryption & keys',
      'Encryption & keys',
      'encryption keys recovery key backup post quantum pq secure',
      route: '$_s/vibe-encryption',
    ),
    BujjiSetting(
      'Devices',
      'Devices',
      'devices sessions logged in phones computers verify',
      route: '$_s/devices',
    ),
    BujjiSetting(
      'Server',
      'Server',
      'homeserver server matrix',
      route: '$_s/homeserver',
    ),
    BujjiSetting(
      'Backups',
      'Settings',
      'backup backups restore export auto',
      open: _backup,
    ),
    BujjiSetting(
      'Updates',
      'Settings',
      'update updates new version upgrade',
      open: _updates,
    ),
    BujjiSetting(
      'About Keepr',
      'About',
      'about version licenses info',
      route: '$_s/vibe-about',
    ),
  ];

  static const _skip = {
    'open', 'go', 'to', 'goto', 'show', 'me', 'take', 'launch', 'bring',
    'up', 'the', 'my', 'a', 'an', 'in', 'on', 'off', 'of', 'for', 'page',
    'screen', 'setting', 'option', 'preference', 'search', 'find', 'look',
    'where', 'is', 'are', 'whats', 'what', 'turn', 'switch', 'enable',
    'disable', 'set', 'toggle', 'please', 'app', 'keepr', 'can', 'you',
    'i', 'change', 'menu', 'section', 'do', 'how', 'with', 'it', 'and',
  };

  static List<String> _words(String s) => [
    for (final w in s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), ' ').split(' '))
      if (w.isNotEmpty) _one(w),
  ].where((w) => !_skip.contains(w)).toList();

  /// "indicators" → "indicator", "notifications" → "notification".
  static String _one(String w) =>
      w.length > 4 && w.endsWith('s') && !w.endsWith('ss')
      ? w.substring(0, w.length - 1)
      : w;

  static bool _near(String a, String b) {
    if ((a.length - b.length).abs() > 1) return false;
    final d = List.generate(a.length + 1, (i) => List.filled(b.length + 1, 0));
    for (var i = 0; i <= a.length; i++) {
      d[i][0] = i;
    }
    for (var j = 0; j <= b.length; j++) {
      d[0][j] = j;
    }
    for (var i = 1; i <= a.length; i++) {
      for (var j = 1; j <= b.length; j++) {
        d[i][j] = math.min(
          math.min(d[i - 1][j] + 1, d[i][j - 1] + 1),
          d[i - 1][j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1),
        );
      }
    }
    return d[a.length][b.length] <= (a.length >= 8 ? 2 : 1);
  }

  /// The settings that match [q], best first. [strict]: every word you
  /// said has to fit.
  static List<BujjiSetting> find(String q, {bool strict = false}) {
    final want = _words(q);
    if (want.isEmpty) return const [];
    final said = want.join(' ');
    final scored = <(double, BujjiSetting)>[];
    for (final s in all) {
      final name = _words(s.name);
      final have = {...name, ..._words(s.words)};
      var hit = 0.0;
      for (final w in want) {
        if (have.contains(w)) {
          hit += 1;
        } else if (w.length >= 4 &&
            have.any((h) => h.length >= 4 && (h.startsWith(w) || w.startsWith(h)))) {
          hit += 0.7;
        } else if (w.length >= 5 && have.any((h) => _near(h, w))) {
          hit += 0.6;
        } else if (strict) {
          hit = 0;
          break;
        }
      }
      if (hit == 0) continue;
      var score = hit / want.length;
      final full = name.join(' ');
      if (said == full) {
        score += 1;
      } else if (full.contains(said) || said.contains(full)) {
        score += 0.4;
      }
      // words in its name count a little more than other words for it
      score += 0.1 * want.where(name.contains).length;
      scored.add((score, s));
    }
    scored.sort((a, b) => b.$1.compareTo(a.$1));
    return [
      for (final x in scored)
        if (x.$1 >= 0.6) x.$2,
    ];
  }

  static void _go(BujjiSetting s) {
    // a moment, so the answer shows before the page opens
    Future.delayed(const Duration(milliseconds: 250), () {
      final c = VibeApp.router.routerDelegate.navigatorKey.currentContext;
      if (c == null || !c.mounted) return;
      final open = s.open;
      if (open != null) {
        open(c);
      } else if (s.route != null) {
        VibeApp.router.push(s.route!);
      }
    });
  }

  static void _theme(ThemeMode mode) {
    final c = VibeApp.router.routerDelegate.navigatorKey.currentContext;
    if (c == null) return;
    ThemeController.of(c).setThemeMode(mode);
  }

  static String _where(BujjiSetting s) =>
      s.page == s.name || s.page == 'Settings' ? s.name : '${s.name} (${s.page})';

  /// A button under the answer: open one of the settings found.
  static BujjiReply choose(String id) {
    final i = int.tryParse(id.substring(4));
    if (i == null || i < 0 || i >= all.length) {
      return const BujjiReply("I can't find that any more.");
    }
    final s = all[i];
    return BujjiReply('Opening ${s.name}.', act: () => _go(s));
  }

  static BujjiChoice _choice(BujjiSetting s) =>
      BujjiChoice(s.name, 'set:${all.indexOf(s)}');

  /// The answer when [low] is about Settings, else null.
  static BujjiReply? answer(String low) {
    // "remind me to turn on dark mode at 9" is a reminder
    if (low.contains('remind')) return null;
    final off = RegExp(r'\b(off|disable|deactivate|stop|no)\b');
    final asks = RegExp(r'^(is|are|what|how|why)\b').hasMatch(low);
    final settingsWord = RegExp(
      r'\b(settings?|options?|preferences?)\b',
    ).hasMatch(low);

    // dark, light or the phone's own
    final theme = RegExp(
      r'\b(dark|night|light|day|system|auto|automatic)\s*(mode|theme)\b|'
      r'\b(go|switch to|make it|use)\s+(dark|light)\b',
    ).firstMatch(low);
    if (theme != null && !asks) {
      final kind = theme.group(1) ?? theme.group(4)!;
      final mode = switch (kind) {
        'dark' || 'night' => off.hasMatch(low) ? ThemeMode.light : ThemeMode.dark,
        'light' || 'day' => off.hasMatch(low) ? ThemeMode.dark : ThemeMode.light,
        _ => ThemeMode.system,
      };
      _theme(mode);
      return BujjiReply(switch (mode) {
        ThemeMode.dark => 'Dark mode is on.',
        ThemeMode.light => 'Light mode is on.',
        ThemeMode.system => 'Following the phone: light by day, dark at night.',
      });
    }

    // turn something on or off
    final toggle =
        RegExp(r'^(turn|switch|set|put)\s+(on|off)\s+(.+)$').firstMatch(low) ??
        RegExp(r'^(turn|switch|set)\s+(.+?)\s+(on|off)$').firstMatch(low) ??
        RegExp(r'^(enable|disable|activate|deactivate)\s+(.+)$').firstMatch(low) ??
        RegExp(r'^(.+?)\s+(on|off)$').firstMatch(low);
    if (toggle != null && !asks) {
      final what = toggle
          .groups(List.generate(toggle.groupCount, (i) => i + 1))
          .whereType<String>()
          .where((g) => !RegExp(r'^(turn|switch|set|put|on|off|enable|disable|activate|deactivate)$').hasMatch(g))
          .join(' ');
      // on unless the words round it say off
      final value = !off.hasMatch(toggle.group(0)!.replaceFirst(what, ' '));
      final hits = find(what, strict: !settingsWord);
      final best = hits.firstOrNull;
      if (best == null) {
        // "lights off" and the like aren't for Settings
        if (!settingsWord) return null;
        return BujjiReply(
          "I couldn't find a setting called \"$what\".",
          choices: [_choice(all.first)],
        );
      }
      final sw = best.toggle;
      if (sw == null) {
        _go(best);
        return BujjiReply(
          "I can't switch ${best.name} myself. Opening it for you.",
        );
      }
      sw.setItem(value);
      return BujjiReply(
        '${best.name} is ${value ? 'on' : 'off'}.',
        choices: [BujjiChoice('Open ${best.page}', 'set:${all.indexOf(best)}')],
      );
    }

    // look something up in Settings
    final search = RegExp(
      r'^(search|find|look for|look up|where is|where are|wheres|where do i find|where can i find|where can i change|how do i change)\s+(.+)$',
    ).firstMatch(low);
    if (search != null && (settingsWord || low.startsWith('search'))) {
      final what = search.group(2)!
          .replaceAll(RegExp(r'\b(in|on|from)?\s*(the\s+)?(settings?|options?)\b'), ' ')
          .trim();
      final hits = find(what).take(4).toList();
      if (hits.isEmpty) {
        return BujjiReply(
          'Nothing in Settings matches "$what".',
          choices: [_choice(all.first)],
        );
      }
      return BujjiReply(
        hits.length == 1
            ? 'Found it: ${_where(hits.first)}.'
            : 'Found these in Settings:\n${hits.map((s) => '· ${_where(s)}').join('\n')}',
        choices: [for (final s in hits) _choice(s)],
      );
    }

    // open a page
    final open = RegExp(
      r'^(open|show|show me|go to|goto|take me to|launch|bring up)\s+(.+)$',
    ).firstMatch(low);
    final what = open?.group(2) ?? (settingsWord ? low : null);
    if (what == null || asks) return null;
    if (RegExp(r'^(my |the |app )?(settings?|options?|preferences?)$').hasMatch(what)) {
      _go(all.first);
      return const BujjiReply('Opening Settings.');
    }
    final best = find(what, strict: !settingsWord).firstOrNull;
    if (best == null) {
      // "open my notes" and the like are for Bujji, not Settings
      if (!settingsWord) return null;
      return BujjiReply(
        "I couldn't find \"$what\" in Settings.",
        choices: [_choice(all.first)],
      );
    }
    _go(best);
    return BujjiReply('Opening ${_where(best)}.');
  }
}

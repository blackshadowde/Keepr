// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:ui';

abstract class AppConfig {
  static const Color primaryColor = Color(0xFF5865F2);

  static const Color chatColor = primaryColor;
  static const double messageFontSize = 16.0;
  static const bool allowOtherHomeservers = true;
  static const bool enableRegistration = true;
  static const bool hideTypingUsernames = false;

  static const String inviteLinkPrefix = 'https://matrix.to/#/';
  static const String deepLinkPrefix = 'keepr://chat/';
  // Vibe's own share link: opens Vibe (or offers to get it) and starts a chat.
  static const String shareLinkPrefix = 'https://get-keepr.github.io/chat.html#';
  // Keepr's default server as it shows in people's IDs (@rahul:unredacted.org).
  // Its address for signing in is AppSettings.defaultHomeserver.
  static const String defaultServerName = 'unredacted.org';
  // Short link for people on that server: get-keepr.github.io/u/rahul
  static const String shortLinkPrefix = 'https://get-keepr.github.io/u/';
  static String shareLink(String id) {
    final end = ':$defaultServerName';
    final name = id.startsWith('@') && id.endsWith(end)
        ? id.substring(1, id.length - end.length)
        : '';
    return RegExp(r'^[a-z0-9._=\-]+$').hasMatch(name)
        ? '$shortLinkPrefix$name'
        : '$shareLinkPrefix$id';
  }
  static const String schemePrefix = 'matrix:';
  static const String pushNotificationsChannelId = 'fluffychat_push';
  static const String pushNotificationsAppId = 'app.keepr.chat';
  static const double borderRadius = 18.0;
  static const double spaceBorderRadius = 11.0;
  static const double columnWidth = 360.0;

  static const String enablePushTutorial =
      'https://get-keepr.github.io/faq.html#push_without_google_services';
  static const String encryptionTutorial =
      'https://get-keepr.github.io/faq.html#how_to_use_end_to_end_encryption';
  static const String startChatTutorial =
      'https://get-keepr.github.io/faq.html#how_do_i_find_other_users';
  static const String howDoIGetStickersTutorial =
      'https://get-keepr.github.io/faq.html#how_do_i_get_stickers';
  static const String appId = 'app.keepr.chat';
  static const String appOpenUrlScheme = 'vibe';
  static const String appSsoUrlScheme = 'chat.keepr.auth';

  // Vibe links (Vibe is based on FluffyChat, credited in About Vibe).
  static const String sourceCodeUrl =
      'https://github.com/blackshadowde/Keepr';
  static const String supportUrl =
      'https://github.com/blackshadowde/Keepr/issues';
  static const String changelogUrl =
      'https://github.com/blackshadowde/Keepr/commits/Vibe';
  static const String helpUrl =
      'https://github.com/blackshadowde/Keepr';

  static const Set<String> defaultReactions = {'👍', '❤️', '😂', '😮', '😢'};

  static final Uri newIssueUrl = Uri(
    scheme: 'https',
    host: 'github.com',
    path: '/blackshadowde/Keepr/issues/new',
  );

  static final Uri homeserverList = Uri.parse(
    'https://get-keepr.github.io/homeservers.json',
  );

  static const String mainIsolatePortName = 'main_isolate';
  static const String pushIsolatePortName = 'push_isolate';
  static const String pushHelperCrashReportKey = 'push_helper_crash_report';
}

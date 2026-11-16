// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:vibe/vibe/vibe_own_profile.dart';
import 'package:vibe/vibe/vibe_settings_search.dart';
import 'package:vibe/vibe/vibe_swipe.dart';
import 'package:vibe/vibe/vibe_backup.dart';
import 'package:vibe/vibe/vibe_motion.dart';
import 'package:vibe/vibe/vibe_settings_style.dart';
import 'package:vibe/vibe/vibe_support.dart';
import 'package:vibe/vibe/vibe_updater.dart';
import 'package:vibe/vibe/vibe_updates_page.dart';
import 'package:async/async.dart';
import 'package:vibe/config/setting_keys.dart';
import 'package:vibe/l10n/l10n.dart';
import 'package:vibe/widgets/avatar.dart';
import 'package:vibe/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart' hide Result;
import 'package:url_launcher/url_launcher.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'settings.dart';

class SettingsView extends StatelessWidget {
  final SettingsController controller;

  const SettingsView(this.controller, {super.key});

  static final _version = VibeUpdater.currentVersion();

  /// Devices, your server, your account on the server, privacy.
  void _devicesSheet(BuildContext context) {
    final client = Matrix.of(context).client;
    showVibeSheet<void>(
      sheetAnimationStyle: vibeSheetStyle,
      context: context,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              VibeSettingsRow(
                icon: Icons.devices_outlined,
                title: L10n.of(context).devices,
                subtitle: 'Where you are signed in',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  context.go('/rooms/settings/devices');
                },
              ),
              VibeSettingsRow(
                icon: Icons.dns_outlined,
                title: 'Your server',
                subtitle: client.userID?.domain,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  context.go('/rooms/settings/homeserver');
                },
              ),
              FutureBuilder(
                future: Result.capture(
                  client.getAuthMetadata(),
                ).then((result) => result.asValue?.value),
                builder: (context, snapshot) {
                  final url = snapshot.data?.accountManagementUri;
                  if (url == null) return const SizedBox.shrink();
                  return VibeSettingsRow(
                    icon: Icons.open_in_new_rounded,
                    title: L10n.of(context).manageAccount,
                    onTap: () =>
                        launchUrl(url, mode: LaunchMode.inAppBrowserView),
                  );
                },
              ),
              VibeSettingsRow(
                icon: Icons.privacy_tip_outlined,
                title: L10n.of(context).privacy,
                onTap: () => launchUrlString(AppSettings.privacyPolicy.value),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Find a setting by name; opens its page.
  Future<void> _search(BuildContext context) async {
    final s = await VibeSettingsSearch.open(context);
    if (s == null || !context.mounted) return;
    final open = s.open;
    if (open != null) {
      open(context);
    } else if (s.route != null) {
      context.go(s.route!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final backupOk = controller.cryptoIdentityConnected == true;
    final client = Matrix.of(context).client;
    final sub = VibeSettingsStyle.text2(context);
    final font = Theme.of(context).textTheme.bodyLarge ?? const TextStyle();

    return VibeSettingsTheme(
      child: Builder(
        builder: (context) => VibeTitledPage(
          key: const Key('SettingsListViewContent'),
          title: L10n.of(context).settings,
          close: true,
          onLeading: () => context.go('/rooms'),
          children: [
            // you: opens your profile (picture, name, status)
            FutureBuilder<Profile>(
              future: controller.profileFuture,
              builder: (context, snapshot) {
                final profile = snapshot.data;
                final mxid = client.userID ?? L10n.of(context).user;
                final name = profile?.displayName ?? mxid.localpart ?? mxid;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: VibePressable(
                    child: Material(
                      color: VibeSettingsStyle.card(context),
                      borderRadius: BorderRadius.circular(24),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () async {
                          await VibeOwnProfile.show(context, client);
                          controller.updateProfile();
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              Avatar(
                                mxContent: profile?.avatarUrl,
                                name: name,
                                size: 54,
                                client: client,
                                presenceUserId: client.userID,
                                presenceBackgroundColor:
                                    VibeSettingsStyle.card(context),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: font.copyWith(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                        height: 1.2,
                                        color: VibeSettingsStyle.text(context),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      mxid,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: font.copyWith(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w500,
                                        height: 1.3,
                                        color: sub,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Your profile, picture and status',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: font.copyWith(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        height: 1.3,
                                        color: sub,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                size: 22,
                                color: VibeSettingsStyle.chevron(context),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            // find any setting by its name or other words for it
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: VibePressable(
                child: Material(
                  color: VibeSettingsStyle.card(context),
                  borderRadius: BorderRadius.circular(25),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _search(context),
                    child: SizedBox(
                      height: 50,
                      child: Row(
                        children: [
                          const SizedBox(width: 18),
                          Icon(Icons.search_rounded, size: 22, color: sub),
                          const SizedBox(width: 12),
                          Text(
                            'Search settings',
                            style: font.copyWith(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w500,
                              color: sub,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            VibeSettingsGroup(
              title: 'Account',
              rows: [
                VibeSettingsRow(
                  icon: Icons.shield_outlined,
                  title: 'Security & sign-in',
                  subtitle: 'Password, sign-in, blocked people',
                  onTap: () => context.go('/rooms/settings/security'),
                ),
                VibeSettingsRow(
                  icon: Icons.lock_outline_rounded,
                  title: 'Encryption & keys',
                  subtitle: 'Your key backup',
                  value: backupOk ? 'Active' : 'Not set up',
                  dot: backupOk
                      ? VibeSettingsStyle.ok(context)
                      : Theme.of(context).colorScheme.error,
                  onTap: () => context.go('/rooms/settings/vibe-encryption'),
                ),
                VibeSettingsRow(
                  icon: Icons.devices_outlined,
                  title: L10n.of(context).devices,
                  subtitle: 'Where you are signed in, your server',
                  onTap: () => _devicesSheet(context),
                ),
              ],
            ),
            VibeSettingsGroup(
              title: 'App',
              rows: [
                VibeSettingsRow(
                  icon: Icons.notifications_none_rounded,
                  title: 'Notifications',
                  subtitle: 'Sounds, privacy, chats with their own setting',
                  onTap: () => context.go('/rooms/settings/notifications'),
                ),
                VibeSettingsRow(
                  icon: Icons.palette_outlined,
                  title: 'Customisation',
                  subtitle: 'Theme, colours, font, Bujji',
                  onTap: () => context.go('/rooms/settings/style'),
                ),
                VibeSettingsRow(
                  icon: Icons.chat_bubble_outline_rounded,
                  title: 'Chats & storage',
                  subtitle: 'Double tap, media, typing',
                  onTap: () => context.go('/rooms/settings/chat'),
                ),
                VibeSettingsRow(
                  icon: Icons.backup_outlined,
                  title: 'Backups',
                  subtitle: 'Your chats, saved to a file',
                  value: AppSettings.vibeAutoBackup.value == 'off'
                      ? null
                      : 'Auto',
                  onTap: () => Navigator.of(context).push(
                    VibeSheetPageRoute(
                      builder: (_) =>
                          const VibeSettingsTheme(child: VibeBackupPage()),
                    ),
                  ),
                ),
              ],
            ),
            FutureBuilder<String>(
              future: _version,
              builder: (context, version) => VibeSettingsGroup(
                title: 'Keepr',
                rows: [
                  // Google Play build: Play does the updating, no Updates row
                  if (!VibeUpdater.fromPlay)
                    ValueListenableBuilder<VibeRelease?>(
                      valueListenable: VibeUpdater.pending,
                      builder: (context, update, _) => VibeSettingsRow(
                        icon: Icons.system_update_outlined,
                        title: 'Updates',
                        subtitle: version.data == null
                            ? null
                            : 'Keepr ${version.data}',
                        value: update == null ? null : 'Update ready',
                        dot: Theme.of(context).colorScheme.primary,
                        onTap: () => VibeUpdatesPage.open(context),
                      ),
                    ),
                  VibeSettingsRow(
                    icon: Icons.favorite_border_rounded,
                    title: 'Support Keepr',
                    onTap: () => VibeSupport.open(context),
                  ),
                  VibeSettingsRow(
                    icon: Icons.info_outline_rounded,
                    title: 'About Keepr',
                    subtitle: 'Version, licences, privacy',
                    onTap: () => context.go('/rooms/settings/vibe-about'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: VibeCard(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  VibeSettingsRow(
                    icon: Icons.logout_rounded,
                    title: 'Sign out',
                    chevron: false,
                    onTap: controller.logoutAction,
                  ),
                ],
              ),
            ),
            FutureBuilder<String>(
              future: _version,
              builder: (context, version) => Padding(
                padding: const EdgeInsets.only(top: 18),
                child: Text(
                  version.data == null ? '' : 'Keepr ${version.data}',
                  textAlign: TextAlign.center,
                  style: font.copyWith(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: sub,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:vibe/vibe/vibe_dialog.dart';
import 'dart:convert';
import 'package:vibe/config/app_config.dart';
import 'package:vibe/l10n/l10n.dart';
import 'package:vibe/vibe/vibe_push_rules.dart';
import 'package:vibe/utils/localized_exception_extension.dart';
import 'package:vibe/widgets/adaptive_dialogs/adaptive_dialog_action.dart';
import 'package:vibe/widgets/adaptive_dialogs/show_modal_action_popup.dart';
import 'package:vibe/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:vibe/widgets/future_loading_dialog.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:vibe/widgets/matrix.dart';
import 'package:vibe/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:vibe/vibe/vibe_settings_style.dart';
import 'package:vibe/config/setting_keys.dart';
import 'package:vibe/config/themes.dart';
import 'package:vibe/utils/background_push.dart';
import 'package:vibe/utils/platform_infos.dart';
import 'package:vibe/utils/push_helper.dart';
import 'package:vibe/vibe/vibe_push_mode_tiles.dart';
import 'package:vibe/vibe/vibe_sound.dart';
import 'package:vibe/widgets/avatar.dart';
import 'package:flutter/foundation.dart';
import 'package:unifiedpush/unifiedpush.dart';
import 'package:unifiedpush_ui/unifiedpush_ui.dart';

class VibeNotificationsPage extends StatefulWidget {
  const VibeNotificationsPage({super.key});

  @override
  _VibeNotificationsPageState createState() =>
      _VibeNotificationsPageState();
}

class _VibeNotificationsPageState extends State<VibeNotificationsPage> {
  bool isLoading = false;

  Future<void> onPusherTap(Pusher pusher) async {
    final delete = await showModalActionPopup<bool>(
      context: context,
      title: pusher.deviceDisplayName,
      message: '${pusher.appDisplayName} (${pusher.appId})',
      cancelLabel: L10n.of(context).cancel,
      actions: [
        AdaptiveModalAction(
          label: L10n.of(context).delete,
          isDestructive: true,
          value: true,
        ),
      ],
    );
    if (delete != true) return;
    if (!mounted) return;

    final success = await showFutureLoadingDialog(
      context: context,
      future: () => Matrix.of(context).client.deletePusher(
        PusherId(appId: pusher.appId, pushkey: pusher.pushkey),
      ),
    );

    if (success.error != null) return;

    setState(() {
      pusherFuture = null;
    });
  }

  Future<List<Pusher>?>? pusherFuture;

  Future<void> togglePushRule(PushRuleKind kind, PushRule pushRule) async {
    setState(() {
      isLoading = true;
    });
    try {
      final updateFromSync = Matrix.of(context).client.onSync.stream
          .where(
            (syncUpdate) =>
                syncUpdate.accountData?.any(
                  (accountData) => accountData.type == 'm.push_rules',
                ) ??
                false,
          )
          .first;
      await Matrix.of(
        context,
      ).client.setPushRuleEnabled(kind, pushRule.ruleId, !pushRule.enabled);
      await updateFromSync;
    } catch (e, s) {
      Logs().w('Unable to toggle push rule', e, s);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toLocalizedString(context))));
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> editPushRule(PushRule rule, PushRuleKind kind) async {
    final theme = Theme.of(context);
    final action = await showVibeDialog<PushRuleDialogAction>(
      context: context,
      builder: (context) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 256),
        child: AlertDialog.adaptive(
          title: Text(rule.getPushRuleName(L10n.of(context))),
          content: Padding(
            padding: const EdgeInsets.only(top: 16.0),
            child: Material(
              borderRadius: BorderRadius.circular(AppConfig.borderRadius),
              color: theme.colorScheme.surfaceContainer,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                scrollDirection: Axis.horizontal,
                child: SelectableText(
                  prettyJson(rule.toJson()),
                  style: TextStyle(color: theme.colorScheme.onSurface),
                ),
              ),
            ),
          ),
          actions: [
            AdaptiveDialogAction(
              onPressed: Navigator.of(context).pop,
              child: Text(L10n.of(context).close),
            ),
            if (!rule.ruleId.startsWith('.m.'))
              AdaptiveDialogAction(
                onPressed: () =>
                    Navigator.of(context).pop(PushRuleDialogAction.delete),
                child: Text(
                  L10n.of(context).delete,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
    if (action == null) return;
    if (!mounted) return;
    switch (action) {
      case PushRuleDialogAction.delete:
        final consent = await showOkCancelAlertDialog(
          context: context,
          title: L10n.of(context).areYouSure,
          message: L10n.of(context).deletePushRuleCanNotBeUndone,
          okLabel: L10n.of(context).delete,
          isDestructive: true,
        );
        if (consent != OkCancelResult.ok) return;
        if (!mounted) return;
        setState(() {
          isLoading = true;
        });
        try {
          final updateFromSync = Matrix.of(context).client.onSync.stream
              .where(
                (syncUpdate) =>
                    syncUpdate.accountData?.any(
                      (accountData) => accountData.type == 'm.push_rules',
                    ) ??
                    false,
              )
              .first;
          await Matrix.of(context).client.deletePushRule(kind, rule.ruleId);
          await updateFromSync;
        } catch (e, s) {
          Logs().w('Unable to delete push rule', e, s);
          if (!mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(e.toLocalizedString(context))));
        } finally {
          if (mounted) {
            setState(() {
              isLoading = false;
            });
          }
        }
        return;
    }
  }

  /// A rule made for one chat (named after its address, !…) or one person
  /// (@…): muting a chat makes one.
  static bool _perChat(PushRule r) =>
      r.ruleId.startsWith('!') || r.ruleId.startsWith('@');

  /// The chat's or person's name instead of their address.
  String _nameOf(PushRule rule) {
    final id = rule.ruleId;
    if (id.startsWith('!')) {
      final room = Matrix.of(context).client.getRoomById(id);
      return room?.getLocalizedDisplayname(MatrixLocals(L10n.of(context))) ??
          'A chat you are no longer in';
    }
    return id.localpart ?? id;
  }

  /// What the rule does, in plain words.
  String _whatItDoes(PushRule rule, PushRuleKind kind) {
    final quiet = rule.actions.isEmpty || rule.actions.contains('dont_notify');
    if (!quiet) return 'Always notifies';
    if (rule.ruleId.startsWith('@')) return 'Muted: nothing from this person';
    return kind == PushRuleKind.room
        ? 'Only when you are mentioned'
        : 'Muted: no notifications from this chat';
  }

  /// Turns a few rules on or off together ("Groups" is two rules: plain
  /// and encrypted).
  Future<void> _setRules(List<(PushRuleKind, PushRule)> rules, bool on) async {
    final client = Matrix.of(context).client;
    final change = rules.where((r) => r.$2.enabled != on).toList();
    if (change.isEmpty) return;
    setState(() => isLoading = true);
    try {
      final updateFromSync = client.onSync.stream
          .where(
            (syncUpdate) =>
                syncUpdate.accountData?.any(
                  (accountData) => accountData.type == 'm.push_rules',
                ) ??
                false,
          )
          .first;
      for (final r in change) {
        await client.setPushRuleEnabled(r.$1, r.$2.ruleId, on);
      }
      await updateFromSync;
    } catch (e, s) {
      Logs().w('Unable to change push rules', e, s);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toLocalizedString(context))));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  bool _allRules = false;

  @override
  Widget build(BuildContext context) {
    final client = Matrix.of(context).client;
    final pushRules = client.globalPushRules;
    List<PushRule> general(List<PushRule>? l) =>
        (l ?? const <PushRule>[]).where((r) => !_perChat(r)).toList();
    final pushCategories = [
      if (general(pushRules?.override).isNotEmpty)
        (rules: general(pushRules?.override), kind: PushRuleKind.override),
      if (pushRules?.content?.isNotEmpty ?? false)
        (rules: pushRules?.content ?? [], kind: PushRuleKind.content),
      if (general(pushRules?.sender).isNotEmpty)
        (rules: general(pushRules?.sender), kind: PushRuleKind.sender),
      if (pushRules?.underride?.isNotEmpty ?? false)
        (rules: pushRules?.underride ?? [], kind: PushRuleKind.underride),
    ];
    // chats and people with a setting of their own, shown by name (they
    // used to show as their long addresses)
    final ownRules = [
      for (final r in pushRules?.override ?? const <PushRule>[])
        if (_perChat(r)) (rule: r, kind: PushRuleKind.override),
      for (final r in pushRules?.room ?? const <PushRule>[])
        if (_perChat(r)) (rule: r, kind: PushRuleKind.room),
      for (final r in pushRules?.sender ?? const <PushRule>[])
        if (_perChat(r)) (rule: r, kind: PushRuleKind.sender),
    ];
    // the server's usual rules, under plain names
    (PushRuleKind, PushRule)? of(PushRuleKind kind, List<PushRule>? l, String id) {
      for (final r in l ?? const <PushRule>[]) {
        if (r.ruleId == id) return (kind, r);
      }
      return null;
    }
    const o = PushRuleKind.override, u = PushRuleKind.underride;
    final master = of(o, pushRules?.override, '.m.rule.master');
    final direct = [
      of(u, pushRules?.underride, '.m.rule.room_one_to_one'),
      of(u, pushRules?.underride, '.m.rule.encrypted_room_one_to_one'),
    ].nonNulls.toList();
    final groups = [
      of(u, pushRules?.underride, '.m.rule.message'),
      of(u, pushRules?.underride, '.m.rule.encrypted'),
    ].nonNulls.toList();
    final mentions = [
      of(o, pushRules?.override, '.m.rule.is_user_mention'),
      of(o, pushRules?.override, '.m.rule.contains_display_name'),
      of(PushRuleKind.content, pushRules?.content, '.m.rule.contains_user_name'),
    ].nonNulls.toList();
    final calls = [of(u, pushRules?.underride, '.m.rule.call')].nonNulls.toList();
    final muted = client.allPushNotificationsMuted;
    Widget rules(IconData icon, String title, List<(PushRuleKind, PushRule)> r) =>
        r.isEmpty
        ? const SizedBox.shrink()
        : VibeSwitchRow(
            icon: icon,
            title: title,
            value: r.any((x) => x.$2.enabled),
            onChanged: isLoading || muted ? null : (v) => _setRules(r, v),
          );
    final pushService = Matrix.of(context).backgroundPush;
    return StreamBuilder(
      stream: client.onSync.stream.where(
        (syncUpdate) =>
            syncUpdate.accountData?.any(
              (accountData) => accountData.type == 'm.push_rules',
            ) ??
            false,
      ),
      builder: (context, _) {
        final theme = Theme.of(context);
        final lastReceivedPush = lastReceivedPushNotification[client.clientName];
        return VibeTitledPage(
          title: L10n.of(context).notifications,
          leading: !VibeThemes.isColumnMode(context),
          children: [
            VibeCard(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                if (master != null)
                  VibeSwitchRow(
                    icon: Icons.notifications_none_rounded,
                    title: 'Notifications',
                    subtitle: muted ? 'Off on all your devices' : null,
                    value: !muted,
                    onChanged: isLoading ? null : (v) => _setRules([master], !v),
                  ),
                if (PlatformInfos.isAndroid) const VibeSoundTile(),
                if (kIsWeb)
                  VibeSwitchRow(
                    icon: Icons.volume_up_outlined,
                    title: 'Sound',
                    value: AppSettings.webNotificationSound.value,
                    onChanged: (v) async {
                      await AppSettings.webNotificationSound.setItem(v);
                      if (mounted) setState(() {});
                    },
                  ),
                VibeSwitchRow(
                  icon: Icons.visibility_off_outlined,
                  title: 'Hide what they say',
                  subtitle: 'Only "New message", no names or pictures',
                  value: AppSettings.vibeHideNotificationContent.value,
                  onChanged: (v) async {
                    await AppSettings.vibeHideNotificationContent.setItem(v);
                    if (mounted) setState(() {});
                  },
                ),
                VibeSwitchRow(
                  icon: Icons.picture_in_picture_alt_outlined,
                  title: 'Pop-ups for muted chats',
                  subtitle: 'Off: muted chats show no notifications, top pill '
                      'or side pictures',
                  value: AppSettings.vibeMutedPopups.value,
                  onChanged: (v) async {
                    await AppSettings.vibeMutedPopups.setItem(v);
                    if (mounted) setState(() {});
                  },
                ),
              ],
            ),
            if (pushRules != null &&
                (direct.isNotEmpty || groups.isNotEmpty || mentions.isNotEmpty || calls.isNotEmpty))
              VibeSettingsGroup(
                title: 'What notifies you',
                rows: [
                  rules(Icons.person_outline_rounded, 'Direct chats', direct),
                  rules(Icons.group_outlined, 'Groups', groups),
                  rules(Icons.alternate_email_rounded, 'When you are mentioned', mentions),
                  rules(Icons.call_outlined, 'Calls', calls),
                ],
              ),
            if (ownRules.isNotEmpty)
              VibeSettingsGroup(
                title: 'Chats and people with their own setting',
                rows: [
                  for (final x in ownRules)
                    VibeSettingsRow(
                      leading: Avatar(
                        mxContent: x.rule.ruleId.startsWith('!')
                            ? client.getRoomById(x.rule.ruleId)?.avatar
                            : null,
                        name: _nameOf(x.rule),
                        size: 38,
                      ),
                      title: _nameOf(x.rule),
                      subtitle: _whatItDoes(x.rule, x.kind),
                      onTap: () => editPushRule(x.rule, x.kind),
                      trailing: VibeSwitch(
                        value: x.rule.enabled,
                        onChanged: isLoading
                            ? null
                            : (_) => togglePushRule(x.kind, x.rule),
                      ),
                    ),
                ],
              ),
            if (PlatformInfos.isAndroid)
              VibeSettingsGroup(
                title: 'How notifications arrive',
                rows: [
                  const VibePushModeTiles(header: false),
                  FutureBuilder(
                    future: UnifiedPush.getDistributors(),
                    builder: (context, snapshot) {
                      final distributors = snapshot.data;
                      if (distributors == null || distributors.isEmpty) {
                        if (pushService?.firebaseEnabled == true &&
                            pushService?.fcmToken == null) {
                          return ListTile(
                            title: Text(
                              L10n.of(context).unableToRegisterDeviceForFirebase,
                            ),
                            leading: VibeIconTile(
                              Icons.close,
                              color: theme.colorScheme.error,
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      }
                      return ListTile(
                        title: Text(L10n.of(context).unifiedPushDistributors),
                        leading: const VibeIconTile(Icons.info_outlined),
                        subtitle: SelectableText(distributors.join(', ')),
                        trailing: distributors.length >= 2
                            ? IconButton(
                                onPressed: () => UnifiedPushUi(
                                  context: context,
                                  instances: ['default'],
                                  unifiedPushFunctions: UPFunctions(),
                                  showNoDistribDialog: false,
                                  onNoDistribDialogDismissed:
                                      () {}, // TODO: Implement me
                                ).registerAppWithDialog(),
                                icon: const Icon(Icons.edit_outlined),
                                style: IconButton.styleFrom(
                                  backgroundColor:
                                      theme.colorScheme.primaryContainer,
                                  foregroundColor:
                                      theme.colorScheme.onPrimaryContainer,
                                ),
                              )
                            : null,
                      );
                    },
                  ),
                ],
              ),
            if (pushRules != null) ...[
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: VibeCard(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    VibeSettingsRow(
                      icon: Icons.rule_rounded,
                      title: 'All rules',
                      subtitle: 'Every notification rule on your account',
                      trailing: AnimatedRotation(
                        turns: _allRules ? 0.25 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          Icons.chevron_right_rounded,
                          size: 22,
                          color: VibeSettingsStyle.chevron(context),
                        ),
                      ),
                      onTap: () => setState(() => _allRules = !_allRules),
                    ),
                  ],
                ),
              ),
              // the full list, as the server has it; tap a rule for details
              AnimatedSize(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: !_allRules
                    ? const SizedBox(width: double.infinity)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final category in pushCategories)
                            VibeSettingsGroup(
                              title: category.kind.localized(L10n.of(context)),
                              rows: [
                                for (final rule in category.rules)
                                  VibeSettingsRow(
                                    title: rule.getPushRuleName(L10n.of(context)),
                                    subtitle: rule.getPushRuleDescription(
                                      L10n.of(context),
                                    ),
                                    wrap: true,
                                    onTap: () => editPushRule(rule, category.kind),
                                    trailing: VibeSwitch(
                                      value: rule.enabled,
                                      onChanged: isLoading
                                          ? null
                                          : rule.ruleId != '.m.rule.master' && muted
                                          ? null
                                          : (_) => togglePushRule(category.kind, rule),
                                    ),
                                  ),
                              ],
                            ),
                        ],
                      ),
              ),
            ],
            if (kDebugMode && lastReceivedPush != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 16, 32, 0),
                child: SelectableText(
                  'Last received push notification: '
                  '${lastReceivedPush.toIso8601String()}',
                ),
              ),
            // (the technical list of push registrations, with the old
            // Google / Firebase one, is no longer shown)
          ],
        );
      },
    );
  }
}

enum PushRuleDialogAction { delete }

String prettyJson(Map<String, Object?> json) {
  const decoder = JsonDecoder();
  const encoder = JsonEncoder.withIndent('    ');
  final object = decoder.convert(jsonEncode(json));
  return encoder.convert(object);
}

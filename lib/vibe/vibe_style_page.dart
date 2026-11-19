// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:vibe/vibe/buddy/vibe_buddy.dart';
import 'package:file_picker/file_picker.dart';
import 'package:vibe/config/setting_keys.dart';
import 'package:vibe/vibe/vibe_typing_style.dart';
import 'package:vibe/utils/account_config.dart';
import 'package:vibe/utils/file_selector.dart';
import 'package:vibe/widgets/future_loading_dialog.dart';
import 'package:vibe/widgets/theme_builder.dart';
import 'package:vibe/vibe/vibe_text_size.dart';
import 'package:flutter/material.dart';
import 'package:vibe/widgets/matrix.dart';
import 'package:vibe/vibe/vibe_motion.dart';
import 'package:vibe/vibe/vibe_settings_style.dart';
import 'package:vibe/vibe/vibe_theme_picker.dart';
import 'package:vibe/vibe/vibe_theme_reveal.dart';
import 'package:vibe/config/themes.dart';
import 'package:vibe/widgets/settings_switch_list_tile.dart';
import 'package:vibe/vibe/vibe_text_size_preview.dart';

class VibeStylePage extends StatefulWidget {
  const VibeStylePage({super.key});

  @override
  _VibeStylePageState createState() => _VibeStylePageState();
}

class _VibeStylePageState extends State<VibeStylePage> {
  void setChatColor(Color? color) {
    AppSettings.colorSchemeSeedInt.setItem(
      color?.toARGB32() ?? AppSettings.colorSchemeSeedInt.defaultValue,
    );
    ThemeController.of(context).setPrimaryColor(color);
  }

  Future<void> setWallpaper() async {
    final client = Matrix.of(context).client;
    final picked = await selectFiles(context, type: FileType.image);
    final pickedFile = picked.firstOrNull;
    if (pickedFile == null) return;
    if (!mounted) return;

    await showFutureLoadingDialog(
      context: context,
      future: () async {
        final url = await client.uploadContent(
          await pickedFile.readAsBytes(),
          filename: pickedFile.name,
        );
        await client.updateApplicationAccountConfig(
          ApplicationAccountConfig(wallpaperUrl: url),
        );
      },
    );
  }

  double get wallpaperOpacity =>
      _wallpaperOpacity ??
      Matrix.of(context).client.applicationAccountConfig.wallpaperOpacity ??
      0.5;

  double? _wallpaperOpacity;

  Future<void> saveWallpaperOpacity(double opacity) async {
    final client = Matrix.of(context).client;
    final result = await showFutureLoadingDialog(
      context: context,
      future: () => client.updateApplicationAccountConfig(
        ApplicationAccountConfig(wallpaperOpacity: opacity),
      ),
    );
    if (result.isValue) return;

    setState(() {
      _wallpaperOpacity = client.applicationAccountConfig.wallpaperOpacity;
    });
  }

  void updateWallpaperOpacity(double opacity) {
    setState(() {
      _wallpaperOpacity = opacity;
    });
  }

  double get wallpaperBlur =>
      _wallpaperBlur ??
      Matrix.of(context).client.applicationAccountConfig.wallpaperBlur ??
      0.5;
  double? _wallpaperBlur;

  Future<void> saveWallpaperBlur(double blur) async {
    final client = Matrix.of(context).client;
    final result = await showFutureLoadingDialog(
      context: context,
      future: () => client.updateApplicationAccountConfig(
        ApplicationAccountConfig(wallpaperBlur: blur),
      ),
    );
    if (result.isValue) return;

    setState(() {
      _wallpaperBlur = client.applicationAccountConfig.wallpaperBlur;
    });
  }

  void updateWallpaperBlur(double blur) {
    setState(() {
      _wallpaperBlur = blur;
    });
  }

  void deleteChatWallpaper() => showFutureLoadingDialog(
    context: context,
    future: () => Matrix.of(context).client.setApplicationAccountConfig(
      const ApplicationAccountConfig(wallpaperUrl: null, wallpaperBlur: null),
    ),
  );

  ThemeMode get currentTheme => ThemeController.of(context).themeMode;
  Color? get currentColor => ThemeController.of(context).primaryColor;

  void switchTheme(ThemeMode? newTheme) {
    if (newTheme == null) return;
    switch (newTheme) {
      case ThemeMode.light:
        ThemeController.of(context).setThemeMode(ThemeMode.light);
        break;
      case ThemeMode.dark:
        ThemeController.of(context).setThemeMode(ThemeMode.dark);
        break;
      case ThemeMode.system:
        ThemeController.of(context).setThemeMode(ThemeMode.system);
        break;
    }
    setState(() {});
  }

  Future<void> changeFontSizeFactor(double d) async {
    await AppSettings.fontSizeFactor.setItem(d);
    setState(() {});
  }

  Future<void> changeTextSize(int size) async {
    if (size == VibeTextSize.value) return;
    await VibeTextSize.set(size);
    setState(() {});
  }

  static String _theirLabel(String v) => switch (v) {
    'theme' => "In the theme's second colour",
    'plain' => 'Plain',
    _ => 'In their own colour',
  };

  /// Their messages: their own colour, the theme's second colour, or plain.
  Future<void> pickTheirColour() async {
    final now = AppSettings.vibeTheirColour.value;
    final pick = await showVibeSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (v, icon, title, sub) in const [
                (
                  'own',
                  Icons.palette_outlined,
                  'Their own colour',
                  'Each person in a soft tone of the colour of their name',
                ),
                (
                  'theme',
                  Icons.format_color_fill_rounded,
                  "The theme's second colour",
                  'Everyone in the same colour from the theme',
                ),
                ('plain', Icons.crop_square_rounded, 'Plain', 'A quiet grey'),
              ])
                VibeSettingsRow(
                  icon: icon,
                  title: title,
                  subtitle: sub,
                  wrap: true,
                  trailing: v == now
                      ? Icon(
                          Icons.check_rounded,
                          color: Theme.of(c).colorScheme.primary,
                        )
                      : const SizedBox(width: 24),
                  onTap: () => Navigator.of(c).pop(v),
                ),
            ],
          ),
        ),
      ),
    );
    if (pick == null || pick == now) return;
    await AppSettings.vibeTheirColour.setItem(pick);
    if (mounted) setState(() {});
  }

  /// A wallpaper is set: pick another picture or remove it.
  Future<void> wallpaperSheet() async {
    final pick = await showVibeSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              VibeSettingsRow(
                icon: Icons.image_outlined,
                title: 'Pick another picture',
                chevron: false,
                onTap: () => Navigator.of(c).pop('pick'),
              ),
              VibeSettingsRow(
                icon: Icons.delete_outline_rounded,
                title: 'Remove the wallpaper',
                color: Theme.of(c).colorScheme.error,
                chevron: false,
                onTap: () => Navigator.of(c).pop('remove'),
              ),
            ],
          ),
        ),
      ),
    );
    if (pick == 'pick') {
      await setWallpaper();
    } else if (pick == 'remove') {
      deleteChatWallpaper();
    }
  }

  @override
  Widget build(BuildContext context) {
    final client = Matrix.of(context).client;
    final tc = ThemeController.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return VibeTitledPage(
      title: 'Customisation',
      leading: !VibeThemes.isColumnMode(context),
      children: [
        // Light, Dark or Auto, then the themes as cards
        const VibeModeSwitch(),
        const VibeSectionLabel('Theme'),
        const VibeThemePicker(),
        VibeCard(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            if (dark)
              VibeSwitchRow(
                icon: Icons.circle,
                title: 'Pure black',
                subtitle: 'Black backgrounds in dark mode',
                value: tc.pureBlack,
                onChanged: (v) {
                  final size = MediaQuery.sizeOf(context);
                  VibeThemeReveal.run(
                    context,
                    Offset(size.width / 2, size.height / 2),
                    () => tc.setPureBlack(v),
                  );
                },
              ),
            VibeSettingsRow(
              icon: Icons.palette_outlined,
              title: 'Your own theme',
              subtitle: 'Pick one colour, Keepr makes the rest',
              onTap: () => VibeThemeEditor.open(context),
            ),
          ],
        ),
        const VibeSectionLabel('Messages'),
        StreamBuilder(
          stream: client.onSync.stream.where(
            (syncUpdate) =>
                syncUpdate.accountData?.any(
                  (accountData) =>
                      accountData.type ==
                      ApplicationAccountConfigExtension.accountDataKey,
                ) ??
                false,
          ),
          builder: (context, snapshot) {
            final hasWallpaper =
                client.applicationAccountConfig.wallpaperUrl != null;
            return VibeCard(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                VibeSettingsRow(
                  icon: Icons.group_outlined,
                  title: 'Their messages',
                  subtitle: _theirLabel(AppSettings.vibeTheirColour.value),
                  onTap: pickTheirColour,
                ),
                // a plain picture behind your chats, on all your devices
                VibeSettingsRow(
                  icon: Icons.image_outlined,
                  title: 'Chat wallpaper',
                  subtitle: 'A picture behind your chats',
                  value: hasWallpaper ? 'On' : 'None',
                  onTap: hasWallpaper ? wallpaperSheet : setWallpaper,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        VibeGroups(
          children: [
            // Looks exactly like a Keepr chat.
            VibeTextSizePreview(size: VibeTextSize.value),
            // Telegram's Text size: 12–30, default 16; only message text
            // changes (names and times keep their size).
            ListTile(
              title: const Text('Text size'),
              trailing: Text(
                '${VibeTextSize.value}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Text('A', style: TextStyle(fontSize: 13)),
                  Expanded(
                    child: Slider.adaptive(
                      min: VibeTextSize.min.toDouble(),
                      max: VibeTextSize.max.toDouble(),
                      divisions: VibeTextSize.max - VibeTextSize.min,
                      value: VibeTextSize.value.toDouble(),
                      label: '${VibeTextSize.value}',
                      semanticFormatterCallback: (d) => '${d.round()}',
                      onChanged: (d) => changeTextSize(d.round()),
                    ),
                  ),
                  const Text('A', style: TextStyle(fontSize: 24)),
                ],
              ),
            ),
            SettingsSwitchListTile.adaptive(
              title: 'Haptic feedback',
              subtitle: 'Vibrate gently on taps, menus and reactions',
              setting: AppSettings.vibeHaptics,
            ),
            // (no "New" pill here: it covered the switch; the tour shows it)
            SettingsSwitchListTile.adaptive(
              title: 'Keep the chat you leave docked',
              subtitle:
                  'Opening another chat from the top pill, or pulling a '
                  'chat\'s name down, keeps it in a strip under the text box',
              setting: AppSettings.vibeChatDock,
            ),
            SettingsSwitchListTile.adaptive(
              title: 'Start-up animation',
              subtitle:
                  'Your chats slide in one after another when Keepr opens '
                  'or comes back after a few minutes',
              setting: AppSettings.vibeBootIntro,
            ),
            ListTile(
              leading: const Icon(Icons.more_horiz_rounded),
              title: const Text('Typing indicator'),
              subtitle: const Text('What people see while you type'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => VibeTypingStylePage.open(context),
            ),
            ListTile(
              leading: const Icon(Icons.pets_rounded),
              title: const Text('Typing buddy'),
              subtitle: const Text('Bujji: outfits, on or off'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => VibeBuddyPage.open(context),
            ),

          ],
        ),
      ],
    );
  }
}

// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:vibe/vibe/vibe_glass.dart';
import 'package:vibe/vibe/vibe_palette.dart';
import 'package:vibe/vibe/vibe_theme_set.dart';
import 'package:collection/collection.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:vibe/utils/color_value.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeBuilder extends StatefulWidget {
  final Widget Function(
    BuildContext context,
    ThemeMode themeMode,
    Color? primaryColor,
  )
  builder;

  final String themeModeSettingsKey;
  final String primaryColorSettingsKey;

  const ThemeBuilder({
    required this.builder,
    this.themeModeSettingsKey = 'theme_mode',
    this.primaryColorSettingsKey = 'primary_color',
    super.key,
  });

  @override
  State<ThemeBuilder> createState() => ThemeController();
}

class ThemeController extends State<ThemeBuilder> {
  SharedPreferences? _sharedPreferences;
  ThemeMode? _themeMode;
  Color? _primaryColor;

  /// The theme picked in Settings > Customisation: 'keepr', 'material' (the
  /// phone's wallpaper colours), a named theme's id, or one of your own.
  String _theme = 'keepr';
  bool _pureBlack = false;

  String get theme => _theme;
  bool get pureBlack => _pureBlack;

  ThemeMode get themeMode => _themeMode ?? ThemeMode.system;

  Color? get primaryColor => _primaryColor;

  static ThemeController of(BuildContext context) =>
      Provider.of<ThemeController>(context, listen: false);

  Future<void> _loadData(_) async {
    final preferences = _sharedPreferences ??=
        await SharedPreferences.getInstance();

    final rawThemeMode = preferences.getString(widget.themeModeSettingsKey);
    final rawColor = preferences.getInt(widget.primaryColorSettingsKey);
    final rawLook = preferences.getString('vibe_look');
    final rawTheme = preferences.getString('keepr_theme');
    VibeThemeSet.loadCustom(preferences.getString(VibeThemeSet.customKey));

    setState(() {
      // before themes: the wallpaper colours look became Material You, and
      // Keepr and the old Glass look became Keepr
      _theme = rawTheme ?? (rawLook == 'wallpaper' ? 'material' : 'keepr');
      _pureBlack = preferences.getBool('keepr_pure_black') ?? false;
      _themeMode = ThemeMode.values.singleWhereOrNull(
        (value) => value.name == rawThemeMode,
      );
      _primaryColor = rawColor == null ? null : Color(rawColor);
    });
  }

  Future<void> setThemeMode(ThemeMode newThemeMode) async {
    final preferences = _sharedPreferences ??=
        await SharedPreferences.getInstance();
    await preferences.setString(widget.themeModeSettingsKey, newThemeMode.name);
    setState(() {
      _themeMode = newThemeMode;
    });
  }

  Future<void> setTheme(String id) async {
    final preferences = _sharedPreferences ??=
        await SharedPreferences.getInstance();
    await preferences.setString('keepr_theme', id);
    setState(() => _theme = id);
  }

  Future<void> setPureBlack(bool on) async {
    final preferences = _sharedPreferences ??=
        await SharedPreferences.getInstance();
    await preferences.setBool('keepr_pure_black', on);
    setState(() => _pureBlack = on);
  }

  /// Your own themes changed: keep them, and show the change.
  Future<void> saveCustomThemes() async {
    final preferences = _sharedPreferences ??=
        await SharedPreferences.getInstance();
    await preferences.setString(
      VibeThemeSet.customKey,
      VibeThemeSet.saveCustom(),
    );
    if (mounted) setState(() {});
  }

  Future<void> setPrimaryColor(Color? newPrimaryColor) async {
    final preferences = _sharedPreferences ??=
        await SharedPreferences.getInstance();
    if (newPrimaryColor == null) {
      await preferences.remove(widget.primaryColorSettingsKey);
    } else {
      await preferences.setInt(
        widget.primaryColorSettingsKey,
        newPrimaryColor.hexValue,
      );
    }
    setState(() {
      _primaryColor = newPrimaryColor;
    });
  }

  @override
  void initState() {
    WidgetsBinding.instance.addPostFrameCallback(_loadData);
    // Glass look: a new wallpaper / palette means new colours
    VibeGlass.version.addListener(_glassChanged);
    // Hypr Launcher's theme: now and whenever Vibe comes back
    VibeGlass.followLauncher();
    _life = AppLifecycleListener(
      onResume: () {
        VibeGlass.followLauncher();
        _rereadWallColours();
      },
    );
    super.initState();
  }

  AppLifecycleListener? _life;

  /// The phone's wallpaper / Material colours, read again whenever Keepr
  /// comes back to the screen. Keepr keeps running in the background now,
  /// so a new wallpaper or colour theme would otherwise only show after a
  /// restart.
  ColorScheme? _wallLight, _wallDark;

  Future<void> _rereadWallColours() async {
    try {
      final palette = await DynamicColorPlugin.getCorePalette();
      if (palette == null || !mounted) return;
      final light = palette.toColorScheme();
      if (light == VibePalette.wallLight) return;
      setState(() {
        _wallLight = light;
        _wallDark = palette.toColorScheme(brightness: Brightness.dark);
      });
    } catch (_) {}
  }

  void _glassChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    VibeGlass.version.removeListener(_glassChanged);
    _life?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Provider(
      create: (_) => this,
      child: DynamicColorBuilder(
        // Vibe: the wallpaper colours are only used when that look is on
        builder: (light, dark) {
          VibePalette.wallLight = _wallLight ?? light;
          VibePalette.wallDark = _wallDark ?? dark;
          final set = VibeThemeSet.byId(_theme);
          VibePalette.set = set;
          VibePalette.look = _theme == 'material'
              ? VibeLook.wallpaper
              : set != null
              ? VibeLook.palette
              : VibeLook.vibe;
          VibePalette.pureBlack = _pureBlack;
          return widget.builder(context, themeMode, primaryColor);
        },
      ),
    );
  }
}

// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:vibe/vibe/vibe_glass.dart';
import 'package:vibe/vibe/vibe_theme_set.dart';
import 'package:flutter/material.dart';

/// Vibe's looks. Only colours change (backgrounds, accent, buttons); the
/// layout stays the same Discord-style, bubble-free chat everywhere.
enum VibeLook {
  /// Discord colours (the default).
  vibe,

  /// Colours from the phone's wallpaper / system theme (Material You,
  /// Android 12+), like Google Messages.
  wallpaper,

  /// Frosted glass (no longer offered: shows as Keepr's colours).
  glass,

  /// One of the named themes, or your own ([VibePalette.set]).
  palette,
}

abstract class VibePalette {
  static const discordBlurple = Color(0xFF5865F2);

  /// The look in use (set by the app's ThemeBuilder).
  static VibeLook look = VibeLook.vibe;

  /// The phone's wallpaper colours; null when the phone has none
  /// (Android 11 and older).
  static ColorScheme? wallLight;
  static ColorScheme? wallDark;

  static bool get wallpaperAvailable => wallLight != null || wallDark != null;

  /// The named theme in use (with [VibeLook.palette]).
  static VibeThemeSet? set;

  /// Pure black in dark mode (Settings > Customisation).
  static bool pureBlack = false;

  /// The look actually shown (wallpaper falls back to Keepr's colours
  /// without colours to take; glass is gone).
  static VibeLook get effective => switch (look) {
    VibeLook.wallpaper when !wallpaperAvailable => VibeLook.vibe,
    VibeLook.palette when set == null => VibeLook.vibe,
    VibeLook.glass => VibeLook.vibe,
    _ => look,
  };

  /// Keepr's own hand-tuned colours are drawn (the Keepr theme, unless pure
  /// black is on in dark mode).
  static bool fixed(BuildContext context) =>
      isVibe &&
      !(pureBlack && Theme.of(context).brightness == Brightness.dark);

  /// The phone's wallpaper colours as a full set, or null without them.
  static ColorScheme? materialYou(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final source = (dark ? wallDark : wallLight) ?? wallDark ?? wallLight;
    if (source == null) return null;
    return _fromSeed(source.primary, brightness);
  }

  /// True while the Discord colours are used, so the hand-tuned Discord
  /// shades stay exactly as they were.
  static bool get isVibe => effective == VibeLook.vibe;

  /// Frosted glass look (see VibeGlass).
  static bool get isGlass => effective == VibeLook.glass;

  /// App font (the same in every look).
  static String get fontFamily => 'Figtree';

  /// The accent of the current look (buttons, links, ticks, toggles).
  /// Kept up to date by the app (from the active theme).
  static Color accent = discordBlurple;

  /// The colour scheme for [brightness], or null for the Discord one.
  static ColorScheme? scheme(Brightness brightness) {
    switch (effective) {
      case VibeLook.vibe:
        return null;
      case VibeLook.wallpaper:
        return materialYou(brightness);
      case VibeLook.glass:
        return VibeGlass.scheme;
      case VibeLook.palette:
        return set?.scheme(brightness);
    }
  }

  /// Keepr's own colours (the Keepr theme), dark and light.
  static const keeprDark = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFF5865F2),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFF3C45A5),
    onPrimaryContainer: Color(0xFFE0E3FF),
    secondary: Color(0xFFB5BAC1),
    onSecondary: Color(0xFF1A191E),
    secondaryContainer: Color(0xFF2E2D33),
    onSecondaryContainer: Color(0xFFF2F3F5),
    tertiary: Color(0xFF949BA4),
    onTertiary: Color(0xFF1A191E),
    tertiaryContainer: Color(0xFF29282D),
    onTertiaryContainer: Color(0xFFF2F3F5),
    error: Color(0xFFF23F42),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFF5A1D1E),
    onErrorContainer: Color(0xFFFFDAD9),
    surface: Color(0xFF1A191E),
    onSurface: Color(0xFFF2F3F5),
    surfaceContainerLowest: Color(0xFF121214),
    surfaceContainerLow: Color(0xFF1E1D22),
    surfaceContainer: Color(0xFF252429),
    surfaceContainerHigh: Color(0xFF29282D),
    surfaceContainerHighest: Color(0xFF323136),
    onSurfaceVariant: Color(0xFFB5BAC1),
    outline: Color(0xFF6D6F78),
    outlineVariant: Color(0xFF3A393F),
    inverseSurface: Color(0xFFF2F3F5),
    onInverseSurface: Color(0xFF1A191E),
    inversePrimary: Color(0xFF5865F2),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    surfaceTint: Color(0x00000000),
  );

  static const keeprLight = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF5865F2),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFE0E3FF),
    onPrimaryContainer: Color(0xFF1E2370),
    secondary: Color(0xFF5C5E66),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFE3E5E8),
    onSecondaryContainer: Color(0xFF313338),
    tertiary: Color(0xFF80848E),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFF2F3F5),
    onTertiaryContainer: Color(0xFF313338),
    error: Color(0xFFD83C3E),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFFDAD9),
    onErrorContainer: Color(0xFF5A1D1E),
    surface: Color(0xFFFFFFFF),
    onSurface: Color(0xFF313338),
    surfaceContainerLowest: Color(0xFFE3E5E8),
    surfaceContainerLow: Color(0xFFF7F7F8),
    surfaceContainer: Color(0xFFF2F3F5),
    surfaceContainerHigh: Color(0xFFEBEDEF),
    surfaceContainerHighest: Color(0xFFE3E5E8),
    onSurfaceVariant: Color(0xFF5C5E66),
    outline: Color(0xFF80848E),
    outlineVariant: Color(0xFFD8D9DC),
    inverseSurface: Color(0xFF313338),
    onInverseSurface: Color(0xFFF2F3F5),
    inversePrimary: Color(0xFF5865F2),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    surfaceTint: Color(0x00000000),
  );

  /// A full scheme from one colour. The accent is a mid tone in light and
  /// dark alike (like Discord's blurple), so white text on buttons stays
  /// readable; error red stays Vibe's.
  static ColorScheme _fromSeed(Color seed, Brightness brightness) {
    final light = ColorScheme.fromSeed(seedColor: seed);
    final s = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    final dark = brightness == Brightness.dark;
    return s.copyWith(
      primary: light.primary,
      onPrimary: Colors.white,
      inversePrimary: light.primary,
      error: dark ? const Color(0xFFF23F42) : const Color(0xFFD83C3E),
      onError: Colors.white,
      surfaceTint: Colors.transparent,
    );
  }
}

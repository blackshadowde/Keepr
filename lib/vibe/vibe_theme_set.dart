// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Theme palettes and the way their colour sets are built are adapted from
// mpvRx (github.com/Riteshp2001/mpvRx, AGPL-3.0-or-later).

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// One theme in Settings > Customisation: a main, second and third colour
/// and a background, for light and for dark. The full colour set (cards,
/// buttons, text) is built from those, so every theme reads well.
class VibeThemeSet {
  final String id;
  final String name;
  final Color primaryLight, primaryDark;
  final Color secondaryLight, secondaryDark;
  final Color tertiaryLight, tertiaryDark;
  final Color backgroundLight, backgroundDark;

  /// Your own theme: the one colour you picked.
  final Color? seed;

  const VibeThemeSet(
    this.id,
    this.name,
    this.primaryLight,
    this.primaryDark,
    this.secondaryLight,
    this.secondaryDark,
    this.tertiaryLight,
    this.tertiaryDark,
    this.backgroundLight,
    this.backgroundDark, {
    this.seed,
  });

  /// Your own theme from one colour: the rest follows from it.
  factory VibeThemeSet.fromSeed(String id, String name, Color seed) {
    final l = ColorScheme.fromSeed(seedColor: seed);
    final d = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    );
    return VibeThemeSet(
      id,
      name,
      l.primary,
      d.primary,
      l.secondary,
      d.secondary,
      l.tertiary,
      d.tertiary,
      l.surface,
      d.surface,
      seed: seed,
    );
  }

  static const all = <VibeThemeSet>[
    VibeThemeSet('mauve', 'Mauve', Color(0xFF794F81), Color(0xFFE8B5EF), Color(0xFF6A596C), Color(0xFFD6C0D6), Color(0xFF82524D), Color(0xFFF5B7B0), Color(0xFFF7F5F8), Color(0xFF161217)),
    VibeThemeSet('catppuccin', 'Catppuccin', Color(0xFF4C6B9A), Color(0xFF9BA8CF), Color(0xFFB76B8F), Color(0xFFD4A5B8), Color(0xFFB8763E), Color(0xFF8AB8A8), Color(0xFFEFF1F5), Color(0xFF1E1E2E)),
    VibeThemeSet('aurora', 'Aurora', Color(0xFF0B3FA0), Color(0xFF5B93FF), Color(0xFF5C6B8C), Color(0xFF9FAEC9), Color(0xFF3648A6), Color(0xFF97A8FF), Color(0xFFF3F6FF), Color(0xFF04070F)),
    VibeThemeSet('tangerine', 'Tangerine', Color(0xFFF6821F), Color(0xFFFFB77C), Color(0xFF6B5E4C), Color(0xFFD6C5AC), Color(0xFF855316), Color(0xFFFABD71), Color(0xFFFFFBF7), Color(0xFF1A1612)),
    VibeThemeSet('cotton_candy', 'Cotton Candy', Color(0xFFE993C1), Color(0xFFFFB1D5), Color(0xFF70A2C2), Color(0xFF9ED0EF), Color(0xFF9C68AC), Color(0xFFDEB0E9), Color(0xFFFFF8FA), Color(0xFF1A1418)),
    VibeThemeSet('doom', 'Doom', Color(0xFFBB2929), Color(0xFFFF6B6B), Color(0xFF6B5353), Color(0xFFD6BABA), Color(0xFF8C4A4A), Color(0xFFFFB4AB), Color(0xFFFFF8F7), Color(0xFF1A1010)),
    VibeThemeSet('green_apple', 'Green Apple', Color(0xFF2E7D32), Color(0xFF81C784), Color(0xFF4A6349), Color(0xFFB0CFB1), Color(0xFF3D7B5F), Color(0xFF8FD5B7), Color(0xFFF6FFF6), Color(0xFF0F1A0F)),
    VibeThemeSet('gruvbox', 'Gruvbox', Color(0xFF9D5B3F), Color(0xFFD89B6A), Color(0xFF7A7556), Color(0xFFB0AE8A), Color(0xFF4A7B7C), Color(0xFF8AAFA8), Color(0xFFFBF1C7), Color(0xFF282828)),
    VibeThemeSet('kanagawa', 'Kanagawa', Color(0xFF5A7785), Color(0xFF7E9CD8), Color(0xFF8A7A6E), Color(0xFFDCA561), Color(0xFF6A8E7F), Color(0xFF98BB6C), Color(0xFFF2ECBC), Color(0xFF1F1F28)),
    VibeThemeSet('lavender', 'Lavender', Color(0xFF7C5AB8), Color(0xFFCFBCFF), Color(0xFF635B70), Color(0xFFCBC3DA), Color(0xFF7E525A), Color(0xFFF2B8C1), Color(0xFFFCF8FF), Color(0xFF16121A)),
    VibeThemeSet('midnight', 'Midnight', Color(0xFF0D47A1), Color(0xFF90CAF9), Color(0xFF455A64), Color(0xFFB0BEC5), Color(0xFF1565C0), Color(0xFF64B5F6), Color(0xFFF5F9FF), Color(0xFF0D1117)),
    VibeThemeSet('mocha', 'Mocha', Color(0xFF795548), Color(0xFFBCAAA4), Color(0xFF5D4037), Color(0xFFA1887F), Color(0xFF6D4C41), Color(0xFFD7CCC8), Color(0xFFFFF9F5), Color(0xFF1A1512)),
    VibeThemeSet('strawberry', 'Strawberry', Color(0xFFD81B60), Color(0xFFF48FB1), Color(0xFF6B4958), Color(0xFFD6B0C1), Color(0xFFC2185B), Color(0xFFF8BBD9), Color(0xFFFFF5F8), Color(0xFF1A1015)),
    VibeThemeSet('teal', 'Teal', Color(0xFF00796B), Color(0xFF80CBC4), Color(0xFF4A635E), Color(0xFFB0CFC9), Color(0xFF00897B), Color(0xFF4DB6AC), Color(0xFFF2FFFD), Color(0xFF0F1A18)),
    VibeThemeSet('nord', 'Nord', Color(0xFF5E81AC), Color(0xFF88C0D0), Color(0xFF4C566A), Color(0xFFD8DEE9), Color(0xFFB48EAD), Color(0xFFD8A9C4), Color(0xFFECEFF4), Color(0xFF2E3440)),
    VibeThemeSet('rose_pine', 'Rosé Pine', Color(0xFF907AA9), Color(0xFFC4A7E7), Color(0xFFB4637A), Color(0xFFEBBCBA), Color(0xFF7A9A8A), Color(0xFF9CCFD8), Color(0xFFFAF4ED), Color(0xFF232136)),
    VibeThemeSet('tako', 'Tako', Color(0xFF66BB6A), Color(0xFFA5D6A7), Color(0xFF546E7A), Color(0xFF90A4AE), Color(0xFF43A047), Color(0xFF81C784), Color(0xFFF5FFF5), Color(0xFF121A12)),
    VibeThemeSet('tokyo_night', 'Tokyo Night', Color(0xFF3D5A80), Color(0xFF7D9BC1), Color(0xFF6B5B95), Color(0xFFA89DC9), Color(0xFF4A6B5C), Color(0xFF8AB4A3), Color(0xFFF0F1F5), Color(0xFF1A1B26)),
    VibeThemeSet('yin_yang', 'Yin Yang', Color(0xFF424242), Color(0xFFBDBDBD), Color(0xFF616161), Color(0xFFE0E0E0), Color(0xFF757575), Color(0xFFEEEEEE), Color(0xFFFAFAFA), Color(0xFF121212)),
    VibeThemeSet('yotsuba', 'Yotsuba', Color(0xFFFF8A65), Color(0xFFFFAB91), Color(0xFF6D5D5B), Color(0xFFD6C4C2), Color(0xFFFF7043), Color(0xFFFFCCBC), Color(0xFFFFF8F5), Color(0xFF1A1412)),
    VibeThemeSet('sapphire', 'Sapphire', Color(0xFF1E88E5), Color(0xFF64B5F6), Color(0xFF5C6BC0), Color(0xFF9FA8DA), Color(0xFF0288D1), Color(0xFF4FC3F7), Color(0xFFF3F8FF), Color(0xFF0D1620)),
    VibeThemeSet('sunset', 'Sunset', Color(0xFFE65100), Color(0xFFFF9E80), Color(0xFFEF6C00), Color(0xFFFFCC80), Color(0xFFF4511E), Color(0xFFFF8A65), Color(0xFFFFF5F0), Color(0xFF1A120D)),
    VibeThemeSet('cyan', 'Cyan', Color(0xFF006064), Color(0xFF4DD0E1), Color(0xFF00838F), Color(0xFF80DEEA), Color(0xFF0097A7), Color(0xFF26C6DA), Color(0xFFF0FFFF), Color(0xFF0A1A1C)),
    VibeThemeSet('forest', 'Forest', Color(0xFF1B5E20), Color(0xFF66BB6A), Color(0xFF33691E), Color(0xFF9CCC65), Color(0xFF2E7D32), Color(0xFFA5D6A7), Color(0xFFF1F8E9), Color(0xFF0D1A0D)),
    VibeThemeSet('rose_gold', 'Rose Gold', Color(0xFFB76E79), Color(0xFFE8A9B0), Color(0xFFAD8075), Color(0xFFDDBFB8), Color(0xFFD4A5A5), Color(0xFFF5D5D5), Color(0xFFFFF5F5), Color(0xFF1A1315)),
    VibeThemeSet('violet', 'Violet', Color(0xFF6A1B9A), Color(0xFFCE93D8), Color(0xFF7B1FA2), Color(0xFFE1BEE7), Color(0xFF8E24AA), Color(0xFFBA68C8), Color(0xFFFCF5FF), Color(0xFF150D1A)),
    VibeThemeSet('amber', 'Amber', Color(0xFFFF8F00), Color(0xFFFFCA28), Color(0xFFFFA000), Color(0xFFFFD54F), Color(0xFFFFB300), Color(0xFFFFE082), Color(0xFFFFFBF0), Color(0xFF1A1508)),
    VibeThemeSet('coral', 'Coral', Color(0xFFFF5252), Color(0xFFFF8A80), Color(0xFFFF6E40), Color(0xFFFFAB91), Color(0xFFFF7043), Color(0xFFFFCCBC), Color(0xFFFFF5F5), Color(0xFF1A1010)),
    VibeThemeSet('slate', 'Slate', Color(0xFF455A64), Color(0xFF90A4AE), Color(0xFF546E7A), Color(0xFFB0BEC5), Color(0xFF607D8B), Color(0xFFCFD8DC), Color(0xFFF5F7F8), Color(0xFF151A1C)),
    VibeThemeSet('dracula', 'Dracula', Color(0xFF6272A4), Color(0xFFBD93F9), Color(0xFF44475A), Color(0xFFFF79C6), Color(0xFF50FA7B), Color(0xFF8BE9FD), Color(0xFFF8F8F2), Color(0xFF282A36)),
    VibeThemeSet('monochrome', 'Monochrome', Color(0xFF212121), Color(0xFFE0E0E0), Color(0xFF424242), Color(0xFFBDBDBD), Color(0xFF616161), Color(0xFF9E9E9E), Color(0xFFFFFFFF), Color(0xFF0A0A0A)),
  ];

  /// Your own themes, newest last (kept on the phone).
  static final custom = <VibeThemeSet>[];

  static const customKey = 'chat.keepr.custom_themes';

  static VibeThemeSet? byId(String id) {
    for (final t in all) {
      if (t.id == id) return t;
    }
    for (final t in custom) {
      if (t.id == id) return t;
    }
    return null;
  }

  static void loadCustom(String? json) {
    custom.clear();
    if (json == null || json.isEmpty) return;
    try {
      for (final e in jsonDecode(json) as List) {
        final m = e as Map;
        custom.add(
          VibeThemeSet.fromSeed(
            m['id'] as String,
            m['name'] as String,
            Color(m['seed'] as int),
          ),
        );
      }
    } catch (_) {}
  }

  static String saveCustom() => jsonEncode([
    for (final t in custom)
      {'id': t.id, 'name': t.name, 'seed': t.seed!.toARGB32()},
  ]);

  ColorScheme scheme(Brightness brightness) =>
      brightness == Brightness.dark ? _dark() : _light();

  ColorScheme _light() {
    final bg = backgroundLight, p = primaryLight;
    final pc = _over(p, .22, bg);
    final sc = _over(secondaryLight, .22, bg);
    final tc = _over(tertiaryLight, .22, bg);
    final variant = _over(p, .10, _darken(bg, .035));
    final dim = _darken(bg, .075), bright = _lighten(bg, .012);
    final lowest = _lighten(bg, .018), low = _over(p, .03, bg);
    final mid = _over(p, .05, bg), high = _over(p, .075, bg);
    final highest = _over(p, .105, bg);
    final under = [bg, variant, dim, bright, lowest, low, mid, high, highest];
    final primary = _readable(p, under);
    final secondary = _readable(secondaryLight, under);
    final tertiary = _readable(tertiaryLight, under);
    return ColorScheme(
      brightness: Brightness.light,
      primary: primary,
      onPrimary: _on(primary),
      primaryContainer: pc,
      onPrimaryContainer: _on(pc),
      secondary: secondary,
      onSecondary: _on(secondary),
      secondaryContainer: sc,
      onSecondaryContainer: _on(sc),
      tertiary: tertiary,
      onTertiary: _on(tertiary),
      tertiaryContainer: tc,
      onTertiaryContainer: _on(tc),
      error: const Color(0xFFBA1A1A),
      onError: Colors.white,
      errorContainer: const Color(0xFFFFDAD6),
      onErrorContainer: const Color(0xFF93000A),
      surface: bg,
      onSurface: _readable(const Color(0xFF1C1B1F), [bg]),
      surfaceDim: dim,
      surfaceBright: bright,
      surfaceContainerLowest: lowest,
      surfaceContainerLow: low,
      surfaceContainer: mid,
      surfaceContainerHigh: high,
      surfaceContainerHighest: highest,
      onSurfaceVariant: _readable(const Color(0xFF49454F), [variant]),
      outline: _over(secondaryLight, .6, const Color(0xFF79747E)),
      outlineVariant: _over(p, .2, const Color(0xFFCAC4D0)),
      inverseSurface: backgroundDark,
      onInverseSurface: const Color(0xFFF4EFF4),
      inversePrimary: _readable(primaryDark, [backgroundDark]),
      shadow: Colors.black,
      scrim: Colors.black,
      surfaceTint: Colors.transparent,
    );
  }

  ColorScheme _dark() {
    final bg = backgroundDark, p = primaryDark;
    final pc = _darken(primaryLight, .2);
    final sc = _darken(secondaryLight, .2);
    final tc = _darken(tertiaryLight, .2);
    final variant = _over(p, .18, const Color(0xFF2A2A2A));
    final lowest = _darken(bg, .2), low = _over(p, .06, bg);
    final mid = _over(p, .08, bg), high = _over(p, .12, bg);
    final highest = _over(p, .16, bg);
    final under = [bg, variant, lowest, low, mid, high, highest];
    final primary = _readable(p, under);
    final secondary = _readable(secondaryDark, under);
    final tertiary = _readable(tertiaryDark, under);
    return ColorScheme(
      brightness: Brightness.dark,
      primary: primary,
      onPrimary: _on(primary),
      primaryContainer: pc,
      onPrimaryContainer: _on(pc),
      secondary: secondary,
      onSecondary: _on(secondary),
      secondaryContainer: sc,
      onSecondaryContainer: _on(sc),
      tertiary: tertiary,
      onTertiary: _on(tertiary),
      tertiaryContainer: tc,
      onTertiaryContainer: _on(tc),
      error: const Color(0xFFFFB4AB),
      onError: const Color(0xFF690005),
      errorContainer: const Color(0xFF93000A),
      onErrorContainer: const Color(0xFFFFDAD6),
      surface: bg,
      onSurface: _readable(const Color(0xFFE6E1E5), [bg]),
      surfaceDim: bg,
      surfaceBright: _over(p, .2, bg),
      surfaceContainerLowest: lowest,
      surfaceContainerLow: low,
      surfaceContainer: mid,
      surfaceContainerHigh: high,
      surfaceContainerHighest: highest,
      onSurfaceVariant: _readable(const Color(0xFFCAC4D0), [variant]),
      outline: _over(secondaryDark, .5, const Color(0xFF938F99)),
      outlineVariant: _over(p, .22, const Color(0xFF49454F)),
      inverseSurface: backgroundLight,
      onInverseSurface: const Color(0xFF313033),
      inversePrimary: _readable(primaryLight, [backgroundLight]),
      shadow: Colors.black,
      scrim: Colors.black,
      surfaceTint: Colors.transparent,
    );
  }

  /// Pure black: a black page, cards and panels a shade above it, the
  /// accents kept.
  static ColorScheme black(ColorScheme s) {
    final p = s.primary;
    return s.copyWith(
      surface: Colors.black,
      surfaceDim: Colors.black,
      surfaceContainerLowest: Colors.black,
      surfaceContainerLow: _over(p, .05, const Color(0xFF101010)),
      surfaceContainer: _over(p, .06, const Color(0xFF151515)),
      surfaceContainerHigh: _over(p, .07, const Color(0xFF1B1B1B)),
      surfaceContainerHighest: _over(p, .09, const Color(0xFF222222)),
      surfaceBright: _over(p, .06, const Color(0xFF2A2A2A)),
    );
  }

  static Color _over(Color c, double alpha, Color bg) =>
      Color.alphaBlend(c.withValues(alpha: alpha), bg);

  static Color _darken(Color c, double f) => Color.from(
    alpha: c.a,
    red: c.r * (1 - f),
    green: c.g * (1 - f),
    blue: c.b * (1 - f),
  );

  static Color _lighten(Color c, double f) => Color.from(
    alpha: c.a,
    red: c.r + (1 - c.r) * f,
    green: c.g + (1 - c.g) * f,
    blue: c.b + (1 - c.b) * f,
  );

  static double _ratio(Color a, Color b) {
    final x = a.computeLuminance(), y = b.computeLuminance();
    return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
  }

  /// Black or white, whichever reads better on [c].
  static Color _on(Color c) =>
      _ratio(c, Colors.black) >= _ratio(c, Colors.white)
      ? Colors.black
      : Colors.white;

  /// [c], moved towards black or white just enough to read on all of [bgs].
  static Color _readable(Color c, List<Color> bgs) {
    double worst(Color x) => bgs.map((b) => _ratio(x, b)).reduce(math.min);
    if (worst(c) >= 4.5) return c;
    final target = worst(Colors.black) >= worst(Colors.white)
        ? Colors.black
        : Colors.white;
    var lo = 0.0, hi = 1.0;
    for (var i = 0; i < 12; i++) {
      final m = (lo + hi) / 2;
      if (worst(Color.lerp(c, target, m)!) >= 4.5) {
        hi = m;
      } else {
        lo = m;
      }
    }
    return Color.lerp(c, target, hi)!;
  }
}

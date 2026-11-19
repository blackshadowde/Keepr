// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:vibe/vibe/vibe_haptics.dart';
import 'package:vibe/vibe/vibe_motion.dart';
import 'package:vibe/vibe/vibe_palette.dart';
import 'package:vibe/vibe/vibe_settings_style.dart';
import 'package:vibe/vibe/vibe_theme_reveal.dart';
import 'package:vibe/vibe/vibe_theme_set.dart';
import 'package:vibe/widgets/theme_builder.dart';

/// Light, Dark or Auto (follows the phone), as one rounded switch; the new
/// mode grows from where you tapped.
class VibeModeSwitch extends StatelessWidget {
  const VibeModeSwitch({super.key});

  @override
  Widget build(BuildContext context) {
    final tc = ThemeController.of(context);
    final cs = Theme.of(context).colorScheme;
    final sub = VibeSettingsStyle.text2(context);
    const modes = [
      (ThemeMode.light, Icons.light_mode_outlined, 'Light'),
      (ThemeMode.dark, Icons.dark_mode_outlined, 'Dark'),
      (ThemeMode.system, Icons.contrast_rounded, 'Auto'),
    ];
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: VibeSettingsStyle.card(context),
        borderRadius: BorderRadius.circular(27),
      ),
      child: Row(
        children: [
          for (final (mode, icon, label) in modes)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) {
                  if (tc.themeMode == mode) return;
                  VibeHaptics.selection();
                  VibeThemeReveal.run(
                    context,
                    d.globalPosition,
                    () => tc.setThemeMode(mode),
                  );
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  height: 44,
                  decoration: BoxDecoration(
                    color: tc.themeMode == mode
                        ? cs.primaryContainer
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        icon,
                        size: 19,
                        color: tc.themeMode == mode
                            ? cs.onPrimaryContainer
                            : sub,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: tc.themeMode == mode
                              ? FontWeight.w700
                              : FontWeight.w600,
                          color: tc.themeMode == mode
                              ? cs.onPrimaryContainer
                              : sub,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The themes as a row of cards you swipe through; each card is a small
/// Keepr chat in that theme's colours. Tap one and it grows from the card.
class VibeThemePicker extends StatefulWidget {
  const VibeThemePicker({super.key});

  /// Bumped when your own themes change (a new card, a removed one).
  static final version = ValueNotifier<int>(0);

  @override
  State<VibeThemePicker> createState() => _VibeThemePickerState();
}

class _VibeThemePickerState extends State<VibeThemePicker> {
  final _scroll = ScrollController();

  static const _cardW = 92.0, _gap = 10.0, _step = _cardW + 6 + _gap;

  @override
  void initState() {
    super.initState();
    // open with the picked theme in view
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final i = _ids().indexOf(ThemeController.of(context).theme);
      if (i <= 0) return;
      _scroll.jumpTo(
        math.min(
          math.max(0.0, i * _step - _step),
          _scroll.position.maxScrollExtent,
        ),
      );
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  List<String> _ids() => [
    if (VibePalette.wallpaperAvailable) 'material',
    'keepr',
    for (final t in VibeThemeSet.all) t.id,
    for (final t in VibeThemeSet.custom) t.id,
  ];

  static String _name(String id) => switch (id) {
    'material' => 'Material You',
    'keepr' => 'Keepr',
    _ => VibeThemeSet.byId(id)?.name ?? '',
  };

  static ColorScheme preview(String id, Brightness b) {
    final dark = b == Brightness.dark;
    final ColorScheme? found = switch (id) {
      'material' => VibePalette.materialYou(b),
      'keepr' => null,
      _ => VibeThemeSet.byId(id)?.scheme(b),
    };
    var s = found ?? (dark ? VibePalette.keeprDark : VibePalette.keeprLight);
    if (dark && VibePalette.pureBlack) s = VibeThemeSet.black(s);
    return s;
  }

  void _pick(String id, Offset at) {
    final tc = ThemeController.of(context);
    if (tc.theme == id) return;
    VibeHaptics.selection();
    VibeThemeReveal.run(context, at, () => tc.setTheme(id));
  }

  @override
  Widget build(BuildContext context) {
    final page = Theme.of(context).colorScheme;
    final b = Theme.of(context).brightness;
    return ValueListenableBuilder<int>(
      valueListenable: VibeThemePicker.version,
      builder: (context, _, _) {
        final ids = _ids();
        final picked = ThemeController.of(context).theme;
        return SizedBox(
          height: 186,
          child: ListView.separated(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            itemCount: ids.length + 1,
            separatorBuilder: (_, _) => const SizedBox(width: _gap),
            itemBuilder: (context, i) {
              if (i == ids.length) {
                return _AddCard(onTap: () => VibeThemeEditor.open(context));
              }
              final id = ids[i];
              final own = VibeThemeSet.custom.where((t) => t.id == id);
              return _ThemeCard(
                name: _name(id),
                scheme: preview(id, b),
                page: page,
                selected: id == picked,
                onTap: (at) => _pick(id, at),
                onLongPress: own.isEmpty
                    ? null
                    : () => VibeThemeEditor.manage(context, own.first),
              );
            },
          ),
        );
      },
    );
  }
}

class _ThemeCard extends StatelessWidget {
  final String name;
  final ColorScheme scheme;
  final ColorScheme page;
  final bool selected;
  final void Function(Offset at) onTap;
  final VoidCallback? onLongPress;
  const _ThemeCard({
    required this.name,
    required this.scheme,
    required this.page,
    required this.selected,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 98,
      child: Column(
        children: [
          GestureDetector(
            onTapUp: (d) => onTap(d.globalPosition),
            onLongPress: onLongPress,
            child: VibePressable(
              scale: 0.95,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: 92,
                height: 148,
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: selected
                          ? page.primary
                          : page.outlineVariant.withValues(alpha: 0.6),
                      spreadRadius: selected ? 3 : 1,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Stack(
                    children: [
                      VibeMiniChat(scheme: scheme, width: 92, height: 148),
                      if (selected)
                        Positioned(
                          left: 7,
                          top: 7,
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: page.primary,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: scheme.surface,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.check_rounded,
                              size: 15,
                              color: page.onPrimary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              color: selected ? page.primary : page.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

/// A tiny chat in [scheme]'s colours: the top pill, two of their messages,
/// one of yours, the text box and the send button.
class VibeMiniChat extends StatelessWidget {
  final ColorScheme scheme;
  final double width, height;
  const VibeMiniChat({
    required this.scheme,
    required this.width,
    required this.height,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final k = width / 92;
    final s = scheme;
    Widget box(
      double x,
      double y,
      double w,
      double h,
      Color c, {
      double? r,
      bool right = false,
      bool bottom = false,
    }) => Positioned(
      left: right ? null : x * k,
      right: right ? x * k : null,
      top: bottom ? null : y * k,
      bottom: bottom ? y * k : null,
      width: w * k,
      height: h * k,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular((r ?? h / 2) * k),
        ),
      ),
    );
    return SizedBox(
      width: width,
      height: height,
      child: ColoredBox(
        color: s.surface,
        child: Stack(
          children: [
            box(8, 9, 14, 14, s.surfaceContainerHigh),
            box(26, 10, 40, 12, s.surfaceContainerHigh),
            box(8, 32, 56, 20, s.tertiaryContainer, r: 10),
            box(8, 55, 40, 20, s.secondaryContainer, r: 10),
            box(8, 80, 58, 20, s.primaryContainer, r: 10, right: true),
            box(8, 9, 52, 20, s.surfaceContainer, r: 10, bottom: true),
            box(8, 9, 20, 20, s.primary, right: true, bottom: true),
          ],
        ),
      ),
    );
  }
}

class _AddCard extends StatelessWidget {
  final VoidCallback onTap;
  const _AddCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 98,
      child: Column(
        children: [
          VibePressable(
            scale: 0.95,
            child: Material(
              color: VibeSettingsStyle.card(context),
              borderRadius: BorderRadius.circular(18),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                child: SizedBox(
                  width: 92,
                  height: 148,
                  child: Icon(Icons.add_rounded, size: 32, color: cs.primary),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your own',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

/// Make your own theme from one colour, change one, or remove one.
abstract class VibeThemeEditor {
  static const swatches = [
    Color(0xFFC2185B),
    Color(0xFFE8590C),
    Color(0xFFB8860B),
    Color(0xFF2E7D32),
    Color(0xFF2E8B7A),
    Color(0xFF1565C0),
    Color(0xFF5865F2),
    Color(0xFF7C5AB8),
    Color(0xFF795548),
    Color(0xFF455A64),
  ];

  static Future<void> open(BuildContext context, {VibeThemeSet? editing}) async {
    final tc = ThemeController.of(context);
    var seed = editing?.seed ?? swatches[4];
    final name = TextEditingController(text: editing?.name ?? '');
    final saved = await showVibeSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) {
          final cs = Theme.of(c).colorScheme;
          final sub = VibeSettingsStyle.text2(c);
          final preview = VibeThemeSet.fromSeed('preview', '', seed);
          Widget sample(Brightness b, String label) => Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: VibeMiniChat(
                  scheme: preview.scheme(b),
                  width: 104,
                  height: 150,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: sub,
                ),
              ),
            ],
          );
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              20,
              8,
              20,
              16 + MediaQuery.viewInsetsOf(c).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your own theme',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  'Pick one colour. Keepr makes the light and dark sets from it.',
                  style: TextStyle(fontSize: 14, color: sub),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    sample(Brightness.light, 'Light'),
                    const SizedBox(width: 14),
                    sample(Brightness.dark, 'Dark'),
                  ],
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 13,
                  runSpacing: 12,
                  children: [
                    for (final c in swatches)
                      GestureDetector(
                        onTap: () => set(() => seed = c),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            boxShadow: c.toARGB32() == seed.toARGB32()
                                ? [
                                    BoxShadow(
                                      color: cs.surfaceContainerLow,
                                      spreadRadius: 3,
                                    ),
                                    BoxShadow(color: c, spreadRadius: 5),
                                  ]
                                : const [],
                          ),
                          child: c.toARGB32() == seed.toARGB32()
                              ? const Icon(
                                  Icons.check_rounded,
                                  size: 18,
                                  color: Colors.white,
                                )
                              : null,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                // or any colour: slide along the rainbow
                _HueBar(
                  color: seed,
                  onChanged: (h) => set(
                    () => seed = HSVColor.fromAHSV(1, h, 0.62, 0.66).toColor(),
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: name,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: 'Name',
                    filled: true,
                    fillColor: cs.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                        ),
                        onPressed: () => Navigator.of(c).pop(false),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                        ),
                        onPressed: () => Navigator.of(c).pop(true),
                        child: const Text('Save'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
    final label = name.text.trim();
    name.dispose();
    if (saved != true || !context.mounted) return;
    final id =
        editing?.id ?? 'custom:${DateTime.now().millisecondsSinceEpoch}';
    final made = VibeThemeSet.fromSeed(
      id,
      label.isEmpty ? 'My theme' : label,
      seed,
    );
    final i = VibeThemeSet.custom.indexWhere((t) => t.id == id);
    if (i >= 0) {
      VibeThemeSet.custom[i] = made;
    } else {
      VibeThemeSet.custom.add(made);
    }
    await tc.saveCustomThemes();
    VibeThemePicker.version.value++;
    if (!context.mounted) return;
    final size = MediaQuery.sizeOf(context);
    await VibeThemeReveal.run(
      context,
      Offset(size.width / 2, size.height / 2),
      () => tc.setTheme(id),
    );
  }

  /// Hold one of your own themes: change it or remove it.
  static Future<void> manage(BuildContext context, VibeThemeSet t) async {
    final tc = ThemeController.of(context);
    final pick = await showVibeSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              VibeSettingsRow(
                icon: Icons.edit_outlined,
                title: 'Change ${t.name}',
                chevron: false,
                onTap: () => Navigator.of(c).pop('edit'),
              ),
              VibeSettingsRow(
                icon: Icons.delete_outline_rounded,
                title: 'Remove ${t.name}',
                color: Theme.of(c).colorScheme.error,
                chevron: false,
                onTap: () => Navigator.of(c).pop('remove'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!context.mounted) return;
    if (pick == 'edit') return open(context, editing: t);
    if (pick != 'remove') return;
    VibeThemeSet.custom.removeWhere((x) => x.id == t.id);
    // it was in use: back to Keepr's colours
    if (tc.theme == t.id) await tc.setTheme('keepr');
    await tc.saveCustomThemes();
    VibeThemePicker.version.value++;
  }
}

/// The rainbow to pick any colour from: tap or slide.
class _HueBar extends StatelessWidget {
  final Color color;
  final ValueChanged<double> onChanged;
  const _HueBar({required this.color, required this.onChanged});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final w = box.maxWidth;
      double hueAt(double x) => (x / w).clamp(0.0, 1.0) * 360;
      final x = HSVColor.fromColor(color).hue / 360 * w;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => onChanged(hueAt(d.localPosition.dx)),
        onHorizontalDragUpdate: (d) => onChanged(hueAt(d.localPosition.dx)),
        child: SizedBox(
          height: 34,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 4,
                height: 26,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(13),
                    gradient: LinearGradient(
                      colors: [
                        for (var h = 0; h <= 360; h += 45)
                          HSVColor.fromAHSV(1, (h % 360).toDouble(), 0.62, 0.9).toColor(),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: (x - 16).clamp(-4.0, w - 28),
                top: 1,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    boxShadow: const [
                      BoxShadow(color: Colors.white, spreadRadius: 3),
                      BoxShadow(color: Color(0x44000000), blurRadius: 6),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

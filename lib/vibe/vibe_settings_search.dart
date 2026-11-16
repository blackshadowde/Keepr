// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:vibe/vibe/buddy/bujji_settings.dart';
import 'package:vibe/vibe/vibe_settings_style.dart';
import 'package:vibe/vibe/vibe_swipe.dart';

/// Search settings: type a setting's name or another word for it ("dark",
/// "wallpaper", "receipts") and tap it to open its page. It searches the
/// same list Bujji uses for "@bujji open …".
class VibeSettingsSearch extends StatefulWidget {
  const VibeSettingsSearch({super.key});

  /// The setting picked, or null.
  static Future<BujjiSetting?> open(BuildContext context) =>
      Navigator.of(context).push<BujjiSetting>(
        VibeSheetPageRoute<BujjiSetting>(
          builder: (_) => const VibeSettingsTheme(child: VibeSettingsSearch()),
        ),
      );

  @override
  State<VibeSettingsSearch> createState() => _VibeSettingsSearchState();
}

class _VibeSettingsSearchState extends State<VibeSettingsSearch> {
  final _text = TextEditingController();

  static const _tries = [
    'Dark mode',
    'Wallpaper',
    'Text size',
    'Read receipts',
    'Notification sound',
    'App lock',
  ];

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  static IconData _iconOf(String page) => switch (page) {
    'Notifications' => Icons.notifications_none_rounded,
    'Customisation' => Icons.palette_outlined,
    'Chats & storage' => Icons.chat_bubble_outline_rounded,
    'Security & sign-in' => Icons.shield_outlined,
    _ => Icons.settings_outlined,
  };

  List<BujjiSetting> _find(String q) {
    final low = q.trim().toLowerCase();
    if (low.isEmpty) return const [];
    // names that contain what you typed first, then Bujji's word matches
    return {
      ...BujjiSettings.all.where((s) => s.name.toLowerCase().contains(low)),
      ...BujjiSettings.find(low),
    }.toList();
  }

  @override
  Widget build(BuildContext context) {
    final sub = VibeSettingsStyle.text2(context);
    final font = Theme.of(context).textTheme.bodyLarge ?? const TextStyle();
    final q = _text.text;
    final hits = _find(q);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: 68,
        leading: Center(
          child: VibeRoundButton(
            icon: Icons.arrow_back_rounded,
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onTap: () => Navigator.of(context).pop(),
          ),
        ),
        titleSpacing: 0,
        // the search box sits where the title would be
        title: Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              color: VibeSettingsStyle.card(context),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: [
                const SizedBox(width: 16),
                Icon(Icons.search_rounded, size: 22, color: sub),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _text,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) {
                      if (hits.isNotEmpty) Navigator.of(context).pop(hits.first);
                    },
                    style: font.copyWith(
                      fontSize: 15.5,
                      color: VibeSettingsStyle.text(context),
                    ),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: 'Search settings',
                      hintStyle: font.copyWith(fontSize: 15.5, color: sub),
                    ),
                  ),
                ),
                if (q.isNotEmpty)
                  IconButton(
                    tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
                    icon: Icon(Icons.close_rounded, size: 20, color: sub),
                    onPressed: () => setState(_text.clear),
                  )
                else
                  const SizedBox(width: 16),
              ],
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 32),
        children: [
          if (q.trim().isEmpty) ...[
            const VibeSectionLabel('Try'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in _tries)
                    ActionChip(
                      label: Text(t),
                      onPressed: () => setState(() {
                        _text.text = t;
                        _text.selection = TextSelection.collapsed(
                          offset: t.length,
                        );
                      }),
                    ),
                ],
              ),
            ),
          ] else if (hits.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 32, 32, 0),
              child: Text(
                'Nothing by that name. Try other words for it.',
                textAlign: TextAlign.center,
                style: font.copyWith(fontSize: 14.5, color: sub),
              ),
            )
          else
            VibeCard(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final s in hits)
                  VibeSettingsRow(
                    icon: _iconOf(s.page),
                    title: s.name,
                    subtitle: s.page,
                    onTap: () => Navigator.of(context).pop(s),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

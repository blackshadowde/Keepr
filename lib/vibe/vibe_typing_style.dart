// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:vibe/config/setting_keys.dart';
import 'package:vibe/vibe/vibe_status.dart';
import 'package:vibe/widgets/matrix.dart';

/// Your own typing indicator: up to three emojis with a little animation and
/// a phrase ("Sam is cooking up a reply…"). Shared in your direct chats like
/// your status, so other Keepr users see it while you type; other apps show
/// their normal typing indicator.
class VibeTypingStyle {
  static const type = 'chat.keepr.typing';
  static const _key = 'keepr.typing_style';

  static const phrases = [
    'is typing…',
    'is writing…',
    'is thinking…',
    'is cooking up a reply…',
    'is choosing words…',
    'is on it…',
    'is scribbling…',
    'is spilling the tea…',
    'is drafting an essay…',
    'is almost done…',
  ];
  static const animations = {
    'bounce': 'Bounce',
    'wave': 'Wave',
    'pulse': 'Pulse',
  };
  static const emojiChoices = [
    '✍️', '💬', '🤔', '🔥', '✨', '🎉', '😎', '🙈', '☕', '🍿', '🎧', '💡',
    '🚀', '🌙', '⭐', '❤️', '😂', '🥳', '👀', '🫶', '🐱', '🐶', '🌸', '🍕',
  ];

  final List<String> emojis;
  final String text;
  final String animation;
  const VibeTypingStyle({
    this.emojis = const [],
    this.text = 'is typing…',
    this.animation = 'bounce',
  });

  bool get isCustom => emojis.isNotEmpty || text != phrases.first;

  factory VibeTypingStyle.fromContent(Map<String, Object?> c) =>
      VibeTypingStyle(
        emojis: (c['emojis'] is List ? c['emojis'] as List : const [])
            .whereType<String>()
            .take(3)
            .toList(),
        text: c['text'] is String && (c['text'] as String).length <= 40
            ? c['text'] as String
            : phrases.first,
        animation: animations.containsKey(c['animation'])
            ? c['animation'] as String
            : 'bounce',
      );

  Map<String, Object?> toContent() => {
    'emojis': emojis,
    'text': text,
    'animation': animation,
  };

  /// Mine, as saved on this phone.
  static VibeTypingStyle mine() {
    try {
      final s = AppSettings.store.getString(_key);
      if (s != null) {
        return VibeTypingStyle.fromContent(
          Map<String, Object?>.from(jsonDecode(s) as Map),
        );
      }
    } catch (_) {}
    return const VibeTypingStyle();
  }

  /// [userId]'s style in [room], or null for the normal indicator.
  static VibeTypingStyle? of(Room room, String userId) {
    final c = room.getState(type, userId)?.content;
    if (c == null || c.isEmpty) return null;
    final s = VibeTypingStyle.fromContent(c);
    return s.isCustom ? s : null;
  }

  /// Save on this phone and share in my direct chats (where my status may
  /// be seen).
  static Future<void> save(Client client, VibeTypingStyle s) async {
    await AppSettings.store.setString(_key, jsonEncode(s.toContent()));
    final content = s.isCustom ? s.toContent() : <String, Object?>{};
    for (final r in client.rooms) {
      if (!r.isDirectChat || r.membership != Membership.join) continue;
      if (!VibeStatus.visibleIn(r)) continue;
      try {
        await client.setRoomStateWithKey(r.id, type, client.userID!, content);
      } catch (_) {}
    }
  }

  /// Chats already checked this session.
  static final _checked = <String>{};

  /// When a direct chat opens: share my style there if it isn't yet (chats
  /// started after I saved it, or where saving failed before).
  static Future<void> shareIn(Room r) async {
    final me = r.client.userID;
    if (me == null || !_checked.add(r.id)) return;
    if (!r.isDirectChat || r.membership != Membership.join) return;
    if (!VibeStatus.visibleIn(r)) return;
    final s = mine();
    final want = s.isCustom ? s.toContent() : <String, Object?>{};
    final have = r.getState(type, me)?.content ?? const <String, Object?>{};
    if (jsonEncode(have) == jsonEncode(want)) return;
    try {
      await r.client.setRoomStateWithKey(r.id, type, me, want);
    } catch (_) {}
  }

  static VibeTypingStyle random() {
    final r = Random();
    final e = List.of(emojiChoices)..shuffle(r);
    return VibeTypingStyle(
      emojis: e.take(1 + r.nextInt(3)).toList(),
      text: phrases[1 + r.nextInt(phrases.length - 1)],
      animation: animations.keys.elementAt(r.nextInt(animations.length)),
    );
  }
}

/// The animated emojis of a typing style.
class VibeTypingEmojis extends StatefulWidget {
  final VibeTypingStyle style;
  const VibeTypingEmojis(this.style, {super.key});

  @override
  State<VibeTypingEmojis> createState() => _VibeTypingEmojisState();
}

class _VibeTypingEmojisState extends State<VibeTypingEmojis>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, _) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < widget.style.emojis.length; i++)
          Builder(
            builder: (context) {
              // each emoji a little after the one before
              final t = (_c.value - i * 0.18) % 1.0;
              final s = sin(t * 2 * pi);
              final child = Text(
                widget.style.emojis[i],
                style: const TextStyle(fontSize: 15),
              );
              return Padding(
                padding: const EdgeInsets.only(right: 2),
                child: switch (widget.style.animation) {
                  'wave' => Transform.rotate(angle: s * 0.35, child: child),
                  'pulse' => Transform.scale(
                    scale: 1 + 0.18 * s.abs(),
                    child: child,
                  ),
                  _ => Transform.translate(
                    offset: Offset(0, -4 * s.clamp(0.0, 1.0)),
                    child: child,
                  ),
                },
              );
            },
          ),
      ],
    ),
  );
}

/// Settings > Customisation > Typing indicator.
class VibeTypingStylePage extends StatefulWidget {
  const VibeTypingStylePage({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const VibeTypingStylePage()));

  @override
  State<VibeTypingStylePage> createState() => _VibeTypingStylePageState();
}

class _VibeTypingStylePageState extends State<VibeTypingStylePage> {
  late VibeTypingStyle _s = VibeTypingStyle.mine();

  Future<void> _set(VibeTypingStyle s) async {
    setState(() => _s = s);
    await VibeTypingStyle.save(Matrix.of(context).client, s);
  }

  Future<void> _pickEmoji(int slot) async {
    final e = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final e in VibeTypingStyle.emojiChoices)
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.of(c).pop(e),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(e, style: const TextStyle(fontSize: 28)),
                  ),
                ),
              if (slot < _s.emojis.length)
                TextButton(
                  onPressed: () => Navigator.of(c).pop(''),
                  child: const Text('Remove'),
                ),
            ],
          ),
        ),
      ),
    );
    if (e == null) return;
    final list = List.of(_s.emojis);
    if (e.isEmpty) {
      list.removeAt(slot);
    } else if (slot < list.length) {
      list[slot] = e;
    } else {
      list.add(e);
    }
    await _set(VibeTypingStyle(
      emojis: list,
      text: _s.text,
      animation: _s.animation,
    ));
  }

  Future<void> _pick(String title, Map<String, String> options, String current,
      void Function(String) onPick) async {
    final v = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final e in options.entries)
                    RadioListTile<String>(
                      value: e.key,
                      groupValue: current,
                      title: Text(e.value),
                      onChanged: (v) => Navigator.of(c).pop(v),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (v != null) onPick(v);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = Matrix.of(context).client.userID?.localpart ?? 'You';
    return Scaffold(
      appBar: AppBar(title: const Text('Typing indicator')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // preview
          Container(
            height: 120,
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_s.emojis.isNotEmpty) ...[
                  VibeTypingEmojis(_s),
                  const SizedBox(width: 8),
                ],
                Text('$name ${_s.text}',
                    style: TextStyle(color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          const Text('Emojis',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Row(
            children: [
              for (var i = 0; i < 3; i++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: i < 2 ? 8 : 0),
                    child: Material(
                      color: cs.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(18),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: i <= _s.emojis.length ? () => _pickEmoji(i) : null,
                        child: SizedBox(
                          height: 72,
                          child: Center(
                            child: i < _s.emojis.length
                                ? Text(_s.emojis[i],
                                    style: const TextStyle(fontSize: 30))
                                : Icon(Icons.add,
                                    color: i == _s.emojis.length
                                        ? cs.onSurfaceVariant
                                        : cs.outlineVariant),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          ListTile(
            tileColor: cs.surfaceContainerHigh,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: const Text('Animation'),
            trailing: Text(VibeTypingStyle.animations[_s.animation]!),
            onTap: () => _pick('Animation', VibeTypingStyle.animations,
                _s.animation, (v) => _set(VibeTypingStyle(
                      emojis: _s.emojis, text: _s.text, animation: v))),
          ),
          const SizedBox(height: 8),
          ListTile(
            tileColor: cs.surfaceContainerHigh,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: const Text('Text'),
            trailing: Text(_s.text),
            onTap: () => _pick(
                'Text',
                {for (final p in VibeTypingStyle.phrases) p: p},
                _s.text,
                (v) => _set(VibeTypingStyle(
                    emojis: _s.emojis, text: v, animation: _s.animation))),
          ),
          const SizedBox(height: 8),
          Text(
            'People using Keepr see this while you type in your direct '
            'chats. Other apps show their normal typing indicator.',
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => _set(VibeTypingStyle.random()),
            icon: const Icon(Icons.casino_outlined),
            label: const Text('Surprise me'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _set(const VibeTypingStyle()),
            icon: const Icon(Icons.block),
            label: const Text('Reset'),
          ),
        ],
      ),
    );
  }
}

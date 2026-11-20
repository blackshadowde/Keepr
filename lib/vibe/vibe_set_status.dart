// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:vibe/vibe/vibe_palette.dart';
import 'package:vibe/vibe/vibe_haptics.dart';
import 'package:vibe/vibe/vibe_name_style.dart';
import 'package:vibe/vibe/vibe_profile_cache.dart';
import 'package:vibe/vibe/vibe_status.dart';
import 'package:vibe/widgets/avatar.dart';
import 'package:vibe/vibe/vibe_motion.dart';
import 'package:vibe/vibe/vibe_member_tags.dart';
import 'package:vibe/vibe/vibe_connections.dart';
import 'package:vibe/vibe/vibe_own_profile.dart';
import 'package:vibe/config/app_config.dart';
import 'package:vibe/widgets/qr_code_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

const _statusHint = 'What are you up to?';
const _onlineGreen = Color(0xFF23A55A);
Color get _blurple => VibePalette.accent;

/// Discord-style thought bubble: two small dots trailing up-left to the
/// profile picture, then a rounded bubble. Shows the status, or
/// "+ What are you currently obsessed with?" when there is none.
class VibeThoughtBubble extends StatelessWidget {
  final String? text;
  final bool showPlus;
  final VoidCallback? onTap;
  const VibeThoughtBubble({this.text, this.showPlus = false, this.onTap, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final fill = !VibePalette.fixed(context)
        ? Theme.of(context).colorScheme.surfaceContainerHigh
        : dark ? const Color(0xFF2B2D31) : Colors.white;
    final edge = dark ? const Color(0xFF3F4147) : const Color(0xFFDDDEE1);
    final ink = dark ? const Color(0xFFF2F3F5) : const Color(0xFF2E3035);
    final empty = text == null || text!.trim().isEmpty;

    Widget dot(double d) => Container(
      width: d,
      height: d,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: Border.all(color: edge),
      ),
    );

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(left: 0, top: 0, child: dot(12)),
          Positioned(left: 18, top: 10, child: dot(20)),
          Padding(
            padding: const EdgeInsets.only(left: 2, top: 22),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: edge),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x1A000000),
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Text.rich(
                TextSpan(
                  children: [
                    if (showPlus && empty)
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: ink,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.add, size: 17, color: fill),
                          ),
                        ),
                      ),
                    TextSpan(text: empty ? _statusHint : text),
                  ],
                ),
                maxLines: empty ? 1 : 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.3,
                  fontStyle: empty ? FontStyle.italic : FontStyle.normal,
                  color: empty ? ink.withValues(alpha: 0.85) : ink,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Round profile picture with a thick ring and the green online dot.
class VibeRingAvatar extends StatelessWidget {
  final Uri? mxc;
  final String name;
  final Client client;
  final double size;
  final Color ring;
  const VibeRingAvatar({
    required this.mxc,
    required this.name,
    required this.client,
    required this.ring,
    this.size = 104,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final ringW = size * 0.06;
    return SizedBox(
      width: size + ringW * 2,
      height: size + ringW * 2,
      child: Stack(
        children: [
          Container(
            padding: EdgeInsets.all(ringW),
            decoration: BoxDecoration(color: ring, shape: BoxShape.circle),
            // big picture: an animated one plays
            child: Avatar(
              mxContent: mxc,
              name: name,
              size: size,
              client: client,
              animated: true,
            ),
          ),
          Positioned(
            right: ringW * 0.6,
            bottom: ringW * 0.6,
            child: Container(
              width: size * 0.26,
              height: size * 0.26,
              decoration: BoxDecoration(
                color: _onlineGreen,
                shape: BoxShape.circle,
                border: Border.all(color: ring, width: ringW),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Set your status" page (Discord style): live preview card, status field
/// with emoji, and "Clear at".
class VibeSetStatusPage extends StatefulWidget {
  final Client client;
  const VibeSetStatusPage({required this.client, super.key});

  static Future<void> open(BuildContext context, Client client) =>
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => VibeSetStatusPage(client: client),
        ),
      );

  @override
  State<VibeSetStatusPage> createState() => _VibeSetStatusPageState();
}

enum _Clear { min30, hour1, hour4, today, tomorrow, week, never }

class _VibeSetStatusPageState extends State<VibeSetStatusPage> {
  final _text = TextEditingController();
  final _name = TextEditingController();
  String _origName = '';
  VibeNameStyle? _style, _origStyle;

  /// The name in a highlighted pill (Customisation > profile).
  bool _pill = false, _origPill = false;

  /// What gets saved: the colours, plus the pill if it's on (a pill
  /// without colours uses Keepr blue).
  VibeNameStyle? get _composed => _pill
      ? (_style ?? const VibeNameStyle(0x5865F2)).withPill(true)
      : _style;
  final _focus = FocusNode();
  String _emoji = '';
  late DateTime? _clearAt; // null = don't clear
  bool _saving = false;
  bool _hadStatus = false;
  late Future<Profile> _profile;

  /// The "clear after" chip that's picked (none when it came from before).
  _Clear? _choice;

  /// Scrolled past the picture: the top bar shows it small with your name.
  final _scroll = ScrollController();
  bool _small = false;

  static const _emojis = [
    '😀', '😎', '🥳', '😴', '🤒', '🤔', '❤️', '🔥', '🎧', '🎮',
    '📚', '💼', '☕', '🍕', '✈️', '🚢', '⚓', '🌊', '🏖️', '🏝️',
    '🏃', '💪', '🎬', '🎉', '🙏', '📵', '🌙', '☀️', '🌧️', '🏠',
  ];

  @override
  void initState() {
    super.initState();
    _profile = VibeProfileCache.get(widget.client);
    _profile.then((p) {
      if (!mounted) return;
      final (plainName, nameStyle) = VibeNameStyle.split(p.displayName ?? '');
      _origName = plainName;
      _origStyle = _style = nameStyle?.withPill(false);
      _origPill = _pill = nameStyle?.pill ?? false;
      if (_name.text.isEmpty) setState(() => _name.text = _origName);
    });
    final s = VibeStatus.mine(widget.client);
    if (s != null && s.active) {
      _hadStatus = true;
      _text.text = s.text;
      _emoji = s.emoji;
      _clearAt = s.until;
      // the chip closest to when it clears
      final until = s.until;
      if (until == null) {
        _choice = _Clear.never;
      } else {
        final now = DateTime.now();
        final left = until.difference(now);
        if (left <= const Duration(minutes: 65)) {
          _choice = _Clear.hour1;
        } else if (until.day == now.day && left < const Duration(days: 1)) {
          _choice = _Clear.today;
        } else if (left <= const Duration(days: 7)) {
          _choice = _Clear.week;
        }
      }
    } else {
      _choice = _Clear.today;
      _clearAt = _resolve(_Clear.today);
    }
    _scroll.addListener(() {
      final small = _scroll.offset > 230;
      if (small != _small) setState(() => _small = small);
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _name.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  DateTime? _resolve(_Clear c) {
    final now = DateTime.now();
    switch (c) {
      case _Clear.min30:
        return now.add(const Duration(minutes: 30));
      case _Clear.hour1:
        return now.add(const Duration(hours: 1));
      case _Clear.hour4:
        return now.add(const Duration(hours: 4));
      case _Clear.today:
        return DateTime(now.year, now.month, now.day, 23, 59);
      case _Clear.tomorrow:
        return now.add(const Duration(days: 1));
      case _Clear.week:
        return now.add(const Duration(days: 7));
      case _Clear.never:
        return null;
    }
  }

  Future<void> _pickEmoji() async {
    final picked = await showVibeSheet<String>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final e in _emojis)
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.pop(ctx, e),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(
                      child: Text(e, style: const TextStyle(fontSize: 26)),
                    ),
                  ),
                ),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => Navigator.pop(ctx, ''),
                child: const SizedBox(
                  width: 48,
                  height: 48,
                  child: Icon(Icons.block, size: 22),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _emoji = picked);
  }

  Widget _swatch(VibeNameStyle? s, [VoidCallback? also]) {
    final selected = _style == s;
    return GestureDetector(
      onTap: () {
        VibeHaptics.selection();
        setState(() => _style = s);
        also?.call();
      },
      child: Container(
        width: 34,
        height: 34,
        margin: const EdgeInsets.only(right: 10, top: 3, bottom: 3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: s == null ? Colors.grey.withValues(alpha: 0.3) : null,
          gradient: s == null
              ? null
              : LinearGradient(
                  colors: [Color(0xFF000000 | s.c1), Color(0xFF000000 | s.c2)],
                ),
          border: Border.all(
            color: selected ? _blurple : Colors.transparent,
            width: 3,
          ),
        ),
        child: s == null ? const Icon(Icons.block, size: 18) : null,
      ),
    );
  }

  void _copy(String text, String done) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(done), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _changePhoto(Profile? p) async {
    final changed = await VibeOwnProfile.changePhoto(
      context,
      widget.client,
      hasPhoto: p?.avatarUrl != null,
    );
    if (!changed || !mounted) return;
    VibeProfileCache.refresh();
    setState(() => _profile = VibeProfileCache.get(widget.client));
  }

  Future<void> _save({bool clear = false}) async {
    if (_saving) return;
    final text = _text.text.trim();
    final clearing = clear || text.isEmpty;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    // the display name (this page is also "Edit profile")
    final newName = _name.text.trim();
    if (newName.isNotEmpty &&
        (newName != _origName || _style != _origStyle || _pill != _origPill)) {
      try {
        await widget.client.setProfileField(widget.client.userID!, 'displayname', {
          'displayname': VibeNameStyle.compose(newName, _composed),
        });
        _origName = newName;
        _origStyle = _style;
        _origPill = _pill;
        VibeProfileCache.refresh();
      } catch (_) {
        messenger.showSnackBar(const SnackBar(content: Text('Could not change your name')));
      }
    }
    if (!clear && text.isEmpty && !_hadStatus) {
      // only the name changed
      VibeHaptics.light();
      if (mounted) Navigator.of(context).pop();
      messenger.showSnackBar(const SnackBar(content: Text('Saved'), duration: Duration(seconds: 2)));
      return;
    }
    final s = clearing
        ? const VibeStatus()
        : VibeStatus(
            emoji: _emoji,
            text: text,
            untilMs: _clearAt?.millisecondsSinceEpoch,
          );
    final n = await VibeStatus.publish(widget.client, s);
    VibeHaptics.light();
    if (mounted) Navigator.of(context).pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          clearing
              ? 'Status cleared'
              : n == 0
              ? 'Could not set status in any chat'
              : 'Status set',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Your name and its colours, in a pane (the pencil by your name).
  Future<void> _editName() async {
    await showVibeSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, again) {
          final cs = Theme.of(ctx).colorScheme;
          return Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(ctx).bottom),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Your name', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _name,
                    autofocus: true,
                    maxLength: 64,
                    onChanged: (_) {
                      setState(() {});
                      again(() {});
                    },
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      counterText: '',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: cs.primary, width: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text(
                        'NAME COLOURS',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.9,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: VibeNameText(
                          VibeNameStyle.compose(
                            _name.text.trim().isEmpty ? 'Your name' : _name.text.trim(),
                            _composed,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        _swatch(null, () => again(() {})),
                        for (final p in VibeNameStyle.presets) _swatch(p, () => again(() {})),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: VibePressable(
                      child: FilledButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('Done'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final canSave = _text.text.trim().isNotEmpty ||
        _hadStatus ||
        (_name.text.trim().isNotEmpty &&
            (_name.text.trim() != _origName ||
                _style != _origStyle ||
                _pill != _origPill));
    final userId = widget.client.userID ?? '';
    final top = MediaQuery.paddingOf(context).top;
    final card = cs.surfaceContainer;
    final tile = cs.surfaceContainerHigh;
    final sub = cs.onSurfaceVariant;
    Widget label(String t) => Text(
      t,
      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.9, color: sub),
    );
    // a settings row: a soft square with its icon, the words, a switch or ›
    Widget row(Widget icon, String title, {String? hint, Widget? end, VoidCallback? onTap}) => VibePressable(
      scale: 0.98,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: tile, borderRadius: BorderRadius.circular(12)),
                child: icon,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
                    if (hint != null) ...[
                      const SizedBox(height: 2),
                      Text(hint, style: TextStyle(fontSize: 13, color: sub)),
                    ],
                  ],
                ),
              ),
              end ?? Icon(Icons.chevron_right_rounded, color: sub, size: 22),
            ],
          ),
        ),
      ),
    );
    Widget box(Widget child, {double top = 12}) => Container(
      margin: EdgeInsets.fromLTRB(16, top, 16, 0),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(24)),
      child: child,
    );
    Widget chip(_Clear c, String text) {
      final on = _choice == c;
      return VibePressable(
        scale: 0.94,
        child: GestureDetector(
          onTap: () {
            VibeHaptics.selection();
            setState(() {
              _choice = c;
              _clearAt = _resolve(c);
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: on ? cs.primaryContainer : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: on ? cs.primary : cs.outlineVariant),
            ),
            // as wide as its words, so the chips sit side by side
            child: Align(
              widthFactor: 1,
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: on ? cs.onPrimaryContainer : cs.onSurface,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: cs.surface,
      body: FutureBuilder<Profile>(
        future: _profile,
        builder: (context, snap) {
          final p = snap.data;
          final name = _name.text.trim().isNotEmpty
              ? _name.text.trim()
              : (p?.displayName?.isNotEmpty ?? false)
              ? p!.displayName!
              : (userId.localpart ?? userId);
          return Stack(
            children: [
              ListView(
                controller: _scroll,
                padding: EdgeInsets.zero,
                children: [
                  // a soft wash behind your picture, your name and your ID
                  Container(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment.topCenter,
                        radius: 1.25,
                        colors: [
                          Color.lerp(cs.primary, cs.surface, 0.45)!,
                          cs.primaryContainer.withValues(alpha: 0.85),
                          cs.surface,
                        ],
                        stops: const [0, 0.45, 1],
                      ),
                    ),
                    padding: EdgeInsets.only(top: top + 60, bottom: 28),
                    child: Column(
                      children: [
                        // tap your picture (or the camera) to change it
                        VibePressable(
                          scale: 0.95,
                          child: GestureDetector(
                            onTap: () => _changePhoto(p),
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Avatar(
                                  mxContent: p?.avatarUrl,
                                  name: name,
                                  size: 112,
                                  client: widget.client,
                                ),
                                Positioned(
                                  right: -2,
                                  bottom: -2,
                                  child: Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: cs.primary,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: cs.surface, width: 3),
                                    ),
                                    child: Icon(Icons.photo_camera_rounded, size: 18, color: cs.onPrimary),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        // your name: tap to change it and its colours
                        GestureDetector(
                          onTap: _editName,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: VibeNameText(
                                    VibeNameStyle.compose(name, _style),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(Icons.edit_rounded, size: 18, color: sub),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        // your Keepr ID: tap to copy it
                        GestureDetector(
                          onTap: () => _copy(userId, 'Copied'),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    userId,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: sub),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Icon(Icons.copy_rounded, size: 15, color: sub),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Online',
                          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Color(0xFF22A55B)),
                        ),
                      ],
                    ),
                  ),
                  // status: what you're up to, and when it clears
                  box(
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          label('STATUS'),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              VibePressable(
                                scale: 0.92,
                                child: GestureDetector(
                                  onTap: _pickEmoji,
                                  child: Container(
                                    width: 46,
                                    height: 46,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: cs.surface,
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: _emoji.isEmpty
                                        ? Icon(Icons.sentiment_satisfied_alt_outlined, size: 24, color: sub)
                                        : Text(_emoji, style: const TextStyle(fontSize: 22)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Container(
                                  height: 46,
                                  alignment: Alignment.centerLeft,
                                  decoration: BoxDecoration(
                                    color: cs.surface,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: TextField(
                                    controller: _text,
                                    focusNode: _focus,
                                    maxLength: 128,
                                    onChanged: (_) => setState(() {}),
                                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                                    decoration: InputDecoration(
                                      counterText: '',
                                      hintText: 'What are you up to?',
                                      border: InputBorder.none,
                                      isDense: true,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                                      // empty it to clear your status when you save
                                      suffixIcon: _text.text.isEmpty
                                          ? null
                                          : IconButton(
                                              tooltip: 'Clear',
                                              icon: Icon(Icons.close_rounded, size: 18, color: sub),
                                              onPressed: () => setState(() {
                                                _text.clear();
                                                _emoji = '';
                                              }),
                                            ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              chip(_Clear.hour1, '1 hour'),
                              chip(_Clear.today, 'Today'),
                              chip(_Clear.week, 'This week'),
                              chip(_Clear.never, "Don't clear"),
                            ],
                          ),
                        ],
                      ),
                    ),
                    top: 0,
                  ),
                  // your Keepr ID: the code right here, with Share and Copy link
                  box(
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: SizedBox.square(
                              dimension: 112,
                              child: PrettyQrView.data(
                                data: AppConfig.shareLink(userId),
                                // dark on white, so any phone can read it
                                decoration: const PrettyQrDecoration(
                                  shape: PrettyQrSmoothSymbol(
                                    roundFactor: 1,
                                    color: Color(0xFF16181D),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                label('YOUR KEEPR ID'),
                                const SizedBox(height: 6),
                                const Text(
                                  'Scan or share to chat with you',
                                  style: TextStyle(fontSize: 14, height: 1.35, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    VibePressable(
                                      scale: 0.94,
                                      child: Material(
                                        color: cs.primary,
                                        shape: const StadiumBorder(),
                                        clipBehavior: Clip.antiAlias,
                                        child: InkWell(
                                          onTap: () => showQrCodeViewer(context, userId),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 14),
                                            child: SizedBox(
                                              height: 38,
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.share_rounded, size: 16, color: cs.onPrimary),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    'Share',
                                                    style: TextStyle(
                                                      fontSize: 13.5,
                                                      fontWeight: FontWeight.w700,
                                                      color: cs.onPrimary,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    VibePressable(
                                      scale: 0.9,
                                      child: Material(
                                        color: cs.surfaceContainerHighest,
                                        shape: const CircleBorder(),
                                        clipBehavior: Clip.antiAlias,
                                        child: InkWell(
                                          onTap: () => _copy(AppConfig.shareLink(userId), 'Link copied'),
                                          child: SizedBox.square(
                                            dimension: 38,
                                            child: Icon(Icons.copy_rounded, size: 18, color: cs.onSurface),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  box(
                    Column(
                      children: [
                        row(
                          // a little pill outline
                          Container(
                            width: 20,
                            height: 11,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: cs.onSurface, width: 2),
                            ),
                          ),
                          'Show my name in a pill',
                          hint: 'Your name and status on your messages',
                          end: Switch(
                            value: _pill,
                            onChanged: (v) {
                              VibeHaptics.selection();
                              setState(() => _pill = v);
                            },
                          ),
                          onTap: () => setState(() => _pill = !_pill),
                        ),
                        row(
                          Icon(Icons.sell_rounded, size: 20, color: cs.onSurface),
                          'Group tag',
                          hint: 'A short tag next to your name in groups',
                          onTap: () => VibeMemberTags.pick(context, widget.client),
                        ),
                      ],
                    ),
                  ),
                  // what you're listening to, from Last.fm or ListenBrainz
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: VibeConnectionsCard(color: card),
                  ),
                  box(
                    row(
                      Icon(Icons.settings_rounded, size: 20, color: cs.onSurface),
                      'Settings',
                      onTap: () {
                        final router = GoRouter.of(context);
                        Navigator.of(context).pop();
                        router.go('/rooms/settings');
                      },
                    ),
                  ),
                  SizedBox(height: 32 + MediaQuery.paddingOf(context).bottom),
                ],
              ),
              // the top bar: close and Save; scrolled down, your picture and
              // name join it
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  color: _small ? cs.surface : cs.surface.withValues(alpha: 0),
                  padding: EdgeInsets.fromLTRB(12, top + 6, 12, 6),
                  child: Row(
                    children: [
                      VibePressable(
                        scale: 0.9,
                        child: Material(
                          color: _small ? tile : Colors.white.withValues(alpha: 0.6),
                          shape: const CircleBorder(),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => Navigator.of(context).pop(),
                            child: SizedBox.square(
                              dimension: 44,
                              child: Icon(Icons.close_rounded, color: _small ? cs.onSurface : Colors.black87),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: AnimatedOpacity(
                          opacity: _small ? 1 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: Row(
                            children: [
                              Avatar(
                                mxContent: p?.avatarUrl,
                                name: name,
                                size: 36,
                                client: widget.client,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      VibePressable(
                        scale: 0.94,
                        child: Material(
                          color: canSave ? cs.primary : cs.primary.withValues(alpha: 0.45),
                          shape: const StadiumBorder(),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: canSave && !_saving ? _save : null,
                            child: SizedBox(
                              height: 40,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 18),
                                child: Center(
                                  widthFactor: 1,
                                  child: _saving
                                      ? SizedBox.square(
                                          dimension: 18,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary),
                                        )
                                      : Text(
                                          'Save',
                                          style: TextStyle(
                                            fontSize: 14.5,
                                            fontWeight: FontWeight.w700,
                                            color: cs.onPrimary,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

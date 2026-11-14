// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:vibe/config/setting_keys.dart';
import 'package:vibe/l10n/l10n.dart';
import 'package:vibe/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:vibe/vibe/buddy/vibe_buddy.dart';
import 'package:vibe/vibe/screens/chat/chat.dart';
import 'package:vibe/vibe/vibe_effects.dart';
import 'package:vibe/vibe/vibe_haptics.dart';
import 'package:vibe/vibe/vibe_hot_words.dart';
import 'package:vibe/vibe/vibe_motion.dart';
import 'package:vibe/vibe/vibe_pq.dart';
import 'package:vibe/vibe/vibe_send_later.dart';

/// The buddy's row above the text box: the buddy on the right and, now and
/// then, a small hint to its left. It watches what you type and what
/// happens in the chat, all on this phone.
class VibeBuddyBar extends StatefulWidget {
  final ChatController controller;
  const VibeBuddyBar(this.controller, {super.key});

  @override
  State<VibeBuddyBar> createState() => _VibeBuddyBarState();
}

class _Hint {
  final String text;
  final IconData icon;
  final VoidCallback? onTap;
  const _Hint(this.text, this.icon, [this.onTap]);
}

class _VibeBuddyBarState extends State<VibeBuddyBar> {
  ChatController get c => widget.controller;
  Room get room => c.room;

  BuddyMood _typingMood = BuddyMood.idle;
  BuddyMood? _flash; // a short mood that wins for a moment
  BuddyProp? _flashProp;
  _Hint? _hint;
  int _hop = 0, _wiggle = 0;
  double _gaze = 0;
  bool _sleepy = false;
  bool _pq = false;

  String _last = '';
  int _deleted = 0;
  Timer? _flashTimer, _hintTimer, _idle, _deleteReset, _pqTimer;
  StreamSubscription? _presence, _sync;
  PresenceType? _theirPresence;
  bool _toldRare = false, _toldSecret = false;
  final _toldEffects = <String>{};

  static final _shownUnverified = <String>{};

  String get _them => room.getLocalizedDisplayname(
    MatrixLocals(L10n.of(context)),
  );

  @override
  void initState() {
    super.initState();
    c.sendController.addListener(_onText);
    VibeBuddy.sent.addListener(_onSent);
    VibeBuddy.changed.addListener(_refresh);
    _wake();
    _pqTimer = Timer.periodic(const Duration(seconds: 30), (_) => _checkPq());
    _checkPq();
    final other = room.directChatMatrixID;
    if (other != null) {
      _presence = room.client.onPresenceChanged.stream
          .where((p) => p.userid == other)
          .listen((p) {
            final was = _theirPresence;
            _theirPresence = p.presence;
            if (was != null &&
                was != PresenceType.online &&
                p.presence == PresenceType.online) {
              _say(_Hint('$_them is here', Icons.waving_hand_outlined),
                  mood: BuddyMood.happy, prop: BuddyProp.wave);
            }
          });
      // they start typing: it looks up and waves
      var typing = false;
      _sync = room.client.onSync.stream.listen((_) {
        final now = room.typingUsers.any((u) => u.id == other);
        if (now && !typing && mounted) {
          _show(BuddyMood.happy, BuddyProp.wave, 1600);
        }
        typing = now;
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _afterOpen());
  }

  @override
  void dispose() {
    c.sendController.removeListener(_onText);
    VibeBuddy.sent.removeListener(_onSent);
    VibeBuddy.changed.removeListener(_refresh);
    for (final t in [_flashTimer, _hintTimer, _idle, _deleteReset, _pqTimer]) {
      t?.cancel();
    }
    _presence?.cancel();
    _sync?.cancel();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _checkPq() {
    final on = VibePq.on(room);
    if (on != _pq && mounted) setState(() => _pq = on);
  }

  Future<void> _afterOpen() async {
    if (!mounted) return;
    VibeBuddy.shareIn(room, Theme.of(context).colorScheme.primary);
    // a draft waiting from last time
    if (c.sendController.text.trim().isNotEmpty) {
      _say(const _Hint('Your draft is still here', Icons.edit_note_rounded),
          mood: BuddyMood.happy, prop: BuddyProp.paper);
    }
    // a device in this chat that isn't verified (once per chat a session)
    if (room.encrypted && !_shownUnverified.contains(room.id)) {
      try {
        final h = await room.calcEncryptionHealthState();
        if (mounted && h == EncryptionHealthState.unverifiedDevices) {
          _shownUnverified.add(room.id);
          _say(
            _Hint(
              "A device here isn't verified",
              Icons.gpp_maybe_outlined,
              () => context.go('/rooms/${room.id}/encryption'),
            ),
            mood: BuddyMood.worried,
            seconds: 7,
          );
        }
      } catch (_) {}
    }
    // let the timeline load, then look for a streak
    Future.delayed(const Duration(seconds: 2), _streak);
  }

  // ---- what you type ----

  void _onText() {
    final text = c.sendController.text;
    _wake();
    if (text.length < _last.length) {
      _deleted += _last.length - text.length;
      _deleteReset?.cancel();
      _deleteReset = Timer(const Duration(seconds: 2), () => _deleted = 0);
      if (_deleted >= 12) {
        _deleted = 0;
        _show(BuddyMood.worried, null, 1800);
      }
    }
    _last = text;
    // eyes follow the caret along the box (it sits at the right end)
    final g = text.isEmpty ? 0.0 : -1 + (text.length.clamp(0, 36) / 36) * 0.8;

    var mood = BuddyMood.idle;
    _Hint? hint;
    if (text.trim().isNotEmpty) {
      if (VibeBuddy.looksSecret(text)) {
        mood = BuddyMood.cover;
        if (!_toldSecret) {
          _toldSecret = true;
          hint = const _Hint(
            'Looks like a password or card number',
            Icons.visibility_off_outlined,
          );
        }
      } else {
        final scenes = VibeHotWords.matchAll(text);
        final first = scenes.firstOrNull;
        mood = switch (first) {
          VibeScene.love ||
          VibeScene.missYou ||
          VibeScene.kiss ||
          VibeScene.hug => BuddyMood.love,
          VibeScene.sorry || VibeScene.bye => BuddyMood.worried,
          VibeScene.wow => BuddyMood.puzzled,
          VibeScene.goodNight || VibeScene.sweetDreams => BuddyMood.sleepy,
          null => BuddyMood.idle,
          _ => BuddyMood.happy,
        };
        // an effect that fits the words (not in post-quantum chats)
        final effect = first == null ? null : _effectFor(first);
        if (effect != null &&
            !_pq &&
            c.editEvent == null &&
            _toldEffects.add(effect.id)) {
          hint = _Hint('Send with ${effect.label}?', Icons.auto_awesome_rounded,
              () {
            VibeHaptics.light();
            c.sendEffect = effect;
            c.send();
          });
        }
        // writing somewhere you rarely talk
        if (hint == null && !_toldRare && _rarelyTalk()) {
          _toldRare = true;
          hint = _Hint(
            "You haven't written to $_them in a while",
            Icons.help_outline_rounded,
          );
          _show(BuddyMood.puzzled, null, 2600);
        }
      }
    }
    setState(() {
      _typingMood = mood;
      _gaze = g;
    });
    if (hint != null) _say(hint, seconds: 6);
  }

  VibeEffect? _effectFor(VibeScene s) => switch (s) {
    VibeScene.love ||
    VibeScene.missYou ||
    VibeScene.kiss ||
    VibeScene.hug => VibeEffects.byId('love'),
    VibeScene.laugh => VibeEffects.byId('lol'),
    VibeScene.birthday => VibeEffects.byId('balloons'),
    VibeScene.party || VibeScene.congrats => VibeEffects.byId('party'),
    _ => null,
  };

  bool _rarelyTalk() {
    final events = c.timeline?.events;
    if (events == null || events.isEmpty) return false;
    final me = room.client.userID;
    bool msg(Event e) => e.type == EventTypes.Message;
    final others = events.where((e) => msg(e) && e.senderId != me);
    if (others.isEmpty) return false; // a new chat isn't a wrong chat
    final mine = events.firstWhereOrNull((e) => msg(e) && e.senderId == me);
    return mine == null ||
        DateTime.now().difference(mine.originServerTs).inDays > 30;
  }

  // ---- after sending ----

  void _onSent() {
    if (!mounted) return;
    VibeHaptics.light();
    final unlocked = VibeBuddy.noteSent();
    setState(() {
      _hop++;
      _hint = null;
      _toldSecret = false;
    });
    if (unlocked != null) {
      _say(
        _Hint('New outfit: ${unlocked.label}', Icons.checkroom_rounded,
            () => VibeBuddyPage.open(context)),
        mood: BuddyMood.happy,
        seconds: 6,
      );
    }
    Future.delayed(const Duration(seconds: 2), _streak);
  }

  /// Days in a row you both wrote; a little party at 3, 7, 14, 30, 60, 100
  /// and 365 (once each).
  void _streak() {
    if (!mounted || !room.isDirectChat) return;
    final events = c.timeline?.events;
    final me = room.client.userID;
    if (events == null || me == null) return;
    DateTime day(DateTime t) => DateTime(t.year, t.month, t.day);
    final mine = <DateTime>{}, theirs = <DateTime>{};
    for (final e in events) {
      if (e.type != EventTypes.Message) continue;
      (e.senderId == me ? mine : theirs).add(day(e.originServerTs));
    }
    var d = day(DateTime.now());
    var n = 0;
    while (mine.contains(d) && theirs.contains(d)) {
      n++;
      d = d.subtract(const Duration(days: 1));
    }
    const marks = [3, 7, 14, 30, 60, 100, 365];
    final key = 'keepr.buddy.streak.${room.id}';
    final done = AppSettings.store.getInt(key) ?? 0;
    final hit = marks.lastWhereOrNull((m) => n >= m && m > done);
    if (hit == null) return;
    AppSettings.store.setInt(key, hit);
    _say(_Hint('$hit days in a row with $_them', Icons.local_fire_department_rounded),
        mood: BuddyMood.happy, seconds: 6);
    final party = VibeEffects.byId('party');
    if (party != null) VibeEffects.play(context, party);
  }

  // ---- moods and hints ----

  void _wake() {
    _idle?.cancel();
    if (_sleepy) setState(() => _sleepy = false);
    _idle = Timer(const Duration(seconds: 45), () {
      if (mounted && c.sendController.text.isEmpty) {
        setState(() => _sleepy = true);
      }
    });
  }

  void _show(BuddyMood mood, BuddyProp? prop, int ms) {
    _flashTimer?.cancel();
    setState(() {
      _flash = mood;
      _flashProp = prop;
    });
    _flashTimer = Timer(Duration(milliseconds: ms), () {
      if (mounted) {
        setState(() {
          _flash = null;
          _flashProp = null;
        });
      }
    });
  }

  void _say(_Hint h, {BuddyMood? mood, BuddyProp? prop, int seconds = 4}) {
    if (!mounted) return;
    _wake();
    _hintTimer?.cancel();
    setState(() => _hint = h);
    if (mood != null) _show(mood, prop, seconds * 1000);
    _hintTimer = Timer(Duration(seconds: seconds), () {
      if (mounted) setState(() => _hint = null);
    });
  }

  // ---- touch ----

  void _tap() {
    VibeHaptics.light();
    _wake();
    setState(() => _wiggle++);
    _show(BuddyMood.giggle, null, 1200);
  }

  void _tickle() {
    VibeHaptics.medium();
    setState(() => _wiggle++);
    Future.delayed(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _wiggle++);
    });
    _show(BuddyMood.giggle, null, 2200);
  }

  Future<void> _menu() async {
    VibeHaptics.medium();
    final cs = Theme.of(context).colorScheme;
    final text = c.sendController.text.trim();
    final pick = await showVibeSheet<String>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (text.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.schedule_send_outlined),
                title: const Text('Send later'),
                onTap: () => Navigator.of(ctx).pop('later'),
              ),
            ListTile(
              leading: const Icon(Icons.alarm_rounded),
              title: Text('Remind me to reply to $_them'),
              onTap: () => Navigator.of(ctx).pop('remind'),
            ),
            ListTile(
              leading: Icon(Icons.pets_rounded, color: cs.primary),
              title: Text('${VibeBuddy.name}: name, outfits, on or off'),
              onTap: () => Navigator.of(ctx).pop('settings'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || pick == null) return;
    switch (pick) {
      case 'later':
        await VibeSendLater.pick(context, c);
      case 'settings':
        await VibeBuddyPage.open(context);
      case 'remind':
        await _remind();
    }
  }

  Future<void> _remind() async {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1, 9);
    final choices = <(String, DateTime)>[
      ('In 30 minutes', now.add(const Duration(minutes: 30))),
      ('In 1 hour', now.add(const Duration(hours: 1))),
      ('In 3 hours', now.add(const Duration(hours: 3))),
      ('Tomorrow morning', tomorrow),
    ];
    final at = await showVibeSheet<DateTime>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (label, t) in choices)
              ListTile(
                leading: const Icon(Icons.alarm_rounded),
                title: Text(label),
                onTap: () => Navigator.of(ctx).pop(t),
              ),
          ],
        ),
      ),
    );
    if (at == null || !mounted) return;
    try {
      await VibeBuddy.remind(room, at, _them);
      _say(const _Hint("I'll remind you", Icons.alarm_on_rounded),
          mood: BuddyMood.happy);
    } catch (_) {
      _say(const _Hint("Couldn't set the reminder", Icons.alarm_off_rounded),
          mood: BuddyMood.worried);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!VibeBuddy.on) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final mood =
        _flash ?? (_sleepy ? BuddyMood.sleepy : _typingMood);
    final prop = _flashProp ?? (_pq ? BuddyProp.shield : BuddyProp.none);
    final hint = _hint;
    return SizedBox(
      height: 46,
      child: Padding(
        padding: const EdgeInsets.only(left: 16, right: 18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.bottomRight,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  transitionBuilder: (child, a) => FadeTransition(
                    opacity: a,
                    child: ScaleTransition(
                      scale: Tween(begin: 0.9, end: 1.0).animate(a),
                      alignment: Alignment.bottomRight,
                      child: child,
                    ),
                  ),
                  child: hint == null
                      ? const SizedBox.shrink()
                      : Padding(
                          key: ValueKey(hint.text),
                          padding: const EdgeInsets.only(bottom: 10, right: 4),
                          child: Material(
                            color: cs.surfaceContainerHigh,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(16),
                              topRight: Radius.circular(16),
                              bottomLeft: Radius.circular(16),
                              bottomRight: Radius.circular(4),
                            ),
                            elevation: 2,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: hint.onTap == null
                                  ? () => setState(() => _hint = null)
                                  : () {
                                      setState(() => _hint = null);
                                      hint.onTap!();
                                    },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 7,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(hint.icon, size: 16, color: cs.primary),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        hint.text,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: cs.onSurface,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                ),
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _tap,
              onDoubleTap: _tickle,
              onLongPress: _menu,
              child: Semantics(
                label: VibeBuddy.name,
                button: true,
                child: VibeBuddyFace(
                  size: 34,
                  color: cs.primary,
                  mood: mood,
                  prop: prop,
                  outfit: VibeBuddy.outfit,
                  gaze: _gaze,
                  hop: _hop,
                  wiggle: _wiggle,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:vibe/config/setting_keys.dart';
import 'package:vibe/l10n/l10n.dart';
import 'package:vibe/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:vibe/vibe/buddy/bujji.dart';
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

class _VibeBuddyBarState extends State<VibeBuddyBar>
    with SingleTickerProviderStateMixin {
  ChatController get c => widget.controller;
  Room get room => c.room;

  BuddyMood _typingMood = BuddyMood.idle;
  BuddyMood? _flash; // a short mood that wins for a moment
  BuddyProp? _flashProp;
  _Hint? _hint;
  int _hop = 0, _wiggle = 0;
  double _gaze = 0;

  /// Bumped to squish Bujji (touching or petting it).
  int _squish = 0;

  /// Pulled by your finger: how far it stretches, and the spring that
  /// brings it back (wobbling a little past its shape) when you let go.
  Offset _pull = Offset.zero, _raw = Offset.zero, _let = Offset.zero;
  late final AnimationController _spring = AnimationController.unbounded(
    vsync: this,
  )..addListener(() => setState(() => _pull = _let * _spring.value));

  /// Where it was, to lean the way it glides.
  double? _lastX;
  double _lean = 0;
  Timer? _leanTimer;
  bool _sleepy = false;

  /// When you last scrolled (so scrolling keeps it awake without a flood).
  int _lastScroll = 0;
  String? _lastEventId;
  bool _toldAsleep = false;
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
    c.scrollController.addListener(_onScroll);
    VibeBuddy.says.addListener(_onSays);
    VibeBuddy.here = room.id;
    _lastEventId = room.lastEvent?.eventId;
    _activity();
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
        // a new message keeps it awake (it sleeps through them at night)
        final last = room.lastEvent?.eventId;
        if (last != _lastEventId) {
          _lastEventId = last;
          _activity();
        }
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
    _spring.dispose();
    c.sendController.removeListener(_onText);
    VibeBuddy.sent.removeListener(_onSent);
    VibeBuddy.changed.removeListener(_refresh);
    c.scrollController.removeListener(_onScroll);
    VibeBuddy.says.removeListener(_onSays);
    if (VibeBuddy.here == room.id) VibeBuddy.here = null;
    VibeBuddy.dozing.value = false;
    for (final t in [
      _leanTimer,
      _flashTimer,
      _hintTimer,
      _idle,
      _deleteReset,
      _pqTimer,
      _answerTimer,
    ]) {
      t?.cancel();
    }
    _presence?.cancel();
    _sync?.cancel();
    super.dispose();
  }

  void _refresh() {
    if (!VibeBuddy.on) VibeBuddy.dozing.value = false;
    if (mounted) setState(() {});
  }

  /// Bujji answered something you asked it here.
  String? _answer;
  List<BujjiChoice> _choices = const [];
  Timer? _answerTimer;

  void _onSays() {
    final a = VibeBuddy.says.value;
    if (a == null || !mounted) return;
    VibeBuddy.says.value = null;
    _activity(pet: true);
    _answerTimer?.cancel();
    final last = Bujji.log.lastOrNull;
    setState(() {
      _answer = a;
      _choices = last != null && !last.me && last.text == a ? last.choices : const [];
      _hop++;
    });
    _show(BuddyMood.happy, null, 1600);
    _answerTimer = Timer(Duration(seconds: (_choices.isEmpty ? 6 : 14) + a.length ~/ 25), () {
      if (mounted) setState(() => _answer = null);
    });
  }

  void _onScroll() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastScroll < 2000) return;
    _lastScroll = now;
    _activity();
  }

  void _checkPq() {
    final on = VibePq.on(room);
    if (on != _pq && mounted) setState(() => _pq = on);
  }

  Future<void> _afterOpen() async {
    if (!mounted) return;
    VibeBuddy.shareIn(room, Theme.of(context).colorScheme.primary);
    // after midnight it's asleep until you pet it
    if (VibeBuddy.night) _setSleep(true);
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
    _activity();
    // typing at night doesn't wake it; say so once
    if (_sleepy && text.trim().isNotEmpty && !_toldAsleep) {
      _toldAsleep = true;
      _say(
        _Hint('${VibeBuddy.name} is asleep. Pet it to wake it',
            Icons.bedtime_outlined, () => _tap()),
        seconds: 5,
      );
    }
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
    if (Bujji.forBujji(text) != null) {
      // talking to Bujji: it listens, nothing else chimes in
      mood = BuddyMood.happy;
    } else if (text.trim().isNotEmpty) {
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

  /// Something happened: it stays (or wakes) up, and dozes off again after
  /// a quiet while (a minute and a half by day, half a minute at bedtime,
  /// a minute after midnight). After midnight only petting wakes it.
  void _activity({bool pet = false}) {
    _idle?.cancel();
    if (_sleepy && (pet || !VibeBuddy.night)) _setSleep(false);
    final quiet = VibeBuddy.night
        ? 60
        : VibeBuddy.bedtime
        ? 30
        : 90;
    _idle = Timer(Duration(seconds: quiet), () {
      if (mounted && c.sendController.text.isEmpty) _setSleep(true);
    });
  }

  void _setSleep(bool v) {
    if (!mounted) return;
    if (_sleepy != v) setState(() => _sleepy = v);
    VibeBuddy.dozing.value = v && VibeBuddy.on;
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
    final wasAsleep = _sleepy;
    _activity(pet: true);
    setState(() => _wiggle++);
    if (wasAsleep) {
      // a stretch and a smile; the chat brightens
      _say(const _Hint("I'm up", Icons.wb_sunny_outlined),
          mood: BuddyMood.happy, prop: BuddyProp.wave, seconds: 2);
      return;
    }
    _show(BuddyMood.giggle, null, 1200);
  }

  // ---- stretch: press and drag, it springs back ----

  void _grab(DragStartDetails d) {
    _spring.stop();
    _raw = Offset.zero;
    VibeHaptics.light();
    _activity(pet: true);
    _show(BuddyMood.giggle, null, 1500);
  }

  void _stretch(DragUpdateDetails d) {
    _raw += d.delta;
    // it gives less the further you pull, up to about 80 px
    final m = _raw.distance;
    setState(
      () => _pull = m == 0
          ? Offset.zero
          : _raw / m * (80 * (1 - math.exp(-m / 80))),
    );
  }

  void _letGo(DragEndDetails d) {
    VibeHaptics.light();
    _let = _pull;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      setState(() => _pull = Offset.zero);
      return;
    }
    _spring.animateWith(
      SpringSimulation(
        SpringDescription.withDampingRatio(mass: 1, stiffness: 320, ratio: 0.28),
        1,
        0,
        0,
      ),
    );
    setState(() => _squish++);
  }

  /// Longer along the pull, thinner across it, leaning after the finger.
  static Matrix4 _stretchOf(Offset pull, double size) {
    final m = pull.distance;
    if (m < 0.5) return Matrix4.identity();
    final c = pull.dx / m, s = pull.dy / m;
    final k = 1 + m / size * 0.9, j = 1 / math.sqrt(k);
    final a = k * c * c + j * s * s, b = (k - j) * c * s;
    final dd = k * s * s + j * c * c;
    return Matrix4(
      a, b, 0, 0, //
      b, dd, 0, 0,
      0, 0, 1, 0,
      pull.dx * 0.35, pull.dy * 0.35, 0, 1,
    );
  }

  void _tickle() {
    VibeHaptics.medium();
    _activity(pet: true);
    setState(() {
      _wiggle++;
      _squish++;
    });
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
              title: Text('${VibeBuddy.name}: outfits, on or off'),
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

  /// Leans (-1 left, 1 right) for a moment when it glides to a new spot.
  double _leanFor(double x) {
    final last = _lastX;
    _lastX = x;
    if (last != null && (x - last).abs() > 3) {
      _lean = (x - last).sign;
      _leanTimer?.cancel();
      _leanTimer = Timer(const Duration(milliseconds: 450), () {
        if (mounted) setState(() => _lean = 0);
      });
    }
    return _lean;
  }

  /// Where the cursor is along the text box, from its left edge.
  double _caretX(double fieldWidth) {
    final text = c.sendController.text;
    if (text.isEmpty) return 0;
    final tp = TextPainter(
      text: TextSpan(text: text, style: const TextStyle(fontSize: 16)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: math.max(40, fieldWidth));
    final x = tp
        .getOffsetForCaret(TextPosition(offset: text.length), Rect.zero)
        .dx;
    tp.dispose();
    return x;
  }

  @override
  Widget build(BuildContext context) {
    if (!VibeBuddy.on) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    // bedtime: tired unless your words say otherwise
    final awake = VibeBuddy.bedtime && _typingMood == BuddyMood.idle
        ? BuddyMood.tired
        : _typingMood;
    final mood = _flash ?? (_sleepy ? BuddyMood.sleepy : awake);
    final prop = _flashProp ?? (_pq ? BuddyProp.shield : BuddyProp.none);
    final hint = _hint;
    final answer = _answer;
    const size = 42.0, box = size * 1.3;
    return AnimatedSize(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      alignment: Alignment.bottomCenter,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // what Bujji says back, above it
          if (answer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Material(
                  color: cs.secondaryContainer,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                    bottomLeft: Radius.circular(4),
                    bottomRight: Radius.circular(18),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () {
                      setState(() => _answer = null);
                      BujjiChatPage.open(context);
                    },
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            answer,
                            maxLines: 8,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14.5,
                              height: 1.35,
                              color: cs.onSecondaryContainer,
                            ),
                          ),
                          if (_choices.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  for (final c in _choices)
                                    ActionChip(
                                      visualDensity: VisualDensity.compact,
                                      label: Text(c.label),
                                      onPressed: () async {
                                        final r = await Bujji.choose(
                                          c,
                                          roomId: widget.controller.room.id,
                                        );
                                        if (mounted) VibeBuddy.says.value = r.text;
                                        r.act?.call();
                                      },
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          SizedBox(
            height: box + 4,
            child: LayoutBuilder(
              builder: (context, cons) {
                final w = cons.maxWidth;
                // the text box starts 26 px in; + and send take ~140 px
                final field = w - 140;
                final x = (26 + _caretX(field) - box / 2).clamp(
                  6.0,
                  w - box - 6,
                );
                final onLeft = x < w / 2;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    if (hint != null)
                      Positioned(
                        left: onLeft ? x + box - 4 : 12,
                        right: onLeft ? 12 : w - x - 4,
                        bottom: 10,
                        child: Align(
                          alignment: onLeft
                              ? Alignment.bottomLeft
                              : Alignment.bottomRight,
                          child: _bubble(hint, cs, onLeft),
                        ),
                      ),
                    // Bujji floats along above the box with your words, leaning
                    // the way it glides
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 650),
                      curve: Curves.easeInOutSine,
                      left: x,
                      bottom: 0,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (_) => setState(() => _squish++),
                        onTap: _tap,
                        onDoubleTap: _tickle,
                        onLongPress: _menu,
                        onPanStart: _grab,
                        onPanUpdate: _stretch,
                        onPanEnd: _letGo,
                        child: Semantics(
                          label: VibeBuddy.name,
                          button: true,
                          child: Transform(
                            alignment: Alignment.center,
                            transform: _stretchOf(_pull, size),
                            child: AnimatedRotation(
                            turns: _leanFor(x) * 0.022,
                            duration: const Duration(milliseconds: 420),
                            curve: Curves.easeOutCubic,
                            alignment: Alignment.bottomCenter,
                            child: VibeBuddyFace(
                              size: size,
                              color: cs.primary,
                              mood: mood,
                              prop: prop,
                              outfit: VibeBuddy.outfit,
                              // while pulled it looks the way it's pulled
                              gaze: _pull == Offset.zero
                                  ? _gaze
                                  : (_pull.dx / 50).clamp(-1.0, 1.0),
                              // it watches your words in the box below
                              look: mood == BuddyMood.sleepy ? 0 : 0.85,
                              floating: true,
                              hop: _hop,
                              wiggle: _wiggle,
                              squish: _squish,
                            ),
                          ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _bubble(_Hint hint, ColorScheme cs, bool fromLeft) => Material(
    color: cs.surfaceContainerHigh,
    elevation: 2,
    borderRadius: BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: Radius.circular(fromLeft ? 4 : 16),
      bottomRight: Radius.circular(fromLeft ? 16 : 4),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        setState(() => _hint = null);
        hint.onTap?.call();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
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
  );
}

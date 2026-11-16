// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:vibe/config/setting_keys.dart';
import 'package:vibe/l10n/l10n.dart';
import 'package:vibe/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:vibe/vibe/buddy/bujji.dart';
import 'package:vibe/vibe/buddy/bujji_life.dart';
import 'package:vibe/vibe/buddy/vibe_buddy.dart';
import 'package:vibe/vibe/screens/chat/chat.dart';
import 'package:vibe/vibe/vibe_connections.dart';
import 'package:vibe/vibe/vibe_effects.dart';
import 'package:vibe/vibe/vibe_haptics.dart';
import 'package:vibe/vibe/vibe_hot_words.dart';
import 'package:vibe/vibe/vibe_motion.dart';
import 'package:vibe/vibe/vibe_pq.dart';
import 'package:vibe/vibe/vibe_live_location.dart';
import 'package:vibe/vibe/vibe_send_later.dart';
import 'package:vibe/widgets/matrix.dart';

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

/// Where Bujji went in the chat, and why: look (a new photo), peek (from
/// behind your message), typing (their dots), sleep (on the newest
/// message), hammer (a message you pinned).
class _Trip {
  final String spot;
  final String why;
  bool back = false;
  Rect? last;
  _Trip(this.spot, this.why);
}

class _VibeBuddyBarState extends State<VibeBuddyBar>
    with TickerProviderStateMixin {
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

  // ---- its life: trips round the chat, moods, things it holds ----
  final _portal = OverlayPortalController();
  final _home = GlobalKey();
  late final AnimationController _hopper = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 760),
  );

  /// Bumped when the chat scrolls, so a visiting Bujji stays on its message.
  final _moved = ValueNotifier<int>(0);
  _Trip? _trip;
  Timer? _tripTimer, _lifeTimer, _crossTimer, _bopTimer;
  StreamSubscription? _tools, _events, _shake, _playing;
  ValueNotifier<String?>? _voice;

  /// Held while something lasts (headphones while a voice note plays).
  BuddyProp? _hold;

  /// The song you're playing (from your connected account): it dances to
  /// it, hopping between messages, or feels it quietly if it's a sad one.
  VibeTrack? _music;
  Timer? _danceTimer;

  /// Poked too much: it hides behind a message until you pet it there.
  bool _sulking = false;
  int _pets = 0;

  /// Poked too often: cross, then its back to you.
  bool _cross = false, _away = false;
  int _pokes = 0, _pokeAt = 0, _shakes = 0, _shakeAt = 0;
  int _lastWander = 0, _lastIdle = 0, _lastOffer = 0;
  final _offered = <String>{};

  static int get _now => DateTime.now().millisecondsSinceEpoch;
  bool get _alive => BujjiLife.pace != BujjiPace.off;

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
    _tools = BujjiLife.tools.listen(_onTool);
    BujjiLife.job.addListener(_onJob);
    _events = room.client.onTimelineEvent.stream
        .where((e) => e.room.id == room.id)
        .listen(_onEvent);
    _lifeTimer = Timer.periodic(const Duration(seconds: 25), (_) => _idleLife());
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
          // then it hurries over to peek at their dots
          Future.delayed(const Duration(milliseconds: 550), () {
            if (mounted && room.typingUsers.any((u) => u.id == other)) {
              _wander('typing', 'typing', const Duration(seconds: 12));
            }
          });
        }
        if (!now && typing && _trip?.why == 'typing') _comeBack();
        typing = now;
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _afterOpen());
  }

  @override
  void dispose() {
    _spring.dispose();
    _hopper.dispose();
    _moved.dispose();
    for (final s in [_tools, _events, _shake, _playing]) {
      s?.cancel();
    }
    for (final t in [_tripTimer, _lifeTimer, _crossTimer, _bopTimer]) {
      t?.cancel();
    }
    _voice?.removeListener(_onVoice);
    VibeConnections.playing.removeListener(_onMusic);
    _danceTimer?.cancel();
    c.sendController.removeListener(_onText);
    VibeBuddy.sent.removeListener(_onSent);
    VibeBuddy.changed.removeListener(_refresh);
    BujjiLife.job.removeListener(_onJob);
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
    // answering: glasses on, something in hand
    _show(
      BuddyMood.smart,
      a.startsWith('Remind you')
          ? BuddyProp.bulb
          : a.startsWith('Found') || a.startsWith('Nothing in Settings')
          ? BuddyProp.magnifier
          : BuddyProp.clipboard,
      2600,
    );
    _answerTimer = Timer(Duration(seconds: (_choices.isEmpty ? 6 : 14) + a.length ~/ 25), () {
      if (mounted) setState(() => _answer = null);
    });
  }

  void _onScroll() {
    _moved.value++;
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
    if (!mounted) return;
    _listenVoice();
    VibeConnections.playing.addListener(_onMusic);
    _onMusic();
    _listenShake();
    // its day: the first chat of the morning, it's having its coffee
    final now = DateTime.now();
    if (_alive && now.hour >= 5 && now.hour < 11) {
      final day = '${now.year}-${now.month}-${now.day}';
      if (AppSettings.store.getString('keepr.bujji.coffee') != day) {
        AppSettings.store.setString('keepr.bujji.coffee', day);
        Future.delayed(const Duration(milliseconds: 900), () {
          if (mounted && _flash == null) {
            _show(BuddyMood.sleepy, BuddyProp.coffee, 3600);
          }
        });
      }
    }
  }

  // ---- what you type ----

  void _onText() {
    final text = c.sendController.text;
    _activity();
    // you're typing: back to the text box
    if (text.isNotEmpty && _trip != null && _trip!.why != 'hammer') {
      _comeBack();
    }
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
    // "you're so cute, Bujji": it goes shy
    if (_alive && BujjiLife.compliment(text)) mood = BuddyMood.shy;
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
        mood: _alive ? BuddyMood.proud : BuddyMood.happy, seconds: 6);
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
    if (!v && _trip?.why == 'sleep') _comeBack();
    if (v && (VibeBuddy.night || VibeBuddy.bedtime)) {
      // late at night it curls up on the newest message
      final id = c.timeline?.events
          .firstWhereOrNull((e) => BujjiLife.rectOf(e.eventId) != null)
          ?.eventId;
      if (id != null) {
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted && _sleepy) {
            _wander(id, 'sleep', const Duration(hours: 1));
          }
        });
      }
    }
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

  // ---- its life ----

  /// Pin, edit, delete, copy: it brings the tool for it.
  void _onTool((String, String?) t) {
    if (!mounted || !VibeBuddy.on) return;
    final (kind, id) = t;
    _activity(pet: true);
    switch (kind) {
      case 'pin':
        // it climbs onto the message and taps the pin in
        if (id != null &&
            _wander(id, 'hammer', const Duration(milliseconds: 2800), force: true)) {
          for (final ms in [1100, 1950, 2600]) {
            Future.delayed(Duration(milliseconds: ms), VibeHaptics.selection);
          }
          return;
        }
        _show(BuddyMood.happy, BuddyProp.hammer, 2600);
      case 'edit':
        // it picks up the pen and keeps it until the edit is sent
        setState(() => _hop++);
      case 'delete':
        _show(BuddyMood.idle, BuddyProp.broom, 2600);
      case 'copy':
        _show(BuddyMood.smart, BuddyProp.clipboard, 1800);
    }
  }

  /// What it's busy with, tool in hand until it's done: the pen while you
  /// edit, a letter while you reply, the magnifier while you search; the
  /// hammer, broom, camera or paper until a pin, delete or upload is done.
  BuddyProp? get _busy {
    if (BujjiLife.pace == BujjiPace.off) return null;
    if (c.editEvent != null) return BuddyProp.pen;
    if (c.searching) return BuddyProp.magnifier;
    if (c.replyEvent != null) return BuddyProp.paper;
    return switch (BujjiLife.job.value) {
      'pin' => BuddyProp.hammer,
      'delete' => BuddyProp.broom,
      'photo' => BuddyProp.camera,
      'file' => BuddyProp.paper,
      _ => null,
    };
  }

  String? _lastJob;

  /// A job finished: puts the tool down, pleased with itself.
  void _onJob() {
    if (!mounted) return;
    final was = _lastJob, now = BujjiLife.job.value;
    _lastJob = now;
    if (was != null && now == null && VibeBuddy.on) {
      _show(BuddyMood.proud, null, 1400);
    } else {
      setState(() {});
    }
  }

  /// Something new in this chat: what it calls for.
  void _onEvent(Event raw) {
    if (!mounted || !VibeBuddy.on || !_alive) return;
    // only what just happened, not history catching up
    if (DateTime.now().difference(raw.originServerTs).inSeconds.abs() > 90) {
      return;
    }
    final e = VibePq.open(raw);
    final mine = e.senderId == room.client.userID;
    if (e.type == EventTypes.Reaction) {
      final key = e.content
              .tryGetMap<String, Object?>('m.relates_to')
              ?.tryGet<String>('key') ??
          '';
      // your heart: it jumps up and catches it
      if (mine && RegExp('^(\u2764|\u2665|\u{1F60D}|\u{1F970}|\u{1F495}|\u{1F496}|\u{1F497})', unicode: true).hasMatch(key)) {
        _show(BuddyMood.love, BuddyProp.catchHeart, 2400);
        setState(() => _hop++);
      }
      return;
    }
    if (!mine &&
        (e.type == EventTypes.CallInvite ||
            (e.type == 'org.matrix.msc3401.call.member' && e.content.isNotEmpty))) {
      _show(BuddyMood.curious, BuddyProp.phone, 4000);
      return;
    }
    if (e.type != EventTypes.Message ||
        e.relationshipType == RelationshipTypes.edit) {
      return;
    }
    if (e.content[VibeLive.checkKey] is Map) {
      _show(BuddyMood.happy, BuddyProp.flag, 2600);
      return;
    }
    switch (e.messageType) {
      case MessageTypes.Image:
        if (mine) {
          _show(BuddyMood.wink, BuddyProp.camera, 2400);
        } else {
          // a new photo: it hops over and sits on it to look
          Future.delayed(const Duration(milliseconds: 900), () {
            if (mounted &&
                !_wander(e.eventId, 'look', const Duration(seconds: 5))) {
              _show(BuddyMood.curious, null, 1800);
            }
          });
        }
      case MessageTypes.Text || MessageTypes.Notice || MessageTypes.Emote:
        final text = e.body;
        final w = BujjiLife.forWords(text, mine: mine);
        if (w != null) {
          _show(w.$1, w.$2 == BuddyProp.none ? null : w.$2, 3000);
        }
        if (mine && BujjiLife.compliment(text)) {
          _show(BuddyMood.shy, null, 2600);
        }
        // a time someone mentions: it offers a reminder (once a message)
        final at = Bujji.timeIn(text);
        if (at != null &&
            _offered.add(e.eventId) &&
            _now - _lastOffer > 120000) {
          _lastOffer = _now;
          Bujji.offer(text, at, room.id);
        }
      default:
        break;
    }
  }

  /// Every little while, if nothing's going on, it does something: peeks
  /// from behind a message, plays catch, reads, has its coffee.
  void _idleLife() {
    if (!mounted || !_alive || !VibeBuddy.on) return;
    if (_trip != null || _cross || _sleepy || _flash != null || _busy != null) {
      return;
    }
    if (_hint != null || _answer != null || c.sendController.text.isNotEmpty) {
      return;
    }
    final now = _now;
    if (now - _lastIdle < 60000) return;
    final r = math.Random();
    if (now - _lastWander > 120000 && r.nextDouble() < 0.3 && _peek()) {
      _lastIdle = now;
      return;
    }
    if (r.nextDouble() > 0.35) return;
    _lastIdle = now;
    final h = DateTime.now().hour;
    if (h >= 13 && h < 17) {
      _show(BuddyMood.happy, BuddyProp.ball, 3200);
      setState(() => _hop++);
    } else if (h >= 19 && h < 22) {
      _show(BuddyMood.smart, BuddyProp.book, 4500);
    } else if (h >= 5 && h < 11) {
      _show(BuddyMood.sleepy, BuddyProp.coffee, 3500);
    }
  }

  /// Peeks out from behind your newest message on screen.
  bool _peek() {
    final me = room.client.userID;
    for (final e in (c.timeline?.events ?? const <Event>[]).take(15)) {
      if (e.senderId != me || e.type != EventTypes.Message) continue;
      if (BujjiLife.rectOf(e.eventId) != null) {
        return _wander(e.eventId, 'peek', const Duration(seconds: 4));
      }
    }
    return false;
  }

  Rect? _homeRect() {
    final r = _home.currentContext?.findRenderObject();
    if (r is! RenderBox || !r.attached || !r.hasSize) return null;
    return r.localToGlobal(Offset.zero) & r.size;
  }

  /// On screen: below the top bar and above the text box.
  static bool _onScreen(Rect to, Rect home) =>
      to.top > 100 && to.top < home.top - 24;

  /// Hops over to [spot] for [stay]. Only when lively, the phone allows
  /// motion, you're not typing and it's on screen.
  bool _wander(String spot, String why, Duration stay, {bool force = false}) {
    if (!mounted || _trip != null || _cross || !VibeBuddy.on) return false;
    if (BujjiLife.pace != BujjiPace.lively ||
        (MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
      return false;
    }
    if (!force && c.sendController.text.isNotEmpty) return false;
    final to = BujjiLife.rectOf(spot), home = _homeRect();
    if (to == null || home == null || !_onScreen(to, home)) return false;
    _lastWander = _now;
    setState(() => _trip = _Trip(spot, why));
    _portal.show();
    VibeHaptics.light();
    _hopper.forward(from: 0).whenComplete(() {
      // lands with a squish
      if (mounted && _trip?.back == false) setState(() => _squish++);
    });
    _tripTimer?.cancel();
    _tripTimer = Timer(stay, _comeBack);
    return true;
  }

  void _comeBack() {
    _tripTimer?.cancel();
    final trip = _trip;
    if (trip == null || trip.back || !mounted) return;
    trip.back = true;
    _hopper.reverse().whenComplete(() {
      if (!mounted) return;
      _portal.hide();
      setState(() {
        _trip = null;
        _squish++;
        // still upset (its message scrolled away): its back to you until
        // you hold it
        if (_sulking) {
          _sulking = false;
          _cross = true;
          _away = true;
        }
      });
    });
  }

  /// Bujji on its trip: hopping in an arc from the text box to the message
  /// and sitting on it (or peeking from behind it).
  Widget _wanderer(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([_hopper, _moved]),
    builder: (context, _) {
      final trip = _trip;
      final home = _homeRect();
      final ob = Overlay.maybeOf(context)?.context.findRenderObject();
      if (trip == null || home == null || ob is! RenderBox || !ob.hasSize) {
        return const SizedBox.shrink();
      }
      var to = BujjiLife.rectOf(trip.spot);
      if (to == null || !_onScreen(to, home)) {
        // scrolled away from under it: it comes home
        if (!trip.back) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _comeBack());
        }
        to = trip.last ?? home;
      } else {
        trip.last = to;
      }
      const size = 42.0, box = size * 1.3;
      final start = home.bottomCenter;
      final end = switch (trip.why) {
        'typing' => Offset(to.right + box * 0.5, to.bottom - 2),
        'hammer' => Offset(to.right - box * 0.75, to.top + 4),
        'peek' || 'hide' => Offset(to.left + box * 0.65, to.top + box * 0.34),
        _ => Offset(
          to.center.dx.clamp(to.left + box / 2, math.max(to.left + box / 2, to.right - box / 2)),
          to.top + 4,
        ),
      };
      final k = Curves.easeInOutCubic.transform(_hopper.value);
      final ctrl = Offset(
        (start.dx + end.dx) / 2,
        math.min(start.dy, end.dy) - 90,
      );
      final g = Offset(
        (1 - k) * (1 - k) * start.dx + 2 * (1 - k) * k * ctrl.dx + k * k * end.dx,
        (1 - k) * (1 - k) * start.dy + 2 * (1 - k) * k * ctrl.dy + k * k * end.dy,
      );
      final p = ob.globalToLocal(g);
      final there = _hopper.value > 0.98 && !trip.back;
      final cs = Theme.of(context).colorScheme;
      final (mood, prop) = switch (trip.why) {
        'sleep' => (BuddyMood.sleepy, BuddyProp.bed),
        'hammer' => (BuddyMood.happy, there ? BuddyProp.hammer : BuddyProp.none),
        'dance' => (BuddyMood.happy, BuddyProp.headphones),
        // hiding, upset; softening as you pet it
        'hide' => (_pets < 2 ? BuddyMood.angry : BuddyMood.shy, BuddyProp.none),
        _ => (BuddyMood.curious, BuddyProp.none),
      };
      final face = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (trip.why == 'hide') {
            _petHidden();
            return;
          }
          VibeHaptics.light();
          _activity(pet: true);
          _comeBack();
        },
        child: VibeBuddyFace(
          size: size,
          color: cs.primary,
          mood: mood,
          prop: prop,
          outfit: VibeBuddy.outfit,
          // hiding: its back to you until the first pet
          away: trip.why == 'hide' && _pets == 0,
          groove: trip.why == 'dance' ? 1 : 0,
          gaze: trip.why == 'typing' ? -1 : trip.why == 'peek' ? 1 : 0,
          look: trip.why == 'sleep' ? 0 : 1,
          floating: !there,
          hop: _hop,
          wiggle: _wiggle,
          squish: _squish,
        ),
      );
      if ((trip.why == 'peek' || trip.why == 'hide') && _hopper.value > 0.7) {
        // only its top shows above your message: it peeks from behind it
        final edge = ob.globalToLocal(Offset(0, to.top)).dy;
        return Stack(
          children: [
            Positioned(
              left: p.dx - box / 2,
              top: edge - box,
              width: box,
              height: box,
              child: ClipRect(
                child: Transform.translate(
                  offset: Offset(0, p.dy - edge),
                  child: face,
                ),
              ),
            ),
          ],
        );
      }
      return Stack(
        children: [
          Positioned(
            left: p.dx - box / 2,
            top: p.dy - box,
            width: box,
            height: box,
            child: face,
          ),
        ],
      );
    },
  );

  // a voice note playing: headphones on, bopping along
  void _listenVoice() {
    try {
      _voice = Matrix.of(context).voiceMessageEventId..addListener(_onVoice);
    } catch (_) {}
  }

  void _onVoice() {
    _playing?.cancel();
    _playing = null;
    if (_voice?.value == null || !mounted) {
      // back to your music if some is playing
      _hold = null;
      _setHold(_music != null && _alive ? BuddyProp.headphones : null);
      return;
    }
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted || _voice?.value == null) return;
      final player = Matrix.of(context).audioPlayer;
      if (player == null) return;
      _playing = player.playingStream.listen(
        (on) => _setHold(on && _alive ? BuddyProp.headphones : null),
      );
    });
  }

  void _setHold(BuddyProp? v) {
    if (!mounted || _hold == v) return;
    setState(() => _hold = v);
    _bopTimer?.cancel();
    if (v == BuddyProp.headphones) {
      // your music moves it smoothly (see groove); a voice note bops it
      if (_voice?.value != null || _music == null) {
        _bopTimer = Timer.periodic(const Duration(milliseconds: 900), (_) {
          if (mounted) setState(() => _wiggle++);
        });
      }
    }
  }

  // your music (from a connected account): headphones on while it plays
  void _onMusic() {
    if (!mounted) return;
    final t = VibeConnections.playing.value;
    final was = _music;
    _music = t;
    _danceTimer?.cancel();
    _danceTimer = null;
    // a voice note playing keeps its own headphones
    if (_voice?.value != null) return;
    if (was?.sad != t?.sad || (was == null) != (t == null)) _hold = null;
    _setHold(t != null && _alive ? BuddyProp.headphones : null);
    if (t == null || t.sad) {
      if (_trip?.why == 'dance') _comeBack();
      return;
    }
    // now and then it hops over to a message and dances on it
    _danceTimer = Timer.periodic(const Duration(seconds: 25), (_) => _danceHop());
    Future<void>.delayed(const Duration(seconds: 4), _danceHop);
  }

  void _danceHop() {
    final t = _music;
    if (!mounted || t == null || t.sad || _trip != null || _busy != null) return;
    final shown = (c.timeline?.events ?? const <Event>[])
        .take(14)
        .where((e) => e.type == EventTypes.Message && BujjiLife.rectOf(e.eventId) != null)
        .toList();
    if (shown.isEmpty) return;
    final e = shown[math.Random().nextInt(shown.length)];
    _wander(e.eventId, 'dance', const Duration(seconds: 6));
  }

  // shake the phone: it gets dizzy
  void _listenShake() {
    if (kIsWeb) return;
    try {
      _shake = userAccelerometerEventStream(
        samplingPeriod: SensorInterval.uiInterval,
      ).listen(
        (a) {
          if (a.x * a.x + a.y * a.y + a.z * a.z < 16 * 16) return;
          final now = _now;
          _shakes = now - _shakeAt < 700 ? _shakes + 1 : 1;
          _shakeAt = now;
          if (_shakes >= 3) {
            _shakes = 0;
            _dizzy();
          }
        },
        onError: (_) {},
        cancelOnError: true,
      );
    } catch (_) {}
  }

  void _dizzy() {
    if (!mounted || !_alive || !VibeBuddy.on || _flash == BuddyMood.dizzy) {
      return;
    }
    VibeHaptics.medium();
    _show(BuddyMood.dizzy, null, 2600);
    setState(() => _wiggle++);
  }

  // poke it again and again: it gets cross and turns its back
  void _poke() {
    setState(() => _squish++);
    if (!_alive || _cross) return;
    final now = _now;
    _pokes = now - _pokeAt < 1500 ? _pokes + 1 : 1;
    _pokeAt = now;
    if (_pokes >= 6) {
      _pokes = 0;
      _getCross();
    }
  }

  void _getCross() {
    _cross = true;
    VibeHaptics.medium();
    if (_trip != null) _comeBack();
    _say(
      const _Hint('Hmph. Stop poking!', Icons.sentiment_dissatisfied_rounded),
      mood: BuddyMood.angry,
      seconds: 3,
    );
    _crossTimer?.cancel();
    _crossTimer = Timer(const Duration(milliseconds: 1600), () {
      if (!mounted || !_cross) return;
      setState(() => _away = true);
      // then it walks off and hides behind a message, until you pet it
      _crossTimer = Timer(const Duration(milliseconds: 1400), () {
        if (!mounted || !_cross) return;
        if (_hideAway()) {
          _say(
            const _Hint('Hiding. Find me and pet me', Icons.visibility_off_outlined),
            seconds: 4,
          );
          return;
        }
        // nowhere to hide: it stays turned away until you hold it
        _say(
          const _Hint('Hold me to make up', Icons.touch_app_outlined),
          seconds: 4,
        );
      });
    });
  }

  /// Hops off to a message on screen and hides behind it.
  bool _hideAway() {
    final shown = (c.timeline?.events ?? const <Event>[])
        .take(14)
        .where((e) => e.type == EventTypes.Message && BujjiLife.rectOf(e.eventId) != null)
        .toList();
    if (shown.isEmpty) return false;
    final e = shown[math.Random().nextInt(shown.length)];
    // a trip can't start while cross
    _cross = false;
    _pets = 0;
    if (!_wander(e.eventId, 'hide', const Duration(hours: 6), force: true)) {
      _cross = true;
      return false;
    }
    setState(() {
      _sulking = true;
      _away = false;
    });
    return true;
  }

  /// Petting it where it hides: a few pets and it comes back, friends again.
  void _petHidden() {
    VibeHaptics.light();
    _activity(pet: true);
    setState(() {
      _pets++;
      _squish++;
    });
    if (_pets < 4) return;
    _sulking = false;
    _comeBack();
    Future<void>.delayed(const Duration(milliseconds: 820), () {
      if (mounted) _makeUp();
    });
  }

  /// Held while cross: friends again.
  void _makeUp() {
    _crossTimer?.cancel();
    VibeHaptics.light();
    setState(() {
      _away = false;
      _cross = false;
      _sulking = false;
      _hint = null;
    });
    _show(BuddyMood.shy, null, 1100);
    Future.delayed(const Duration(milliseconds: 1100), () {
      if (!mounted) return;
      _show(BuddyMood.love, BuddyProp.heart, 2400);
      setState(() => _hop++);
    });
  }

  // ---- touch ----

  void _tap() {
    if (_cross) return;
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
    // flung hard: it spins
    if (d.velocity.pixelsPerSecond.distance > 2400) _dizzy();
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
    if (_cross) return;
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
    final mood = _cross
        ? BuddyMood.angry
        : _flash ??
              (_sleepy
                  ? BuddyMood.sleepy
                  : _hold == BuddyProp.headphones
                  ? (_music?.sad == true && _voice?.value == null
                        ? BuddyMood.worried
                        : BuddyMood.happy)
                  : awake);
    final bed = _sleepy && _alive && (VibeBuddy.night || VibeBuddy.bedtime);
    final prop =
        _flashProp ??
        _busy ??
        _hold ??
        (bed
            ? BuddyProp.bed
            : _pq
            ? BuddyProp.shield
            : BuddyProp.none);
    final hint = _hint;
    final answer = _answer;
    const size = 42.0, box = size * 1.3;
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: _wanderer,
      child: AnimatedSize(
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
                        key: _home,
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (_) => _poke(),
                        onTap: _tap,
                        onDoubleTap: _tickle,
                        // cross: holding it makes up
                        onLongPress: _cross ? _makeUp : _menu,
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
                            // away visiting a message: it isn't here
                            child: Opacity(
                              opacity: _trip == null ? 1 : 0,
                              child: BujjiSpot(
                                id: 'tour.bujji',
                                child: VibeBuddyFace(
                              size: size,
                              color: cs.primary,
                              mood: mood,
                              prop: prop,
                              away: _away,
                              outfit: VibeBuddy.outfit,
                              // while pulled it looks the way it's pulled
                              gaze: _pull == Offset.zero
                                  ? _gaze
                                  : (_pull.dx / 50).clamp(-1.0, 1.0),
                              // it watches your words in the box below
                              look: mood == BuddyMood.sleepy ? 0 : 0.85,
                              floating: true,
                              groove: _hold == BuddyProp.headphones &&
                                      _music != null &&
                                      _voice?.value == null
                                  ? (_music!.sad ? 0.4 : 1.0)
                                  : 0,
                              hop: _hop,
                              wiggle: _wiggle,
                              squish: _squish,
                            ),
                            ),
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

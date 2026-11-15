// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:vibe/vibe/buddy/bujji_live.dart';
import 'package:vibe/vibe/buddy/bujji_model.dart';
import 'package:vibe/vibe/buddy/bujji_settings.dart';
import 'package:vibe/vibe/buddy/vibe_buddy.dart';
import 'package:vibe/vibe/vibe_whats_new.dart';

/// Bujji's memory: things you tell it, reminders you ask for, and your talk
/// with it. Plain rules (plus, if you download it, a small sentence model
/// that runs on the phone); all of it stays in this phone's secure storage
/// and never goes into a chat.
///
/// In any chat, a message that starts with @bujji goes to Bujji, not to the
/// chat: "@bujji naren phone number is 12257383929", "@bujji what's naren's
/// mobile", "@bujji gowthu birthday is today, remind me to wish her at 3",
/// "@bujji chat".
class BujjiNote {
  final String id;

  /// What it's about ("naren phone number"); empty for a plain note.
  final String key;
  final String value;
  final int ts;
  const BujjiNote(this.id, this.key, this.value, this.ts);

  String get label => key.isEmpty ? value : Bujji.cap(key);

  Map<String, Object?> toJson() => {'id': id, 'k': key, 'v': value, 't': ts};
  static BujjiNote from(Map j) => BujjiNote(
    j['id'] as String,
    j['k'] as String,
    j['v'] as String,
    j['t'] as int,
  );
}

class BujjiReminder {
  final String id;
  final String text;
  final int at;

  /// '', 'daily', 'weekly', 'monthly' or 'yearly'.
  final String repeat;
  final String? roomId;
  const BujjiReminder(this.id, this.text, this.at, this.repeat, this.roomId);

  bool get yearly => repeat == 'yearly';
  DateTime get when => DateTime.fromMillisecondsSinceEpoch(at);

  /// The next time it rings (repeating ones roll forward).
  DateTime get next {
    var d = when;
    final now = DateTime.now();
    var guard = 0;
    while (repeat.isNotEmpty && d.isBefore(now) && guard++ < 4000) {
      d = switch (repeat) {
        'daily' => DateTime(d.year, d.month, d.day + 1, d.hour, d.minute),
        'weekly' => DateTime(d.year, d.month, d.day + 7, d.hour, d.minute),
        'monthly' => DateTime(d.year, d.month + 1, d.day, d.hour, d.minute),
        _ => DateTime(d.year + 1, d.month, d.day, d.hour, d.minute),
      };
    }
    return d;
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'x': text,
    'at': at,
    'rp': repeat,
    'r': roomId,
  };
  static BujjiReminder from(Map j) => BujjiReminder(
    j['id'] as String,
    j['x'] as String,
    j['at'] as int,
    (j['rp'] as String?) ?? (j['y'] == true ? 'yearly' : ''),
    j['r'] as String?,
  );
}

/// A button under one of Bujji's answers.
class BujjiChoice {
  final String label;
  final String id;
  const BujjiChoice(this.label, this.id);
  List<String> toJson() => [label, id];
}

class BujjiLine {
  final bool me;
  final String text;
  final int ts;
  final List<BujjiChoice> choices;
  const BujjiLine(this.me, this.text, this.ts, [this.choices = const []]);
  Map<String, Object?> toJson() => {
    'm': me,
    'x': text,
    't': ts,
    if (choices.isNotEmpty) 'c': choices.map((c) => c.toJson()).toList(),
  };
  static BujjiLine from(Map j) => BujjiLine(
    j['m'] == true,
    j['x'] as String,
    j['t'] as int,
    [
      for (final c in (j['c'] as List? ?? const []))
        BujjiChoice((c as List)[0] as String, c[1] as String),
    ],
  );
}

class BujjiReply {
  final String text;
  final bool openChat;
  final List<BujjiChoice> choices;

  /// Something to do in the app (open a Settings page); whoever shows the
  /// answer runs it.
  final VoidCallback? act;
  const BujjiReply(
    this.text, {
    this.openChat = false,
    this.choices = const [],
    this.act,
  });
}

abstract class Bujji {
  static const _storage = FlutterSecureStorage();
  static const _slot = 'keepr.bujji.memory';

  static final notes = <BujjiNote>[];
  static final reminders = <BujjiReminder>[];
  static final log = <BujjiLine>[];

  /// First words you've taught it: "buy" means remember, and so on.
  static final _learned = <String, String>{};

  /// Fires when anything in its memory changes.
  static final changed = ValueNotifier<int>(0);
  static bool _loaded = false;

  // the conversation so far
  static String? _pending; // a reminder waiting for its time
  static String? _person; // who "her" / "him" means
  static String? _unclear; // what you said that it asked about

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final s = await _storage.read(key: _slot);
      if (s != null) {
        final j = jsonDecode(s) as Map;
        notes.addAll((j['n'] as List? ?? []).map((e) => BujjiNote.from(e as Map)));
        reminders.addAll(
          (j['r'] as List? ?? []).map((e) => BujjiReminder.from(e as Map)),
        );
        log.addAll((j['l'] as List? ?? []).map((e) => BujjiLine.from(e as Map)));
        _learned.addAll(Map<String, String>.from(j['k'] as Map? ?? const {}));
      }
    } catch (_) {}
    BujjiModel.refresh();
    changed.value++;
  }

  static Future<void> _save() async {
    if (log.length > 400) log.removeRange(0, log.length - 400);
    changed.value++;
    try {
      await _storage.write(
        key: _slot,
        value: jsonEncode({
          'n': notes.map((e) => e.toJson()).toList(),
          'r': reminders.map((e) => e.toJson()).toList(),
          'l': log.map((e) => e.toJson()).toList(),
          'k': _learned,
        }),
      );
    } catch (_) {}
  }

  static String _id() =>
      '${DateTime.now().microsecondsSinceEpoch}${math.Random().nextInt(999)}';

  /// The text after "@bujji" (or "@<its name>"), or null when the message
  /// isn't for Bujji.
  static String? forBujji(String text) {
    final t = text.trimLeft();
    final names = {'bujji', VibeBuddy.name.toLowerCase()};
    for (final n in names) {
      final m = RegExp('^@${RegExp.escape(n)}\\b[\\s,:]*', caseSensitive: false)
          .firstMatch(t);
      if (m != null) return t.substring(m.end).trim();
    }
    return null;
  }

  /// Things due today: reminders and yearly days (birthdays).
  static List<BujjiReminder> today() {
    final now = DateTime.now();
    bool same(DateTime d) =>
        d.year == now.year && d.month == now.month && d.day == now.day;
    return reminders.where((r) => same(r.next)).toList()
      ..sort((a, b) => a.next.compareTo(b.next));
  }

  /// Birthdays and anniversaries in the next [days] days (not today).
  static List<BujjiReminder> soon([int days = 7]) {
    final now = DateTime.now();
    final end = now.add(Duration(days: days));
    final today0 = DateTime(now.year, now.month, now.day + 1);
    return reminders
        .where((r) => r.yearly && !r.next.isBefore(today0) && r.next.isBefore(end))
        .toList()
      ..sort((a, b) => a.next.compareTo(b.next));
  }

  // ---- words ----

  static String fmtTime(DateTime d) {
    final now = DateTime.now();
    final t = DateFormat.jm().format(d);
    final days = DateTime(d.year, d.month, d.day)
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
    if (days == 0) return t;
    if (days == 1) return 'tomorrow at $t';
    if (days > 1 && days < 7) return '${DateFormat.EEEE().format(d)} at $t';
    return '${DateFormat('d MMM').format(d)} at $t';
  }

  static String cap(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  static const _stop = {
    'what', 'whats', "what's", 'is', 'are', 'the', 'a', 'an', 'of', 'my',
    'me', 'tell', 'do', 'you', 'know', 'when', 'whens', "when's", 'where',
    'who', 'whos', "who's", 'which', 'how', 'does', 'did', 'was', 'about',
    'please', 'bujji', 'his', 'her', 'their', 'to', 'for', 'and', 's',
    'remember', 'can', 'could', 'i', 'it', 'in', 'on', 'at', 'again',
  };

  /// Words that mean the same thing, folded to one.
  static const _same = {
    'mobile': 'phone', 'number': 'phone', 'contact': 'phone', 'cell': 'phone',
    'ph': 'phone', 'num': 'phone', 'phno': 'phone', 'reach': 'phone',
    'call': 'phone',
    'bday': 'birthday', 'birth': 'birthday', 'born': 'birthday',
    'dob': 'birthday',
    'mail': 'email', 'gmail': 'email', 'emailid': 'email',
    'addr': 'address', 'house': 'address', 'lives': 'address', 'live': 'address',
    'mum': 'mom', 'amma': 'mom', 'mother': 'mom', 'mommy': 'mom',
    'father': 'dad', 'nanna': 'dad', 'appa': 'dad', 'daddy': 'dad',
    'pwd': 'password', 'pass': 'password', 'passcode': 'password',
  };

  static List<String> _words(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r"'s\b"), '')
      .replaceAll(RegExp(r"[^a-z0-9\s]"), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty && !_stop.contains(w))
      .map((w) => _same[w] ?? w)
      .toList();

  /// Small typing slips count as the same word ("gowtu" is "gowthu").
  static bool _alike(String a, String b) {
    if (a == b) return true;
    final n = math.min(a.length, b.length);
    if (n < 4) return false;
    return _edits(a, b) <= (math.max(a.length, b.length) >= 7 ? 2 : 1);
  }

  static int _edits(String a, String b) {
    var prev = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
      for (var j = 1; j <= b.length; j++) {
        cur[j] = [
          prev[j] + 1,
          cur[j - 1] + 1,
          prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1),
        ].reduce(math.min);
      }
      prev = cur;
    }
    return prev[b.length];
  }

  static String _key(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r"'s\b"), '')
      .replaceAll(RegExp(r'^(my|the)\s+'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Drops filler and folds the many ways of asking into a few.
  static String _clean(String text) {
    var t = text.trim().replaceAll('\u2019', "'");
    final fill = RegExp(
      r"^(please|pls|plz|kindly|hey|hi|hello|ok|okay|so|also|just|can you|could you|would you|will you)\b[\s,]*",
      caseSensitive: false,
    );
    for (var i = 0; i < 4; i++) {
      final m = fill.firstMatch(t);
      if (m == null) break;
      t = t.substring(m.end);
    }
    final rules = <(RegExp, String)>[
      (RegExp(r"\b(?:do not|don'?t|dont) let me forget(?: to| about)?\b", caseSensitive: false), 'remind me to'),
      (RegExp(r'\bset (?:a |an )?(?:reminder|alarm)(?: to| for)?\b', caseSensitive: false), 'remind me to'),
      (RegExp(r'\b(?:ping|alert|notify|wake|nudge|buzz) me\b', caseSensitive: false), 'remind me'),
      (RegExp(r'^reminder\s*[:,-]?\s*', caseSensitive: false), 'remind me to '),
      (RegExp(r'^(?:note|save|store|keep in mind)(?: that)?\s*[:,-]?\s+', caseSensitive: false), 'remember '),
    ];
    for (final (re, to) in rules) {
      t = t.replaceAll(re, to);
    }
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  // ---- talking ----

  /// Handles what you said to Bujji and returns its answer. [chatName] is
  /// the person you're chatting with, for "her" and "him".
  static Future<BujjiReply> handle(
    String said, {
    String? roomId,
    String? chatName,
  }) async {
    await load();
    final text = said.trim();
    log.add(
      BujjiLine(
        true,
        text.isEmpty ? '@${VibeBuddy.name}' : text,
        DateTime.now().millisecondsSinceEpoch,
      ),
    );
    final reply = await _answer(text, roomId, chatName);
    log.add(
      BujjiLine(false, reply.text, DateTime.now().millisecondsSinceEpoch, reply.choices),
    );
    await _save();
    return reply;
  }

  /// Bujji tells you something on its own (live locations, check-ins):
  /// a line in its chat, and above the typing bar when that chat is open.
  static Future<void> tell(
    String text, {
    String? roomId,
    List<BujjiChoice> choices = const [],
  }) async {
    await load();
    log.add(
      BujjiLine(false, text, DateTime.now().millisecondsSinceEpoch, choices),
    );
    await _save();
    if (roomId != null && VibeBuddy.here == roomId) VibeBuddy.says.value = text;
  }

  /// One of the buttons under an answer was tapped.
  static Future<BujjiReply> choose(BujjiChoice c, {String? roomId}) async {
    await load();
    log.add(BujjiLine(true, c.label, DateTime.now().millisecondsSinceEpoch));
    final said = _unclear ?? '';
    final first = _words(said).firstOrNull;
    BujjiReply reply;
    if (c.id.startsWith('live:') ||
        c.id.startsWith('check:') ||
        c.id.startsWith('set:') ||
        c.id.startsWith('rem:')) {
      if (c.id.startsWith('rem:')) {
        // a reminder it offered for a time in the chat
        final p = c.id.split(':');
        final at = DateTime.fromMillisecondsSinceEpoch(int.tryParse(p[1]) ?? 0);
        final task = p.sublist(2).join(':').replaceAll('∶', ':');
        reply = at.isAfter(DateTime.now())
            ? _setReminder(task, at, '', roomId)
            : const BujjiReply('That time has passed.');
      } else {
        reply = c.id.startsWith('set:')
            ? BujjiSettings.choose(c.id)
            : BujjiReply(await BujjiLive.act(c.id));
      }
      log.add(
        BujjiLine(false, reply.text, DateTime.now().millisecondsSinceEpoch),
      );
      await _save();
      return reply;
    } else if (c.id.startsWith('note:')) {
      final n = notes.where((n) => n.id == c.id.substring(5)).firstOrNull;
      reply = n == null
          ? const BujjiReply("I don't have that any more.")
          : _tell(n);
    } else {
      // remember what this kind of sentence means next time
      if (first != null && said.isNotEmpty) _learned[first] = c.id;
      reply = switch (c.id) {
        'remind' => _remindFrom(said, roomId, null),
        'ask' => await _ask(said.toLowerCase()),
        _ => _isFact(said.toLowerCase()) ? _learn(said) : _note(said),
      };
    }
    _unclear = null;
    log.add(
      BujjiLine(false, reply.text, DateTime.now().millisecondsSinceEpoch, reply.choices),
    );
    await _save();
    return reply;
  }

  static final _question = RegExp(
    r"^(what|whats|what's|when|whens|when's|where|wheres|where's|who|whos|who's|which|how|tell me|do you know|any|is there|did i)\b",
  );

  static Future<BujjiReply> _answer(
    String said,
    String? roomId,
    String? chatName,
  ) async {
    final text = _clean(said);
    final low = text.toLowerCase().replaceAll(RegExp(r'[?!.]+$'), '').trim();
    if (low.isEmpty || low == 'hi' || low == 'hello' || low == 'hey') {
      return const BujjiReply(
        'Hi! Tell me something to remember, ask me about it, or ask for a '
        'reminder. Say "@bujji help" for examples.',
      );
    }
    if (const {'chat', 'open', 'open chat', 'notes', 'your chat', 'memory'}
        .contains(low)) {
      return const BujjiReply('Opening my notes.', openChat: true);
    }
    if (low == 'help') {
      return const BujjiReply(
        'Try:\n'
        '@bujji naren phone number is 98xxxxxx\n'
        "@bujji what's naren's mobile\n"
        '@bujji gowthu birthday is 3 march\n'
        '@bujji remind me to call mom at 6 pm\n'
        "@bujji don't let me forget the rent on the 5th\n"
        '@bujji ping me in half an hour\n'
        '@bujji every monday at 10 remind me to send the report\n'
        '@bujji what do you remember\n'
        '@bujji forget naren phone number\n'
        '@bujji open notification settings\n'
        '@bujji turn on dark mode\n'
        '@bujji search typing indicators in settings\n'
        "@bujji what's new\n"
        '@bujji chat',
      );
    }
    // the update tour, told by Bujji
    if (RegExp(r"^(what('|\u2019)?s new|what is new|new features|(show me )?(the )?tour)$")
        .hasMatch(low)) {
      return const BujjiReply("Here's what's new!", act: VibeWhatsNew.tour);
    }
    // Settings: open a page, switch something, find where it is
    final settings = BujjiSettings.answer(low);
    if (settings != null) return settings;
    if (RegExp(r'^(what do you (remember|know)|list|everything|show notes)$')
        .hasMatch(low)) {
      final up = reminders.where((r) => r.next.isAfter(DateTime.now())).length;
      if (notes.isEmpty && up == 0) {
        return const BujjiReply('Nothing yet. Tell me something to remember.');
      }
      final some = notes.reversed
          .take(6)
          .map((n) => n.key.isEmpty ? '· ${n.value}' : '· ${n.label}: ${n.value}')
          .join('\n');
      return BujjiReply(
        '${notes.length} notes and $up reminders.${some.isEmpty ? '' : '\n$some'}',
      );
    }
    if (RegExp(r'^(my |any |show )?reminders( today)?$').hasMatch(low) ||
        low.contains('what are my reminders')) {
      final up = reminders.where((r) => r.next.isAfter(DateTime.now())).toList()
        ..sort((a, b) => a.next.compareTo(b.next));
      if (up.isEmpty) return const BujjiReply('No reminders coming up.');
      return BujjiReply(
        up.take(6).map((r) => '· ${fmtTime(r.next)}: ${r.text}').join('\n'),
      );
    }
    final forget = RegExp(r'^(forget|delete|remove|erase)\s+(about\s+)?(.+)$')
        .firstMatch(low);
    if (forget != null) return _forget(forget.group(3)!);

    // the answer to "when should I remind you?"
    final pending = _pending;
    _pending = null;
    if (pending != null) {
      final (at, left, repeat) = _when(low);
      if (at != null && _words(left).isEmpty) {
        return _setReminder(pending, at, repeat, roomId);
      }
    }

    if (low.contains('remind me')) return _remind(text, low, roomId, chatName);
    if (_question.hasMatch(low) || said.trim().endsWith('?')) {
      return _ask(low);
    }
    if (low.startsWith('remember ')) {
      final rest = text.substring(9).replaceFirst(
        RegExp(r'^that\s+', caseSensitive: false),
        '',
      );
      // "remember to call mom at 5" asks for a reminder
      if (rest.toLowerCase().startsWith('to ')) {
        return _remindFrom(rest, roomId, chatName);
      }
      return _isFact(rest.toLowerCase()) ? _learn(rest) : _note(rest);
    }
    if (_isFact(low)) return _learn(text);

    // something it has learned from your taps
    final first = _words(low).firstOrNull;
    switch (first == null ? null : _learned[first]) {
      case 'remind':
        return _remindFrom(text, roomId, chatName);
      case 'ask':
        return _ask(low);
      case 'remember':
        return _note(text);
    }
    // a time in it: probably a reminder
    final (at, _, _) = _when(low);
    if (at != null) return _remindFrom(text, roomId, chatName);

    // not sure: ask, and learn from the answer
    _unclear = text;
    return const BujjiReply(
      'Should I remember this, set a reminder, or is it a question?',
      choices: [
        BujjiChoice('Remember', 'remember'),
        BujjiChoice('Remind me', 'remind'),
        BujjiChoice('Question', 'ask'),
      ],
    );
  }

  static BujjiReply _forget(String what) {
    final w = _words(what);
    if (w.isEmpty) return const BujjiReply("I don't have that.");
    bool hits(String s) {
      final k = _words(s);
      return w.every((x) => k.any((y) => _alike(x, y)));
    }
    final gone = notes.where((n) => hits(n.key.isEmpty ? n.value : n.key)).toList();
    final goneR = reminders.where((r) => hits(r.text)).toList();
    if (gone.isEmpty && goneR.isEmpty) return const BujjiReply("I don't have that.");
    notes.removeWhere(gone.contains);
    for (final r in goneR) {
      _cancel(r);
    }
    reminders.removeWhere(goneR.contains);
    return BujjiReply(
      'Forgotten: ${[...gone.map((n) => n.key.isEmpty ? n.value : n.key), ...goneR.map((r) => r.text)].join(', ')}.',
    );
  }

  // ---- reminders ----

  static final _remindRe = RegExp(
    r'^(.*?)(?:,?\s*(?:so|and|then)\s+|,\s*|^|\s+)remind me\s*(?:to\s+|about\s+|of\s+|that\s+)?(.*)$',
  );

  static BujjiReply _remind(String text, String low, String? roomId, String? chatName) {
    final m = _remindRe.firstMatch(low);
    if (m == null) return _remindFrom(text, roomId, chatName);
    final before = m.group(1)!.trim();
    final after = m.group(2)!.trim();
    final out = <String>[];
    var timeText = after;
    if (before.isNotEmpty) {
      if (_isFact(before)) {
        out.add(_learn(text.substring(0, before.length)).text);
      } else {
        // "at 3 remind me to …": the time can come first
        timeText = '$before $after';
      }
    }
    final r = _remindFrom(timeText, roomId, chatName);
    out.add(r.text);
    return BujjiReply(out.join(' '), choices: r.choices);
  }

  /// A reminder from words that hold a task and (maybe) a time.
  static BujjiReply _remindFrom(String words, String? roomId, String? chatName) {
    final (at, left, repeat) = _when(words.toLowerCase());
    var task = left
        .replaceAll(RegExp(r'^(remind me|to|that|about)\s+'), '')
        .trim();
    // "her" / "him": the last person you talked about, or this chat
    final who = _person ?? chatName;
    if (who != null && who.isNotEmpty) {
      task = task.replaceAllMapped(
        RegExp(r'\b(her|him|them)\b'),
        (_) => cap(who.split(' ').first),
      );
    }
    if (at == null) {
      _pending = task.isEmpty ? 'the thing you asked' : task;
      return const BujjiReply(
        'When should I remind you? Just say a time, like "at 3 pm", "in 20 '
        'minutes" or "tomorrow morning".',
      );
    }
    return _setReminder(task.isEmpty ? 'the thing you asked' : task, at, repeat, roomId);
  }

  /// A time someone mentions in a message ("tomorrow 5 pm"), when it's
  /// between half an hour and a week away: Bujji offers a reminder.
  static DateTime? timeIn(String text) {
    final low = text.toLowerCase();
    // only when it really names a time or a day
    if (!RegExp(
      r'\b(\d{1,2}(:\d{2})?\s*(am|pm)|\d{1,2}:\d{2}|tomorrow|tonight|today|'
      r'monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b',
    ).hasMatch(low)) {
      return null;
    }
    final (at, _, repeat) = _when(low);
    if (at == null || repeat.isNotEmpty) return null;
    final d = at.difference(DateTime.now());
    if (d < const Duration(minutes: 30) || d > const Duration(days: 7)) {
      return null;
    }
    return at;
  }

  /// Offers to remind you a little before [at] (30 min, or at the time when
  /// that's too soon).
  static void offer(String text, DateTime at, String roomId) {
    final when = at.subtract(const Duration(minutes: 30));
    final remind = when.isAfter(DateTime.now().add(const Duration(minutes: 5)))
        ? when
        : at;
    final task = text.length > 60 ? '${text.substring(0, 57)}…' : text;
    tell(
      'Remind you ${fmtTime(remind)}?',
      roomId: roomId,
      choices: [
        BujjiChoice(
          'Remind me',
          'rem:${remind.millisecondsSinceEpoch}:${task.replaceAll(':', '∶')}',
        ),
        const BujjiChoice('No thanks', 'live:ok'),
      ],
    );
  }

  static BujjiReply _setReminder(String task, DateTime at, String repeat, String? roomId) {
    final r = BujjiReminder(_id(), task, at.millisecondsSinceEpoch, repeat, roomId);
    reminders.add(r);
    _schedule(r);
    final every = switch (repeat) {
      'daily' => 'every day at ${DateFormat.jm().format(at)}',
      'weekly' => 'every ${DateFormat.EEEE().format(at)} at ${DateFormat.jm().format(at)}',
      'monthly' => 'every month on the ${at.day}${_th(at.day)} at ${DateFormat.jm().format(at)}',
      'yearly' => 'every year on ${DateFormat('d MMMM').format(at)}',
      _ => fmtTime(at),
    };
    return BujjiReply("Okay, I'll remind you $every: $task.");
  }

  static String _th(int d) => d >= 11 && d <= 13
      ? 'th'
      : switch (d % 10) {
          1 => 'st',
          2 => 'nd',
          3 => 'rd',
          _ => 'th',
        };

  // ---- facts and questions ----

  static final _fact = RegExp(
    r'^(.+?)\s+(?:is|are|=|:)\s+(.+)$',
    caseSensitive: false,
  );
  static bool _isFact(String low) => _fact.hasMatch(low) && !_question.hasMatch(low);

  static BujjiReply _note(String text) {
    notes.add(BujjiNote(_id(), '', text.trim(), DateTime.now().millisecondsSinceEpoch));
    return const BujjiReply('Saved as a note.');
  }

  static BujjiReply _learn(String text) {
    final m = _fact.firstMatch(text.trim())!;
    final key = _key(m.group(1)!);
    var value = m.group(2)!.trim().replaceAll(RegExp(r'[.!]+$'), '');
    _who(key);
    final day = _day(value.toLowerCase().replaceFirst(RegExp(r'^on\s+'), ''));
    var extra = '';
    if (day != null) {
      value = DateFormat('d MMMM').format(day);
      // birthdays and anniversaries: a reminder that morning, every year
      if (_words(key).contains('birthday') || key.contains('anniversary')) {
        final title = '${cap(key)} today';
        reminders.removeWhere((r) {
          final same = r.yearly && r.text == title;
          if (same) _cancel(r);
          return same;
        });
        final at = DateTime(day.year, day.month, day.day, 9);
        final r = BujjiReminder(_id(), title, at.millisecondsSinceEpoch, 'yearly', null);
        reminders.add(r);
        _schedule(r);
        extra = " I'll remind you every year that morning.";
      }
    }
    notes.removeWhere((n) => n.key == key);
    notes.add(BujjiNote(_id(), key, value, DateTime.now().millisecondsSinceEpoch));
    return BujjiReply('Got it. ${cap(key)} is $value.$extra');
  }

  /// "naren phone number": later "call him" means Naren.
  static void _who(String key) {
    final w = _words(key);
    if (w.length >= 2 &&
        w.skip(1).any(const {'phone', 'birthday', 'email', 'address', 'anniversary'}.contains)) {
      _person = key.split(' ').first;
    }
  }

  static BujjiReply _tell(BujjiNote n) {
    _who(n.key);
    return BujjiReply(n.key.isEmpty ? n.value : '${cap(n.key)} is ${n.value}.');
  }

  /// Finds the note a question is about: by its words (allowing for
  /// synonyms and small slips), and by meaning when the model is on.
  static Future<BujjiReply> _ask(String low) async {
    if (notes.isEmpty) {
      return const BujjiReply("I don't know anything yet. Tell me something first.");
    }
    final q = _words(low);
    // by words
    BujjiNote? best;
    var score = 0;
    for (final n in notes) {
      final k = _words(n.key.isEmpty ? n.value : n.key);
      final s = q.where((w) => k.any((x) => _alike(w, x))).length;
      if (s > score || (s == score && s > 0 && n.ts > (best?.ts ?? 0))) {
        best = n;
        score = s;
      }
    }
    if (best != null && q.isNotEmpty && score == q.length) return _tell(best);
    // by meaning
    final qv = await BujjiModel.embed(low);
    if (qv != null) {
      final ranked = <(double, BujjiNote)>[];
      for (final n in notes) {
        final v = await BujjiModel.embed(
          n.key.isEmpty ? n.value : '${n.key}: ${n.value}',
        );
        if (v != null) ranked.add((BujjiModel.similarity(qv, v), n));
      }
      ranked.sort((a, b) => b.$1.compareTo(a.$1));
      if (ranked.isNotEmpty && ranked.first.$1 >= 0.5) return _tell(ranked.first.$2);
      final maybe = ranked.where((r) => r.$1 >= 0.33).take(2).toList();
      if (maybe.isNotEmpty) {
        _unclear = low;
        return BujjiReply(
          'Did you mean:',
          choices: [for (final r in maybe) BujjiChoice(r.$2.label, 'note:${r.$2.id}')],
        );
      }
    }
    if (best != null && score > 0) return _tell(best);
    return const BujjiReply(
      "I don't know that yet. Tell me, like: @bujji naren phone number is …",
    );
  }

  // ---- dates and times ----

  static const _months = [
    'jan', 'feb', 'mar', 'apr', 'may', 'jun',
    'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
  ];

  static int? _mon(String s) {
    if (s.length < 3) return null;
    final i = _months.indexWhere((m) => s.startsWith(m));
    return i < 0 ? null : i + 1;
  }

  /// "today", "tomorrow", "15 nov", "nov 15", "15th of november", "15/11".
  static DateTime? _day(String v) {
    final now = DateTime.now();
    v = v.trim();
    if (v == 'today') return now;
    if (v == 'tomorrow') return now.add(const Duration(days: 1));
    if (v == 'yesterday') return now.subtract(const Duration(days: 1));
    var m = RegExp(r'^(\d{1,2})(?:st|nd|rd|th)?\s+(?:of\s+)?([a-z]+)(?:\s+\d{4})?$').firstMatch(v);
    if (m != null && _mon(m.group(2)!) != null) {
      return DateTime(now.year, _mon(m.group(2)!)!, int.parse(m.group(1)!));
    }
    m = RegExp(r'^([a-z]+)\s+(\d{1,2})(?:st|nd|rd|th)?(?:,?\s+\d{4})?$').firstMatch(v);
    if (m != null && _mon(m.group(1)!) != null) {
      return DateTime(now.year, _mon(m.group(1)!)!, int.parse(m.group(2)!));
    }
    m = RegExp(r'^(\d{1,2})[/.-](\d{1,2})(?:[/.-]\d{2,4})?$').firstMatch(v);
    if (m != null) {
      final d = int.parse(m.group(1)!), mo = int.parse(m.group(2)!);
      if (mo >= 1 && mo <= 12 && d >= 1 && d <= 31) return DateTime(now.year, mo, d);
    }
    return null;
  }

  static const _weekdays = {
    'monday': 1, 'mon': 1, 'tuesday': 2, 'tue': 2, 'tues': 2,
    'wednesday': 3, 'wed': 3, 'thursday': 4, 'thu': 4, 'thur': 4,
    'thurs': 4, 'friday': 5, 'fri': 5, 'saturday': 6, 'sat': 6,
    'sunday': 7, 'sun': 7,
  };

  /// The time in [s] and what's left of the words (the task), and how it
  /// repeats: "at 3", "3:30 pm", "3 o'clock", "in 20 minutes", "in half an
  /// hour", "tomorrow morning", "tonight", "next friday", "on the 5th",
  /// "on 20 nov", "this weekend", "after lunch", "every monday at 10",
  /// "every day", "every month", "every year".
  static (DateTime?, String, String) _when(String s) {
    final now = DateTime.now();
    var rest = ' ${s.toLowerCase()} ';
    String cut(RegExpMatch m) {
      rest = rest.replaceFirst(m.group(0)!, ' ');
      return m.group(0)!;
    }

    var repeat = '';
    DateTime? day;
    int? weekday;
    int? hour, minute;
    var evening = false, morning = false;

    // how it repeats
    final every = RegExp(
      r'\b(?:every\s*(day|morning|night|evening|week|month|year|monday|mon|tuesday|tue|tues|wednesday|wed|thursday|thu|thur|thurs|friday|fri|saturday|sat|sunday|sun)|(daily|weekly|monthly|yearly|annually|everyday))\b',
    ).firstMatch(rest);
    if (every != null) {
      cut(every);
      final w = every.group(1) ?? every.group(2)!;
      if (_weekdays.containsKey(w)) {
        repeat = 'weekly';
        weekday = _weekdays[w];
      } else {
        repeat = switch (w) {
          'week' || 'weekly' => 'weekly',
          'month' || 'monthly' => 'monthly',
          'year' || 'yearly' || 'annually' => 'yearly',
          _ => 'daily',
        };
        if (w == 'morning') morning = true;
        if (w == 'night' || w == 'evening') evening = true;
      }
    }

    // "in 20 minutes", "in half an hour", "in a week"
    final rel = RegExp(
      r'\bin\s+(\d+|a|an|one|two|three|half an?)\s*(minutes?|mins?|hours?|hrs?|days?|weeks?)\b',
    ).firstMatch(rest);
    if (rel != null && repeat.isEmpty) {
      cut(rel);
      final raw = rel.group(1)!;
      final u = rel.group(2)!;
      final n = switch (raw) {
        'a' || 'an' || 'one' => 1.0,
        'two' => 2.0,
        'three' => 3.0,
        'half a' || 'half an' => 0.5,
        _ => double.parse(raw),
      };
      final mins = u.startsWith('w')
          ? n * 7 * 24 * 60
          : u.startsWith('d')
          ? n * 24 * 60
          : u.startsWith('h')
          ? n * 60
          : n;
      final at = now.add(Duration(minutes: mins.round()));
      return (at, _left(rest), '');
    }

    // which day
    void dayWord(String re, int add) {
      final m = RegExp('\\b$re\\b').firstMatch(rest);
      if (m != null && day == null) {
        cut(m);
        day = DateTime(now.year, now.month, now.day + add);
      }
    }
    dayWord('day after tomorrow', 2);
    dayWord('tomorrow', 1);
    final tonight = RegExp(r'\btonight\b').firstMatch(rest);
    if (tonight != null) {
      cut(tonight);
      day ??= DateTime(now.year, now.month, now.day);
      evening = true;
    }
    dayWord('today', 0);
    final weekend = RegExp(r'\b(this|the|next)?\s*weekend\b').firstMatch(rest);
    if (weekend != null && day == null) {
      cut(weekend);
      weekday ??= 6;
      hour ??= 10;
    }
    final wd = RegExp(
      r'\b(next|this|on|coming)?\s*(monday|tuesday|tues|wednesday|thursday|thurs|friday|saturday|sunday|mon|tue|wed|thu|thur|fri|sat|sun)\b',
    ).firstMatch(rest);
    if (wd != null && day == null) {
      cut(wd);
      weekday = _weekdays[wd.group(2)!];
    }
    final nth = RegExp(r'\bon\s+(?:the\s+)?(\d{1,2})(?:st|nd|rd|th)\b').firstMatch(rest);
    if (nth != null && day == null) {
      cut(nth);
      final d = int.parse(nth.group(1)!);
      var t = DateTime(now.year, now.month, d);
      if (t.isBefore(DateTime(now.year, now.month, now.day))) {
        t = DateTime(now.year, now.month + 1, d);
      }
      day = t;
    }
    final date = RegExp(
      r'\b(?:on\s+)?(\d{1,2}(?:st|nd|rd|th)?\s+(?:of\s+)?(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*|(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\s+\d{1,2}(?:st|nd|rd|th)?|\d{1,2}[/-]\d{1,2})\b',
    ).firstMatch(rest);
    if (date != null && day == null) {
      final d = _day(date.group(1)!);
      if (d != null) {
        cut(date);
        day = d.isBefore(DateTime(now.year, now.month, now.day))
            ? DateTime(d.year + 1, d.month, d.day)
            : d;
      }
    }

    // parts of the day
    for (final (re, h, eve, morn) in [
      (r'\bafter lunch\b', 14, false, false),
      (r'\b(?:at\s+)?lunch(?:\s*time)?\b', 13, false, false),
      (r'\b(?:at\s+)?dinner(?:\s*time)?\b', 20, true, false),
      (r'\b(?:at\s+)?noon\b', 12, false, false),
      (r'\b(?:at\s+)?midnight\b', 0, false, false),
      (r'\b(?:in the\s+)?morning\b', 9, false, true),
      (r'\b(?:in the\s+)?afternoon\b', 15, true, false),
      (r'\b(?:in the\s+)?evening\b', 18, true, false),
      (r'\b(?:at\s+)?night\b', 21, true, false),
    ]) {
      final m = RegExp(re).firstMatch(rest);
      if (m != null) {
        cut(m);
        hour ??= h;
        evening = evening || eve;
        morning = morning || morn;
        if (h == 0) day ??= DateTime(now.year, now.month, now.day + 1);
        break;
      }
    }

    // the clock
    final clock = RegExp(
      r"\b(?:at\s+|by\s+|@\s*)?(\d{1,2})(?:[:.](\d{2}))?\s*(am|pm|a\.m\.|p\.m\.|o'?\s?clock|hrs)\b|\b(?:at|by|@)\s*(\d{1,2})(?:[:.](\d{2}))?\b",
    ).firstMatch(rest);
    String? ap;
    var clockHour = false;
    if (clock != null) {
      cut(clock);
      hour = int.parse(clock.group(1) ?? clock.group(4)!);
      minute = int.parse(clock.group(2) ?? clock.group(5) ?? '0');
      ap = clock.group(3);
      clockHour = true;
    }

    if (day == null && weekday == null && hour == null && repeat.isEmpty) {
      return (null, _left(rest), '');
    }
    var h = hour ?? (evening ? 21 : 9);
    final mi = minute ?? 0;
    if (h > 23 || mi > 59) return (null, _left(rest), '');
    final isPm = ap != null && ap.startsWith('p');
    final isAm = ap != null && ap.startsWith('a');
    if (isPm && h < 12) h += 12;
    if (isAm && h == 12) h = 0;
    final told = ap != null && !ap.contains('clock') && ap != 'hrs';
    if (clockHour && !told && h < 12) {
      // no am or pm: evening words, or small numbers, mean the afternoon
      if (evening || (!morning && h >= 1 && h <= 7)) h += 12;
    }
    var base = day ?? DateTime(now.year, now.month, now.day);
    if (weekday != null) {
      var add = (weekday! - now.weekday + 7) % 7;
      final todayAt = DateTime(now.year, now.month, now.day, h, mi);
      if (add == 0 && todayAt.isBefore(now)) add = 7;
      base = DateTime(now.year, now.month, now.day + add);
    }
    var at = DateTime(base.year, base.month, base.day, h, mi);
    if (clockHour && !told && day == null && weekday == null && !evening && !morning &&
        at.isBefore(now) && h < 12) {
      // "at 10" said at 11 am: 10 pm
      final pm = at.add(const Duration(hours: 12));
      if (pm.isAfter(now)) at = pm;
    }
    // already gone today: the same time tomorrow (the answer says so)
    if (at.isBefore(now)) at = at.add(const Duration(days: 1));
    return (at, _left(rest), repeat);
  }

  static String _left(String rest) => rest
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'^\s*(remind me\s+)?(to|that|about|on|at)\s+'), '')
      .replaceAll(RegExp(r'\s+(on|at|by)\s*$'), '')
      .trim();

  // ---- notifications ----

  static int _nid(BujjiReminder r) => 'bujji_${r.id}'.hashCode;

  static Future<void> _schedule(BujjiReminder r) async {
    try {
      await FlutterLocalNotificationsPlugin().zonedSchedule(
        id: _nid(r),
        title: VibeBuddy.name,
        body: cap(r.text),
        scheduledDate: tz.TZDateTime.from(r.next.toUtc(), tz.UTC),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: switch (r.repeat) {
          'daily' => DateTimeComponents.time,
          'weekly' => DateTimeComponents.dayOfWeekAndTime,
          'monthly' => DateTimeComponents.dayOfMonthAndTime,
          'yearly' => DateTimeComponents.dateAndTime,
          _ => null,
        },
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'keepr_reminders',
            'Reminders',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
    } catch (_) {}
  }

  static Future<void> _cancel(BujjiReminder r) async {
    try {
      await FlutterLocalNotificationsPlugin().cancel(id: _nid(r));
    } catch (_) {}
  }

  static Future<void> removeNote(BujjiNote n) async {
    notes.remove(n);
    await _save();
  }

  static Future<void> removeReminder(BujjiReminder r) async {
    await _cancel(r);
    reminders.remove(r);
    await _save();
  }
}

/// Bujji's own chat: what you told it, what it answered, your notes and
/// reminders. Type here without "@bujji".
class BujjiChatPage extends StatefulWidget {
  const BujjiChatPage({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
    rootNavigator: true,
  ).push(MaterialPageRoute(builder: (_) => const BujjiChatPage()));

  @override
  State<BujjiChatPage> createState() => _BujjiChatPageState();
}

class _BujjiChatPageState extends State<BujjiChatPage> {
  final _text = TextEditingController();
  int _tab = 0;
  int _hop = 0;

  @override
  void initState() {
    super.initState();
    Bujji.load();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    _text.clear();
    setState(() => _hop++);
    final r = await Bujji.handle(Bujji.forBujji(t) ?? t);
    r.act?.call();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            VibeBuddyFace(size: 30, color: cs.primary, mood: BuddyMood.happy, hop: _hop),
            const SizedBox(width: 8),
            Text(VibeBuddy.name),
          ],
        ),
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: Bujji.changed,
        builder: (context, _, _) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                segments: [
                  const ButtonSegment(value: 0, label: Text('Chat')),
                  ButtonSegment(value: 1, label: Text('Notes ${Bujji.notes.length}')),
                  ButtonSegment(
                    value: 2,
                    label: Text('Reminders ${Bujji.reminders.length}'),
                  ),
                ],
                selected: {_tab},
                onSelectionChanged: (s) => setState(() => _tab = s.first),
              ),
            ),
            Expanded(
              child: switch (_tab) {
                1 => _notes(cs),
                2 => _reminders(cs),
                _ => _chat(cs),
              },
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _text,
                        textCapitalization: TextCapitalization.sentences,
                        onSubmitted: (_) => _send(),
                        decoration: InputDecoration(
                          hintText: 'Tell ${VibeBuddy.name} something…',
                          filled: true,
                          fillColor: cs.surfaceContainerHigh,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _send,
                      icon: const Icon(Icons.send_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty(String s) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(s, textAlign: TextAlign.center),
    ),
  );

  Widget _chat(ColorScheme cs) {
    final log = Bujji.log;
    if (log.isEmpty) {
      return _empty(
        'Tell ${VibeBuddy.name} things to remember, ask about them later, or '
        'ask for reminders. In any chat, start a message with @bujji.',
      );
    }
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: log.length,
      itemBuilder: (context, i) {
        final l = log[log.length - 1 - i];
        final bubble = Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.72,
          ),
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: l.me ? cs.primaryContainer : cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            l.text,
            style: TextStyle(
              fontSize: 15,
              color: l.me ? cs.onPrimaryContainer : cs.onSurface,
            ),
          ),
        );
        return Row(
          mainAxisAlignment: l.me ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!l.me) ...[
              VibeBuddyFace(size: 26, color: cs.primary, mood: BuddyMood.happy),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: i == 0 && !l.me && l.choices.isNotEmpty
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        bubble,
                        Wrap(
                          spacing: 6,
                          children: [
                            for (final c in l.choices)
                              ActionChip(
                                label: Text(c.label),
                                onPressed: () async =>
                                    (await Bujji.choose(c)).act?.call(),
                              ),
                          ],
                        ),
                      ],
                    )
                  : bubble,
            ),
          ],
        );
      },
    );
  }

  Widget _notes(ColorScheme cs) {
    final n = Bujji.notes.reversed.toList();
    if (n.isEmpty) return _empty('No notes yet.');
    return ListView(
      children: [
        for (final x in n)
          ListTile(
            leading: const Icon(Icons.sticky_note_2_outlined),
            title: Text(x.key.isEmpty ? x.value : Bujji.cap(x.key)),
            subtitle: x.key.isEmpty ? null : Text(x.value),
            trailing: IconButton(
              tooltip: 'Forget',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () => Bujji.removeNote(x),
            ),
          ),
      ],
    );
  }

  Widget _reminders(ColorScheme cs) {
    final r = [...Bujji.reminders]..sort((a, b) => a.next.compareTo(b.next));
    if (r.isEmpty) return _empty('No reminders yet.');
    final now = DateTime.now();
    return ListView(
      children: [
        for (final x in r)
          ListTile(
            leading: Icon(
              x.yearly
                  ? Icons.cake_outlined
                  : x.repeat.isNotEmpty
                  ? Icons.repeat_rounded
                  : Icons.alarm_rounded,
              color: x.next.isBefore(now) ? cs.onSurfaceVariant : cs.primary,
            ),
            title: Text(Bujji.cap(x.text)),
            subtitle: Text(
              switch (x.repeat) {
                'yearly' => 'Every year, ${DateFormat('d MMMM').format(x.next)}',
                'monthly' => 'Every month · next ${Bujji.fmtTime(x.next)}',
                'weekly' => 'Every ${DateFormat.EEEE().format(x.next)}, ${DateFormat.jm().format(x.next)}',
                'daily' => 'Every day, ${DateFormat.jm().format(x.next)}',
                _ => x.next.isBefore(now)
                    ? 'Done · ${Bujji.fmtTime(x.next)}'
                    : Bujji.fmtTime(x.next),
              },
            ),
            trailing: IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () => Bujji.removeReminder(x),
            ),
          ),
      ],
    );
  }
}

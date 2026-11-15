// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:vibe/vibe/buddy/vibe_buddy.dart';

/// Bujji's memory: things you tell it, reminders you ask for, and your talk
/// with it. Plain rules, no AI; all of it stays in this phone's secure
/// storage and never goes into a chat.
///
/// In any chat, a message that starts with @bujji goes to Bujji, not to the
/// chat: "@bujji naren phone number is 12257383929", "@bujji what's naren
/// phone number", "@bujji gowthu birthday is today, remind me to ask her
/// for a date at 3", "@bujji chat".
class BujjiNote {
  final String id;

  /// What it's about ("naren phone number"); empty for a plain note.
  final String key;
  final String value;
  final int ts;
  const BujjiNote(this.id, this.key, this.value, this.ts);

  Map<String, Object?> toJson() => {'id': id, 'k': key, 'v': value, 't': ts};
  static BujjiNote from(Map j) =>
      BujjiNote(j['id'] as String, j['k'] as String, j['v'] as String, j['t'] as int);
}

class BujjiReminder {
  final String id;
  final String text;
  final int at;
  final bool yearly;
  final String? roomId;
  const BujjiReminder(this.id, this.text, this.at, this.yearly, this.roomId);

  DateTime get when => DateTime.fromMillisecondsSinceEpoch(at);

  /// The next time it rings (yearly ones roll over to next year).
  DateTime get next {
    var d = when;
    final now = DateTime.now();
    while (yearly && d.isBefore(now)) {
      d = DateTime(d.year + 1, d.month, d.day, d.hour, d.minute);
    }
    return d;
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'x': text,
    'at': at,
    'y': yearly,
    'r': roomId,
  };
  static BujjiReminder from(Map j) => BujjiReminder(
    j['id'] as String,
    j['x'] as String,
    j['at'] as int,
    j['y'] == true,
    j['r'] as String?,
  );
}

class BujjiLine {
  final bool me;
  final String text;
  final int ts;
  const BujjiLine(this.me, this.text, this.ts);
  Map<String, Object?> toJson() => {'m': me, 'x': text, 't': ts};
  static BujjiLine from(Map j) =>
      BujjiLine(j['m'] == true, j['x'] as String, j['t'] as int);
}

class BujjiReply {
  final String text;
  final bool openChat;
  const BujjiReply(this.text, {this.openChat = false});
}

abstract class Bujji {
  static const _storage = FlutterSecureStorage();
  static const _slot = 'keepr.bujji.memory';

  static final notes = <BujjiNote>[];
  static final reminders = <BujjiReminder>[];
  static final log = <BujjiLine>[];

  /// Fires when anything in its memory changes.
  static final changed = ValueNotifier<int>(0);
  static bool _loaded = false;

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
      }
    } catch (_) {}
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
      final m = RegExp('^@$n\\b[\\s,:]*', caseSensitive: false).firstMatch(t);
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

  // ---- talking ----

  static String _fmtTime(DateTime d) {
    final now = DateTime.now();
    final t = DateFormat.jm().format(d);
    final days = DateTime(d.year, d.month, d.day)
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
    if (days == 0) return t;
    if (days == 1) return 'tomorrow at $t';
    return '${DateFormat('d MMM').format(d)} at $t';
  }

  static String _cap(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  static const _stop = {
    'what', 'whats', 'what\'s', 'is', 'are', 'the', 'a', 'an', 'of', 'my',
    'me', 'tell', 'do', 'you', 'know', 'when', 'whens', 'when\'s', 'where',
    'who', 'whos', 'who\'s', 'which', 'how', 'does', 'did', 'was', 'about',
    'please', 'bujji', 'his', 'her', 'their', 'to', 'for', 'and', 's', 'remember',
  };

  static List<String> _words(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r"'s\b"), '')
      .replaceAll(RegExp(r"[^a-z0-9\s]"), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty && !_stop.contains(w))
      .toList();

  static String _key(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r"'s\b"), '')
      .replaceAll(RegExp(r'^(my|the)\s+'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Handles what you said to Bujji and returns its answer.
  static Future<BujjiReply> handle(String said, {String? roomId}) async {
    await load();
    final text = said.trim();
    log.add(BujjiLine(true, text.isEmpty ? '@${VibeBuddy.name}' : text, DateTime.now().millisecondsSinceEpoch));
    final reply = _answer(text, roomId);
    log.add(BujjiLine(false, reply.text, DateTime.now().millisecondsSinceEpoch));
    await _save();
    return reply;
  }

  static BujjiReply _answer(String text, String? roomId) {
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
        "@bujji what's naren phone number\n"
        '@bujji gowthu birthday is today\n'
        '@bujji remind me to call mom at 6 pm\n'
        '@bujji remind me in 20 minutes to check the oven\n'
        '@bujji what do you remember\n'
        '@bujji forget naren phone number\n'
        '@bujji chat',
      );
    }
    if (RegExp(r'^(what do you (remember|know)|list|everything)$').hasMatch(low)) {
      final up = reminders.where((r) => r.next.isAfter(DateTime.now())).length;
      if (notes.isEmpty && up == 0) {
        return const BujjiReply("Nothing yet. Tell me something to remember.");
      }
      final some = notes.reversed
          .take(6)
          .map((n) => n.key.isEmpty ? '· ${n.value}' : '· ${_cap(n.key)}: ${n.value}')
          .join('\n');
      return BujjiReply(
        '${notes.length} notes and $up reminders.${some.isEmpty ? '' : '\n$some'}',
      );
    }
    if (RegExp(r'^(my )?reminders( today)?$').hasMatch(low) ||
        low.contains('what are my reminders')) {
      final up = reminders.where((r) => r.next.isAfter(DateTime.now())).toList()
        ..sort((a, b) => a.next.compareTo(b.next));
      if (up.isEmpty) return const BujjiReply('No reminders coming up.');
      return BujjiReply(
        up.take(6).map((r) => '· ${_fmtTime(r.next)}: ${r.text}').join('\n'),
      );
    }
    final forget = RegExp(r'^(forget|delete|remove)\s+(about\s+)?(.+)$').firstMatch(low);
    if (forget != null) {
      final w = _words(forget.group(3)!).toSet();
      final gone = notes.where((n) {
        final k = _words('${n.key} ${n.key.isEmpty ? n.value : ''}').toSet();
        return w.isNotEmpty && w.every(k.contains);
      }).toList();
      final goneR = reminders.where((r) {
        final k = _words(r.text).toSet();
        return w.isNotEmpty && w.every(k.contains);
      }).toList();
      if (gone.isEmpty && goneR.isEmpty) {
        return const BujjiReply("I don't have that.");
      }
      notes.removeWhere(gone.contains);
      for (final r in goneR) {
        _cancel(r);
      }
      reminders.removeWhere(goneR.contains);
      return BujjiReply('Forgotten: ${[...gone.map((n) => n.key.isEmpty ? n.value : n.key), ...goneR.map((r) => r.text)].join(', ')}.');
    }
    // "… remind me (to) … at 3"
    final rem = RegExp(
      r'^(.*?)(?:,?\s*(?:so|and)\s+|,\s*|^|\s+)remind me\s*(?:to\s+)?(.*)$',
    ).firstMatch(low);
    if (rem != null) {
      final before = rem.group(1)!.trim();
      final out = <String>[];
      if (before.isNotEmpty && _isFact(before)) {
        out.add(_learn(text.substring(0, before.length)).text);
      }
      final (at, task) = _when(rem.group(2)!);
      if (at == null) {
        out.add(
          'When should I remind you? Add a time, like "at 3 pm" or "in 20 '
          'minutes".',
        );
        return BujjiReply(out.join(' '));
      }
      final what = task.isEmpty ? 'the thing you asked' : task;
      final r = BujjiReminder(_id(), what, at.millisecondsSinceEpoch, false, roomId);
      reminders.add(r);
      _schedule(r);
      out.add("Okay, I'll remind you ${_fmtTime(at)}: $what.");
      return BujjiReply(out.join(' '));
    }
    // questions
    if (RegExp(
          r"^(what|whats|what's|when|whens|when's|where|who|whos|who's|which|how|tell me|do you know)\b",
        ).hasMatch(low) ||
        text.trim().endsWith('?')) {
      return _ask(low);
    }
    if (low.startsWith('remember ')) {
      final rest = text.trim().substring(9).replaceFirst(RegExp(r'^that\s+', caseSensitive: false), '');
      return _isFact(rest.toLowerCase()) ? _learn(rest) : _note(rest);
    }
    if (_isFact(low)) return _learn(text);
    return _note(text);
  }

  static final _fact = RegExp(
    r'^(.+?)\s+(?:is|are|=|:)\s+(.+)$',
    caseSensitive: false,
  );
  static bool _isFact(String low) => _fact.hasMatch(low);

  static BujjiReply _note(String text) {
    notes.add(BujjiNote(_id(), '', text.trim(), DateTime.now().millisecondsSinceEpoch));
    return const BujjiReply('Saved as a note.');
  }

  static BujjiReply _learn(String text) {
    final m = _fact.firstMatch(text.trim())!;
    final key = _key(m.group(1)!);
    var value = m.group(2)!.trim().replaceAll(RegExp(r'[.!]+$'), '');
    final day = _day(value.toLowerCase());
    var extra = '';
    if (day != null) {
      value = DateFormat('d MMMM').format(day);
      // birthdays and anniversaries: a reminder that morning, every year
      if (RegExp(r'birthday|anniversary|bday').hasMatch(key)) {
        final at = DateTime(day.year, day.month, day.day, 9);
        reminders.removeWhere((r) {
          final same = r.yearly && r.text == "${_cap(key)} today";
          if (same) _cancel(r);
          return same;
        });
        final r = BujjiReminder(_id(), "${_cap(key)} today", at.millisecondsSinceEpoch, true, null);
        reminders.add(r);
        _schedule(r);
        extra = " I'll remind you every year that morning.";
      }
    }
    notes.removeWhere((n) => n.key == key);
    notes.add(BujjiNote(_id(), key, value, DateTime.now().millisecondsSinceEpoch));
    return BujjiReply('Got it. ${_cap(key)} is $value.$extra');
  }

  static BujjiReply _ask(String low) {
    final q = _words(low);
    if (q.isEmpty) return const BujjiReply('Ask me about something you told me.');
    BujjiNote? best;
    var score = 0;
    for (final n in notes) {
      final k = _words(n.key.isEmpty ? n.value : n.key).toSet();
      final s = q.where(k.contains).length;
      if (s > score || (s == score && s > 0 && n.ts > (best?.ts ?? 0))) {
        best = n;
        score = s;
      }
    }
    if (best == null || score == 0) {
      return const BujjiReply(
        "I don't know that yet. Tell me, like: @bujji naren phone number is …",
      );
    }
    return BujjiReply(
      best.key.isEmpty ? best.value : '${_cap(best.key)} is ${best.value}.',
    );
  }

  /// "today", "tomorrow", "15 nov", "nov 15", "15/11".
  static DateTime? _day(String v) {
    final now = DateTime.now();
    if (v == 'today') return now;
    if (v == 'tomorrow') return now.add(const Duration(days: 1));
    if (v == 'yesterday') return now.subtract(const Duration(days: 1));
    const months = [
      'jan', 'feb', 'mar', 'apr', 'may', 'jun',
      'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
    ];
    int? mon(String s) {
      final i = months.indexWhere((m) => s.startsWith(m));
      return i < 0 ? null : i + 1;
    }
    var m = RegExp(r'^(\d{1,2})(?:st|nd|rd|th)?\s+(?:of\s+)?([a-z]+)$').firstMatch(v);
    if (m != null && mon(m.group(2)!) != null) {
      return DateTime(now.year, mon(m.group(2)!)!, int.parse(m.group(1)!));
    }
    m = RegExp(r'^([a-z]+)\s+(\d{1,2})(?:st|nd|rd|th)?$').firstMatch(v);
    if (m != null && mon(m.group(1)!) != null) {
      return DateTime(now.year, mon(m.group(1)!)!, int.parse(m.group(2)!));
    }
    m = RegExp(r'^(\d{1,2})[/.-](\d{1,2})$').firstMatch(v);
    if (m != null) {
      final d = int.parse(m.group(1)!), mo = int.parse(m.group(2)!);
      if (mo >= 1 && mo <= 12 && d >= 1 && d <= 31) return DateTime(now.year, mo, d);
    }
    return null;
  }

  /// A time in [s] ("at 3", "at 3:30 pm", "3 o'clock", "in 20 minutes",
  /// "tomorrow", "tonight") and what's left of the words.
  static (DateTime?, String) _when(String s) {
    final now = DateTime.now();
    var rest = ' $s ';
    DateTime? at;
    final rel = RegExp(r'\bin\s+(\d+)\s*(minutes?|mins?|hours?|hrs?|days?)\b').firstMatch(rest);
    if (rel != null) {
      final n = int.parse(rel.group(1)!);
      final u = rel.group(2)!;
      at = now.add(
        u.startsWith('h')
            ? Duration(hours: n)
            : u.startsWith('d')
            ? Duration(days: n)
            : Duration(minutes: n),
      );
      rest = rest.replaceFirst(rel.group(0)!, ' ');
    }
    var dayOffset = 0;
    var tonight = false;
    for (final (w, d) in [
      ('day after tomorrow', 2),
      ('tomorrow', 1),
      ('tonight', 0),
      ('today', 0),
    ]) {
      if (RegExp('\\b$w\\b').hasMatch(rest)) {
        dayOffset = d;
        tonight = w == 'tonight';
        rest = rest.replaceFirst(RegExp('\\b$w\\b'), ' ');
        break;
      }
    }
    final clock = RegExp(
      r"\b(?:at\s+)?(\d{1,2})(?:[:.](\d{2}))?\s*(am|pm|a\.m\.|p\.m\.|o'?\s?clock)\b|\bat\s+(\d{1,2})(?:[:.](\d{2}))?\b",
    ).firstMatch(rest);
    if (at == null && (clock != null || dayOffset > 0 || tonight)) {
      var h = 9, mi = 0;
      String? ap;
      if (clock != null) {
        h = int.parse(clock.group(1) ?? clock.group(4)!);
        mi = int.parse(clock.group(2) ?? clock.group(5) ?? '0');
        ap = clock.group(3);
        rest = rest.replaceFirst(clock.group(0)!, ' ');
      } else if (tonight) {
        h = 21;
      }
      final base = DateTime(now.year, now.month, now.day + dayOffset);
      if (ap != null && ap.startsWith('p') && h < 12) h += 12;
      if (ap != null && ap.startsWith('a') && h == 12) h = 0;
      if (h > 23 || mi > 59) return (null, s.trim());
      var t = DateTime(base.year, base.month, base.day, h, mi);
      final ampm = ap != null && !ap.contains('clock');
      if (!ampm && h <= 12) {
        // no am or pm: the next time that hour comes round, afternoon for
        // small numbers ("at 3" is 3 pm)
        if (h >= 1 && h <= 7) {
          t = t.add(const Duration(hours: 12));
        } else if (dayOffset == 0 && t.isBefore(now) && h < 12) {
          final pm = t.add(const Duration(hours: 12));
          t = pm.isAfter(now) ? pm : t;
        }
      }
      if (t.isBefore(now)) t = t.add(const Duration(days: 1));
      at = t;
    }
    final task = rest
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'^\s*(to|that)\s+'), '')
        .trim();
    return (at, task);
  }

  // ---- notifications ----

  static int _nid(BujjiReminder r) => 'bujji_${r.id}'.hashCode;

  static Future<void> _schedule(BujjiReminder r) async {
    try {
      await FlutterLocalNotificationsPlugin().zonedSchedule(
        id: _nid(r),
        title: VibeBuddy.name,
        body: _cap(r.text),
        scheduledDate: tz.TZDateTime.from(r.next.toUtc(), tz.UTC),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: r.yearly ? DateTimeComponents.dateAndTime : null,
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
    await Bujji.handle(Bujji.forBujji(t) ?? t);
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
            Flexible(child: bubble),
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
            title: Text(x.key.isEmpty ? x.value : Bujji._cap(x.key)),
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
              x.yearly ? Icons.cake_outlined : Icons.alarm_rounded,
              color: x.next.isBefore(now) ? cs.onSurfaceVariant : cs.primary,
            ),
            title: Text(Bujji._cap(x.text)),
            subtitle: Text(
              x.yearly
                  ? 'Every year, ${DateFormat('d MMMM').format(x.next)}'
                  : x.next.isBefore(now)
                  ? 'Done · ${Bujji._fmtTime(x.next)}'
                  : Bujji._fmtTime(x.next),
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

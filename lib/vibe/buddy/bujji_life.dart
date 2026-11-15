// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:vibe/config/setting_keys.dart';
import 'package:vibe/vibe/buddy/vibe_buddy.dart';

/// How much Bujji does on its own: wanders the chat and brings things
/// (lively), brings things but stays on the text box (calm), or neither.
enum BujjiPace { lively, calm, off }

/// Bujji's life: what it notices and where things are on screen. All on
/// the phone; nothing it notices is sent anywhere.
abstract class BujjiLife {
  static BujjiPace get pace => BujjiPace.values.firstWhere(
    (p) => p.name == AppSettings.vibeBujjiLife.value,
    orElse: () => BujjiPace.lively,
  );

  static Future<void> setPace(BujjiPace p) async {
    await AppSettings.vibeBujjiLife.setItem(p.name);
    VibeBuddy.changed.value++;
  }

  // ---- things you do that it brings a tool for ----

  static final _tools = StreamController<(String, String?)>.broadcast();

  /// pin, edit, delete, copy, and the message it was done to.
  static Stream<(String, String?)> get tools => _tools.stream;

  static void use(String kind, [String? eventId]) {
    if (pace != BujjiPace.off) _tools.add((kind, eventId));
  }

  // ---- where messages are on screen ----

  static final _spots = <String, BuildContext>{};

  /// Where message [id] (or 'typing', the typing dots) is on screen now, if
  /// it's showing.
  static Rect? rectOf(String id) {
    final c = _spots[id];
    if (c == null || !c.mounted) return null;
    final r = c.findRenderObject();
    if (r is! RenderBox || !r.attached || !r.hasSize || r.size.isEmpty) {
      return null;
    }
    return r.localToGlobal(Offset.zero) & r.size;
  }

  // ---- what the words in a message call for ----

  static final _rain = RegExp(
    r'\b(rain|raining|rainy|drizzl\w*|umbrella|monsoon|pouring|thunderstorm)\b',
  );
  static final _birthday = RegExp(
    r'\b(happy birthday|happy bday|hbd|many happy returns)\b',
  );
  static final _morning = RegExp(r'\b(good morning|gm|morning)\b');
  static final _love = RegExp(
    r'\b(love you|love u|luv u|luv you|miss you|miss u|hugs?|kisses|xoxo)\b',
  );
  static final _hi = RegExp(r'^\s*(hi+|hey+|hello+|hola|yo|namaste|heya)\b');
  static final _nice = RegExp(
    r'\b(cute|sweet|adorable|good|lovely|clever|smart|best)\b[^.!?]{0,24}\bbujji\b|'
    r'\bbujji\b[^.!?]{0,24}\b(cute|sweet|adorable|good|lovely|clever|smart|best)\b',
    caseSensitive: false,
  );

  /// The face and the thing to hold for what a message says, if any.
  static (BuddyMood, BuddyProp)? forWords(String text, {required bool mine}) {
    final low = text.toLowerCase();
    final h = DateTime.now().hour;
    if (_rain.hasMatch(low)) return (BuddyMood.curious, BuddyProp.umbrella);
    if (_birthday.hasMatch(low)) return (BuddyMood.happy, BuddyProp.popper);
    if (h >= 5 && h < 11 && _morning.hasMatch(low)) {
      return (BuddyMood.sleepy, BuddyProp.coffee);
    }
    if (!mine && _love.hasMatch(low)) return (BuddyMood.love, BuddyProp.heart);
    if (mine && _hi.hasMatch(low)) return (BuddyMood.wink, BuddyProp.none);
    return null;
  }

  /// You're calling it cute (or good, sweet...): it goes shy.
  static bool compliment(String text) => _nice.hasMatch(text);
}

/// Marks a message (or the typing dots) so Bujji can find it on screen and
/// go and sit on it.
class BujjiSpot extends StatefulWidget {
  final String id;
  final Widget child;
  const BujjiSpot({required this.id, required this.child, super.key});

  @override
  State<BujjiSpot> createState() => _BujjiSpotState();
}

class _BujjiSpotState extends State<BujjiSpot> {
  @override
  void initState() {
    super.initState();
    BujjiLife._spots[widget.id] = context;
  }

  @override
  void didUpdateWidget(BujjiSpot old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id) {
      if (BujjiLife._spots[old.id] == context) BujjiLife._spots.remove(old.id);
      BujjiLife._spots[widget.id] = context;
    }
  }

  @override
  void dispose() {
    if (BujjiLife._spots[widget.id] == context) {
      BujjiLife._spots.remove(widget.id);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

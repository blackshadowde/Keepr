// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';

import 'package:vibe/vibe/buddy/bujji_life.dart';
import 'package:vibe/vibe/buddy/vibe_buddy.dart';

/// A reaction you'd miss: someone reacted to a message of yours that's
/// scrolled away.
class BujjiGift {
  /// The message they reacted to.
  final String target;

  /// The emoji.
  final String key;

  /// The reaction itself (taken back if they remove it).
  final String reaction;

  const BujjiGift(this.target, this.key, this.reaction);
}

/// Reactions on messages you can't see. Bujji holds them and hops till you
/// tap it, then takes you to the message; with lots it brings a basket and
/// tips them out above the text box. With Bujji off they float above the
/// send button instead.
abstract class BujjiGifts {
  /// Oldest first, for the open chat.
  static final list = ValueNotifier<List<BujjiGift>>(const []);

  /// This many at once and Bujji brings a basket.
  static const basket = 4;

  /// Bujji carries them (on and lively or calm); otherwise they float.
  static bool get byBujji => VibeBuddy.on && BujjiLife.pace != BujjiPace.off;

  static void add(BujjiGift g) {
    if (list.value.any((o) => o.reaction == g.reaction)) return;
    list.value = [...list.value, g];
  }

  /// Seen or taken back: the ones for [target], or the one [reaction].
  static void drop({String? target, String? reaction}) {
    final left = list.value
        .where((g) => g.target != target && g.reaction != reaction)
        .toList();
    if (left.length != list.value.length) list.value = left;
  }

  static void clear() {
    if (list.value.isNotEmpty) list.value = const [];
  }
}

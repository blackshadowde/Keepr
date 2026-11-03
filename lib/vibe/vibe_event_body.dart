// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

/// A message's one-line text (notifications, chat list, replies), with
/// Vibe's text stickers called stickers: they're sent as pictures with a
/// `chat.keepr.sticker` mark, so Matrix alone would say "sent a picture".
extension VibeEventBody on Event {
  String? _vibeSticker(MatrixLocalizations i18n) {
    if (redacted || content['chat.keepr.sticker'] != true) return null;
    return i18n.sentASticker(
      senderFromMemoryOrFallback.calcDisplayname(i18n: i18n),
    );
  }

  /// Plain-text message types that get the "Name: " prefix.
  static const Set<String> _textTypes = {
    MessageTypes.Text,
    MessageTypes.Notice,
    MessageTypes.Emote,
    MessageTypes.None,
  };

  /// "Name: text" (or "You: text") for chat lists and group notifications.
  /// The Matrix SDK stopped doing this in 15.0, so Keepr adds it itself,
  /// the same way the SDK used to.
  String _withPrefix(MatrixLocalizations i18n, String body) {
    if (type != EventTypes.Message || !_textTypes.contains(messageType)) {
      return body;
    }
    final who = senderId == room.client.userID
        ? i18n.you
        : senderFromMemoryOrFallback.calcDisplayname(i18n: i18n);
    return '$who: $body';
  }

  Future<String> vibeBody(
    MatrixLocalizations i18n, {
    bool withSenderNamePrefix = false,
    bool hideReply = false,
    bool hideEdit = false,
    bool plaintextBody = false,
    bool removeMarkdown = false,
  }) async {
    final sticker = _vibeSticker(i18n);
    if (sticker != null) return sticker;
    // names come from memory: load the sender (and who removed it) first
    if (redacted) await redactedBecause?.fetchSenderUser();
    if (withSenderNamePrefix &&
        (type == EventTypes.Message || type.contains(EventTypes.Encrypted))) {
      await fetchSenderUser();
    }
    return vibeBodyFallback(
      i18n,
      withSenderNamePrefix: withSenderNamePrefix,
      hideReply: hideReply,
      hideEdit: hideEdit,
      plaintextBody: plaintextBody,
      removeMarkdown: removeMarkdown,
    );
  }

  /// The same, right away (names only from what's already loaded).
  String vibeBodyFallback(
    MatrixLocalizations i18n, {
    bool withSenderNamePrefix = false,
    bool hideReply = false,
    bool hideEdit = false,
    bool plaintextBody = false,
    bool removeMarkdown = false,
  }) {
    final sticker = _vibeSticker(i18n);
    if (sticker != null) return sticker;
    final body = calcLocalizedBody(
      i18n,
      hideReply: hideReply,
      hideEdit: hideEdit,
      plaintextBody: plaintextBody,
      removeMarkdown: removeMarkdown,
    );
    return withSenderNamePrefix ? _withPrefix(i18n, body) : body;
  }
}

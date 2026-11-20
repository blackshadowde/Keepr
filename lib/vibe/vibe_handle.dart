// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:vibe/config/app_config.dart';

// Short handles: people type and see "@rahul" for someone on Keepr's own
// server. The full ID (@rahul:unredacted.org) is still used underneath, and
// people on other servers keep their server in the name.

/// What someone typed, pasted or scanned, as a Matrix user ID. A plain
/// "rahul" or "@rahul" is someone on Keepr's server; a full ID, a matrix.to
/// or matrix: link, Keepr's chat link or a short link gives that ID. Null
/// when it isn't a person.
String? normalizeHandle(String raw) {
  var text = raw.trim();
  try {
    text = Uri.decodeFull(text);
  } catch (_) {}
  final full = RegExp(r'@[^\s/?#:@]+:[^\s/?#@]+').firstMatch(text);
  if (full != null) return full.group(0);
  final short = keeprShortLinkId(text);
  if (short != null) return short;
  final uri = RegExp(r'^matrix:u/([^\s/?#:]+):([^\s/?#]+)').firstMatch(text);
  if (uri != null) return '@${uri.group(1)}:${uri.group(2)}';
  final name = (text.startsWith('@') ? text.substring(1) : text).toLowerCase();
  return RegExp(r'^[a-z0-9._=\-/+]+$').hasMatch(name)
      ? '@$name:${AppConfig.defaultServerName}'
      : null;
}

/// The person in a Keepr short link (get-keepr.github.io/u/rahul), or null.
String? keeprShortLinkId(String text) {
  final host = RegExp.escape(
    AppConfig.shortLinkPrefix.replaceFirst('https://', ''),
  );
  final m = RegExp(
    '^(?:https?://)?$host([A-Za-z0-9._=\\-]+)/?\$',
    caseSensitive: false,
  ).firstMatch(text.trim());
  return m == null
      ? null
      : '@${m.group(1)!.toLowerCase()}:${AppConfig.defaultServerName}';
}

/// "@rahul" for people on Keepr's server, the full ID for everyone else.
String formatDisplayHandle(String mxid) {
  final end = ':${AppConfig.defaultServerName}';
  return mxid.startsWith('@') && mxid.endsWith(end)
      ? mxid.substring(0, mxid.length - end.length)
      : mxid;
}

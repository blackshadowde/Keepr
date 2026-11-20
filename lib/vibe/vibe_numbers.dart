// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:vibe/utils/platform_infos.dart';
import 'package:vibe/vibe/vibe_haptics.dart';
import 'package:vibe/vibe/vibe_motion.dart';
import 'package:vibe/widgets/vibe_app.dart';

/// A number in a message worth copying: a code, an ID, a phone number.
class VibeNumber {
  /// As written in the message.
  final String shown;

  /// What's copied: the digits (with a leading + for phone numbers).
  final String copy;

  /// Looks like a phone number (call it, or copy it).
  final bool phone;
  const VibeNumber(this.shown, this.copy, this.phone);
}

/// Numbers in messages: underlined faintly so you can tap one to copy it
/// (a phone number also offers Call), and listed in Select text.
abstract class VibeNumbers {
  // digits, with spaces, dashes or brackets inside (phone numbers), or a
  // + in front; never part of a word
  static final _re = RegExp(r'(?<![\w+])\+?\d(?:[\d \-()]*\d)?(?!\w)');

  /// Every number of 3 digits or more in [text], once each.
  static List<VibeNumber> all(String text) => _find(text, min: 3);

  /// The ones worth a tap in the message itself: codes of 5 digits or more
  /// and phone numbers (years and small amounts stay plain).
  static List<VibeNumber> _tappable(String text) =>
      _find(text, min: 5, unique: false);

  static List<VibeNumber> _find(
    String text, {
    required int min,
    bool unique = true,
  }) {
    final out = <VibeNumber>[];
    final seen = <String>{};
    void add(String shown) {
      final plus = shown.startsWith('+');
      final digits = shown.replaceAll(RegExp(r'\D'), '');
      if (digits.length < min || digits.length > 16) return;
      final copy = '${plus ? '+' : ''}$digits';
      if (!seen.add(copy) && unique) return;
      out.add(VibeNumber(shown, copy, plus || digits.length >= 10));
    }

    for (final m in _re.allMatches(text)) {
      final s = m.group(0)!.trim();
      final digits = s.replaceAll(RegExp(r'\D'), '');
      // "10 - 20" or "2 3 4" are separate numbers, not one
      if (s.contains(RegExp(r'[ \-()]')) &&
          !s.startsWith('+') &&
          digits.length < 9) {
        for (final part in RegExp(r'\d+').allMatches(s)) {
          add(part.group(0)!);
        }
      } else {
        add(s);
      }
    }
    return out;
  }

  /// [text] with its codes and phone numbers tappable.
  static InlineSpan span(String text) {
    final found = _tappable(text);
    if (found.isEmpty) return TextSpan(text: text);
    final parts = <InlineSpan>[];
    var at = 0;
    for (final n in found) {
      final i = text.indexOf(n.shown, at);
      if (i < 0) continue;
      if (i > at) parts.add(TextSpan(text: text.substring(at, i)));
      parts.add(
        TextSpan(
          text: n.shown,
          style: const TextStyle(
            decoration: TextDecoration.underline,
            decorationStyle: TextDecorationStyle.dotted,
          ),
          recognizer: TapGestureRecognizer()..onTap = () => open(n),
        ),
      );
      at = i + n.shown.length;
    }
    if (at < text.length) parts.add(TextSpan(text: text.substring(at)));
    return TextSpan(children: parts);
  }

  /// A code is copied at once; a phone number offers Call and Copy.
  static Future<void> open(VibeNumber n) async {
    final context = VibeApp.router.routerDelegate.navigatorKey.currentContext;
    if (!n.phone || context == null) return copy(context, n.copy);
    VibeHaptics.medium();
    await showVibeSheet<void>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheet) {
        final cs = Theme.of(sheet).colorScheme;
        Widget action(IconData icon, String label, VoidCallback onTap) =>
            ListTile(
              leading: Icon(icon, color: cs.onSurface),
              title: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              onTap: onTap,
            );
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: cs.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.dialpad_rounded,
                          color: cs.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          n.shown,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                action(Icons.call_outlined, 'Call', () {
                  Navigator.of(sheet).pop();
                  launchUrl(Uri(scheme: 'tel', path: n.copy));
                }),
                action(Icons.copy_rounded, 'Copy number', () {
                  Navigator.of(sheet).pop();
                  copy(context, n.copy);
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  static Future<void> copy(BuildContext? context, String text) async {
    VibeHaptics.light();
    await Clipboard.setData(ClipboardData(text: text));
    // phones say so themselves
    if (context == null || !context.mounted || PlatformInfos.isMobile) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text('Copied $text'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

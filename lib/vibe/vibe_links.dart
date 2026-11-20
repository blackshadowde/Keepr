// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_linkify/flutter_linkify.dart';

import 'package:vibe/l10n/l10n.dart';
import 'package:vibe/utils/platform_infos.dart';
import 'package:vibe/utils/url_launcher.dart';
import 'package:vibe/utils/vibe_share.dart';
import 'package:vibe/vibe/vibe_haptics.dart';
import 'package:vibe/vibe/vibe_motion.dart';
import 'package:vibe/vibe/vibe_numbers.dart';

/// Links in messages: tap one to open it, hold it for Open, Copy link and
/// Share.
abstract class VibeLinks {
  /// The text with its links tappable, each one findable by [at].
  static TextSpan span({
    required String text,
    required TextStyle linkStyle,
    required void Function(LinkableElement) onOpen,
  }) {
    // as linkify() does, with the web and email linkifiers
    const options = LinkifyOptions(humanize: false);
    var parts = <LinkifyElement>[TextElement(text)];
    for (final l in const [UrlLinkifier(), EmailLinkifier()]) {
      parts = l.parse(parts, options);
    }
    return TextSpan(
      children: [
        for (final e in parts)
          if (e is LinkableElement)
            TextSpan(
              text: e.text,
              style: linkStyle,
              recognizer: VibeLinkTap(e.url)..onTap = () => onOpen(e),
            )
          else
            // codes and phone numbers: tap to copy (or call)
            VibeNumbers.span(e.text),
      ],
    );
  }

  /// The link under the finger at [global] (in a message's text, a link
  /// written as a link, or a preview card), if any.
  static String? at(BuildContext context, Offset global) {
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(
      result,
      global,
      View.of(context).viewId,
    );
    for (final entry in result.path) {
      final t = entry.target;
      if (t is TextSpan) {
        final r = t.recognizer;
        if (r is VibeLinkTap) return r.url;
      }
      if (t is RenderMetaData) {
        final m = t.metaData;
        if (m is VibeLinkHit) return m.url;
      }
    }
    return null;
  }

  /// Open, Copy link and Share for [url], under the link itself.
  static Future<void> options(BuildContext context, String url) {
    VibeHaptics.medium();
    return showVibeSheet<void>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheet) => _LinkSheet(url: url, outer: context),
    );
  }
}

/// A link's tap, knowing which link it is.
class VibeLinkTap extends TapGestureRecognizer {
  final String url;
  VibeLinkTap(this.url);
}

/// Marks a widget as a link, for [VibeLinks.at] (wrap it in a [MetaData]).
class VibeLinkHit {
  final String url;
  const VibeLinkHit(this.url);
}

class _LinkSheet extends StatelessWidget {
  final String url;
  final BuildContext outer;
  const _LinkSheet({required this.url, required this.outer});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final uri = Uri.tryParse(url);
    final host = (uri?.host ?? '').replaceFirst(RegExp(r'^www\.'), '');
    Widget action(IconData icon, String label, VoidCallback onTap) => ListTile(
      leading: Icon(icon, color: cs.onSurface),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      onTap: onTap,
    );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // which link it is
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
                    child: Icon(Icons.link_rounded, color: cs.onPrimaryContainer),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (host.isNotEmpty)
                          Text(
                            host,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        Text(
                          url,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            action(Icons.open_in_new_rounded, 'Open link', () {
              Navigator.of(context).pop();
              UrlLauncher(outer, url).launchUrl();
            }),
            action(Icons.copy_rounded, 'Copy link', () async {
              Navigator.of(context).pop();
              await Clipboard.setData(ClipboardData(text: url));
              // phones say so themselves
              if (!outer.mounted || PlatformInfos.isMobile) return;
              ScaffoldMessenger.of(outer).showSnackBar(
                SnackBar(content: Text(L10n.of(outer).copiedToClipboard)),
              );
            }),
            action(Icons.share_outlined, 'Share', () {
              Navigator.of(context).pop();
              VibeShare.share(url, outer);
            }),
          ],
        ),
      ),
    );
  }
}

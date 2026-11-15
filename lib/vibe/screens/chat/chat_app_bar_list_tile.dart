// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:vibe/utils/url_launcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_linkify/flutter_linkify.dart';

class ChatAppBarListTile extends StatelessWidget {
  final Widget? leading;
  final String title;
  final Widget? trailing;
  final void Function()? onTap;

  /// A 42 high card with 3 above and below.
  static const double fixedHeight = 48.0;

  const ChatAppBarListTile({
    super.key,
    this.leading,
    required this.title,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final leading = this.leading;
    final trailing = this.trailing;
    // its own card, like the name pill, so it reads over the messages
    // scrolling under the see-through bar
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 3, 12, 3),
      child: Material(
      color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.96),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      shadowColor: Colors.black26,
      child: SizedBox(
      height: fixedHeight - 6,
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            ?leading,
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: Linkify(
                  text: title,
                  textScaleFactor: MediaQuery.textScalerOf(context).scale(1),
                  options: const LinkifyOptions(humanize: false),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    overflow: TextOverflow.ellipsis,
                    fontSize: 14,
                  ),
                  linkStyle: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontSize: 14,
                    decoration: TextDecoration.underline,
                    decorationColor: theme.colorScheme.onSurfaceVariant,
                  ),
                  onOpen: (url) => UrlLauncher(context, url.url).launchUrl(),
                ),
              ),
            ),
            ?trailing,
          ],
        ),
      ),
      ),
      ),
    );
  }
}
